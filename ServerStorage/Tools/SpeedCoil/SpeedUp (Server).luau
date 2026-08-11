local players = game:GetService("Players")

local character_service = require(game.ServerScriptService.character_service)
local tool = script.Parent
local equipped_player

local function apply()
	if equipped_player and equipped_player.Parent then
		character_service.apply_movement(equipped_player)
	end
end

local function equipped()
	local character = tool.Parent
	equipped_player = character and players:GetPlayerFromCharacter(character)
	if not equipped_player then
		return
	end
	apply()
	local handle = tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("CoilSound")
	if sound then
		sound:Play()
	end
end

local function unequipped()
	local player = equipped_player
	equipped_player = nil
	task.defer(function()
		if player and player.Parent then
			character_service.apply_movement(player)
		end
	end)
end

tool.Equipped:Connect(equipped)
tool.Unequipped:Connect(unequipped)
