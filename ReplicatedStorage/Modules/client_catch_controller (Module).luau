local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local run_service = game:GetService("RunService")
local tween_service = game:GetService("TweenService")

local controller = {}
local started = false
local player = players.LocalPlayer
local timer_event = replicated_storage.RemoteEvents:WaitForChild("TimerEvent")
local hook_event = replicated_storage.RemoteEvents:WaitForChild("HookUpEvent")
local timer_function = replicated_storage.RemoteFunctions:WaitForChild("TimerFunction")
local data_function = replicated_storage.RemoteFunctions:WaitForChild("DataFunction")

local timer_generation = 0
local elapsed = 0
local previous_coins = 0
local previous_diamonds = 0
local glued = false
local camera_connection

local function format_time(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return minutes > 0 and string.format("%dm %ds", minutes, secs) or string.format("%ds", secs)
end

local function fade_black(frame, transparency, reverses)
	local tween = tween_service:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, reverses == true), {
		BackgroundTransparency = transparency,
	})
	tween:Play()
	tween.Completed:Wait()
end

local function lock_camera()
	if camera_connection then camera_connection:Disconnect() end
	camera_connection = run_service.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		if not root or not camera then return end
		camera.CameraType = Enum.CameraType.Scriptable
		local position = root.Position + root.CFrame.LookVector * 6 + Vector3.new(0, 3, 0)
		camera.CFrame = CFrame.new(position, root.Position + Vector3.new(0, 2, 0))
	end)
end

local function unlock_camera()
	if camera_connection then camera_connection:Disconnect() camera_connection = nil end
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end

local function stats_snapshot()
	local ok, stats = pcall(function() return data_function:InvokeServer("Get", "Stats") end)
	if ok and type(stats) == "table" then
		previous_coins = stats.Coins or 0
		previous_diamonds = stats.Diamonds or 0
	end
end

local function show_earnings(label)
	local ok, stats = pcall(function() return data_function:InvokeServer("Get", "Stats") end)
	local coins = 0
	local diamonds = 0
	if ok and type(stats) == "table" then
		coins = math.max(0, (stats.Coins or 0) - previous_coins)
		diamonds = math.max(0, (stats.Diamonds or 0) - previous_diamonds)
	end
	label.RichText = true
	label.Text = '<font color="rgb(255,255,255)">You Earned </font><font color="rgb(80,255,80)">$' .. tostring(coins) .. '</font><font color="rgb(255,255,255)"> and </font><font color="rgb(80,180,255)">' .. tostring(diamonds) .. ' Diamonds</font>'
	label.Visible = true
end

local function reset_label(label)
	label.RichText = false
	label.Visible = false
	label.Text = "Survival Time: 0s"
	elapsed = 0
	previous_coins = 0
	previous_diamonds = 0
end

local function animate_button(button)
	local original = button.Size
	local down = tween_service:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(original.X.Scale * 0.9, original.X.Offset, original.Y.Scale * 0.9, original.Y.Offset),
	})
	down:Play()
	down.Completed:Wait()
	tween_service:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = original }):Play()
end

function controller.start()
	if started then return end
	started = true
	local game_ui = player:WaitForChild("PlayerGui"):WaitForChild("GameUI")
	local label = game_ui:WaitForChild("TextLabel")
	local black = game_ui:WaitForChild("BlackScreen")
	local button = game_ui:WaitForChild("ClickButton")
	black.BackgroundTransparency = 1
	button.Visible = false
	label.Visible = false

	timer_event.OnClientEvent:Connect(function(action)
		if action == "StartTimer" then
			timer_generation += 1
			local generation = timer_generation
			elapsed = 0
			label.RichText = false
			label.Text = "Survival Time: 0s"
			label.Visible = true
			stats_snapshot()
			task.spawn(function()
				while generation == timer_generation do
					task.wait(1)
					if generation ~= timer_generation then break end
					local ok, state = pcall(function() return timer_function:InvokeServer() end)
					elapsed += ok and state and state.IsInWater and 2 or 1
					label.Text = "Survival Time: " .. format_time(elapsed)
				end
			end)
		elseif action == "StopTimer" then
			timer_generation += 1
		end
	end)

	button.Activated:Connect(function()
		if not glued then return end
		hook_event:FireServer("EscapeClick")
		task.spawn(animate_button, button)
	end)

	hook_event.OnClientEvent:Connect(function(action)
		if action == "BlackScreen" then
			glued = false
			button.Visible = false
			fade_black(black, 0, true)
			task.wait(0.1)
			lock_camera()
			task.wait(0.2)
			show_earnings(label)
		elseif action == "ButtonClick" then
			glued = true
			button.Visible = true
		elseif action == "Escaped" then
			glued = false
			button.Visible = false
			fade_black(black, 0, true)
			task.wait(0.1)
			unlock_camera()
			reset_label(label)
			task.wait(0.2)
			fade_black(black, 1, false)
		end
	end)
end

return controller
