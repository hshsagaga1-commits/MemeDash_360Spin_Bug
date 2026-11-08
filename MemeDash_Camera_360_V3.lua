-- MemeDash SyncSpin 360 V3 | iPhone / Delta
-- Fixed camera offset behind the character, synchronized 360 spin.
-- Smooth acceleration, deceleration and handoff to the native camera.
-- No WalkSpeed, velocity, humanoid movement, or player position changes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
local key = "__MemeDashCamera360"
local old = env[key]
if type(old) == "table" and type(old.Destroy) == "function" then
    pcall(old.Destroy)
end

local renderName = "MemeDashSyncSpin360V3"
pcall(function() RunService:UnbindFromRenderStep(renderName) end)

local cfg = {
    speed = 180,       -- degrees per second
    distance = 9,      -- studs behind the player; always constant
    height = 3.0,      -- camera elevation relative to focus
    direction = 1,
    focusHeight = 1.7,
    startSeconds = 0.26,
    stopSeconds = 0.85,
    returnSeconds = 0.75,
}

local phase = "idle" -- idle, spinning, braking, handoff
local yaw, elapsed, brakeElapsed = 0, 0, 0
local charRoot, humanoid, savedAutoRotate
local savedCamera, savedType, savedSubject
local introCFrame, introRootPos
local handoffCFrame, handoffRootPos
local disposed = false
local activeConnections = {}
local syncUI = function() end

local function ease(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function getAvatar()
    local char = player.Character
    if not char then return nil, nil end
    local h = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not h or not root or h.Health <= 0 then return nil, nil end
    return h, root
end

local function releaseAvatar()
    if humanoid and humanoid.Parent then
        pcall(function() humanoid.AutoRotate = savedAutoRotate end)
    end
    humanoid, charRoot, savedAutoRotate = nil, nil, nil
end

local function acquireAvatar(h, root)
    if humanoid == h and charRoot == root then return end
    releaseAvatar()
    humanoid, charRoot = h, root
    savedAutoRotate = h.AutoRotate
    h.AutoRotate = false
    local look = root.CFrame.LookVector
    yaw = math.atan2(-look.X, -look.Z)
end

local function restoreCamera()
    local cam = savedCamera
    if cam and cam.Parent then
        pcall(function()
            if savedSubject and savedSubject.Parent then
                cam.CameraSubject = savedSubject
            end
            cam.CameraType = savedType or Enum.CameraType.Custom
        end)
    end
    savedCamera, savedSubject, savedType = nil, nil, nil
end

local function finish()
    phase = "idle"
    pcall(function() RunService:UnbindFromRenderStep(renderName) end)
    releaseAvatar()
    restoreCamera()
    syncUI()
end

local function handoff()
    local cam = workspace.CurrentCamera
    if not cam then finish() return end
    handoffCFrame = cam.CFrame
    handoffRootPos = charRoot and charRoot.Position or Vector3.zero
    releaseAvatar()
    -- The native camera updates first (render priority Camera), this script
    -- blends its result afterwards to prevent a one-frame snap.
    restoreCamera()
    phase = "handoff"
    elapsed = 0
    syncUI()
end

local function frame(dt)
    if disposed or phase == "idle" then return end
    dt = math.clamp(dt, 0, 0.07)
    local cam = workspace.CurrentCamera
    if not cam then finish() return end

    if phase == "handoff" then
        elapsed = elapsed + dt
        local _, root = getAvatar()
        local translation = root and (root.Position - handoffRootPos) or Vector3.zero
        local from = CFrame.new(translation) * handoffCFrame
        -- At this point CameraModule has already produced the destination CFrame.
        local nativeCFrame = cam.CFrame
        local a = ease(elapsed / cfg.returnSeconds)
        cam.CFrame = from:Lerp(nativeCFrame, a)
        if elapsed >= cfg.returnSeconds then finish() end
        return
    end

    local h, root = getAvatar()
    if not h or not root then
        handoff()
        return
    end
    if humanoid ~= h or charRoot ~= root then
        acquireAvatar(h, root)
    end

    local velocity = math.rad(cfg.speed * cfg.direction)
    if phase == "spinning" then
        elapsed = elapsed + dt
        velocity = velocity * ease(elapsed / cfg.startSeconds)
    elseif phase == "braking" then
        brakeElapsed = math.min(cfg.stopSeconds, brakeElapsed + dt)
        local remaining = 1 - brakeElapsed / cfg.stopSeconds
        velocity = velocity * ease(remaining)
    end

    yaw = (yaw + velocity * dt) % (math.pi * 2)

    -- Single phase angle for both avatar and camera. No independent orbit.
    -- Preserve exact root position each frame; never change movement speed.
    local at = root.Position
    local rotation = CFrame.Angles(0, yaw, 0)
    root.CFrame = CFrame.new(at) * rotation

    local focus = at + Vector3.new(0, cfg.focusHeight, 0)
    -- Camera is ALWAYS behind the current avatar orientation at a fixed range.
    local cameraPos = focus + rotation:VectorToWorldSpace(Vector3.new(0, cfg.height, cfg.distance))
    local target = CFrame.lookAt(cameraPos, focus)

    if cam.CameraType ~= Enum.CameraType.Scriptable then
        cam.CameraType = Enum.CameraType.Scriptable
    end
    if introCFrame then
        local a = ease(elapsed / cfg.startSeconds)
        local translation = at - introRootPos
        local origin = CFrame.new(translation) * introCFrame
        cam.CFrame = origin:Lerp(target, a)
        if a >= 1 then introCFrame = nil end
    else
        cam.CFrame = target
    end
    cam.Focus = CFrame.new(focus)

    if phase == "braking" and brakeElapsed >= cfg.stopSeconds then
        handoff()
    end
end

local function start()
    if disposed or phase ~= "idle" then return end
    local h, root = getAvatar()
    local cam = workspace.CurrentCamera
    if not h or not root or not cam then return end

    savedCamera, savedType, savedSubject = cam, cam.CameraType, cam.CameraSubject
    introCFrame, introRootPos = cam.CFrame, root.Position
    acquireAvatar(h, root)
    phase, elapsed, brakeElapsed = "spinning", 0, 0
    cam.CameraType = Enum.CameraType.Scriptable
    RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, frame)
    syncUI()
