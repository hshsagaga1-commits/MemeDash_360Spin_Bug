-- MemeDash Sync 360 V23 | 2026-11-10 | Delta iOS
-- OFF: camera 100% padrao do Roblox; nao intercepta toque ou zoom.
-- ON: bloco de giro V22 preservado literalmente, 590 graus/s.
-- Ao OFF: remove render callback e restaura Humanoid.AutoRotate.
-- UI V22 de 96px, arraste persistente e cadeado preservados.
-- A retomada nativa pode causar snap, dependente do CameraModule.
-- Teste real no iPhone ainda pendente.

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
local renderKey = "MemeDashSync360V23"
for _, oldKey in ipairs({
    "MemeDashSyncSpin360V3", "MemeDashSyncSpin360V5",
    "MemeDashSyncSpin360V6", "MemeDashSyncSpin360V7",
    "MemeDashSync360V8", "MemeDashSync360V9", "MemeDashSync360V10", "MemeDashSync360V11",
    "MemeDashSync360V12", "MemeDashSync360V13", "MemeDashSync360V14", "MemeDashSync360V15", "MemeDashSync360V16", "MemeDashSync360V17", "MemeDashSync360V18", "MemeDashSync360V19", "MemeDashSync360V20", "MemeDashSync360V21", "MemeDashSync360V22", "MemeDashCamera360_Render", "MemeDash360SpinEffect",
    renderKey
}) do
    pcall(function() RunService:UnbindFromRenderStep(oldKey) end)
end

local cfg = {
    speed = 590,
    direction = -1,
    acceleration = 0.10,
}

-- idle: camera nativa integralmente
-- arming: captura pose nativa apos CameraModule
-- spinning: unico modo em que o script sobrescreve a camera
local state = "idle"
local currentSpeed = 0
local yaw = 0
local controlledHumanoid, controlledRoot, originalAutoRotate
local savedCamera, savedCameraType, savedCameraSubject
local relativeCamera, relativeFocus
local lastNativeCamera
local destroyed = false
local connections = {}
local uiRefresh = function() end

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

finish = function()
    -- Limpeza real, inclusive quando PlayerGui e destruida.
    state = "idle"
    pcall(function() RunService:UnbindFromRenderStep(renderKey) end)
    releaseAvatar()
    savedCamera, savedCameraType, savedCameraSubject = nil, nil, nil
    relativeCamera, relativeFocus = nil, nil
    lastNativeCamera = nil
    currentSpeed = 0
    uiRefresh()
end

local function render(dt)
    if destroyed or state == "idle" then return end

    dt = math.clamp(dt, 0, 0.066)
    local cam = workspace.CurrentCamera
    local h, root = getChar()
    if not cam or not h or not root then
        finish()
        return
    end

    if state == "arming" then
        -- Este frame vem APOS CameraModule: pose original sem alteracao.
        controlledHumanoid, controlledRoot = h, root
        originalAutoRotate = h.AutoRotate
        savedCamera, savedCameraType, savedCameraSubject =
            cam, cam.CameraType, cam.CameraSubject

        yaw = flatYaw(root.CFrame, 0)
        local reference = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
        relativeCamera = reference:ToObjectSpace(cam.CFrame)
        relativeFocus = reference:PointToObjectSpace(cam.Focus.Position)

        currentSpeed = 0
        h.AutoRotate = false
        -- NAO usar CameraType.Scriptable: evita o reset de angulo quando OFF.
        state = "spinning"
        uiRefresh()
        return
    end

    if h ~= controlledHumanoid or root ~= controlledRoot
        or cam ~= savedCamera then
        finish()
        return
    end

    if h.AutoRotate then h.AutoRotate = false end
    local goal = math.rad(cfg.speed * cfg.direction)
    currentSpeed = currentSpeed + (goal - currentSpeed)
        * (1 - math.exp(-dt / cfg.acceleration))

    -- BLOCO DE GIRO V12: PRESERVADO SEM ALTERAR UMA UNICA FORMULA.
    yaw = yaw + currentSpeed * dt
    local before = root.CFrame
    local pos = before.Position
    local physicalYaw = flatYaw(before, yaw)
    local tilt = CFrame.Angles(0, -physicalYaw, 0) * before.Rotation
    root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * tilt

    local bodyYawFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
    -- Salva camera NATIVA para detectar gestos no OFF sem snap.
    lastNativeCamera = cam.CFrame
    cam.CFrame = bodyYawFrame * relativeCamera
    cam.Focus = CFrame.new(bodyYawFrame:PointToWorldSpace(relativeFocus))
end

local function start()
    if destroyed or state ~= "idle" then return end
    local h, root = getChar()
    local cam = workspace.CurrentCamera
    if not h or not root or not cam then return end
    state = "arming"
    RunService:BindToRenderStep(
        renderKey, Enum.RenderPriority.Last.Value - 1, render
    )
    uiRefresh()
end

local function stop()
    if state ~= "spinning" and state ~= "arming" then return end
    -- Camera 100% nativa no OFF. Nenhum ajuste de CFrame ou Focus.
    finish()
end

local function toggleSpin()
    if state == "idle" then
        start()
    else
        stop()
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


-- UI: compatibilidade com o Mover Botoes pelo mesmo nome.
local prefsKey = "__MemeDash360UiPrefs"
local prefs = env[prefsKey]
if type(prefs) ~= "table" then
    prefs = {locked=false}
    env[prefsKey] = prefs
end
if type(prefs.locked) ~= "boolean" then prefs.locked = false end

