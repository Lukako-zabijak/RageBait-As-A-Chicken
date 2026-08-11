-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

-- starts presentation controllers once and isolates their failures so one ui
-- feature cannot prevent the rest of the client from initializing.

local players = game:GetService("Players")
local modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")

local bootstrap = {}
local started = false

local controller_names = {
	"client_reset_controller",
	"client_camera_controller",
	"client_chicken_animation_controller",
	"client_ui_manager",
	"client_stats_controller",
	"client_combo_controller",
	"client_message_controller",
	"client_dialogue_controller",
	"client_tutorial_controller",
	"client_shop_controller",
	"client_rewards_controller",
	"client_inventory_controller",
	"client_crate_shop_controller",
	"client_crate_open_controller",
	"client_upgrade_controller",
	"client_catch_controller",
	"client_chat_controller",
}

local function start_controller(name)
	local module = modules:FindFirstChild(name)
	if not module then
		warn("[client] missing controller " .. name)
		return
	end
	local loaded, controller = pcall(require, module)
	if not loaded then
		warn("[client] failed to require " .. name .. ": " .. tostring(controller))
		return
	end
	if type(controller) ~= "table" or type(controller.start) ~= "function" then
		warn("[client] invalid controller " .. name)
		return
	end
	local ok, err = pcall(controller.start)
	if not ok then
		warn("[client] failed to start " .. name .. ": " .. tostring(err))
	end
end

local function restore_initial_view()
	local player = players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	local camera = workspace.CurrentCamera
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
	local player_gui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 15)
	local game_ui = player_gui and (player_gui:FindFirstChild("GameUI") or player_gui:WaitForChild("GameUI", 15))
	local black = game_ui and game_ui:FindFirstChild("BlackScreen")
	if black and black:IsA("GuiObject") then
		black.BackgroundTransparency = 1
		if black:IsA("ImageLabel") or black:IsA("ImageButton") then
			black.ImageTransparency = 1
		end
	end
end

function bootstrap.start()
	if started then return end
	started = true
	for _, name in ipairs(controller_names) do
		task.spawn(start_controller, name)
	end
	task.spawn(restore_initial_view)
end

return bootstrap
