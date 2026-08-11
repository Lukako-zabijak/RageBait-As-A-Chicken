-- owns crate purchase, inventory consumption, reward selection, and the
-- pending-result handoff used by the client-side opening presentation.

local replicated_storage = game:GetService("ReplicatedStorage")

local data_service = require(script.Parent.data_service)
local inventory_service = require(script.Parent.inventory_service)
local config = require(replicated_storage.Modules.CrateConfig)

local crate_service = {}

local pending_rewards = {}

local function crate_by_name(name)
	for _, crate in ipairs(config.Crates) do
		if crate.Name == name then
			return crate
		end
	end
	return nil
end

local function stock_needs_refresh(profile, now)
	if type(profile.CrateStock) ~= "table" or type(profile.CrateStock.Stock) ~= "table" then
		return true
	end
	local last = tonumber(profile.CrateStock.LastRestock) or 0
	if last <= 0 or now - last >= config.RestockTime then
		return true
	end
	for _, crate in ipairs(config.Crates) do
		if type(profile.CrateStock.Stock[crate.Name]) ~= "number" then
			return true
		end
	end
	return false
end

local function ensure_stock(profile, now)
	profile.CrateStock = type(profile.CrateStock) == "table" and profile.CrateStock or { Stock = {}, LastRestock = 0 }
	profile.CrateStock.Stock = type(profile.CrateStock.Stock) == "table" and profile.CrateStock.Stock or {}
	local last = tonumber(profile.CrateStock.LastRestock) or 0
	if last <= 0 then
		last = now
		profile.CrateStock.LastRestock = now
	end
	local restock_due = now - last >= config.RestockTime
	for _, crate in ipairs(config.Crates) do
		if restock_due or type(profile.CrateStock.Stock[crate.Name]) ~= "number" then
			profile.CrateStock.Stock[crate.Name] = crate.Stock
		end
	end
	if restock_due then
		profile.CrateStock.LastRestock = now
	end
end

function crate_service.on_player_added(player)
	data_service.mutate(player, function(profile)
		ensure_stock(profile, os.time())
	end)
end

function crate_service.status(player)
	local profile = data_service.get(player)
	if not profile then
		return nil
	end
	local now = os.time()
	if stock_needs_refresh(profile, now) then
		data_service.mutate(player, function(data)
			ensure_stock(data, now)
		end)
		profile = data_service.get(player)
	end
	local stock = profile.CrateStock
	local crates = {}
	for _, crate in ipairs(config.Crates) do
		local rewards = {}
		for _, reward in ipairs(crate.Rewards) do
			table.insert(rewards, {
				ToolName = reward.ToolName,
				Image = inventory_service.get_tool_image(reward.ToolName),
				Chance = reward.Chance,
			})
		end
		table.insert(crates, {
			Name = crate.Name,
			Order = crate.Order,
			CoinPrice = crate.CoinPrice,
			RobuxPrice = crate.RobuxPrice,
			DeveloperProductId = crate.DeveloperProductId,
			Stock = stock.Stock[crate.Name] or 0,
			Rewards = rewards,
		})
	end
	return {
		Crates = crates,
		TimeUntilRestock = math.max(0, config.RestockTime - (os.time() - stock.LastRestock)),
	}
end

function crate_service.force_restock_in_profile(profile)
	ensure_stock(profile, os.time())
	for _, crate in ipairs(config.Crates) do
		profile.CrateStock.Stock[crate.Name] = crate.Stock
	end
	profile.CrateStock.LastRestock = os.time()
	return true
end

function crate_service.force_restock(player)
	return data_service.mutate(player, function(profile)
		crate_service.force_restock_in_profile(profile)
	end)
end

function crate_service.buy_with_coins(player, crate_name)
	if type(crate_name) ~= "string" or #crate_name > 100 then
		return false, "InvalidCrate"
	end
	local crate = crate_by_name(crate_name)
	if not crate then
		return false, "InvalidCrate"
	end
	local result = "Failed"
	local item_key
	local ok = data_service.mutate(player, function(profile)
		ensure_stock(profile, os.time())
		local available = profile.CrateStock.Stock[crate_name] or 0
		if available <= 0 then
			result = "OutOfStock"
			return
		end
		if profile.States.Coins < crate.CoinPrice then
			result = "NotEnoughCoins"
			return
		end
		profile.States.Coins -= crate.CoinPrice
		profile.CrateStock.Stock[crate_name] = available - 1
		item_key = inventory_service.new_key(crate_name)
		profile.InventoryItems[item_key] = {
			IsCrate = true,
			CrateName = crate_name,
			Image = "",
		}
		result = "Success"
	end)
	if not ok then
		return false, "NoData"
	end
	return result == "Success", result, item_key
end

local function random_reward(crate)
	local roll = math.random(1, 100)
	local cumulative = 0
	for _, reward in ipairs(crate.Rewards) do
		cumulative += reward.Chance
		if roll <= cumulative then
			return reward
		end
	end
	return crate.Rewards[#crate.Rewards]
end

function crate_service.open(player, crate_key)
	if type(crate_key) ~= "string" or #crate_key > 200 then
		return nil, "NoCrates"
	end
	local reward_result
	local reason = "NoCrates"
	local ok = data_service.mutate(player, function(profile)
		local crate_item = profile.InventoryItems[crate_key]
		if not crate_item or not crate_item.IsCrate then
			return
		end
		local crate = crate_by_name(crate_item.CrateName)
		if not crate then
			reason = "InvalidCrate"
			return
		end
		local reward = random_reward(crate)
		if not reward then
			reason = "InvalidCrate"
			return
		end
		profile.InventoryItems[crate_key] = nil
		local item_key = inventory_service.new_key(reward.ToolName)
		local image = inventory_service.get_tool_image(reward.ToolName)
		profile.InventoryItems[item_key] = {
			IsCrate = false,
			Image = image,
			DisplayName = reward.ToolName,
		}
		reward_result = {
			ToolName = reward.ToolName,
			Image = image,
			Chance = reward.Chance,
		}
		reason = nil
	end)
	if not ok then
		return nil, "NoData"
	end
	return reward_result, reason
end

function crate_service.begin_open_animation(player, crate_key)
	local reward, reason = crate_service.open(player, crate_key)
	if not reward then
		return nil, reason
	end
	pending_rewards[player.UserId] = reward
	local profile = data_service.get(player)
	local crate_name
	-- The original crate was consumed, so the caller should pass the visual name separately when needed.
	return reward
end

function crate_service.set_pending(player, reward)
	pending_rewards[player.UserId] = reward
end

function crate_service.take_pending(player)
	local reward = pending_rewards[player.UserId]
	pending_rewards[player.UserId] = nil
	return reward
end

function crate_service.grant_crate_in_profile(profile, crate, purchase_id)
	if not profile or not crate then
		return false
	end
	ensure_stock(profile, os.time())
	local stock = profile.CrateStock.Stock[crate.Name] or 0
	if stock > 0 then
		profile.CrateStock.Stock[crate.Name] = stock - 1
	end
	local key = crate.Name .. "_receipt_" .. tostring(purchase_id)
	profile.InventoryItems[key] = {
		IsCrate = true,
		CrateName = crate.Name,
		Image = "",
	}
	return true
end

function crate_service.find_by_product_id(product_id)
	for _, crate in ipairs(config.Crates) do
		if crate.DeveloperProductId ~= 0 and crate.DeveloperProductId == product_id then
			return crate
		end
	end
	return nil
end

function crate_service.on_player_removing(player)
	pending_rewards[player.UserId] = nil
end

return crate_service
