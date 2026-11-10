-- MemeDash Sync 360 V10 | Delta iOS | 2026-11-10
-- V8 aprovada para giro, mas CameraModule assumia controle ao parar.
-- V9 NAO devolve camera ao Roblox quando o giro para: fica presa ao
-- personagem em solo, salto, queda e repouso (modo LOCKED).
-- Pose RELATIVA ORIGINAL da V8 mantida: sem distancia configuravel.
-- Botao unico: verde ON, cinza OFF. Padrao 540 graus/s anti-horario.
-- V8 preservada e intacta no GitHub.
-- EXPERIMENTAL: logica conferida; falta validar comportamento no jogo.

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

local renderKey = "MemeDashSync360V10"
for _, oldKey in ipairs({
    "MemeDashSyncSpin360V3", "MemeDashSyncSpin360V5",
    "MemeDashSyncSpin360V6", "MemeDashSyncSpin360V7",
    "MemeDashSync360V8", "MemeDashSync360V9", "MemeDashCamera360_Render",
    "MemeDash360SpinEffect", renderKey
}) do
    pcall(function() RunService:UnbindFromRenderStep(oldKey) end)
end

local cfg = {
    speed = 540,
    direction = -1,
    acceleration = 0.10,
}

-- idle = antes do primeiro uso; locked = camera presa, spin OFF
-- spinning = giro ON; waiting = respawn
local state = "idle"
local currentSpeed = 0
local yaw = 0
local controlledHumanoid, controlledRoot, originalAutoRotate
local savedCamera, savedCameraType, savedCameraSubject
local relativeCamera, relativeFocus
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
    local look = cf.LookVector
    local len2 = look.X * look.X + look.Z * look.Z
    if len2 > 0.075 then
        return math.atan2(-look.X, -look.Z)
    end
    return fallback or 0
end

local function restoreAutoRotate()
    if controlledHumanoid and controlledHumanoid.Parent then
        pcall(function()
            controlledHumanoid.AutoRotate = originalAutoRotate
        end)
    end
end

local function releaseAvatar()
    restoreAutoRotate()
    controlledHumanoid, controlledRoot, originalAutoRotate = nil, nil, nil
end

local function returnNativeCamera()
    local cam = savedCamera
    if cam and cam.Parent then
        pcall(function()
            if savedCameraSubject and savedCameraSubject.Parent then
                cam.CameraSubject = savedCameraSubject
            end
            cam.CameraType = (savedCameraType == Enum.CameraType.Scriptable)
                and Enum.CameraType.Custom or (savedCameraType or Enum.CameraType.Custom)
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
    currentSpeed = 0
    uiRefresh()
end

local function capture(h, root, cam, mode)
    controlledHumanoid, controlledRoot = h, root
    originalAutoRotate = h.AutoRotate
    savedCamera, savedCameraType, savedCameraSubject =
        cam, cam.CameraType, cam.CameraSubject

    yaw = flatYaw(root.CFrame, 0)
    local reference = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)

    -- Mesma formula da V8 aprovada: nao refaz zoom, raio ou altura.
    relativeCamera = reference:ToObjectSpace(cam.CFrame)
    relativeFocus = reference:PointToObjectSpace(cam.Focus.Position)
    currentSpeed = 0
    state = mode
    if state == "spinning" then
        h.AutoRotate = false
    end
    cam.CameraType = Enum.CameraType.Scriptable
    uiRefresh()
end

local function suspendUntilRespawn()
    -- So durante a morte, libera CameraModule temporariamente.
    -- Quando o novo HRP estiver disponivel, prende a camera outra vez.
    releaseAvatar()
    returnNativeCamera()
    savedCamera, savedCameraType, savedCameraSubject = nil, nil, nil
    relativeCamera, relativeFocus = nil, nil
    currentSpeed = 0
    state = "waiting"
    uiRefresh()
end

