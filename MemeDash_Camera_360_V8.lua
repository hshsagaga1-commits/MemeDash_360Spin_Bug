-- MemeDash Sync 360 V8 | 2026-11-10 | Delta iPhone
-- V7: camera e personagem dessicronizados; controle de distancia indevido;
-- parada e retomada com saltos. V8 elimina a distancia completamente.
-- CAMERA FIXA RELATIVA AO PERSONAGEM: captura a pose da camera APENAS
-- ao ativar. A mesma pose relativa e preservada em TODOS os frames.
-- O mesmo yaw controla o personagem e a pose da camera; sem orbitas extras.
-- FREIO: velocidade continua em 0.18s, sem corte seco.
-- Botao durante freio = cancelar freio; durante retorno = recapturar pose.
-- V5, V6 e V7 preservados. EXPERIMENTAL, nao validado dentro do jogo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then return end

local env = (getgenv and getgenv()) or _G
local key = "__MemeDashCamera360"

-- Fecha a instancia anterior e remove callbacks de versoes antigas.
if type(env[key]) == "table" and type(env[key].Destroy) == "function" then
    pcall(env[key].Destroy)
end
local renderKey = "MemeDashSync360V8"
for _, oldKey in ipairs({
    "MemeDashSyncSpin360V3", "MemeDashSyncSpin360V5",
    "MemeDashSyncSpin360V6", "MemeDashSyncSpin360V7",
    "MemeDashCamera360_Render", "MemeDash360SpinEffect",
    renderKey
}) do
    pcall(function() RunService:UnbindFromRenderStep(oldKey) end)
end

local cfg = {
    speed = 300,              -- graus por segundo
    direction = 1,
    acceleration = 0.10,      -- entrada responsiva
    brakeTime = 0.18,         -- freada curta, nao instantanea
    releaseTime = 0.16,       -- devolucao curta para a camera nativa
}

local state = "idle"          -- idle / spinning / braking / release
local currentSpeed = 0
local brakeInitial, brakeClock, releaseClock = 0, 0, 0
local yaw = 0
local controlledHumanoid, controlledRoot, originalAutoRotate
local savedCamera, savedCameraType, savedCameraSubject
local relativeCamera, relativeFocus
local releaseCamera, releaseRootPos
local destroyed = false
local connections = {}
local uiRefresh = function() end

