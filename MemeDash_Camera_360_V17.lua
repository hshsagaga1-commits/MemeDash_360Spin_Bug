-- MemeDash Sync 360 V17 | 2026-11-10 | Delta iOS
-- OFF para o giro INSTANTANEAMENTE, sem freio nem rotacao reversa.
-- Correcao real: o nativo atualiza camera ANTES do macro; apos OFF,
-- pode readquirir direcao diferente, causando tranco sem toque.
-- No modo guarded, camera conserva orientacao final, seguindo somente
-- posicao do avatar; primeira interacao real da camera encerra guarded.
-- CameraModule segue ativo para gestos/primeira pessoa; ele nunca e
-- trocado para Scriptable. Avatar nunca tem velocidade artificial.
-- Quando acessivel, sincroniza ultimo CFrame do controlador nativo.
-- Nao intercepta nem injeta getRotation; codigo 560/s preservado.
-- Botao e posicao do Mover Botoes preservados. Requer teste no iPhone.

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
local renderKey = "MemeDashSync360V17"
for _, oldKey in ipairs({
    "MemeDashSyncSpin360V3", "MemeDashSyncSpin360V5",
    "MemeDashSyncSpin360V6", "MemeDashSyncSpin360V7",
    "MemeDashSync360V8", "MemeDashSync360V9", "MemeDashSync360V10", "MemeDashSync360V11",
    "MemeDashSync360V12", "MemeDashSync360V13", "MemeDashSync360V14", "MemeDashSync360V15", "MemeDashSync360V16", "MemeDashCamera360_Render", "MemeDash360SpinEffect",
    renderKey
}) do
    pcall(function() RunService:UnbindFromRenderStep(oldKey) end)
end

local cfg = {
    speed = 560,
    direction = -1,
    acceleration = 0.10,
}

-- idle: camera 100% nativa
-- arming: captura pose nativa apos CameraModule
-- spinning: giro em 560/s
-- guarded: giro ZERO e camera estabilizada; input real reativa nativa
local state = "idle"
local currentSpeed = 0
local yaw = 0
local controlledHumanoid, controlledRoot, originalAutoRotate
local savedCamera, savedCameraType, savedCameraSubject
local relativeCamera, relativeFocus
local guardCamPose, guardRootPosition, guardRoot, guardCamera
local guardNativeController, guardCameraInput, guardManualMove
local guardFrameCount, guardReleaseReason = 0, "none"
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

local function getNativeCameraController()
    local scripts = player:FindFirstChild("PlayerScripts")
    local module = scripts and scripts:FindFirstChild("PlayerModule")
    local camModule = module and module:FindFirstChild("CameraModule")
    if not camModule then return nil, nil end
    local controller, input
    local ok, api = pcall(require, camModule)
    if ok and type(api) == "table" then
        controller = api.activeCameraController
    end
    local source = camModule:FindFirstChild("CameraInput")
    if source then
        local inputOK, inputAPI = pcall(require, source)
        if inputOK and type(inputAPI) == "table" then input = inputAPI end
    end
    return controller, input
end

local function syncNativeController(cam)
    -- Nao sobrescrever funcoes internas nem campos se controller indisponivel.
    local controller = guardNativeController
    if type(controller) ~= "table" then return end
    pcall(function()
        if controller.lastCameraTransform ~= nil then
            controller.lastCameraTransform = cam.CFrame
        end
        if controller.lastCameraFocus ~= nil then
            controller.lastCameraFocus = cam.Focus
        end
        if type(controller.lastUserPanCamera) == "number" then
            -- Impede follow auto de girar a camera ao soltar o botao.
            controller.lastUserPanCamera = tick()
        end
        if controller.resetCameraAngle ~= nil then
            controller.resetCameraAngle = false
        end
    end)
end

local function isCameraBeingMoved()
    if guardManualMove then return true end
    local input = guardCameraInput
    if input and type(input.getRotationActivated) == "function" then
        local ok, panning = pcall(input.getRotationActivated)
        if ok and panning then return true end
    end
    return false
end

local finish -- forward declaration: beginGuard pode encerrar em erro

