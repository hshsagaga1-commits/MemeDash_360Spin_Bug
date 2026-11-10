-- MemeDash SyncSpin 360 V7 | Delta iOS | 2026-11-10
-- Correcao baseada na gravacao do usuario, que mostrou descompasso
-- camera/avatar e avatar fora do enquadramento ao girar com a V6.
-- V7 aplica um yaw ABSOLUTO ao personagem depois da fisica do jogo,
-- e calcula a camera usando a ORIENTACAO REALMENTE APLICADA no root.
-- Camera olha para o personagem e preserva o zoom atual.
-- A V6 permanece intacta no repositorio.
-- EXPERIMENTAL: validacao estatica nao garante resultado no iPhone.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then return end

local env = (getgenv and getgenv()) or _G
local key = "__MemeDashCamera360"
if type(env[key]) == "table" and type(env[key].Destroy) == "function" then
    pcall(env[key].Destroy)
end
local renderKey = "MemeDashSyncSpin360V7"
pcall(function() RunService:UnbindFromRenderStep(renderKey) end)

local cfg = {
    speed = 300,         -- deg/s, alteravel na interface
    direction = 1,
    distance = nil,      -- AUTO usa o zoom capturado na ativacao
    acceleration = 0.10,
    brakeTime = 0.18,    -- desaceleracao curta sem corte instantaneo
    releaseTime = 0.16, -- camera nativa volta em 160 ms
}

local state = "idle"
local currentRate, brakeRate = 0, 0
local brakeClock, releaseClock = 0, 0
local accumulatedYaw, startYaw = 0, 0
local controlledHumanoid, controlledRoot, oldAutoRotate
local cameraBefore, typeBefore, subjectBefore
local baseOffset, baseDistance, focusHeight
local camStartCFrame, rootStartPosition, enterClock = nil, nil, 0
local camAtRelease, rootAtRelease
local destroyed = false
local uiRefresh = function() end
local connections = {}

