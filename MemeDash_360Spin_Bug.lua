-- MemeDash 360 Spin Bug
-- Uses the same camera-offset pattern as MicroCam.lua:
-- remove our previous offset after the game camera updates, then apply a fresh one.

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
local spinAngle = 0
local previousOffset = CFrame.identity
local bindName = "MemeDash360SpinEffect"
local SPEED_DEGREES_PER_SECOND = 1440 -- 4 full turns per second

local gui = Instance.new("ScreenGui")
gui.Name = "MemeDash360SpinControls"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = playerGui

local toggle = Instance.new("TextButton")
toggle.Name = "SpinToggle"
toggle.Size = UDim2.fromOffset(100, 42)
toggle.Position = UDim2.new(1, -116, 0, 24)
toggle.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggle.Text = "SPIN: OFF"
toggle.TextSize = 14
toggle.Font = Enum.Font.GothamBold
toggle.Parent = gui
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)

toggle.Activated:Connect(function()
    enabled = not enabled
    if enabled then
        spinAngle = 0
    end
    toggle.Text = enabled and "SPIN: ON" or "SPIN: OFF"
    toggle.BackgroundColor3 = enabled and Color3.fromRGB(25, 190, 105) or Color3.fromRGB(40, 40, 48)
end)

local function cleanup()
    alive = false
    enabled = false
    pcall(function()
        RunService:UnbindFromRenderStep(bindName)
    end)
    if gui.Parent then
        gui:Destroy()
    end
end

_G.MemeDash360Cleanup = cleanup

RunService:BindToRenderStep(bindName, Enum.RenderPriority.Last.Value + 100, function(dt)
    local camera = workspace.CurrentCamera
    if not camera then
        previousOffset = CFrame.identity
        return
    end

    -- Match MicroCam: undo only the offset we applied on the previous frame.
    if previousOffset ~= CFrame.identity then
        camera.CFrame = camera.CFrame * previousOffset:Inverse()
        previousOffset = CFrame.identity
    end

    if not enabled then return end

    spinAngle = (spinAngle + math.rad(SPEED_DEGREES_PER_SECOND * dt)) % (2 * math.pi)
    previousOffset = CFrame.Angles(0, spinAngle, 0)
    camera.CFrame = camera.CFrame * previousOffset
end)

gui.Destroying:Connect(function()
    if alive then
        alive = false
        enabled = false
        pcall(function()
            RunService:UnbindFromRenderStep(bindName)
        end)
    end
end)