local function beginGuard()
    local cam = workspace.CurrentCamera
    local _, root = getChar()
    if not cam or not root then
        finish()
        return
    end
    -- Capture exatamente o ultimo quadro exibido, SEM refazer zoom/angulos.
    guardCamPose = cam.CFrame
    guardRootPosition = root.Position
    guardRoot = root
    guardCamera = cam
    guardManualMove = false
    guardFrameCount = 0
    guardReleaseReason = "none"
    guardNativeController, guardCameraInput = getNativeCameraController()
    currentSpeed = 0
    state = "guarded"

    -- Movimento volta ao Humanoid; jamais reescrevemos a velocidade linear.
    releaseAvatar()
    savedCamera, savedCameraType, savedCameraSubject = nil, nil, nil
    relativeCamera, relativeFocus = nil, nil
    syncNativeController(cam)
    uiRefresh()
end

finish = function()
    -- Limpeza real, inclusive quando PlayerGui e destruida.
    state = "idle"
    pcall(function() RunService:UnbindFromRenderStep(renderKey) end)
    releaseAvatar()
    savedCamera, savedCameraType, savedCameraSubject = nil, nil, nil
    relativeCamera, relativeFocus = nil, nil
    guardCamPose, guardRootPosition, guardRoot, guardCamera = nil, nil, nil, nil
    guardNativeController, guardCameraInput = nil, nil
    guardManualMove = false
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

    if state == "guarded" then
        if cam ~= guardCamera or root ~= guardRoot then
            guardReleaseReason = "character_or_camera_changed"
            finish()
            return
        end
        -- Ao primeiro swipe/pan real, CameraModule assume no mesmo frame.
        -- Nenhuma escrita em CFrame depois do desbloqueio.
        if isCameraBeingMoved() then
            guardReleaseReason = "manual_camera_input"
            finish()
            return
        end
        -- ZERO velocidade angular imediatamente: posicao segue o avatar,
        -- mas nao altera yaw, pitch, zoom nem sentido de giro.
        local translation = root.Position - guardRootPosition
        cam.CFrame = CFrame.new(translation) * guardCamPose
        -- O Focus nativo ja foi atualizado nesse quadro e fica intacto.
        syncNativeController(cam)
        guardFrameCount += 1
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
    -- Overlay da pose do giro, sem desativar os controles nativos.
    cam.CFrame = bodyYawFrame * relativeCamera
    cam.Focus = CFrame.new(bodyYawFrame:PointToWorldSpace(relativeFocus))
end

local function start()
    if destroyed or (state ~= "idle" and state ~= "guarded") then return end
    local h, root = getChar()
    local cam = workspace.CurrentCamera
    if not h or not root or not cam then return end
    if state == "guarded" then
        -- ReON: recaptura do ultimo quadro guardado; nao reseta para uma
        -- pose velha da camera nativa, evitando tranco no rearm.
        local delta = root.Position - guardRootPosition
        local pose = CFrame.new(delta) * guardCamPose
        yaw = flatYaw(root.CFrame, 0)
        local reference = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
        relativeCamera = reference:ToObjectSpace(pose)
        relativeFocus = reference:PointToObjectSpace(cam.Focus.Position)
        controlledHumanoid, controlledRoot = h, root
        originalAutoRotate = h.AutoRotate
        savedCamera, savedCameraType, savedCameraSubject =
            cam, cam.CameraType, cam.CameraSubject
        currentSpeed = 0
        h.AutoRotate = false
        state = "spinning"
        guardCamPose, guardRootPosition, guardRoot, guardCamera = nil, nil, nil, nil
        guardNativeController, guardCameraInput = nil, nil
        guardManualMove = false
        uiRefresh()
        return
    end
    state = "arming"
    RunService:BindToRenderStep(
        renderKey, Enum.RenderPriority.Last.Value - 1, render
    )
    uiRefresh()
end

local function stop()
    if state ~= "spinning" and state ~= "arming" then return end
    if state == "arming" then
        finish()
    else
        -- Giro instantaneamente zero; apenas a camera permanece estavel
        -- ate toque do jogador. Nao ha blend/rotacao horaria de release.
        beginGuard()
    end
end

local function toggleSpin()
    if state == "idle" or state == "guarded" then
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
-- Fallback para versoes de CameraModule que nao exportam getRotationActivated.
-- Nao captura toque: apenas observa movimento NA AREA DA CAMERA, sem joystick.
connect(UIS.TouchMoved, function(input, processed)
    if state ~= "guarded" or processed then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local x = input.Position.X
    if x > cam.ViewportSize.X * 0.40 then
        guardManualMove = true
    end
end)
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