local function smooth(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function yawOf(frame, fallback)
    -- LookVector fica vertical em certas animacoes/ragdolls: fallback
    -- para RightVector evita saltos de 180 graus nesses quadros.
    local look = frame.LookVector
    if look.X * look.X + look.Z * look.Z > 0.08 then
        return math.atan2(-look.X, -look.Z)
    end
    local right = frame.RightVector
    if right.X * right.X + right.Z * right.Z > 0.08 then
        return math.atan2(-right.Z, right.X)
    end
    return fallback or 0
end

local function character()
    local ch = player.Character
    if not ch then return nil, nil end
    local h = ch:FindFirstChildOfClass("Humanoid")
    local root = ch:FindFirstChild("HumanoidRootPart")
    if h and root and h.Health > 0 then return h, root end
    return nil, nil
end

local function restoreAvatar()
    if controlledHumanoid and controlledHumanoid.Parent then
        pcall(function()
            controlledHumanoid.AutoRotate = oldAutoRotate
        end)
    end
    controlledHumanoid, controlledRoot, oldAutoRotate = nil, nil, nil
end

local function restoreCamera()
    if cameraBefore and cameraBefore.Parent then
        pcall(function()
            if subjectBefore and subjectBefore.Parent then
                cameraBefore.CameraSubject = subjectBefore
            end
            cameraBefore.CameraType = (typeBefore == Enum.CameraType.Scriptable)
                and Enum.CameraType.Custom or (typeBefore or Enum.CameraType.Custom)
        end)
    end
    cameraBefore, typeBefore, subjectBefore = nil, nil, nil
end

local function done()
    state = "idle"
    pcall(function() RunService:UnbindFromRenderStep(renderKey) end)
    restoreAvatar()
    restoreCamera()
    currentRate, brakeRate = 0, 0
    baseOffset, baseDistance, focusHeight = nil, nil, nil
    camStartCFrame, rootStartPosition, enterClock = nil, nil, 0
    camAtRelease, rootAtRelease = nil, nil
    uiRefresh()
end

local function beginRelease()
    if state == "idle" or state == "release" then return end
    local cam = workspace.CurrentCamera
    if not cam then done() return end
    camAtRelease = cam.CFrame
    rootAtRelease = controlledRoot and controlledRoot.Position or Vector3.zero
    releaseClock = 0
    state = "release"

    -- O CameraModule passa a atualizar a camera, mas o AutoRotate ainda
    -- fica desabilitado durante a transicao para nao girar o avatar no meio.
    if cam == cameraBefore then
        if subjectBefore and subjectBefore.Parent then
            cam.CameraSubject = subjectBefore
        end
        cam.CameraType = (typeBefore == Enum.CameraType.Scriptable)
            and Enum.CameraType.Custom or (typeBefore or Enum.CameraType.Custom)
    else
        cam.CameraType = Enum.CameraType.Custom
    end
    uiRefresh()
end

local function render(dt)
    if destroyed or state == "idle" then return end
    local cam = workspace.CurrentCamera
    if not cam then done() return end
    dt = math.clamp(dt, 0, 0.066)

    if state == "release" then
        -- A camera nativa ja atualizou antes do nosso RenderStep.
        local native = cam.CFrame
        local _, currentRoot = character()
        local moved = currentRoot and rootAtRelease
            and (currentRoot.Position - rootAtRelease) or Vector3.zero
        local from = camAtRelease and CFrame.new(moved) * camAtRelease or native
        releaseClock = math.min(cfg.releaseTime, releaseClock + dt)
        cam.CFrame = from:Lerp(native, smooth(releaseClock / cfg.releaseTime))
        if releaseClock >= cfg.releaseTime then done() end
        return
    end

    local h, root = character()
    if not h or root ~= controlledRoot or h ~= controlledHumanoid
        or cam ~= cameraBefore then
        done()
        return
    end
    if h.AutoRotate then h.AutoRotate = false end

    if state == "spinning" then
        local goal = math.rad(cfg.speed * cfg.direction)
        currentRate = currentRate + (goal - currentRate)
            * (1 - math.exp(-dt / cfg.acceleration))
    else
        brakeClock = math.min(cfg.brakeTime, brakeClock + dt)
        currentRate = brakeRate * (1 - smooth(brakeClock / cfg.brakeTime))
    end

    -- A V6 aplicava um DELTA sobre o root, mas girava a camera com
    -- um angulo acumulado separado. Se a fisica corrigisse o root,
    -- ambos se desencontravam. Aqui usamos a orientacao ALVO absoluta.
    accumulatedYaw = accumulatedYaw + currentRate * dt
    local desiredYaw = startYaw + accumulatedYaw
    local pos = root.Position
    local currentRotation = root.CFrame.Rotation
    local physicalYaw = yawOf(currentRotation, desiredYaw)
    local pitchRoll = CFrame.Angles(0, -physicalYaw, 0) * currentRotation
    root.CFrame = CFrame.new(pos) * CFrame.Angles(0, desiredYaw, 0) * pitchRoll

    -- Consultar a orientacao APOS aplicar ao avatar sincroniza o giro
    -- e mantem a camera ancorada mesmo se o jogo mexer no personagem.
    local appliedYaw = yawOf(root.CFrame.Rotation, desiredYaw)
    local offsetAngle = appliedYaw - startYaw
    local rotation = CFrame.Angles(0, offsetAngle, 0)
    local radius = cfg.distance or baseDistance
    local offset = rotation:VectorToWorldSpace(baseOffset * (radius / baseDistance))
    local focus = pos + Vector3.new(0, focusHeight, 0)
    local cameraPosition = focus + offset

    -- Sem roll na camera, sem orbita independente, foco no avatar.
    local wanted = CFrame.lookAt(cameraPosition, focus, Vector3.yAxis)
    if cam.CameraType ~= Enum.CameraType.Scriptable then
        cam.CameraType = Enum.CameraType.Scriptable
    end
    if camStartCFrame then
        enterClock = math.min(0.12, enterClock + dt)
        local moved = pos - rootStartPosition
        local from = CFrame.new(moved) * camStartCFrame
        local blend = smooth(enterClock / 0.12)
        cam.CFrame = from:Lerp(wanted, blend)
        if enterClock >= 0.12 then camStartCFrame = nil end
    else
        cam.CFrame = wanted
    end
    cam.Focus = CFrame.new(focus)

    if state == "braking" and brakeClock >= cfg.brakeTime then
        currentRate = 0
        beginRelease()
    end
end

local function start()
    if destroyed or state ~= "idle" then return end
    local h, root = character()
    local cam = workspace.CurrentCamera
    if not h or not root or not cam then return end

    controlledHumanoid, controlledRoot = h, root
    oldAutoRotate = h.AutoRotate
    h.AutoRotate = false
    cameraBefore, typeBefore, subjectBefore = cam, cam.CameraType, cam.CameraSubject
    startYaw = yawOf(root.CFrame.Rotation, 0)
    accumulatedYaw = 0
    currentRate, brakeRate, brakeClock, releaseClock = 0, 0, 0, 0

    -- Capturar zoom e angulo do momento de ativacao.
    local rootPos = root.Position
    local focusY = cam.Focus.Position.Y - rootPos.Y
    if focusY ~= focusY then focusY = 1.7 end
    focusHeight = math.clamp(focusY, 1.2, 3.2)
    local focus = rootPos + Vector3.new(0, focusHeight, 0)
    baseOffset = cam.CFrame.Position - focus
    if baseOffset.Magnitude < 0.8 then
        baseOffset = -cam.CFrame.LookVector * 5 + Vector3.new(0, 1.5, 0)
    end
    baseDistance = math.max(0.8, baseOffset.Magnitude)

    camStartCFrame, rootStartPosition = cam.CFrame, rootPos
    enterClock = 0
    state = "spinning"
    cam.CameraType = Enum.CameraType.Scriptable
    RunService:BindToRenderStep(
        renderKey, Enum.RenderPriority.Camera.Value + 20, render
    )
    uiRefresh()
end

local function stop()
    if state ~= "spinning" then return end
    state = "braking"
    brakeRate, brakeClock = currentRate, 0
    uiRefresh()
end

local function destroy()
    if destroyed then return end
    destroyed = true
    done()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
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
    Name = "MemeDashSyncSpinV7UI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 3000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, guiParent)
local panel = make("Frame", {
    Name = "Settings",
    AnchorPoint = Vector2.new(0, 0),
    Position = UDim2.fromOffset(20, 20),
    Size = UDim2.fromOffset(376, 326),
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
label("MEMEDASH | SYNC 360 V7", 15, 9, 253, 38, 20, bar)
local minimize = button("_", 270, 7, 46, 42, bar, nil, 26)
local close = button("X", 324, 7, 43, 42, bar, Color3.fromRGB(147, 51, 65), 24)

local toggle = button("ATIVAR GIRO 360", 14, 62, 347, 66, panel, Color3.fromRGB(33, 150, 118), 23)

label("VELOCIDADE", 19, 146, 169, 40, 19)
local speedMinus = button("-", 186, 143, 49, 49)
local speedValue = label("300", 239, 147, 61, 39, 23)
speedValue.TextXAlignment = Enum.TextXAlignment.Center
local speedPlus = button("+", 308, 143, 53, 49)

label("DISTANCIA", 19, 207, 166, 39, 19)
local distanceMinus = button("-", 186, 204, 49, 49)
local distanceValue = label("AUTO", 237, 207, 70, 39, 20)
distanceValue.TextXAlignment = Enum.TextXAlignment.Center
local distancePlus = button("+", 308, 204, 53, 49)

label("SENTIDO", 19, 268, 112, 43, 19)
local direction = button("HORARIO >", 142, 264, 219, 49, panel, nil, 20)

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
    local factor = math.min(1.70, (v.X - 24) / 376, (v.Y - 24) / 326)
    uiScale.Scale = math.max(0.65, factor)
    local size = Vector2.new(376 * uiScale.Scale, 326 * uiScale.Scale)
    if not camReady then
        -- Large but always inside the right-hand side of the landscape phone.
        panel.Position = UDim2.fromOffset(math.max(8, v.X - size.X - 12),
            math.max(8, (v.Y - size.Y) / 2))
        camReady = true
    else
        local p = clampPosition(Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset), size)
        panel.Position = UDim2.fromOffset(p.X, p.Y)
    end
    mini.Position = UDim2.fromOffset(math.max(8, v.X - 315), math.max(8, v.Y / 2 - 45))
end
resize()
if workspace.CurrentCamera then
    connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), resize)
