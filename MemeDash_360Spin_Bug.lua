-- MemeDash 360 Spin Bug | Roblox Mobile
-- Mantem a UI/toggle do MicroCam, mas substitui o tremor por giro real da tela.
-- O roll usa o eixo Z da camera: a imagem gira em torno do centro, sem virar a direcao da personagem.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if not player then return end
local playerGui = player:WaitForChild("PlayerGui")

if _G.MemeDash360Cleanup then
    pcall(_G.MemeDash360Cleanup)
end

local enabled = false
local alive = true
local bindName = "MemeDash360SpinEffect"
local previousOffset = CFrame.identity
local spinAngle = 0
local SPEED_DEGREES_PER_SECOND = 540 -- 1,5 volta por segundo

local gui = Instance.new("ScreenGui")
gui.Name = "MicroGlitchUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = playerGui

-- Mesmo botao do MicroCam: pequeno, redondo, com ponto preto.
local button = Instance.new("ImageButton")
button.Name = "GlitchToggle"
button.Size = UDim2.fromOffset(26, 26)
button.Position = UDim2.new(0.78, 0, 0.65, 0)
button.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
button.BackgroundTransparency = 0.35
button.ImageTransparency = 1
button.AutoButtonColor = true
button.Active = true
button.Parent = gui

local round = Instance.new("UICorner")
round.CornerRadius = UDim.new(1, 0)
round.Parent = button

local dot = Instance.new("Frame")
dot.Name = "PositionDot"
dot.Size = UDim2.fromOffset(3, 3)
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dot.BorderSizePixel = 0
dot.Active = false
dot.ZIndex = button.ZIndex + 1
dot.Parent = button

button.Activated:Connect(function()
    enabled = not enabled
    if enabled then spinAngle = 0 end
    button.BackgroundColor3 = enabled and Color3.fromRGB(25, 190, 105) or Color3.fromRGB(40, 40, 48)
end)

local function cleanup()
    alive = false
    enabled = false
    pcall(function() RunService:UnbindFromRenderStep(bindName) end)
    if gui.Parent then gui:Destroy() end
end

_G.MemeDash360Cleanup = cleanup

RunService:BindToRenderStep(bindName, Enum.RenderPriority.Last.Value + 100, function(dt)
    local camera = workspace.CurrentCamera
    if not camera then
        previousOffset = CFrame.identity
        return
    end

    -- Remove o efeito anterior depois que a camera do jogo atualiza.
    if previousOffset ~= CFrame.identity then
        camera.CFrame = camera.CFrame * previousOffset:Inverse()
        previousOffset = CFrame.identity
    end

    if not enabled then return end

    spinAngle = (spinAngle + math.rad(SPEED_DEGREES_PER_SECOND * dt)) % (2 * math.pi)
    -- Roll absoluto no eixo Z: gira a tela inteira, nao faz tremidinhas de yaw.
    previousOffset = CFrame.Angles(0, 0, spinAngle)
    camera.CFrame = camera.CFrame * previousOffset
end)

gui.Destroying:Connect(function()
    if alive then
        alive = false
        enabled = false
        pcall(function() RunService:UnbindFromRenderStep(bindName) end)
    end
end)
