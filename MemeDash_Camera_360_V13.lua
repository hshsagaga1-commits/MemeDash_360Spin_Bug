-- MemeDash Sync 360 V13 | 2026-11-10 | Delta iOS
-- Usa a rotacao personagem+camera da V12 APROVADA, sem alteracoes.
-- ON: referencia capturada no RenderStep apos CameraModule, SEM salto.
-- OFF: cancela giro no instante; HOLD mantem ultimo CFrame e Focus.
-- HOLD segue deslocamento REAL do jogador, sem nova rotacao orbital.
-- Camera nativa segue ativa em HOLD para transparencia da primeira pessoa,
-- mas pose exibida e preservada ao final de cada frame.
-- Reativacao recaptura pose HOLD sem trocar zoom/altura/angulo.
-- Circle do Mover Botoes mantem nome/texto/ScreenGui da V12.
-- V12 e V8 preservadas; ainda exige validacao real no iPhone.

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
local renderKey = "MemeDashSync360V13"
for _, oldKey in ipairs({
    "MemeDashSyncSpin360V3", "MemeDashSyncSpin360V5",
    "MemeDashSyncSpin360V6", "MemeDashSyncSpin360V7",
    "MemeDashSync360V8", "MemeDashSync360V9", "MemeDashSync360V10", "MemeDashSync360V11",
    "MemeDashSync360V12", "MemeDashCamera360_Render", "MemeDash360SpinEffect",
    renderKey
}) do
    pcall(function() RunService:UnbindFromRenderStep(oldKey) end)
end

local cfg = {
    speed = 560,
    direction = -1,
    acceleration = 0.10,
}

-- idle: nao ligado | arming: captura pose apos camera nativa
-- spinning: rotacao | held: rotacao zero, camera no angulo final
local state = "idle"
local currentSpeed = 0
local yaw = 0
local controlledHumanoid, controlledRoot, originalAutoRotate
local savedCamera, savedCameraType, savedCameraSubject
local relativeCamera, relativeFocus
local heldCamPose, heldFocusPosition, heldRootPosition
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
    heldCamPose, heldFocusPosition, heldRootPosition = nil, nil, nil
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
        -- CameraModule ja renderizou neste frame (nossa prioridade e posterior).
        -- Capturar agora evita a mudanca vista quando se ativava a V12.
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
        cam.CameraType = Enum.CameraType.Scriptable
        state = "spinning"
        uiRefresh()
        return  -- sem alterar CFrame nem Focus sequer no quadro da ativacao
    end

    if h ~= controlledHumanoid or root ~= controlledRoot
        or cam ~= savedCamera then
        finish()
        return
    end

    if state == "held" then
        -- Congela EXATAMENTE o ultimo angulo/zoom/pitch da camera.
        -- Somente acompanha deslocamento real de avatar, inclusive no ar.
        local translation = root.Position - heldRootPosition
        cam.CFrame = CFrame.new(translation) * heldCamPose
        cam.Focus = CFrame.new(heldFocusPosition + translation)
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
    if cam.CameraType ~= Enum.CameraType.Scriptable then
        cam.CameraType = Enum.CameraType.Scriptable
    end
    cam.CFrame = bodyYawFrame * relativeCamera
    cam.Focus = CFrame.new(bodyYawFrame:PointToWorldSpace(relativeFocus))
end

local function start()
    if destroyed then return end
    if state == "idle" then
        local h, root = getChar()
        local cam = workspace.CurrentCamera
        if not h or not root or not cam then return end
        -- Nao mexa na camera neste clique. O render captura o frame ATUAL.
        state = "arming"
        RunService:BindToRenderStep(
            renderKey, Enum.RenderPriority.Last.Value - 1, render
        )
        uiRefresh()
    elseif state == "held" then
        local h, root = getChar()
        local cam = workspace.CurrentCamera
        if not h or root ~= controlledRoot or h ~= controlledHumanoid
            or cam ~= savedCamera then
            finish()
            return
        end
        -- Reativar no mesmo angulo congelado, sem recenter/zoom.
        local delta = root.Position - heldRootPosition
        local frozenCam = CFrame.new(delta) * heldCamPose
        local frozenFocus = heldFocusPosition + delta
        yaw = flatYaw(root.CFrame, yaw)
        local reference = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
        relativeCamera = reference:ToObjectSpace(frozenCam)
        relativeFocus = reference:PointToObjectSpace(frozenFocus)
        cam.CFrame = frozenCam
        cam.Focus = CFrame.new(frozenFocus)
        currentSpeed = 0
        h.AutoRotate = false
        cam.CameraType = Enum.CameraType.Scriptable
        state = "spinning"
        uiRefresh()
    end
end

local function stop()
    if state == "arming" then
        finish()
        return
    end
    if state ~= "spinning" then return end
    local h, root = getChar()
    local cam = workspace.CurrentCamera
    if not h or root ~= controlledRoot or cam ~= savedCamera then
        finish()
        return
    end

    -- SEM freio, SEM retorno horario: copia exatamente pose do ultimo render.
    currentSpeed = 0
    heldCamPose = cam.CFrame
    heldFocusPosition = cam.Focus.Position
    heldRootPosition = root.Position
    state = "held"

    -- CameraModule continua processando primeira pessoa/transparencia.
    -- A camera VISUAL e reposta pelo render held a cada frame.
    if h.Parent then h.AutoRotate = originalAutoRotate end
    returnNativeCamera()
    uiRefresh()
end

local function toggleSpin()
    if state == "spinning" or state == "arming" then
        stop()
    elseif state == "held" or state == "idle" then
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
