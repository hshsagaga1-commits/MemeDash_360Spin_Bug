-- MemeDash SyncSpin 360 V5 | Delta iOS
-- Fixed character framing: the CAMERA and AVATAR share one spin angle.
-- Fixed radius, stable height and lookAt center, no drifting or flying away.
-- Smooth acceleration, braking, and blend back to native camera.
-- Never changes WalkSpeed, JumpPower, or linear velocity.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
local key = "__MemeDashCamera360"

if type(env[key]) == "table" and type(env[key].Destroy) == "function" then
    pcall(env[key].Destroy)
end
local renderKey = "MemeDashSyncSpin360V5"
pcall(function() RunService:UnbindFromRenderStep(renderKey) end)

local cfg = {
    speed = 180,
    direction = 1,
    distance = 9.0,        -- constant horizontal distance (studs)
    height = 3.2,          -- constant camera height above focus
    focusHeight = 1.7,
    acceleration = 0.28,   -- time to ramp up spin speed
    brakeTime = 0.90,      -- smooth deceleration
    releaseTime = 0.80,    -- smooth native camera handoff
    enterTime = 0.35,
}

local state = "idle"   -- idle / spinning / braking / release
local currentRate = 0
local brakeRate, brakeClock, enterClock, releaseClock = 0, 0, 0, 0
local accumulatedYaw = 0
local controlledHumanoid, controlledRoot, oldAutoRotate
local cameraBefore, typeBefore, subjectBefore
local firstCam, firstRootPos, originalHorizontal
local camAtRelease, rootAtRelease
local destroyed = false
local uiRefresh = function() end
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
    if h and r and h.Health > 0 then
        return h, r
    end
    return nil, nil
end

local function restoreAvatar()
    if controlledHumanoid and controlledHumanoid.Parent then
        pcall(function() controlledHumanoid.AutoRotate = oldAutoRotate end)
    end
    controlledHumanoid, controlledRoot, oldAutoRotate = nil, nil, nil
end

local function restoreCamera()
    if cameraBefore and cameraBefore.Parent then
        pcall(function()
            if subjectBefore and subjectBefore.Parent then
                cameraBefore.CameraSubject = subjectBefore
            end
            cameraBefore.CameraType = typeBefore or Enum.CameraType.Custom
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
    firstCam, firstRootPos, originalHorizontal = nil, nil, nil
    camAtRelease, rootAtRelease = nil, nil
    uiRefresh()
end

local function beginRelease()
    if state == "release" or state == "idle" then return end
    local cam = workspace.CurrentCamera
    if not cam or not camAtRelease and not controlledRoot then
        done()
        return
    end
    camAtRelease = cam.CFrame
    rootAtRelease = controlledRoot and controlledRoot.Position or firstRootPos
    state = "release"
    releaseClock = 0
    -- CameraModule resumes here; V5 blends it in on each rendered frame.
    if cam == cameraBefore then
        if subjectBefore and subjectBefore.Parent then
            cam.CameraSubject = subjectBefore
        end
        cam.CameraType = typeBefore or Enum.CameraType.Custom
    else
        cam.CameraType = Enum.CameraType.Custom
    end
    uiRefresh()
end

local function render(dt)
    if destroyed or state == "idle" then return end
    dt = math.clamp(dt, 0, 0.075)
    local cam = workspace.CurrentCamera
    if not cam then done() return end

    if state == "release" then
        local native = cam.CFrame -- read after Roblox CameraModule updates
        local _, currentRoot = character()
        local moved = currentRoot and rootAtRelease
            and (currentRoot.Position - rootAtRelease) or Vector3.zero
        local anchor = camAtRelease and (CFrame.new(moved) * camAtRelease) or native
        releaseClock = math.min(cfg.releaseTime, releaseClock + dt)
        local t = smooth(releaseClock / cfg.releaseTime)
        cam.CFrame = anchor:Lerp(native, t)
        if releaseClock >= cfg.releaseTime then done() end
        return
    end

    local h, root = character()
    if not h or not root or root ~= controlledRoot or h ~= controlledHumanoid then
        beginRelease()
        return
    end

    -- Keep native character movement in charge; only its yaw is altered.
    if h.AutoRotate then h.AutoRotate = false end
    if state == "spinning" then
        local target = math.rad(cfg.speed * cfg.direction)
        currentRate = currentRate + (target - currentRate)
            * (1 - math.exp(-dt / cfg.acceleration))
    elseif state == "braking" then
        brakeClock = math.min(cfg.brakeTime, brakeClock + dt)
        currentRate = brakeRate * (1 - smooth(brakeClock / cfg.brakeTime))
    end

    -- One shared angular step drives both the avatar and the camera.
    local delta = currentRate * dt
    accumulatedYaw = (accumulatedYaw + delta) % (2 * math.pi)

    -- Rotate around the WORLD vertical axis, preserving the avatar's live
    -- pitch/roll, physics position and translations. Never upright-force ragdolls.
    local pos = root.Position
    if math.abs(delta) > 0.000001 then
        root.CFrame = CFrame.new(pos)
            * CFrame.Angles(0, delta, 0)
            * (root.CFrame - pos)
    end

    local focus = pos + Vector3.new(0, cfg.focusHeight, 0)

    -- Fixed-radius orbit RELATIVE TO THE AVATAR (not fixed to the map).
    -- Unlike V3, this cannot accumulate radius error as the player moves:
    -- camera position is recomputed from player's position every single frame.
    local directionYaw = CFrame.Angles(0, accumulatedYaw, 0)
    local direction = directionYaw:VectorToWorldSpace(originalHorizontal)
    local cameraPosition = focus
        + direction * cfg.distance
        + Vector3.new(0, cfg.height, 0)
    local wanted = CFrame.lookAt(cameraPosition, focus)

    if cam.CameraType ~= Enum.CameraType.Scriptable then
        cam.CameraType = Enum.CameraType.Scriptable
    end
    enterClock = math.min(cfg.enterTime, enterClock + dt)
    if firstCam then
        local blend = smooth(enterClock / cfg.enterTime)
        local moved = pos - firstRootPos
        cam.CFrame = (CFrame.new(moved) * firstCam):Lerp(wanted, blend)
        if blend >= 1 then firstCam = nil end
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
    firstCam, firstRootPos = cam.CFrame, root.Position
    local offset = cam.CFrame.Position - root.Position
    local flat = Vector3.new(offset.X, 0, offset.Z)
    if flat.Magnitude < 0.01 then
        -- Fallback when first-person or right above the avatar.
        local back = -cam.CFrame.LookVector
        flat = Vector3.new(back.X, 0, back.Z)
    end
    if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, 1) end
    originalHorizontal = flat.Unit
    accumulatedYaw = 0
    currentRate, brakeRate = 0, 0
    brakeClock, enterClock = 0, 0
    state = "spinning"
    cam.CameraType = Enum.CameraType.Scriptable
    -- This is after default camera and most camera scripts.
    RunService:BindToRenderStep(renderKey, Enum.RenderPriority.Camera.Value + 20, render)
    uiRefresh()
