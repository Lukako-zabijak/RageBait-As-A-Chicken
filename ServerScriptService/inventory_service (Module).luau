-- maintains authoritative inventory mutations and validates equipment against
-- the player's loaded profile before cloning server-owned tools.

local http_service = game:GetService("HttpService")
local server_storage = game:GetService("ServerStorage")
local replicated_storage = game:GetService("ReplicatedStorage")

local data_service = require(script.Parent.data_service)
local upgrades_config = require(replicated_storage.Modules.UpgradesConfig)
local skin_storage = require(script.Parent.SkinServer.Storage)

local inventory_service = {}

local tools_folder = server_storage:WaitForChild("Tools")
local equipped_tools = {}
local skin_changed_callback

local function get_upgrade(name)
	for _, upgrade in ipairs(upgrades_config.Upgrades) do
		if upgrade.Name == name then
			return upgrade
		end
	end
	return nil
end

local function tool_image(tool)
	if not tool then
		return ""
	end
	local ok, texture = pcall(function()
		return tool.TextureId
	end)
	if ok and type(texture) == "string" and texture ~= "" then
		return texture
	end
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("SpecialMesh") and descendant.TextureId ~= "" then
			return descendant.TextureId
		elseif descendant:IsA("Decal") and descendant.Texture ~= "" then
			return descendant.Texture
		end
	end
	return ""
end

function inventory_service.max_space(player_or_user_id)
	local profile = data_service.get(player_or_user_id)
	if not profile then
		return 5
	end
	local upgrade = get_upgrade("Inventory Space")
	local level = math.clamp(tonumber(profile.Upgrades.InventorySpace) or 1, 1, upgrade and upgrade.MaxLevel or 1)
	local level_data = upgrade and upgrade.Levels[level]
	return level_data and level_data.Value or 5
end

function inventory_service.status(player_or_user_id)
	local profile = data_service.get(player_or_user_id)
	if not profile then
		return nil
	end
	local items = {}
	for key, info in pairs(profile.InventoryItems) do
		if type(info) == "table" then
			if info.IsCrate then
				table.insert(items, {
					Name = key,
					IsCrate = true,
					IsSkin = false,
					CrateName = info.CrateName,
					Image = info.Image or "",
				})
			elseif info.IsSkin then
				table.insert(items, {
					ID = key,
					Name = key,
					IsCrate = false,
					IsSkin = true,
					DisplayName = info.SkinName,
					SkinType = info.SkinType,
				})
			else
				table.insert(items, {
					Name = key,
					IsCrate = false,
					IsSkin = false,
					DisplayName = info.DisplayName or key,
					Image = info.Image or "",
				})
			end
		end
	end
	table.sort(items, function(a, b)
		return tostring(a.DisplayName or a.CrateName or a.Name) < tostring(b.DisplayName or b.CrateName or b.Name)
	end)
	return {
		InventoryItems = items,
		EquippedTool = profile.EquippedTool or "",
		SkinEquipped = profile.SkinEquipped or "WhiteChicken",
		SkinType = profile.SkinType or "Chicken",
		MaxSpace = inventory_service.max_space(player_or_user_id),
	}
end

function inventory_service.new_key(prefix)
	return tostring(prefix) .. "_" .. http_service:GenerateGUID(false)
end

function inventory_service.add_item(player, key, item)
	if type(key) ~= "string" or #key > 200 or type(item) ~= "table" then
		return false
	end
	return data_service.mutate(player, function(profile)
		profile.InventoryItems[key] = item
	end)
end

function inventory_service.add_skin(player, skin_name, key)
	if type(skin_name) ~= "string" or #skin_name > 80 then
		return false
	end
	key = key or inventory_service.new_key(skin_name)
	return inventory_service.add_item(player, key, {
		IsSkin = true,
		SkinName = skin_name,
		SkinType = "Chicken",
	})
end

function inventory_service.owns_skin(player, skin_name)
	local profile = data_service.get(player)
	if not profile then
		return false
	end
	for _, item in pairs(profile.InventoryItems) do
		if type(item) == "table" and item.IsSkin and item.SkinName == skin_name then
			return true
		end
	end
	return false
end