local function render(dt)
    if destroyed or state == "idle" then return end
    dt = math.clamp(dt, 0, 0.066)
    local cam = workspace.CurrentCamera
    local h, root = getChar()

    if state == "waiting" then
        if cam and h and root then capture(h, root, cam, "locked") end
        return
    end
    if not h or not root or h ~= controlledHumanoid
        or root ~= controlledRoot then
        suspendUntilRespawn()
        return
    end
    if not cam then return end

    -- Roblox pode trocar CurrentCamera sem avisar; preserve a pose relativa
    -- capturada e reaplique neste novo objeto sem perder o LOCK.
    if cam ~= savedCamera then
        savedCamera = cam
        savedCameraType = cam.CameraType
        savedCameraSubject = cam.CameraSubject
    end

    if state == "spinning" then
        if h.AutoRotate then h.AutoRotate = false end
        local target = math.rad(cfg.speed * cfg.direction)
        currentSpeed = currentSpeed + (target - currentSpeed)
            * (1 - math.exp(-dt / cfg.acceleration))

        -- Mantem EXATAMENTE a base da V8 (pitch/roll preservados).
        yaw = yaw + currentSpeed * dt
        local before = root.CFrame
        local pos = before.Position
        local physicalYaw = flatYaw(before, yaw)
        local tilt = CFrame.Angles(0, -physicalYaw, 0) * before.Rotation
        root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * tilt
    else
        -- LOCKED: deixa movimento/AutoRotate naturais.
        -- A camera segue o yaw REAL do personagem, mesmo no ar.
        yaw = flatYaw(root.CFrame, yaw)
    end

    -- Prioridade apos o CameraModule + ancora por POSICAO REAL do root:
    -- na queda, salto, plataformas e giros rapidos camera acompanha.
    -- Nao depende de CFrame do frame anterior => sem drift acumulado.
    local actualYaw = flatYaw(root.CFrame, yaw)
    local bodyFrame = CFrame.new(root.Position)
        * CFrame.Angles(0, actualYaw, 0)
    if cam.CameraType ~= Enum.CameraType.Scriptable then
        cam.CameraType = Enum.CameraType.Scriptable
    end
    cam.CFrame = bodyFrame * relativeCamera
    cam.Focus = CFrame.new(bodyFrame:PointToWorldSpace(relativeFocus))


end

local function start()
    if destroyed then return end
    if state == "idle" then
        local h, root = getChar()
        local cam = workspace.CurrentCamera
        if not h or not root or not cam then return end
        capture(h, root, cam, "spinning")
        RunService:BindToRenderStep(
            renderKey, Enum.RenderPriority.Last.Value + 100, render
        )
    elseif state == "locked" then
        -- Reativar NAO recaptura camera, nao muda zoom nem enquadramento.
        local h, root = getChar()
        if not h or root ~= controlledRoot or h ~= controlledHumanoid then
            suspendUntilRespawn()
            return
        end
        yaw = flatYaw(root.CFrame, yaw)
        currentSpeed = 0
        h.AutoRotate = false
        state = "spinning"
        uiRefresh()
    elseif state == "waiting" then
        local h, root = getChar()
        local cam = workspace.CurrentCamera
        if h and root and cam then
            capture(h, root, cam, "spinning")
        end
    end
end

local function stop()
    if state ~= "spinning" then return end
    currentSpeed = 0
    state = "locked"
    restoreAutoRotate()
    uiRefresh()
end

local function toggleSpin()
    if state == "spinning" then
        stop()
    elseif state == "idle" or state == "locked" or state == "waiting" then
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

-- Interface: somente um botao, sem painel nem controle adicional.
local guiParent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "MemeDashSyncSpinV10UI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 3000
gui.Parent = guiParent
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "Spin360Toggle"
toggleButton.AnchorPoint = Vector2.new(1, 0.5)
toggleButton.Position = UDim2.new(1, -18, 0.32, 0)
toggleButton.Size = UDim2.fromOffset(132, 56)
toggleButton.BackgroundColor3 = Color3.fromRGB(60, 69, 83)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 21
toggleButton.Text = "360 OFF"
toggleButton.AutoButtonColor = false
toggleButton.BorderSizePixel = 0
toggleButton.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = toggleButton
local border = Instance.new("UIStroke")
border.Color = Color3.fromRGB(89, 105, 134)
border.Thickness = 2
border.Parent = toggleButton
uiRefresh = function()
    if destroyed or not toggleButton.Parent then return end
    local on = state == "spinning"
    toggleButton.Text = on and "360 ON" or "360 OFF"
    toggleButton.BackgroundColor3 = on and Color3.fromRGB(24, 192, 92)
        or Color3.fromRGB(60, 69, 83)
end
connect(toggleButton.Activated, toggleSpin)
connect(gui.Destroying, function()
    if not destroyed then destroy() end
end)
env[key] = {
    Destroy = function()
        destroy()
        if gui.Parent then gui:Destroy() end
    end,
    Settings = cfg,
}
uiRefresh()