local gui = Instance.new("ScreenGui")
gui.Name = "MemeDashSync360V12UI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 3000
gui.Parent = player:WaitForChild("PlayerGui")

local circle = Instance.new("TextButton")
circle.Name = "Spin360MoveButton"
circle.AnchorPoint = Vector2.new(0.5,0.5)
circle.Size = UDim2.fromOffset(96,96)
circle.Position = typeof(prefs.position) == "UDim2"
    and prefs.position or UDim2.fromScale(0.83,0.38) -- migracao abaixo
circle.BackgroundColor3 = Color3.fromRGB(65,73,88)
circle.Text = "360"
circle.TextSize = 26
circle.TextColor3 = Color3.fromRGB(255,255,255)
circle.Font = Enum.Font.GothamBold
circle.BorderSizePixel = 0
circle.AutoButtonColor = false
circle.Active = true
circle.Parent = gui
local rounded = Instance.new("UICorner")
rounded.CornerRadius = UDim.new(1,0)
rounded.Parent = circle
local edge = Instance.new("UIStroke")
edge.Thickness = 3
edge.Color = Color3.fromRGB(93,112,140)
edge.Parent = circle

local lockButton = Instance.new("TextButton")
lockButton.Name = "Spin360PositionLock"
lockButton.AnchorPoint = Vector2.new(0.5,0.5)
lockButton.Size = UDim2.fromOffset(44,44)
lockButton.BackgroundColor3 = Color3.fromRGB(45,53,65)
lockButton.BorderSizePixel = 0
lockButton.Font = Enum.Font.GothamBold
lockButton.TextSize = 24
lockButton.TextColor3 = Color3.fromRGB(255,255,255)
lockButton.AutoButtonColor = false
lockButton.Active = true
lockButton.Parent = gui
local lockCorner = Instance.new("UICorner")
lockCorner.CornerRadius = UDim.new(0,14)
lockCorner.Parent = lockButton
local lockEdge = Instance.new("UIStroke")
lockEdge.Thickness = 2
lockEdge.Color = Color3.fromRGB(112,128,149)
lockEdge.Parent = lockButton


local function viewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(900,400)
end
local function centerFromUDim(p)
    local vp = viewport()
    return Vector2.new(vp.X*p.X.Scale + p.X.Offset,
                       vp.Y*p.Y.Scale + p.Y.Offset)
end
local function clampCenter(v)
    local vp=viewport()
    return Vector2.new(
        math.clamp(v.X,55,math.max(55,vp.X-92)),
        math.clamp(v.Y,72,math.max(72,vp.Y-55))
    )
end
local logicalCenter = typeof(prefs.position)=="Vector2"
    and prefs.position or centerFromUDim(circle.Position)
logicalCenter = clampCenter(logicalCenter)
local ownPositionWrite = false
local function setCenter(v)
    logicalCenter = clampCenter(v)
    prefs.position = logicalCenter
    ownPositionWrite = true
    circle.Position = UDim2.fromOffset(logicalCenter.X,logicalCenter.Y)
    ownPositionWrite = false
end
setCenter(logicalCenter)

local function positionLock()
    local p = circle.Position
    lockButton.Position = UDim2.new(
        p.X.Scale, p.X.Offset+62, p.Y.Scale, p.Y.Offset-42)
end
local function refreshLock()
    lockButton.Text = prefs.locked and "🔒" or "🔓"
    lockButton.BackgroundColor3 = prefs.locked
        and Color3.fromRGB(140,96,32) or Color3.fromRGB(45,53,65)
end
positionLock()
refreshLock()
connect(circle:GetPropertyChangedSignal("Position"),function()
    positionLock()
    if not ownPositionWrite then
        -- Mover Botoes externo ainda pode reposicionar o 360.
        logicalCenter = clampCenter(centerFromUDim(circle.Position))
        prefs.position = logicalCenter
    end
end)
connect(lockButton.Activated, function()
    prefs.locked = not prefs.locked
    prefs.position = logicalCenter
    refreshLock()
end)

-- Coordenada unica entre gestos: novo arrasto sempre parte do ultimo
-- centro LOGICO salvo. Nunca usar circle.AbsolutePosition na origem.
local dragging, dragAt, centerAt, didDrag = nil,nil,nil,false
local function to2(v)
    return Vector2.new(v.X,v.Y)
end
connect(circle.InputBegan,function(input)
    if dragging then return end
    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    dragging = input
    dragAt = to2(input.Position)
    centerAt = logicalCenter
    didDrag = false
end)
connect(UIS.InputChanged,function(input)
    if not dragging then return end
    if input ~= dragging and not (
        dragging.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
    local delta = to2(input.Position)-dragAt
    if delta.Magnitude>10 then didDrag=true end
    if didDrag and not prefs.locked then setCenter(centerAt+delta) end
end)
connect(UIS.InputEnded,function(input)
    if input~=dragging then return end
    local moved = didDrag
    dragging,dragAt,centerAt,didDrag=nil,nil,nil,false
    -- Um toque curto ativa o giro; arrastar NUNCA ativa.
    if not moved then toggleSpin() end
end)

uiRefresh=function()
    if destroyed or not circle.Parent then return end
    local active = state=="spinning" or state=="arming"
    circle.BackgroundColor3=active
        and Color3.fromRGB(24,192,92) or Color3.fromRGB(65,73,88)
end
connect(gui.Destroying,function()
    if not destroyed then destroy() end
end)
env[key]={
    Destroy=function()
        destroy()
        if gui.Parent then gui:Destroy() end
    end,
    Settings=cfg
}
uiRefresh()
