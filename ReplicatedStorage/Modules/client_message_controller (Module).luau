local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local tween_service = game:GetService("TweenService")

local controller = {}
local started = false
local player = players.LocalPlayer
local messages = {}

local function reflow()
	for index, frame in ipairs(messages) do
		if frame and frame.Parent then
			tween_service:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, -frame.AbsoluteSize.X / 2, index * 0.1, 0),
			}):Play()
		end
	end
end

local function show(text)
	if type(text) ~= "string" or text == "" then
		return
	end
	for _, frame in ipairs(messages) do
		local label = frame and frame:FindFirstChild("TextLabel")
		if label and label.Text == text then
			return
		end
	end
	local holder = player:WaitForChild("PlayerGui"):FindFirstChild("MessageHolder", true)
	local template = replicated_storage.Stuff:FindFirstChild("MessageGUI")
	if not holder or not template then
		return
	end
	if #messages >= 5 then
		local oldest = table.remove(messages, 1)
		if oldest then oldest:Destroy() end
	end
	local frame = template:Clone()
	local label = frame:FindFirstChild("TextLabel")
	if label then label.Text = text end
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 0)
	frame.Parent = holder
	table.insert(messages, frame)
	local target_y = #messages * 0.1
	tween_service:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, target_y, 0),
	}):Play()
	task.delay(2, function()
		local index = table.find(messages, frame)
		if index then table.remove(messages, index) end
		if frame.Parent then frame:Destroy() end
		reflow()
	end)
end

function controller.start()
	if started then return end
	started = true
	replicated_storage.RemoteEvents.MessageEvent.OnClientEvent:Connect(show)
end

return controller