end

local function stop()
    if state ~= "spinning" then return end
    state = "braking"
    brakeRate = currentRate
    brakeClock = 0
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
    Name = "MemeDashSyncSpinV5UI",
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
label("MEMEDASH | SYNC 360 V5", 15, 9, 253, 38, 20, bar)
local minimize = button("_", 270, 7, 46, 42, bar, nil, 26)
local close = button("X", 324, 7, 43, 42, bar, Color3.fromRGB(147, 51, 65), 24)

local toggle = button("ATIVAR GIRO 360", 14, 62, 347, 66, panel, Color3.fromRGB(33, 150, 118), 23)

label("VELOCIDADE", 19, 146, 169, 40, 19)
local speedMinus = button("-", 186, 143, 49, 49)
local speedValue = label("180", 239, 147, 61, 39, 23)
speedValue.TextXAlignment = Enum.TextXAlignment.Center
local speedPlus = button("+", 308, 143, 53, 49)

label("DISTANCIA", 19, 207, 166, 39, 19)
local distanceMinus = button("-", 186, 204, 49, 49)
local distanceValue = label("9", 237, 207, 70, 39, 20)
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
    toggle.Text = spinning and "PARAR SUAVEMENTE"
        or busy and "DESACELERANDO..." or "ATIVAR GIRO 360"
    miniButton.Text = spinning and "PARAR GIRO"
        or busy and "PARANDO..." or "ATIVAR GIRO"
    local shade = spinning and Color3.fromRGB(181, 68, 77)
        or Color3.fromRGB(33, 150, 118)
    toggle.BackgroundColor3 = shade
    miniButton.BackgroundColor3 = shade
    speedValue.Text = tostring(cfg.speed)
    distanceValue.Text = tostring(cfg.distance)
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
    cfg.distance = math.max(6, cfg.distance - 1)
    uiRefresh()
end)
connect(distancePlus.MouseButton1Click, function()
    cfg.distance = math.min(13, cfg.distance + 1)
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