function inventory_service.buy_skin(player, skin_name)
	local price = skin_storage.ChickenSkinPrice[skin_name]
	if type(price) ~= "number" then
		return false, "invalid_skin"
	end
	local outcome = "failed"
	local key
	local ok = data_service.mutate(player, function(profile)
		for _, item in pairs(profile.InventoryItems) do
			if type(item) == "table" and item.IsSkin and item.SkinName == skin_name then
				outcome = "owned"
				return
			end
		end
		if profile.States.Coins < price then
			outcome = "not_enough_coins"
			return
		end
		profile.States.Coins -= price
		key = inventory_service.new_key(skin_name)
		profile.InventoryItems[key] = {
			IsSkin = true,
			SkinName = skin_name,
			SkinType = "Chicken",
		}
		outcome = "purchased"
	end)
	if not ok then
		return false, "profile_unavailable"
	end
	return outcome == "purchased", outcome, key
end

local function remove_equipped_clone(user_id)
	local tool = equipped_tools[user_id]
	if tool and tool.Parent then
		tool:Destroy()
	end
	equipped_tools[user_id] = nil
end

local function give_tool(player, tool_name)
	local source = tools_folder:FindFirstChild(tool_name)
	if not source or not source:IsA("Tool") then
		return nil
	end
	local clone = source:Clone()
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
	clone.Parent = player:WaitForChild("Backpack")
	return clone
end

function inventory_service.equip_tool(player, item_key)
	if type(item_key) ~= "string" or #item_key > 200 then
		return false
	end
	local profile = data_service.get(player)
	local info = profile and profile.InventoryItems[item_key]
	if not info or info.IsCrate or info.IsSkin then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local tool_name = info.DisplayName or item_key
	remove_equipped_clone(player.UserId)
	local clone = give_tool(player, tool_name)
	if not clone then
		return false
	end
	equipped_tools[player.UserId] = clone
	data_service.mutate(player, function(data)
		data.EquippedTool = item_key
	end)
	return true
end

function inventory_service.unequip_tool(player)
	remove_equipped_clone(player.UserId)
	return data_service.mutate(player, function(profile)
		profile.EquippedTool = ""
	end)
end

function inventory_service.delete_item(player, item_key)
	if type(item_key) ~= "string" or #item_key > 200 then
		return false
	end
	local deleted = false
	local skin_changed = false
	local ok = data_service.mutate(player, function(profile)
		local info = profile.InventoryItems[item_key]
		if not info or info.IsCrate then
			return
		end
		if info.IsSkin and info.SkinName == "WhiteChicken" then
			return
		end
		if profile.EquippedTool == item_key then
			profile.EquippedTool = ""
			remove_equipped_clone(player.UserId)
		end
		if info.IsSkin and profile.SkinEquipped == info.SkinName then
			profile.SkinEquipped = "WhiteChicken"
			profile.SkinType = "Chicken"
			skin_changed = true
		end
		profile.InventoryItems[item_key] = nil
		deleted = true
	end)
	if ok and skin_changed and skin_changed_callback then
		task.defer(skin_changed_callback, player)
	end
	return ok and deleted
end

function inventory_service.change_skin(player, skin_name, skin_type, skin_key)
	if type(skin_name) ~= "string" or type(skin_type) ~= "string" or type(skin_key) ~= "string" then
		return false
	end
	if #skin_name > 80 or #skin_type > 40 or #skin_key > 200 then
		return false
	end
	local changed = false
	local ok = data_service.mutate(player, function(profile)
		local item = profile.InventoryItems[skin_key]
		if item and item.IsSkin and item.SkinName == skin_name and item.SkinType == skin_type then
			profile.SkinEquipped = skin_name
			profile.SkinType = skin_type
			changed = true
		end
	end)
	if ok and changed and skin_changed_callback then
		task.defer(skin_changed_callback, player)
	end
	return ok and changed
end

function inventory_service.restore_equipped_tool(player)
	remove_equipped_clone(player.UserId)
	local profile = data_service.get(player)
	if not profile or profile.EquippedTool == "" then
		return
	end
	local info = profile.InventoryItems[profile.EquippedTool]
	if not info or info.IsCrate or info.IsSkin then
		data_service.mutate(player, function(data)
			data.EquippedTool = ""
		end)
		return
	end
	local clone = give_tool(player, info.DisplayName or profile.EquippedTool)
	if clone then
		equipped_tools[player.UserId] = clone
	end
end

function inventory_service.set_skin_changed_callback(callback)
	skin_changed_callback = callback
end

function inventory_service.clear_player(player)
	remove_equipped_clone(player.UserId)
end

function inventory_service.get_tool_image(tool_name)
	return tool_image(tools_folder:FindFirstChild(tool_name))
end

return inventory_service