local function smooth01(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function getChar()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return nil, nil end
    return hum, root
end

local function flatYaw(cf, fallback)
    -- Yaw no plano horizontal, sem inclinar camera com corpo.
    -- Nas posicoes verticais/ragdoll, conserva yaw previo.
    local f = cf.LookVector
    local sq = f.X * f.X + f.Z * f.Z
    if sq > 0.075 then
        return math.atan2(-f.X, -f.Z)
    end
    return fallback or 0
end

local function releaseAvatar()
    if controlledHumanoid and controlledHumanoid.Parent then
        pcall(function()
            controlledHumanoid.AutoRotate = originalAutoRotate
        end)
    end
    controlledHumanoid, controlledRoot, originalAutoRotate = nil, nil, nil
end

local function returnNativeCamera()
    local cam = savedCamera
    if cam and cam.Parent then
        pcall(function()
            if savedCameraSubject and savedCameraSubject.Parent then
                cam.CameraSubject = savedCameraSubject
            end
            cam.CameraType =
                (savedCameraType == Enum.CameraType.Scriptable)
                and Enum.CameraType.Custom
                or (savedCameraType or Enum.CameraType.Custom)
        end)
    end
end

local function finish()
    state = "idle"
    pcall(function() RunService:UnbindFromRenderStep(renderKey) end)
    releaseAvatar()
    returnNativeCamera()
    savedCamera, savedCameraType, savedCameraSubject = nil, nil, nil
    relativeCamera, relativeFocus = nil, nil
    releaseCamera, releaseRootPos = nil, nil
    currentSpeed, brakeInitial, brakeClock, releaseClock = 0, 0, 0, 0
    uiRefresh()
end

local function beginRelease()
    if state == "idle" or state == "release" then return end
    local cam = workspace.CurrentCamera
    if not cam then finish() return end
    releaseCamera = cam.CFrame
    releaseRootPos = controlledRoot and controlledRoot.Position or Vector3.zero
    releaseClock = 0
    state = "release"
    returnNativeCamera()
    uiRefresh()
end

local function render(dt)
    if destroyed or state == "idle" then return end
    dt = math.clamp(dt, 0, 0.066)
    local cam = workspace.CurrentCamera
    if not cam then finish() return end

    if state == "release" then
        -- O CameraModule ja executou nesse frame: blend SEM teleportar.
        local native = cam.CFrame
        local _, root = getChar()
        local moved = root and (root.Position - releaseRootPos) or Vector3.zero
        local from = CFrame.new(moved) * releaseCamera
        releaseClock = math.min(cfg.releaseTime, releaseClock + dt)
        cam.CFrame = from:Lerp(native, smooth01(releaseClock / cfg.releaseTime))
        if releaseClock >= cfg.releaseTime then finish() end
        return
    end

    local h, root = getChar()
    if not h or h ~= controlledHumanoid or root ~= controlledRoot
        or cam ~= savedCamera then
        finish()
        return
    end

    if h.AutoRotate then h.AutoRotate = false end
    if state == "spinning" then
        local goal = math.rad(cfg.speed * cfg.direction)
        currentSpeed = currentSpeed + (goal - currentSpeed)
            * (1 - math.exp(-dt / cfg.acceleration))
    elseif state == "braking" then
        brakeClock = math.min(cfg.brakeTime, brakeClock + dt)
        currentSpeed = brakeInitial *
            (1 - smooth01(brakeClock / cfg.brakeTime))
    end

    -- Uma UNICA orientacao dirige o avatar e a camera no mesmo frame.
    -- Nada de angulos acumulados diferentes ou zoom recalculado.
    yaw = yaw + currentSpeed * dt
    local before = root.CFrame
    local pos = before.Position
    local physicalYaw = flatYaw(before, yaw)
    local tilt = CFrame.Angles(0, -physicalYaw, 0) * before.Rotation
    root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * tilt

    -- CAM FIXA: referencia LOCAL capturada ao ligar.
    -- Independente da posicao global do jogador, do FPS e de giros >360.
    local bodyYawFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
    if cam.CameraType ~= Enum.CameraType.Scriptable then
        cam.CameraType = Enum.CameraType.Scriptable
    end
    cam.CFrame = bodyYawFrame * relativeCamera
    cam.Focus = CFrame.new(bodyYawFrame:PointToWorldSpace(relativeFocus))

    if state == "braking" and brakeClock >= cfg.brakeTime then
        currentSpeed = 0
        beginRelease()
    end
end

local function start()
    if destroyed or state ~= "idle" then return end
    local h, root = getChar()
    local cam = workspace.CurrentCamera
    if not h or not root or not cam then return end

    controlledHumanoid, controlledRoot = h, root
    originalAutoRotate = h.AutoRotate
    h.AutoRotate = false
    savedCamera, savedCameraType, savedCameraSubject =
        cam, cam.CameraType, cam.CameraSubject
    yaw = flatYaw(root.CFrame, 0)
    local reference = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)

    -- Camera atual capturada SEM mudar sua altura, zoom ou pitch.
    relativeCamera = reference:ToObjectSpace(cam.CFrame)
    relativeFocus = reference:PointToObjectSpace(cam.Focus.Position)

    currentSpeed, brakeInitial, brakeClock, releaseClock = 0, 0, 0, 0
    state = "spinning"
    cam.CameraType = Enum.CameraType.Scriptable
    RunService:BindToRenderStep(
        renderKey, Enum.RenderPriority.Last.Value - 1, render
    )
    uiRefresh()
end

local function stop()
    if state ~= "spinning" then return end
    brakeInitial = currentSpeed
    brakeClock = 0
    state = "braking"
    uiRefresh()
end

