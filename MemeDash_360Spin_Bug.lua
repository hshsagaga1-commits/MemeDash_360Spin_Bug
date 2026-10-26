-- MemeDash 360 Spin Bug
-- Local camera effect for Roblox. Run as a client-side LocalScript.
-- Stop with the on-screen STOP button or by disabling this script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("MemeDash360SpinControls")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "MemeDash360SpinControls"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local stopButton = Instance.new("TextButton")
stopButton.Name = "StopSpin"
stopButton.Size = UDim2.fromOffset(100, 42)
stopButton.Position = UDim2.new(1, -116, 0, 24)
stopButton.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
stopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
stopButton.Text = "STOP SPIN"
stopButton.TextSize = 14
stopButton.Font = Enum.Font.GothamBold
stopButton.Parent = gui
Instance.new("UICorner", stopButton).CornerRadius = UDim.new(0, 8)

local SPEED_DEGREES_PER_SECOND = 2400 -- 6.67 rotations per second
local running = true
local connection

connection = RunService.RenderStepped:Connect(function(dt)
    if not running then return end
    local camera = workspace.CurrentCamera
    if not camera then return end

    -- Rotate around the camera's local vertical axis, keeping its position fixed.
    local delta = math.rad(SPEED_DEGREES_PER_SECOND * dt)
    camera.CFrame = camera.CFrame * CFrame.Angles(0, delta, 0)
end)

local function stop()
    running = false
    if connection then
        connection:Disconnect()
        connection = nil
    end
    if gui then gui:Destroy() end
end

stopButton.Activated:Connect(stop)
script.Destroying:Connect(stop)
