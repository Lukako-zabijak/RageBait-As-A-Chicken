-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local marketplace_service = game:GetService("MarketplaceService")

local data_service = require(script.Parent.data_service)
local shop_storage = require(script.Parent.ShopHandler.ShopStorage)

local entitlement_service = {}

local passes = {
	money = shop_storage.Gamepasses["2X Money"].ID,
	diamonds = shop_storage.Gamepasses["2X Diamond"].ID,
	vip = shop_storage.Gamepasses.VIP.ID,
}

local function known_pass(pass_id)
	return pass_id == passes.money or pass_id == passes.diamonds or pass_id == passes.vip
end

local function apply_attribute(player, pass_id)
	if pass_id == passes.money then
		player:SetAttribute("Has2XMoney", true)
	elseif pass_id == passes.diamonds then
		player:SetAttribute("Has2XDiamonds", true)
	elseif pass_id == passes.vip then
		player:SetAttribute("HasVIP", true)
	end
end

function entitlement_service.grant(player, pass_id, is_purchase)
	if type(pass_id) ~= "number" or not known_pass(pass_id) then
		return false
	end
	local changed = false
	local ok = data_service.mutate(player, function(profile)
		local already_entitled = table.find(profile.GamePasses, pass_id) ~= nil
		if not already_entitled then
			table.insert(profile.GamePasses, pass_id)
			changed = true
		end

		if pass_id == passes.vip then
			local vip = shop_storage.Gamepasses.VIP
			local skin_name = vip.Skin
			if skin_name and not profile.InventoryItems[skin_name] then
				profile.InventoryItems[skin_name] = {
					IsSkin = true,
					SkinName = skin_name,
					SkinType = "Chicken",
				}
				changed = true
			end

			local reward_key = tostring(pass_id)
			local reward_handled = profile.GamePassRewards[reward_key] == true
			local should_grant_package = not reward_handled and (is_purchase == true or not already_entitled)
			if should_grant_package then
				profile.States.Coins += math.max(0, tonumber(vip.Money) or 0)
				profile.States.Diamonds += math.max(0, tonumber(vip.Diamond) or 0)
				profile.GamePassRewards[reward_key] = true
				changed = true
			elseif already_entitled and profile.GamePassRewards[reward_key] == nil then
				profile.GamePassRewards[reward_key] = true
				changed = true
			end
		end
	end)
	if not ok then
		return false
	end
	apply_attribute(player, pass_id)
	if is_purchase or changed then
		return data_service.save(player, false, true)
	end
	return true
end

function entitlement_service.reconcile(player)
	local profile = data_service.get(player)
	if not profile then
		return
	end
	for _, pass_id in pairs(passes) do
		if table.find(profile.GamePasses, pass_id) then
			apply_attribute(player, pass_id)
			entitlement_service.grant(player, pass_id, false)
		end
	end

	task.spawn(function()
		for _, pass_id in pairs(passes) do
			if not player.Parent then
				return
			end
			local owns = false
			local ok = pcall(function()
				owns = marketplace_service:UserOwnsGamePassAsync(player.UserId, pass_id)
			end)
			if ok and owns then
				entitlement_service.grant(player, pass_id, false)
			end
		end
	end)
end

function entitlement_service.confirm_ownership(player, pass_id)
	if not known_pass(pass_id) then
		return false
	end
	for attempt = 1, 4 do
		local owns = false
		local ok = pcall(function()
			owns = marketplace_service:UserOwnsGamePassAsync(player.UserId, pass_id)
		end)
		if ok and owns then
			return true
		end
		if attempt < 4 then
			task.wait(0.5 * attempt)
		end
	end
	return false
end

function entitlement_service.is_known(pass_id)
	return known_pass(pass_id)
end

function entitlement_service.ids()
	return passes
end

return entitlement_service