local function toggleSpin()
    if state == "idle" then
        start()
    elseif state == "spinning" then
        stop()
    elseif state == "braking" then
        -- Retomada durante a freada, SEM reiniciar o yaw ou a camera.
        state = "spinning"
        uiRefresh()
    elseif state == "release" then
        -- Recaptura a camera DO FRAME ATUAL; cancela o retorno sem
        -- carregar referencia antiga ou duplicar RenderStep.
        finish()
        start()
    end
end

local function destroy()
    if destroyed then return end
    destroyed = true
    finish()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
end

local function connect(signal, fn)
    local conn = signal:Connect(fn)
    connections[#connections + 1] = conn
    return conn
end

local function make(kind, props, par)
    local obj = Instance.new(kind)
    for keyName, val in pairs(props) do obj[keyName] = val end
    obj.Parent = par
    return obj
end
local function round(parent, px)
    make("UICorner", {CornerRadius = UDim.new(0, px or 11)}, parent)
end
local guiParent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local gui = make("ScreenGui", {
    Name = "MemeDashSyncSpinV8UI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 3000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, guiParent)
local panel = make("Frame", {
    Name = "Settings",
    AnchorPoint = Vector2.new(0, 0),
    Position = UDim2.fromOffset(20, 20),
    Size = UDim2.fromOffset(376, 275),
    BackgroundColor3 = Color3.fromRGB(18, 23, 33),
    BorderSizePixel = 0,
    Active = true
}, gui)
round(panel, 17)
make("UIStroke", {Thickness = 2, Color = Color3.fromRGB(87, 104, 136)}, panel)
local uiScale = make("UIScale", {Scale = 1}, panel)

local function button(txt, x, y, w, h, owner, shade, size)
    local b = make("TextButton", {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        Text = txt,
        Font = Enum.Font.GothamBold,
        TextSize = size or 21,
        TextColor3 = Color3.fromRGB(250, 252, 255),
        BackgroundColor3 = shade or Color3.fromRGB(53, 64, 83),
        BorderSizePixel = 0,
        AutoButtonColor = true
    }, owner or panel)
    round(b, 12)
    return b
end
local function label(txt, x, y, w, h, size, owner)
    return make("TextLabel", {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        Text = txt,
        Font = Enum.Font.GothamSemibold,
        TextSize = size or 19,
        TextColor3 = Color3.fromRGB(238, 242, 250),
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, owner or panel)
end

local bar = make("Frame", {
    Size = UDim2.new(1, 0, 0, 55),
    BackgroundTransparency = 1,
    Active = true
}, panel)
label("MEMEDASH | SYNC 360 V8", 15, 9, 253, 38, 20, bar)
local minimize = button("_", 270, 7, 46, 42, bar, nil, 26)
local close = button("X", 324, 7, 43, 42, bar, Color3.fromRGB(147, 51, 65), 24)

local toggle = button("ATIVAR GIRO 360", 14, 62, 347, 66, panel, Color3.fromRGB(33, 150, 118), 23)

label("VELOCIDADE", 19, 146, 169, 40, 19)
local speedMinus = button("-", 186, 143, 49, 49)
local speedValue = label("300", 239, 147, 61, 39, 23)
speedValue.TextXAlignment = Enum.TextXAlignment.Center
local speedPlus = button("+", 308, 143, 53, 49)

label("SENTIDO", 19, 207, 112, 43, 19)
local direction = button("HORARIO >", 142, 203, 219, 49, panel, nil, 20)

local mini = make("Frame", {
    Name = "MiniController",
    Size = UDim2.fromOffset(303, 90),
    Position = UDim2.fromOffset(12, 12),
    BackgroundColor3 = Color3.fromRGB(18, 23, 33),
    BorderSizePixel = 0,
    Active = true,
    Visible = false,
}, gui)
round(mini, 16)
make("UIStroke", {Thickness = 2, Color = Color3.fromRGB(87, 104, 136)}, mini)
local miniButton = button("ATIVAR GIRO", 10, 9, 214, 72, mini, Color3.fromRGB(33, 150, 118), 21)
local open = button("+", 233, 9, 59, 72, mini, nil, 28)

local camReady = false
local function getView()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(844, 390)
end
local function clampPosition(pos, size)
    local v = getView()
    local maxX = math.max(8, v.X - size.X - 8)
    local maxY = math.max(8, v.Y - size.Y - 8)
    return Vector2.new(math.clamp(pos.X, 8, maxX), math.clamp(pos.Y, 8, maxY))
end
local function resize()
    local v = getView()
    local factor = math.min(1.22, (v.X - 24) / 376, (v.Y - 24) / 275)
    uiScale.Scale = math.max(0.65, factor)
    local size = Vector2.new(376 * uiScale.Scale, 275 * uiScale.Scale)
    if not camReady then
        -- Painel a direita sem tapar o personagem no centro.
        panel.Position = UDim2.fromOffset(math.max(8, v.X - size.X - 12),
            math.max(8, (v.Y - size.Y) / 2))
        camReady = true
    else
        local p = clampPosition(Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset), size)
        panel.Position = UDim2.fromOffset(p.X, p.Y)
    end
    mini.Position = UDim2.fromOffset(math.max(8, v.X - 315), math.max(8, v.Y / 3 - 45))
end
resize()
if workspace.CurrentCamera then
    connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), resize)
end

uiRefresh = function()
    if destroyed or not gui.Parent then return end
    local spinning = state == "spinning"
    local busy = state == "braking" or state == "release"
    toggle.Text = spinning and "PARAR GIRO"
        or busy and "RETOMAR GIRO" or "ATIVAR GIRO 360"
    miniButton.Text = spinning and "PARAR GIRO"
        or busy and "RETOMAR" or "ATIVAR GIRO"
    local shade = spinning and Color3.fromRGB(181, 68, 77)
        or Color3.fromRGB(33, 150, 118)
    toggle.BackgroundColor3 = shade
    miniButton.BackgroundColor3 = shade
    speedValue.Text = tostring(cfg.speed)
    direction.Text = cfg.direction == 1 and "HORARIO >" or "< ANTI-HORARIO"
end

local function click()
    toggleSpin()
    if state == "spinning" then
        -- Nao deixa o painel tapar o avatar durante o giro.
        panel.Visible = false
        mini.Visible = true
    end
end
connect(toggle.MouseButton1Click, click)
connect(miniButton.MouseButton1Click, click)
connect(speedMinus.MouseButton1Click, function()
    cfg.speed = math.max(60, cfg.speed - 30); uiRefresh()
end)
connect(speedPlus.MouseButton1Click, function()
    cfg.speed = math.min(540, cfg.speed + 30); uiRefresh()
end)
connect(direction.MouseButton1Click, function()
    cfg.direction = -cfg.direction
    uiRefresh()
end)
connect(minimize.MouseButton1Click, function()
    panel.Visible = false
    mini.Visible = true
end)
connect(open.MouseButton1Click, function()
    mini.Visible = false
    panel.Visible = true
    resize()
end)
connect(close.MouseButton1Click, function()
    destroy()
    gui:Destroy()
end)

local dragging, draggingInput, dragStart, startPanel
connect(bar.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    dragging = true
    draggingInput = input
    dragStart = input.Position
    startPanel = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
end)
connect(UIS.InputEnded, function(input)
    if input == draggingInput then dragging, draggingInput = false, nil end
end)
connect(UIS.InputChanged, function(input)
    if not dragging then return end
    if input ~= draggingInput and not
        (draggingInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
    local p = startPanel + Vector2.new(input.Position.X - dragStart.X, input.Position.Y - dragStart.Y)
    local sz = Vector2.new(376 * uiScale.Scale, 275 * uiScale.Scale)
    local safe = clampPosition(p, sz)
    panel.Position = UDim2.fromOffset(safe.X, safe.Y)
end)

env[key] = {
    Destroy = function()
        destroy()
        if gui.Parent then gui:Destroy() end
    end,
    Settings = cfg
}
uiRefresh()