end

local function stop()
    if phase == "spinning" then
        phase, brakeElapsed = "braking", 0
        introCFrame = nil
        syncUI()
    end
end

local function destroy()
    if disposed then return end
    disposed = true
    finish()
    for _, connection in ipairs(activeConnections) do
        pcall(function() connection:Disconnect() end)
    end
    if env[key] and env[key].Destroy == destroy then env[key] = nil end
end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(activeConnections, c)
    return c
end

local function create(kind, props, parent)
    local inst = Instance.new(kind)
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function corner(parent, r)
    create("UICorner", {CornerRadius = UDim.new(0, r or 13)}, parent)
end

local parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
local gui = create("ScreenGui", {
    Name = "MemeDashSyncSpin360V3UI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 1999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, parent)

local panel = create("Frame", {
    Name = "LargePanel",
    Size = UDim2.fromOffset(380, 350),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.50, 0.50),
    BackgroundColor3 = Color3.fromRGB(19, 23, 32),
    BorderSizePixel = 0,
    Active = true
}, gui)
corner(panel, 18)
create("UIStroke", {Thickness = 2, Color = Color3.fromRGB(88, 104, 128)}, panel)
local scaling = create("UIScale", {Scale = 1}, panel)

local function button(txt, x, y, w, h, parentNode, tint, textSize)
    local b = create("TextButton", {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        Text = txt, Font = Enum.Font.GothamBold,
        TextSize = textSize or 20,
        TextColor3 = Color3.fromRGB(250, 250, 255),
        BackgroundColor3 = tint or Color3.fromRGB(48, 59, 77),
        BorderSizePixel = 0,
        AutoButtonColor = true
    }, parentNode or panel)
    corner(b, 12)
    return b
end

local function label(txt, x, y, w, h, fontSize, parentNode)
    return create("TextLabel", {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1,
        Text = txt, Font = Enum.Font.GothamSemibold,
        TextColor3 = Color3.fromRGB(230, 235, 245),
        TextSize = fontSize or 18,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parentNode or panel)
end

local bar = create("Frame", {
    Size = UDim2.new(1, 0, 0, 54),
    BackgroundTransparency = 1,
    Active = true
}, panel)
label("MEMEDASH  360 V3", 17, 8, 250, 41, 22, bar)
local minBtn = button("_", 273, 9, 47, 40, bar, nil, 25)
local closeBtn = button("X", 327, 9, 45, 40, bar, Color3.fromRGB(126, 53, 65), 21)
local toggle = button("ATIVAR GIRO 360", 15, 61, 350, 64, panel, Color3.fromRGB(44, 139, 112), 22)

label("VELOCIDADE", 20, 139, 170, 43, 19)
local speedDown = button("-", 194, 137, 48, 48)
local speedText = label("180", 245, 139, 59, 42, 20)
speedText.TextXAlignment = Enum.TextXAlignment.Center
local speedUp = button("+", 311, 137, 54, 48)

label("DISTANCIA", 20, 198, 170, 43, 19)
local distDown = button("-", 194, 196, 48, 48)
local distText = label("9", 245, 198, 59, 42, 20)
distText.TextXAlignment = Enum.TextXAlignment.Center
local distUp = button("+", 311, 196, 54, 48)

label("SENTIDO", 20, 261, 119, 45, 19)
local directionButton = button("HORARIO >", 144, 260, 221, 48, panel, nil, 19)
label("Arraste pelo topo. Toque _ para minimizar.", 19, 319, 349, 23, 14)

-- Compact control stays accessible while the large settings panel is hidden.
local mini = create("Frame", {
    Name = "MiniBar",
    Size = UDim2.fromOffset(244, 72),
    Position = UDim2.new(1, -261, 0.5, -36),
    BackgroundColor3 = Color3.fromRGB(19, 23, 32),
    BorderSizePixel = 0,
    Active = true,
    Visible = false
}, gui)
corner(mini, 16)
create("UIStroke", {Thickness = 2, Color = Color3.fromRGB(88, 104, 128)}, mini)
local miniToggle = button("GIRO 360", 8, 8, 165, 56, mini, Color3.fromRGB(44, 139, 112), 18)
local maximize = button("+", 181, 8, 55, 56, mini, nil, 26)

local function resizeUI()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local v = cam.ViewportSize
    if v.X < 1 or v.Y < 1 then return end
    scaling.Scale = math.max(0.55, math.min(1.75, (v.X - 18) / 380, (v.Y - 18) / 350))
    -- Panel remains fully on-screen even with the larger touch targets.
    local sx = math.clamp(panel.Position.X.Scale, 0.04, 0.96)
    local sy = math.clamp(panel.Position.Y.Scale, 0.04, 0.96)
    panel.Position = UDim2.new(sx, 0, sy, 0)
end
resizeUI()
local currentCam = workspace.CurrentCamera
if currentCam then connect(currentCam:GetPropertyChangedSignal("ViewportSize"), resizeUI) end

syncUI = function()
    if disposed or not panel.Parent then return end
    local on = phase == "spinning"
    local slowing = phase == "braking" or phase == "handoff"
    toggle.Text = on and "PARAR SUAVEMENTE" or (slowing and "DESACELERANDO..." or "ATIVAR GIRO 360")
    miniToggle.Text = on and "PARAR GIRO" or (slowing and "PARANDO..." or "ATIVAR GIRO")
    toggle.BackgroundColor3 = on and Color3.fromRGB(176, 76, 79) or Color3.fromRGB(44, 139, 112)
    miniToggle.BackgroundColor3 = toggle.BackgroundColor3
    speedText.Text = tostring(cfg.speed)
    distText.Text = tostring(cfg.distance)
    directionButton.Text = cfg.direction == 1 and "HORARIO >" or "< ANTI-HORARIO"
end

local function clickToggle()
    if phase == "idle" then start()
    elseif phase == "spinning" then stop()
    end
end
connect(toggle.MouseButton1Click, clickToggle)
connect(miniToggle.MouseButton1Click, clickToggle)
connect(speedDown.MouseButton1Click, function()
    cfg.speed = math.max(60, cfg.speed - 30)
    syncUI()
end)
connect(speedUp.MouseButton1Click, function()
    cfg.speed = math.min(540, cfg.speed + 30)
    syncUI()
end)
connect(distDown.MouseButton1Click, function()
    cfg.distance = math.max(5, cfg.distance - 1)
    syncUI()
end)
connect(distUp.MouseButton1Click, function()
    cfg.distance = math.min(16, cfg.distance + 1)
    syncUI()
end)
connect(directionButton.MouseButton1Click, function()
    cfg.direction = -cfg.direction
    syncUI()
end)
connect(minBtn.MouseButton1Click, function()
    panel.Visible = false
    mini.Visible = true
end)
connect(maximize.MouseButton1Click, function()
    mini.Visible = false
    panel.Visible = true
    resizeUI()
end)
connect(closeBtn.MouseButton1Click, function()
    destroy()
    gui:Destroy()
end)

-- Touch/mouse dragging: delta must be divided by UIScale to track fingers.
local dragInput, dragPoint, dragPanel
connect(bar.InputBegan, function(input)
    local k = input.UserInputType
    if k ~= Enum.UserInputType.Touch and k ~= Enum.UserInputType.MouseButton1 then return end
    dragInput = input
    dragPoint = input.Position
    dragPanel = panel.Position
    connect(input.Changed, function()
        if input.UserInputState == Enum.UserInputState.End and dragInput == input then
            dragInput = nil
        end
    end)
end)
connect(UIS.InputChanged, function(input)
    if not dragInput then return end
    if input ~= dragInput
        and not (dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement) then
        return
    end
    local d = (input.Position - dragPoint) / scaling.Scale
    panel.Position = UDim2.new(dragPanel.X.Scale, dragPanel.X.Offset + d.X,
        dragPanel.Y.Scale, dragPanel.Y.Offset + d.Y)
end)

env[key] = {Destroy = function()
    destroy()
    if gui.Parent then gui:Destroy() end
end, Settings = cfg}
syncUI()
