-- MemeDash FixedCamera Spin 360 V4 | Delta iOS
-- Camera stays world-locked at its ORIGINAL angle and distance.
-- The camera follows only player TRANSLATION, not player ROTATION.
-- Avatar spins 360 degrees; braking and release are time-based.
-- Does not edit WalkSpeed, JumpPower, velocity, or player position.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
local key = "__MemeDashCamera360"

if type(env[key]) == "table" and type(env[key].Destroy) == "function" then
    pcall(env[key].Destroy)
end
local renderKey = "MemeDashFixedCameraV4"
pcall(function() RunService:UnbindFromRenderStep(renderKey) end)

local cfg = {
    speed = 180,           -- degrees per second
    direction = 1,
    brakeTime = 0.85,      -- actual slowdown duration
    releaseTime = 0.55,    -- blend back to the game camera
    acceleration = 0.22,
}

local state = "idle"       -- idle, spinning, braking, release
local currentRate, brakeRate, brakeClock, releaseClock = 0, 0, 0, 0
local yaw = 0
local controlledHumanoid, controlledRoot, oldAutoRotate
local cameraOrigin, rootOrigin, cameraAtRelease
local destroyed, uiRefresh = false, function() end
local connections = {}

local function smooth(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end
local function character()
    local ch = player.Character
    if not ch then return nil, nil end
    local h = ch:FindFirstChildOfClass("Humanoid")
    local r = ch:FindFirstChild("HumanoidRootPart")
    if h and r and h.Health > 0 then return h, r end
    return nil, nil
end
local function releaseHumanoid()
    if controlledHumanoid and controlledHumanoid.Parent then
        pcall(function() controlledHumanoid.AutoRotate = oldAutoRotate end)
    end
    controlledHumanoid, controlledRoot, oldAutoRotate = nil, nil, nil
end
local function controlHumanoid(h, r)
    if controlledHumanoid == h and controlledRoot == r then return end
    releaseHumanoid()
    controlledHumanoid, controlledRoot = h, r
    oldAutoRotate = h.AutoRotate
    h.AutoRotate = false
    local forward = r.CFrame.LookVector
    yaw = math.atan2(-forward.X, -forward.Z)
end

local function done()
    state = "idle"
    currentRate, brakeRate = 0, 0
    pcall(function() RunService:UnbindFromRenderStep(renderKey) end)
    releaseHumanoid()
    cameraOrigin, rootOrigin, cameraAtRelease = nil, nil, nil
    uiRefresh()
end

local function beginRelease()
    if state == "release" or state == "idle" then return end
    releaseHumanoid()
    state = "release"
    releaseClock = 0
    uiRefresh()
end

local function render(dt)
    if destroyed or state == "idle" then return end
    dt = math.clamp(dt, 0, 0.08)
    local cam = workspace.CurrentCamera
    if not cam then done() return end

    -- Let the Roblox camera render first. Then gradually blend from the
    -- locked pose into its own CFrame. No CameraType flip or distance snap.
    if state == "release" then
        releaseClock = math.min(cfg.releaseTime, releaseClock + dt)
        local native = cam.CFrame
        local h, root = character()
        local posDelta = root and rootOrigin and (root.Position - rootOrigin) or Vector3.zero
        local locked = cameraOrigin and (CFrame.new(posDelta) * cameraOrigin) or native
        local a = smooth(releaseClock / cfg.releaseTime)
        cam.CFrame = locked:Lerp(native, a)
        if releaseClock >= cfg.releaseTime then done() end
        return
    end

    local h, root = character()
    if not h or not root then beginRelease() return end
    if controlledHumanoid ~= h or controlledRoot ~= root then
        -- New respawn: abort instead of splicing unrelated character poses.
        beginRelease()
        return
    end

    if state == "spinning" then
        local wanted = math.rad(cfg.speed * cfg.direction)
        local gain = 1 - math.exp(-dt / cfg.acceleration)
        currentRate = currentRate + (wanted - currentRate) * gain
    elseif state == "braking" then
        brakeClock = math.min(cfg.brakeTime, brakeClock + dt)
        currentRate = brakeRate * (1 - smooth(brakeClock / cfg.brakeTime))
    end
    yaw = (yaw + currentRate * dt) % (math.pi * 2)

    -- Rotate the character WITHOUT changing its world position.
    local at = root.Position
    root.CFrame = CFrame.new(at) * CFrame.Angles(0, yaw, 0)

    -- ABSOLUTELY NO CAMERA ORBIT: never derive the camera from spin yaw.
    -- Preserve the exact view angle and camera-to-player distance at start.
    local displacement = at - rootOrigin
    cam.CFrame = CFrame.new(displacement) * cameraOrigin

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
    cameraOrigin = cam.CFrame
    rootOrigin = root.Position
    controlHumanoid(h, root)
    currentRate, brakeRate, brakeClock = 0, 0, 0
    state = "spinning"
    -- Roblox camera still runs underneath; this script only pins its view.
    RunService:BindToRenderStep(renderKey, Enum.RenderPriority.Camera.Value + 1, render)
    uiRefresh()
end
local function stop()
    if state ~= "spinning" then return end
    brakeRate = currentRate
    brakeClock = 0
    state = "braking"
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
    Name = "MemeDashFixedCameraV4UI",
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
label("MEMEDASH | CAM FIXA V4", 15, 9, 253, 38, 20, bar)
local minimize = button("_", 270, 7, 46, 42, bar, nil, 26)
local close = button("X", 324, 7, 43, 42, bar, Color3.fromRGB(147, 51, 65), 24)

local toggle = button("ATIVAR GIRO 360", 14, 62, 347, 66, panel, Color3.fromRGB(33, 150, 118), 23)

label("VELOCIDADE", 19, 146, 169, 40, 19)
local speedMinus = button("-", 186, 143, 49, 49)
local speedValue = label("180", 239, 147, 61, 39, 23)
speedValue.TextXAlignment = Enum.TextXAlignment.Center
local speedPlus = button("+", 308, 143, 53, 49)

label("FREIO SUAVE", 19, 207, 166, 39, 19)
local brakeMinus = button("-", 186, 204, 49, 49)
local brakeValue = label("0.85s", 237, 207, 70, 39, 20)
brakeValue.TextXAlignment = Enum.TextXAlignment.Center
local brakePlus = button("+", 308, 204, 53, 49)

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
    toggle.Text = spinning and "PARAR SUAVEMENTE"
        or busy and "DESACELERANDO..." or "ATIVAR GIRO 360"
    miniButton.Text = spinning and "PARAR GIRO"
        or busy and "PARANDO..." or "ATIVAR GIRO"
    local shade = spinning and Color3.fromRGB(181, 68, 77)
        or Color3.fromRGB(33, 150, 118)
    toggle.BackgroundColor3 = shade
    miniButton.BackgroundColor3 = shade
    speedValue.Text = tostring(cfg.speed)
    brakeValue.Text = string.format("%.2fs", cfg.brakeTime)
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
connect(brakeMinus.MouseButton1Click, function()
    cfg.brakeTime = math.max(0.30, math.floor((cfg.brakeTime - 0.1) * 100 + 0.5) / 100)
    uiRefresh()
end)
connect(brakePlus.MouseButton1Click, function()
    cfg.brakeTime = math.min(2.0, math.floor((cfg.brakeTime + 0.1) * 100 + 0.5) / 100)
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
