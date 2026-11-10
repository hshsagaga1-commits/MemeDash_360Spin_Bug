-- MemeDash Sync 360 V20 | Delta iOS | Native CameraInput
-- FIX V19: a camera nao girava pois CameraModule sobrescrevia CFrame.
-- V20 nao escreve Camera.CFrame nem Camera.Focus em momento algum.
-- Em vez disso, injeta yaw no CameraInput.getRotation ORIGINAL do Roblox.
-- A CameraModule produz e guarda a camera FINAL todo frame.
-- Avatar gira EXATAMENTE no mesmo callback que aplica delta nativo.
-- Ao OFF remove hook + RenderStep, sem HOLD, sem blend e sem tranco
-- causado por entregar camera com orientacao diferente.
-- 590 graus/s, anti-horario. Preserva os controles de toque nativos.
-- Se CameraInput nao estiver disponivel, NAO inicia giro so do avatar.
-- Se CameraModule nao consumir getRotation, para automaticamente.
-- Botao circular conservado para a posicao do Mover Botoes.
-- EXPERIMENTAL: nao validado em aparelho/servidor real.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
if not player then return end

local env = (getgenv and getgenv()) or _G
local key = "__MemeDashCamera360"
if type(env[key]) == "table" and type(env[key].Destroy) == "function" then
    pcall(env[key].Destroy)
end

local renderKey = "MemeDashSync360V20"
for _, oldKey in ipairs({
    "MemeDashSyncSpin360V3", "MemeDashSyncSpin360V5",
    "MemeDashSyncSpin360V6", "MemeDashSyncSpin360V7",
    "MemeDashSync360V8", "MemeDashSync360V9", "MemeDashSync360V10",
    "MemeDashSync360V11", "MemeDashSync360V12", "MemeDashSync360V13",
    "MemeDashSync360V14", "MemeDashSync360V15", "MemeDashSync360V16",
    "MemeDashSync360V17", "MemeDashSync360V18", "MemeDashSync360V19",
    "MemeDashCamera360_Render", "MemeDash360SpinEffect", renderKey
}) do
    pcall(function() RunService:UnbindFromRenderStep(oldKey) end)
end

local cfg = {
    speed = 590,
    direction = -1,
    acceleration = 0.10,
}

local state = "idle"
local yaw = 0
local currentSpeed = 0
local pendingDelta = 0
local missedFrames = 0
local trackedHumanoid, trackedRoot, oldAutoRotate
local inputAPI, originalGetRotation, wrappedGetRotation
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
    local f = cf.LookVector
    if f.X * f.X + f.Z * f.Z > 0.075 then
        return math.atan2(-f.X, -f.Z)
    end
    return fallback or 0
end

local function findCameraInput()
    local playerScripts = player:FindFirstChild("PlayerScripts")
    local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
    local cameraModule = playerModule and playerModule:FindFirstChild("CameraModule")
    local inputScript = cameraModule and cameraModule:FindFirstChild("CameraInput")
    if not inputScript then return nil end
    local ok, module = pcall(require, inputScript)
    if not ok or type(module) ~= "table"
        or type(module.getRotation) ~= "function" then
        return nil
    end
    return module
end

local function stop(reason)
    if state == "idle" then return end
    state = "idle"
    pendingDelta = 0
    currentSpeed = 0
    pcall(function() RunService:UnbindFromRenderStep(renderKey) end)

    -- Nao modificar metodos de CameraInput de outros scripts.
    if inputAPI and inputAPI.getRotation == wrappedGetRotation then
        inputAPI.getRotation = originalGetRotation
    end
    inputAPI, originalGetRotation, wrappedGetRotation = nil, nil, nil

    if trackedHumanoid and trackedHumanoid.Parent then
        pcall(function() trackedHumanoid.AutoRotate = oldAutoRotate end)
    end
    trackedHumanoid, trackedRoot, oldAutoRotate = nil, nil, nil
    missedFrames = 0
    uiRefresh()
    if reason then
        warn("[MemeDash 360 V20] " .. reason)
    end
end

local function rotateAvatar(delta)
    if not trackedRoot or not trackedHumanoid
        or trackedHumanoid.Health <= 0
        or trackedRoot.Parent == nil then
        return false
    end

    -- Mesma geometria do giro V18, agora acionada NO MOMENTO em que
    -- a CameraModule consome o delta de rotacao da camera.
    yaw = yaw + delta
    local before = trackedRoot.CFrame
    local pos = before.Position
    local physicalYaw = flatYaw(before, yaw)
    local tilt = CFrame.Angles(0, -physicalYaw, 0) * before.Rotation
    trackedRoot.CFrame =
        CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * tilt
    return true
