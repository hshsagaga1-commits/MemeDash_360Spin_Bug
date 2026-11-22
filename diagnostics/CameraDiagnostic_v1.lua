-- MemeDash Camera Diagnostic v1.0
-- Read-only client telemetry. No movement automation, physics writes, camera writes or network.
-- Run once on the client. START, move manually, STOP, then COPY / NEXT.
-- Each page is independent JSON. Send all pages of the same recording.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local parent = player:WaitForChild("PlayerGui")
local NAME = "MemeDashCameraDiagnosticV1"
local previous = parent:FindFirstChild(NAME)
if previous then previous:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = parent
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(252, 112)
panel.Position = UDim2.new(0.5, -126, 0, 12)
panel.BackgroundColor3 = Color3.fromRGB(20, 23, 34)
panel.BackgroundTransparency = 0.12
panel.Parent = gui
local corner = Instance.new("UICorner", panel)
corner.CornerRadius = UDim.new(0, 10)
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -12, 0, 25)
status.Position = UDim2.fromOffset(6, 2)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(220, 238, 255)
status.TextSize = 12
status.Font = Enum.Font.Gotham
status.Text = "Camera diagnostic | READY"
status.Parent = panel
local function button(label, x, y, w)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, 32)
    b.Position = UDim2.fromOffset(x, y)
    b.Text = label
    b.TextColor3 = Color3.new(1,1,1)
    b.BackgroundColor3 = Color3.fromRGB(50, 64, 92)
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.Parent = panel
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end
local start = button("START", 6, 30, 77)
local stop = button("STOP", 87, 30, 77)
local mark = button("MARK", 168, 30, 77)
local copy = button("COPY", 6, 70, 77)
local nextPage = button("NEXT", 87, 70, 77)
local close = button("CLOSE", 168, 70, 77)
local output = Instance.new("TextBox")
output.Size = UDim2.new(0.85, 0, 0.6, 0)
output.Position = UDim2.new(0.075, 0, 0.3, 0)
output.BackgroundColor3 = Color3.fromRGB(20, 23, 34)
output.TextColor3 = Color3.new(1,1,1)
output.TextSize = 12
output.Font = Enum.Font.Code
output.MultiLine = true
output.ClearTextOnFocus = false
output.TextWrapped = true
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.Visible = false
output.Parent = gui

local MAX_SECONDS, MAX_FRAMES, PAGE_SIZE = 20, 2400, 60
local recording, t0, page, session = false, 0, 1, ""
local rows, events, marks = {}, {}, {}
local lastYaw, lastTime, lastVelocity, lastRoot = nil, nil, nil, nil
local touchIds, touchCount, touchSerial = {}, 0, 0
local touchX, touchY, mouseX, mouseY = 0,0,0,0
local connections = {}
local binding = NAME .. "_" .. HttpService:GenerateGUID(false)
local function connect(signal, callback)
    table.insert(connections, signal:Connect(callback))
end
local function round(v)
    if v ~= v or v == math.huge or v == -math.huge then return 0 end
    return math.round(v*1000)/1000
end
local function elapsed() return round(os.clock()-t0) end
local function yaw(v) return math.deg(math.atan2(-v.X, -v.Z)) end
local function wrap(a) return (a+180)%360-180 end
local function event(kind, id, processed)
    if recording and #events < 4000 then
        table.insert(events, {elapsed(),kind,id,processed and 1 or 0})
    end
end
connect(UIS.InputBegan, function(input, gp)
    if input.UserInputType == Enum.UserInputType.Touch then
        touchSerial += 1
        touchIds[input] = touchSerial
        touchCount += 1
        event("touch_begin",touchSerial,gp)
    elseif input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.Gamepad1 then
        event("input_begin",input.KeyCode.Name,gp)
    end
end)
connect(UIS.InputEnded, function(input,gp)
    if input.UserInputType == Enum.UserInputType.Touch then
        if touchIds[input] then
            event("touch_end",touchIds[input],gp)
            touchIds[input] = nil
            touchCount = math.max(0,touchCount-1)
        end
    elseif input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.Gamepad1 then
        event("input_end",input.KeyCode.Name,gp)
    end
end)
connect(UIS.InputChanged, function(input)
    if not recording then return end
    if input.UserInputType == Enum.UserInputType.Touch then
        touchX += input.Delta.X
        touchY += input.Delta.Y
    elseif input.UserInputType == Enum.UserInputType.MouseMovement then
        mouseX += input.Delta.X
        mouseY += input.Delta.Y
    end
end)
connect(UIS.JumpRequest,function() event("jump_request",0,false) end)

