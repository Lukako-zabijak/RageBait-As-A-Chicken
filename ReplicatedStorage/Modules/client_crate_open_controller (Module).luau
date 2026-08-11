local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local tween_service = game:GetService("TweenService")
local user_input_service = game:GetService("UserInputService")
local run_service = game:GetService("RunService")

local ui_util = require(replicated_storage.Modules.ui_util)

local controller = {}
local started = false
local player = players.LocalPlayer
local event = replicated_storage.RemoteEvents:WaitForChild("CrateOpenEvent")
local opening = false
local clicks = 0
local current_model
local render_connection

local function clear_viewport(viewport)
	if render_connection then render_connection:Disconnect() render_connection = nil end
	for _, child in ipairs(viewport:GetChildren()) do child:Destroy() end
	current_model = nil
end

local function create_crate(viewport, crate_name)
	clear_viewport(viewport)
	local folder = replicated_storage:FindFirstChild("Crates")
	local source = folder and folder:FindFirstChild(crate_name)
	if not source or not source:IsA("Model") then return end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	current_model = source:Clone()
	for _, descendant in ipairs(current_model:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.Anchored = true end
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then descendant:Destroy() end
	end
	current_model.Parent = world
	current_model:PivotTo(CFrame.new())
	local _, size = current_model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local distance = math.max(4, size.Magnitude * 0.8)
	camera.CFrame = CFrame.lookAt(Vector3.new(distance, math.max(1.5, size.Y * 0.4), distance), Vector3.new(0, size.Y * 0.15, 0))
	local started_at = os.clock()
	render_connection = run_service.RenderStepped:Connect(function(dt)
		if not current_model or not current_model.Parent then return end
		local t = os.clock() - started_at
		current_model:PivotTo(CFrame.new(0, math.sin(t * 2) * 0.12, 0) * CFrame.Angles(0, t * 0.7, 0))
	end)
end

local function twitch()
	if not current_model then return end
	local base = current_model:GetPivot()
	local offset = CFrame.new(math.random(-5, 5) / 100, math.random(-3, 3) / 100, 0) * CFrame.Angles(0, 0, math.rad(math.random(-8, 8)))
	current_model:PivotTo(base * offset)
end

local function explode(viewport)
	if render_connection then render_connection:Disconnect() render_connection = nil end
	if not current_model then return end
	for _, part in ipairs(current_model:GetDescendants()) do
		if part:IsA("BasePart") then
			local direction = part.Position.Magnitude > 0.01 and part.Position.Unit or Vector3.new(math.random() - 0.5, math.random(), math.random() - 0.5).Unit
			tween_service:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = part.Position + direction * 3,
				Size = part.Size * 0.3,
				Transparency = 1,
			}):Play()
		end
	end
	task.delay(0.5, function() clear_viewport(viewport) end)
end

local function close(gui)
	opening = false
	clicks = 0
	local background = gui.BackgroundFrame
	local viewport = gui.ViewportFrame
	local reward = gui.RewardFrame
	tween_service:Create(background, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	tween_service:Create(viewport, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, 0, 0, 0) }):Play()
	task.wait(0.3)
	clear_viewport(viewport)
	background.Visible = false
	viewport.Visible = false
	gui.ClickText.Visible = false
	reward.Visible = false
end

local function begin(gui, data)
	if opening or type(data) ~= "table" then return end
	opening = true
	clicks = 0
	local background = gui.BackgroundFrame
	local viewport = gui.ViewportFrame
	local click_text = gui.ClickText
	local reward = gui.RewardFrame
	reward.Visible = false
	background.Visible = true
	background.BackgroundTransparency = 1
	viewport.Visible = true
	local original_size = viewport:GetAttribute("original_size")
	if typeof(original_size) ~= "UDim2" then
		original_size = viewport.Size
		viewport:SetAttribute("original_size", original_size)
	end
	viewport.Size = UDim2.new(0, 0, 0, 0)
	click_text.Visible = true
	click_text.Text = "Click to Open!"
	create_crate(viewport, data.CrateName)
	tween_service:Create(background, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.4 }):Play()
	tween_service:Create(viewport, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = original_size }):Play()
end

local function register_click(gui)
	if not opening or clicks >= 5 then return end
	clicks += 1
	local sound_name = clicks >= 5 and "CrateLastClick" or "CrateClick"
	ui_util.play_sound(replicated_storage.Sounds:FindFirstChild(sound_name))
	twitch()
	local viewport = gui.ViewportFrame
	local original = viewport.Size
	tween_service:Create(viewport, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(original.X.Scale * 0.88, original.X.Offset, original.Y.Scale * 0.88, original.Y.Offset),
	}):Play()
	task.delay(0.07, function()
		if viewport.Parent then
			tween_service:Create(viewport, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = original }):Play()
		end
	end)
	if clicks >= 5 then
		gui.ClickText.Text = "Opening..."
		explode(viewport)
		task.delay(0.5, function()
			if opening then event:FireServer("RequestReward") end
		end)
	end
end

local function show_reward(gui, data)
	if type(data) ~= "table" then return end
	local frame = gui.RewardFrame
	frame.RewardImage.Image = data.Image or ""
	frame.RewardName.Text = tostring(data.ToolName or "Reward")
	frame.Visible = true
	local target = frame:GetAttribute("original_size")
	if typeof(target) ~= "UDim2" then
		target = frame.Size
		frame:SetAttribute("original_size", target)
	end
	frame.Size = UDim2.new(0, 0, 0, 0)
	tween_service:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = target }):Play()
	gui.ClickText.Visible = false
end

function controller.start()
	if started then return end
	started = true
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("CrateOpenGui")
	gui.BackgroundFrame.Visible = false
	gui.ViewportFrame.Visible = false
	gui.ClickText.Visible = false
	gui.RewardFrame.Visible = false
	gui.BackgroundFrame.BackgroundTransparency = 1
	local continue = gui.RewardFrame:WaitForChild("ContinueButton")
	ui_util.bind_click(continue, function() task.spawn(close, gui) end, replicated_storage.Sounds:FindFirstChild("Click"))
	event.OnClientEvent:Connect(function(action, data)
		if action == "StartOpen" then
			begin(gui, data)
		elseif action == "RewardResult" then
			show_reward(gui, data)
		end
	end)
	user_input_service.InputBegan:Connect(function(input)
		if not opening then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			register_click(gui)
		end
	end)
end

return controller