end

local function prepareFrame(dt)
    if destroyed or state ~= "spinning" then return end

    -- Se a camera nativa nao consome o hook, o avatar NAO gira sozinho.
    if pendingDelta ~= 0 then
        missedFrames = missedFrames + 1
        if missedFrames >= 12 then
            stop("CameraModule nao consumiu CameraInput.getRotation; giro cancelado.")
            return
        end
    else
        missedFrames = 0
    end

    local hum, root = getChar()
    if hum ~= trackedHumanoid or root ~= trackedRoot then
        stop("Personagem mudou; macro desligado.")
        return
    end
    if hum.AutoRotate then hum.AutoRotate = false end

    dt = math.clamp(dt, 0, 0.066)
    local goal = math.rad(cfg.speed * cfg.direction)
    currentSpeed = currentSpeed
        + (goal - currentSpeed) * (1 - math.exp(-dt / cfg.acceleration))
    pendingDelta = currentSpeed * dt
end

local function start()
    if state ~= "idle" or destroyed then return end
    local hum, root = getChar()
    local camera = workspace.CurrentCamera
    if not hum or not root or not camera then return end

    local module = findCameraInput()
    if not module then
        warn("[MemeDash 360 V20] CameraInput nativo indisponivel; sem giro parcial.")
        return
    end

    inputAPI = module
    originalGetRotation = module.getRotation
    trackedHumanoid, trackedRoot = hum, root
    oldAutoRotate = hum.AutoRotate
    yaw = flatYaw(root.CFrame, 0)
    currentSpeed, pendingDelta, missedFrames = 0, 0, 0

    local prior = originalGetRotation
    wrappedGetRotation = function(...)
        local native = prior(...)
        if state ~= "spinning" or pendingDelta == 0 then
            return native
        end
        if typeof(native) ~= "Vector2" then
            return native
        end

        local step = pendingDelta
        pendingDelta = 0
        if not rotateAvatar(step) then
            task.defer(function()
                stop("Rotacao do avatar indisponivel.")
            end)
            return native
        end

        -- BaseCamera: newLook = CFrame.Angles(0, -rotateInput.X, 0)
        -- Portanto X negativo do delta de yaw sincroniza sentido e ritmo.
        -- A CameraModule tambem recebe os gestos NORMAIS do usuario.
        return native + Vector2.new(-step, 0)
    end

    -- Instalado ANTES de vincular o step; CameraModule ja usa a mesma
    -- tabela CameraInput via require. Sem controlar Camera.CFrame.
    module.getRotation = wrappedGetRotation
    state = "spinning"
    hum.AutoRotate = false
    RunService:BindToRenderStep(
        renderKey, Enum.RenderPriority.Camera.Value - 1, prepareFrame
    )
    uiRefresh()
end

local function toggleSpin()
    if state == "idle" then start() else stop() end
end

local function destroy()
    if destroyed then return end
    destroyed = true
    stop()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end

-- Controlador circular em PlayerGui para ser selecionado pelo Mover Botoes.
local gui=Instance.new("ScreenGui")
gui.Name="MemeDashSync360V12UI"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=3000
gui.Parent=player:WaitForChild("PlayerGui")
local circle=Instance.new("TextButton")
circle.Name="Spin360MoveButton"
circle.Size=UDim2.fromOffset(68,68)
circle.AnchorPoint=Vector2.new(0.5,0.5)
circle.Position=UDim2.fromScale(0.85,0.38)
circle.BackgroundColor3=Color3.fromRGB(65,73,88)
circle.BorderSizePixel=0
circle.Text="360"
circle.TextColor3=Color3.fromRGB(255,255,255)
circle.TextSize=19
circle.Font=Enum.Font.GothamBold
circle.AutoButtonColor=false
circle.Active=true
circle.Parent=gui
local round=Instance.new("UICorner")
round.CornerRadius=UDim.new(1,0)
round.Parent=circle
local edge=Instance.new("UIStroke")
edge.Thickness=2
edge.Color=Color3.fromRGB(93,112,140)
edge.Parent=circle
uiRefresh=function()
    if destroyed or not circle.Parent then return end
    local on=state=="spinning" or state=="arming"
    circle.BackgroundColor3=on and Color3.fromRGB(24,192,92) or Color3.fromRGB(65,73,88)
    circle.Text="360" -- nome/texto estavel para salvar no Mover Botoes
end
connect(circle.Activated,toggleSpin)
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
