-- MemeDash V11: ORIGINAL V8 APPROVED BY USER + THREE CHANGES
-- 540 deg/s anticlockwise; only one round toggle; instant OFF.
-- Camera and avatar rotation calculations are identical to V8.
-- OFF restores native CameraModule controls and first-person.
-- Original V8 preserved. iPhone test not yet performed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
if not player then return end

local env = (getgenv and getgenv()) or _G
local key = "__MemeDashCamera360"

-- Fecha a instancia anterior e remove callbacks de versoes antigas.
if type(env[key]) == "table" and type(env[key].Destroy) == "function" then
    pcall(env[key].Destroy)
end
local renderKey = "MemeDashSync360V11"
for _, oldKey in ipairs({
    "MemeDashSyncSpin360V3", "MemeDashSyncSpin360V5",
    "MemeDashSyncSpin360V6", "MemeDashSyncSpin360V7",
    "MemeDashSync360V8", "MemeDashSync360V9", "MemeDashSync360V10",
    "MemeDashCamera360_Render", "MemeDash360SpinEffect",
    renderKey
}) do
    pcall(function() RunService:UnbindFromRenderStep(oldKey) end)
end

local cfg = {
    speed = 540,
    direction = -1,
    acceleration = 0.10,
}
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
    currentSpeed = 0
    uiRefresh()
end

local function render(dt)
    if destroyed or state == "idle" then return end
    dt = math.clamp(dt, 0, 0.066)
    local cam = workspace.CurrentCamera
    if not cam then finish() return end

    local h, root = getChar()
    if not h or h ~= controlledHumanoid or root ~= controlledRoot
        or cam ~= savedCamera then
        finish()
        return
    end

    if h.AutoRotate then h.AutoRotate = false end
    local goal = math.rad(cfg.speed * cfg.direction)
    currentSpeed = currentSpeed + (goal - currentSpeed)
        * (1 - math.exp(-dt / cfg.acceleration))

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

    currentSpeed = 0
    state = "spinning"
    cam.CameraType = Enum.CameraType.Scriptable
    RunService:BindToRenderStep(
        renderKey, Enum.RenderPriority.Last.Value - 1, render
    )
    uiRefresh()
end

local function stop()
    if state ~= "spinning" then return end
    -- OFF immediately: stop render hook, restore avatar rotation and native camera.
    finish()
end

local function toggleSpin()
    if state == "idle" then
        start()
    elseif state == "spinning" then
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

-- One circle only: green ON, neutral OFF. No other controls.
local guiParent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "MemeDashSync360V11UI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 3000
gui.Parent = guiParent
local circle = Instance.new("TextButton")
circle.Name = "Spin360"
circle.AnchorPoint = Vector2.new(1, 0.5)
circle.Position = UDim2.new(1, -20, 0.38, 0)
circle.Size = UDim2.fromOffset(66, 66)
circle.BackgroundColor3 = Color3.fromRGB(65, 73, 88)
circle.TextColor3 = Color3.fromRGB(255, 255, 255)
circle.Font = Enum.Font.GothamBold
circle.TextSize = 19
circle.Text = "360"
circle.AutoButtonColor = false
circle.BorderSizePixel = 0
circle.Active = true
circle.Parent = gui
local round = Instance.new("UICorner")
round.CornerRadius = UDim.new(1, 0)
round.Parent = circle
local outline = Instance.new("UIStroke")
outline.Thickness = 2
outline.Color = Color3.fromRGB(93, 112, 140)
outline.Parent = circle
uiRefresh = function()
    if destroyed or not circle.Parent then return end
    local on = state == "spinning"
    circle.BackgroundColor3 = on and Color3.fromRGB(24, 192, 92)
        or Color3.fromRGB(65, 73, 88)
    circle.Text = on and "ON" or "360"
end
connect(circle.Activated, toggleSpin)
connect(gui.Destroying, function()
    if not destroyed then destroy() end
end)
env[key] = {
    Destroy = function()
        destroy()
        if gui.Parent then gui:Destroy() end
    end,
    Settings = cfg
}
uiRefresh()