end

uiRefresh = function()
    if destroyed or not gui.Parent then return end
    local spinning = state == "spinning"
    local busy = state == "braking" or state == "release"
    toggle.Text = spinning and "PARAR 360"
        or busy and "FINALIZANDO..." or "ATIVAR GIRO 360"
    miniButton.Text = spinning and "PARAR GIRO"
        or busy and "PARANDO..." or "ATIVAR GIRO"
    local shade = spinning and Color3.fromRGB(181, 68, 77)
        or Color3.fromRGB(33, 150, 118)
    toggle.BackgroundColor3 = shade
    miniButton.BackgroundColor3 = shade
    speedValue.Text = tostring(cfg.speed)
    distanceValue.Text = cfg.distance and string.format("%.1f",cfg.distance) or "AUTO"
    direction.Text = cfg.direction == 1 and "HORARIO >" or "< ANTI-HORARIO"
end

local function click()
    if state == "idle" then start() elseif state == "spinning" then stop() end
end
connect(toggle.MouseButton1Click, click)
connect(miniButton.MouseButton1Click, click)
connect(speedMinus.MouseButton1Click, function()
    cfg.speed = math.max(60, cfg.speed - 30); uiRefresh()
end)
connect(speedPlus.MouseButton1Click, function()
    cfg.speed = math.min(540, cfg.speed + 30); uiRefresh()
end)
connect(distanceMinus.MouseButton1Click, function()
    cfg.distance = math.max(2, (cfg.distance or baseDistance or 9) - 1)
    uiRefresh()
end)
connect(distancePlus.MouseButton1Click, function()
    cfg.distance = math.min(26, (cfg.distance or baseDistance or 9) + 1)
    uiRefresh()
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
    local sz = Vector2.new(376 * uiScale.Scale, 326 * uiScale.Scale)
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
