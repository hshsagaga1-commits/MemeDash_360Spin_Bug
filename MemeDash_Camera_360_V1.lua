-- MemeDash Camera 360 V1 | iOS / Delta
-- Orbita a camera continuamente em torno do personagem.
-- Nao muda WalkSpeed, velocidade fisica ou CFrame do personagem.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local guiParent = player:WaitForChild("PlayerGui")
local env = (getgenv and getgenv()) or _G
local key = "__MemeDashCamera360"
local old = env[key]
if type(old) == "table" and type(old.Destroy) == "function" then
    pcall(old.Destroy)
end

local renderName = "MemeDashCamera360_Render"
pcall(function() RunService:UnbindFromRenderStep(renderName) end)

local settings = {
    speed = 180,       -- graus por segundo: 360 / 180 = 2s por volta
    radius = 14,       -- abertura da orbita
    height = 8,        -- inclinacao moderada, vista um pouco de cima
    direction = 1,     -- 1 = direita; -1 = esquerda
}
local running, angle, intro = false, 0, 0
local cameraBefore, typeBefore, subjectBefore, initialCFrame
local connections = {}
local destroyed = false
local onStatusChanged = function() end

local function restoreCamera()
    local camera = cameraBefore
    if camera and camera.Parent then
        pcall(function()
            camera.CameraType = typeBefore or Enum.CameraType.Custom
            if subjectBefore and subjectBefore.Parent then
                camera.CameraSubject = subjectBefore
            end
        end)
    end
    cameraBefore, typeBefore, subjectBefore = nil, nil, nil
end

local function stopSpin()
    running = false
    pcall(function() RunService:UnbindFromRenderStep(renderName) end)
    restoreCamera()
    onStatusChanged()
end

local function startSpin()
    if running or destroyed then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local camera = workspace.CurrentCamera
    if not (root and camera) then return end

    cameraBefore = camera
    typeBefore = camera.CameraType
    subjectBefore = camera.CameraSubject
    initialCFrame = camera.CFrame

    local center = root.Position + Vector3.new(0, 1.6, 0)
    local delta = camera.CFrame.Position - center
    angle = math.atan2(delta.X, delta.Z)
    intro = 0
    running = true
    camera.CameraType = Enum.CameraType.Scriptable

    RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
        local cam = workspace.CurrentCamera
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not (cam and hrp) then return end
        if cam.CameraType ~= Enum.CameraType.Scriptable then
            cam.CameraType = Enum.CameraType.Scriptable
        end

        -- Framerate-independent: mesma velocidade a 30 ou 60 FPS.
        angle = (angle + math.rad(settings.speed * settings.direction) * dt) % (math.pi * 2)
        local focus = hrp.Position + Vector3.new(0, 1.6, 0)
        local offset = Vector3.new(
            math.sin(angle) * settings.radius,
            settings.height,
            math.cos(angle) * settings.radius
        )
        local desired = CFrame.lookAt(focus + offset, focus)

        -- Entrada gradual para evitar um corte seco ao ligar.
        if intro < 0.45 then
            intro = math.min(0.45, intro + dt)
            local t = intro / 0.45
            t = t * t * (3 - 2 * t)
            cam.CFrame = initialCFrame:Lerp(desired, t)
        else
            cam.CFrame = desired
        end
        cam.Focus = CFrame.new(focus)
    end)
    onStatusChanged()
end