local fields = {
    "t_s","render_dt_s","camera_yaw_deg","camera_pitch_deg","camera_dyaw_deg","camera_yaw_rate_deg_s",
    "camera_look_x","camera_look_y","camera_look_z","camera_type",
    "root_yaw_deg","root_x","root_y","root_z","vx","vy","vz","horizontal_speed","speed_3d",
    "horizontal_accel","move_x","move_y","move_z","humanoid_state","floor_material","walk_speed",
    "touch_count","touch_dx_sum","touch_dy_sum","mouse_dx_sum","mouse_dy_sum","has_character"
}
local function stopRecording()
    recording = false
    local total = math.max(1,math.ceil(#rows/PAGE_SIZE))
    status.Text = ("STOPPED | %d frames | %d pages"):format(#rows,total)
end
RunService:BindToRenderStep(binding, Enum.RenderPriority.Camera.Value+1, function(dt)
    if not recording then return end
    local now = os.clock()
    if now-t0 >= MAX_SECONDS or #rows >= MAX_FRAMES then stopRecording(); return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local look = camera.CFrame.LookVector
    local cy = yaw(look)
    local diff = lastYaw and wrap(cy-lastYaw) or 0
    local sampleDt = lastTime and math.max(now-lastTime,0.000001) or math.max(dt,0.000001)
    local c = player.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    local humanoid = c and c:FindFirstChildOfClass("Humanoid")
    local valid = root ~= nil and humanoid ~= nil
    local p = valid and root.Position or Vector3.zero
    local v = valid and root.AssemblyLinearVelocity or Vector3.zero
    local mv = valid and humanoid.MoveDirection or Vector3.zero
    local horizontal = Vector3.new(v.X,0,v.Z).Magnitude
    local accel = valid and lastRoot == root and lastVelocity and (horizontal-lastVelocity)/sampleDt or 0
    table.insert(rows,{
        round(now-t0),round(dt),round(cy),round(math.deg(math.asin(math.clamp(look.Y,-1,1)))),
        round(diff),round(diff/sampleDt),round(look.X),round(look.Y),round(look.Z),camera.CameraType.Name,
        valid and round(yaw(root.CFrame.LookVector)) or 0,round(p.X),round(p.Y),round(p.Z),
        round(v.X),round(v.Y),round(v.Z),round(horizontal),round(v.Magnitude),round(accel),
        round(mv.X),round(mv.Y),round(mv.Z),valid and humanoid:GetState().Name or "Missing",
        valid and humanoid.FloorMaterial.Name or "Missing",valid and round(humanoid.WalkSpeed) or 0,
        touchCount,round(touchX),round(touchY),round(mouseX),round(mouseY),valid and 1 or 0
    })
    lastYaw,lastTime,lastVelocity,lastRoot = cy,now,horizontal,root
    touchX,touchY,mouseX,mouseY = 0,0,0,0
    if #rows%12 == 0 then
        status.Text = ("REC %.1fs | speed %.1f | %d"):format(now-t0,horizontal,#rows)
    end
end)
local function exportPage()
    if recording or #rows == 0 then status.Text = "STOP before exporting"; return nil end
    local total = math.ceil(#rows/PAGE_SIZE)
    page = math.clamp(page,1,total)
    local first, last = (page-1)*PAGE_SIZE+1,math.min(page*PAGE_SIZE,#rows)
    local chunk, chunkEvents, chunkMarks = {},{},{}
    local lower = page==1 and 0 or rows[first][1]
    local upper = page==total and math.huge or rows[last+1][1]
    for i=first,last do table.insert(chunk,rows[i]) end
    for _,e in ipairs(events) do if e[1]>=lower and e[1]<upper then table.insert(chunkEvents,e) end end
    for _,m in ipairs(marks) do if m>=lower and m<upper then table.insert(chunkMarks,m) end end
    local payload = HttpService:JSONEncode({
        schema="memedash-camera-v1",session=session,place_id=tostring(game.PlaceId),
        page=page,pages=total,total_frames=#rows,first_frame=first,
        fields=fields,frames=chunk,events=chunkEvents,marks=chunkMarks,
        units="seconds,degrees,studs,studs/second; input deltas in pixels"
    })
    status.Text = ("EXPORT | page %d/%d"):format(page,total)
    return payload
end
connect(start.Activated,function()
    if recording then return end
    output.Visible=false
    rows,events,marks={}, {}, {}
    page=1
    session=HttpService:GenerateGUID(false)
    lastYaw,lastTime,lastVelocity,lastRoot=nil,nil,nil,nil
    touchX,touchY,mouseX,mouseY=0,0,0,0
    t0=os.clock()
    recording=true
    status.Text="REC | move camera manually"
end)
connect(stop.Activated,function() if recording then stopRecording() end end)
connect(mark.Activated,function() if recording then table.insert(marks,elapsed()) end end)
connect(copy.Activated,function()
    local payload=exportPage()
    if not payload then return end
    -- Optional clipboard support when supplied by the client environment.
    local ok=false
    if type(setclipboard)=="function" then ok=pcall(setclipboard,payload) end
    if not ok then
        output.Text=payload
        output.Visible=true
    else
        output.Visible=false
        status.Text ..= " | COPIED"
    end
end)
connect(nextPage.Activated,function()
    if recording or #rows==0 then return end
    page=page%math.ceil(#rows/PAGE_SIZE)+1
    local payload=exportPage()
    if output.Visible and payload then output.Text=payload end
end)
connect(close.Activated,function() gui:Destroy() end)
gui.Destroying:Connect(function()
    recording=false
    RunService:UnbindFromRenderStep(binding)
    for _,c in ipairs(connections) do c:Disconnect() end
end)
