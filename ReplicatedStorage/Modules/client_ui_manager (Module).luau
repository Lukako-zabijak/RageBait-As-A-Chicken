-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local tween_service = game:GetService("TweenService")

local ui_util = require(replicated_storage.Modules.ui_util)

local controller = {}
local started = false
local current_frame
local original_sizes = {}

local player = players.LocalPlayer
local click_sound = replicated_storage.Sounds:FindFirstChild("Click")
local hover_sound = replicated_storage.Sounds:FindFirstChild("Hover")

local function close_frame(frame)
	if not frame or not frame.Visible then
		return
	end
	local original = original_sizes[frame] or frame.Size
	local tween = tween_service:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0),
	})
	tween:Play()
	tween.Completed:Once(function()
		if frame.Parent then
			frame.Visible = false
			frame.Size = original
		end
	end)
	if current_frame == frame then
		current_frame = nil
	end
end

local function open_frame(frame)
	if not frame then
		return
	end
	if current_frame and current_frame ~= frame then
		close_frame(current_frame)
	end
	if frame.Visible then
		close_frame(frame)
		return
	end
	local original = original_sizes[frame] or frame.Size
	original_sizes[frame] = original
	frame.Size = UDim2.new(0, 0, 0, 0)
	frame.Visible = true
	current_frame = frame
	tween_service:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = original,
	}):Play()
end

function controller.open(frame)
	open_frame(frame)
end

function controller.close(frame)
	close_frame(frame or current_frame)
end

function controller.start()
	if started then
		return
	end
	started = true
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("GameUI")
	local buttons = gui:WaitForChild("ButtonsFrame")
	local frames = gui:WaitForChild("Frames")
	for _, name in ipairs({ "DailyRewards", "PlayTimeRewards", "Inventory", "Shop" }) do
		local button = buttons:FindFirstChild(name)
		local frame = frames:FindFirstChild(name)
		if button and frame then
			original_sizes[frame] = frame.Size
			frame.Visible = false
			ui_util.bind_hover(button, hover_sound)
			ui_util.bind_click(button, function()
				open_frame(frame)
			end, click_sound)
			local close_button = frame:FindFirstChild("CloseButton")
			if close_button and close_button:IsA("GuiButton") then
				close_button.MouseButton1Click:Connect(function()
					ui_util.play_sound(click_sound)
					close_frame(frame)
				end)
			end
		end
	end
end

return controller
