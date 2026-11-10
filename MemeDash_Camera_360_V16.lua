-- MemeDash Sync 360 V16 | 2026-11-10 | Delta iOS
-- Resolucao direcionada ao tranco quando OFF sem tocar a tela.
-- ClassicCamera usa lastUserPanCamera; dedo em movimento renova contador.
-- V16 ao desligar sincroniza CameraModule disponivel e emite
-- UM delta quase zero em CameraInput.getRotation, temporariamente.
-- ON: formulas de giro e camera da V15 INTACTAS; 560/s anti-horario.
-- OFF: solta render imediatamente e nao reescreve CFrame apos parar.
-- So um circulo no PlayerGui, mesmo nome/chave do Mover Botoes.
-- Nao altera CameraType, zoom, inclinacao ou controles de toque.
-- V15 preservada. Validacao estatica apenas, teste no aparelho necessario.

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
local renderKey = "MemeDashSync360V16"
for _, oldKey in ipairs({
    "MemeDashSyncSpin360V3", "MemeDashSyncSpin360V5",
    "MemeDashSyncSpin360V6", "MemeDashSyncSpin360V7",
    "MemeDashSync360V8", "MemeDashSync360V9", "MemeDashSync360V10", "MemeDashSync360V11",
    "MemeDashSync360V12", "MemeDashSync360V13", "MemeDashSync360V14", "MemeDashSync360V15", "MemeDashCamera360_Render", "MemeDash360SpinEffect",
    renderKey
}) do
    pcall(function() RunService:UnbindFromRenderStep(oldKey) end)
end

local cfg = {
    speed = 560,
    direction = -1,
    acceleration = 0.10,
}

-- idle: CameraModule controla camera e entrada do usuario
-- arming: captura pose do camera nativa no primeiro RenderStep
-- spinning: macro faz overlay apos CameraModule; unico modo ativo
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

-- Igual ao que acontece quando o usuario move a camera com o dedo:
-- ClassicCamera reseta lastUserPanCamera sempre que getRotation() e nao-zero.
-- Esse metodo remove o tranco de auto-alinhamento SEM travar Camera.CFrame.
local function primeNativeCameraAtStop()
    local ps = player:FindFirstChildOfClass("PlayerScripts")
        or player:FindFirstChild("PlayerScripts")
    local playerModule = ps and ps:FindFirstChild("PlayerModule")
    local cameraModuleScript = playerModule and playerModule:FindFirstChild("CameraModule")
    if not cameraModuleScript then return false end
    local cam = workspace.CurrentCamera
    if not cam then return false end

    -- API interna opcional: algumas builds retornam {} de CameraModule,
    -- por isso o bloqueio deve funcionar tambem sem acesso a esse objeto.
    pcall(function()
        local api = require(cameraModuleScript)
        if type(api) ~= "table" then return end
        local controller = api.activeCameraController
        if type(controller) ~= "table" then return end
        controller.lastCameraTransform = cam.CFrame
        controller.lastCameraFocus = cam.Focus
        controller.lastUserPanCamera = tick()
        controller.resetCameraAngle = false
    end)

    -- Fallback essencial: a camera normalmente consome este ModuleScript
    -- por referencia, entao 1 delta infinitesimal reinicia o contador de pan.
    local cameraInputScript = cameraModuleScript:FindFirstChild("CameraInput")
    if not cameraInputScript then return false end
    local ok, cameraInput = pcall(require, cameraInputScript)
    if not ok or type(cameraInput) ~= "table"
        or type(cameraInput.getRotation) ~= "function" then
        return false
    end

    local prior = cameraInput.getRotation
    local patched
    patched = function(...)
        if cameraInput.getRotation == patched then
            cameraInput.getRotation = prior
        end
        local actual = prior(...)
        if typeof(actual) == "Vector2" and actual.Magnitude < 0.0000001 then
            -- Epsilon ≈ 0,000057 graus, imperceptivel, mas conta como pan.
            return Vector2.new(0.000001, 0)
        end
        return actual
    end
    cameraInput.getRotation = patched

    -- Se CameraModule nao requisitar getRotation (ex.: camera customizada),
    -- restaura a tabela automaticamente sem hooks permanentes.
    task.delay(0.35, function()
        if cameraInput.getRotation == patched then
            cameraInput.getRotation = prior
        end
    end)
    return true
end

local function finish()
    -- Fundamental: nao tocamos CameraType nem Camera.CFrame ao sair.
    -- A CameraModule sempre esteve em controle e agora assume o
    -- frame seguinte sem ficar bloqueada por outro RenderStep.
    state = "idle"
    pcall(function() RunService:UnbindFromRenderStep(renderKey) end)
    -- CameraModule permanece em Custom desde o inicio.
    -- Sincroniza a pose que ele deve assumir no quadro seguinte ao OFF,
    -- ANTES de devolver o AutoRotate e sem escrever camera CFrame.
    pcall(primeNativeCameraAtStop) -- a camera customizada nunca impede a limpeza
    releaseAvatar()
    controlledHumanoid, controlledRoot, originalAutoRotate = nil, nil, nil
    savedCamera, savedCameraType, savedCameraSubject = nil, nil, nil
    relativeCamera, relativeFocus = nil, nil
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
    -- Overlay da pose do giro, sem desativar os controles nativos.
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
    -- Um toque = corte seco no giro. Sem freada, sem camera HOLD,
    -- sem trocar CameraType, sem redefinir a orientacao do usuario.
    finish()
end

local function toggleSpin()
    if state == "idle" then start() else stop() end
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