local function create(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end
local function rounded(parent, pixels)
    create("UICorner", {CornerRadius = UDim.new(0, pixels or 9)}, parent)
end

local screen = create("ScreenGui", {
    Name = "MemeDashCamera360UI", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)
local panel = create("Frame", {
    Size = UDim2.fromOffset(266, 234),
    Position = UDim2.new(0.53, 0, 0.46, 0),
    BackgroundColor3 = Color3.fromRGB(23, 26, 34),
    BorderSizePixel = 0,
    Active = true,
}, screen)
rounded(panel, 12)
create("UIStroke", {Color = Color3.fromRGB(69, 77, 96), Thickness = 1}, panel)

local bar = create("Frame", {
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundTransparency = 1, Active = true,
}, panel)
create("TextLabel", {
    Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -47, 1, 0),
    BackgroundTransparency = 1, Text = "MEMEDASH  |  CAMERA 360",
    TextColor3 = Color3.fromRGB(238, 242, 251),
    TextSize = 13, Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
}, bar)

local function mkButton(text, x, y, w, h, parent)
    local b = create("TextButton", {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = Color3.fromRGB(51, 58, 74),
        BorderSizePixel = 0, AutoButtonColor = true,
        Text = text, TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14, Font = Enum.Font.GothamBold,
    }, parent or panel)
    rounded(b, 8)
    return b
end

local close = mkButton("X", 229, 5, 30, 25, bar)
close.Position = UDim2.fromOffset(229, 5)
local toggle = mkButton("ATIVAR GIRO 360", 12, 41, 242, 37)

local function label(text, x, y, w, h, size)
    return create("TextLabel", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, Text = text,
        TextColor3 = Color3.fromRGB(221, 226, 237),
        TextSize = size or 12, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)
end

label("Velocidade", 12, 91, 90, 24)
local speedMinus = mkButton("-", 103, 90, 29, 27)
local speedValue = label("180°/s", 139, 91, 65, 24)
speedValue.TextXAlignment = Enum.TextXAlignment.Center
local speedPlus = mkButton("+", 216, 90, 37, 27)

label("Distância", 12, 130, 90, 24)
local distMinus = mkButton("-", 103, 129, 29, 27)
local distValue = label("14", 139, 130, 65, 24)
distValue.TextXAlignment = Enum.TextXAlignment.Center
local distPlus = mkButton("+", 216, 129, 37, 27)

label("Sentido", 12, 170, 90, 24)
local directionBtn = mkButton("HORARIO  >", 103, 167, 150, 29)
label("Arraste a barra superior para mover", 12, 207, 242, 17, 10)

local function syncUI()
    if destroyed then return end
    toggle.Text = running and "DESATIVAR GIRO" or "ATIVAR GIRO 360"
    toggle.BackgroundColor3 = running
        and Color3.fromRGB(174, 66, 73)
        or Color3.fromRGB(53, 119, 106)
    speedValue.Text = tostring(settings.speed) .. "°/s"
    distValue.Text = tostring(settings.radius)
    directionBtn.Text = (settings.direction == 1) and "HORARIO  >" or "<  ANTI-HORARIO"
end
onStatusChanged = syncUI

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

connect(toggle.MouseButton1Click, function()
    if running then stopSpin() else startSpin() end
end)
connect(speedMinus.MouseButton1Click, function()
    settings.speed = math.max(60, settings.speed - 30)
    syncUI()
end)
connect(speedPlus.MouseButton1Click, function()
    settings.speed = math.min(540, settings.speed + 30)
    syncUI()
end)
connect(distMinus.MouseButton1Click, function()
    settings.radius = math.max(7, settings.radius - 1)
    syncUI()
end)
connect(distPlus.MouseButton1Click, function()
    settings.radius = math.min(26, settings.radius + 1)
    syncUI()
end)
connect(directionBtn.MouseButton1Click, function()
    settings.direction = -settings.direction
    syncUI()
end)

-- Painel arrastavel no touchscreen e mouse.
local dragging, dragStart, panelStart = false, nil, nil
connect(bar.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        panelStart = panel.Position
        connect(input.Changed, function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
connect(UserInputService.InputChanged, function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local d = input.Position - dragStart
    panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + d.X,
        panelStart.Y.Scale, panelStart.Y.Offset + d.Y)
end)

local function destroy()
    if destroyed then return end
    stopSpin()
    destroyed = true
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    screen:Destroy()
    if env[key] and env[key].Destroy == destroy then env[key] = nil end
end
connect(close.MouseButton1Click, destroy)
env[key] = {Destroy = destroy, Settings = settings}
syncUI()