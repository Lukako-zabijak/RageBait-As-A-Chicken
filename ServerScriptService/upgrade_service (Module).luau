local replicated_storage = game:GetService("ReplicatedStorage")

local data_service = require(script.Parent.data_service)
local config = require(replicated_storage.Modules.UpgradesConfig)

local upgrade_service = {}

local purchase_busy = {}
local last_purchase = {}
local purchase_cooldown = 0.75

local function find_upgrade(name)
	for _, upgrade in ipairs(config.Upgrades) do
		if upgrade.Name == name then
			return upgrade
		end
	end
	return nil
end

local function level_for(profile, name)
	if name == "Inventory Space" then
		return profile.Upgrades.InventorySpace
	elseif name == "Multi Ragebait" then
		return profile.Upgrades.MultiRagebait
	end
	return nil
end

local function set_level(profile, name, level)
	if name == "Inventory Space" then
		profile.Upgrades.InventorySpace = level
	elseif name == "Multi Ragebait" then
		profile.Upgrades.MultiRagebait = level
	end
end

local function currency_balance(profile, currency)
	if currency == "Coins" then
		return profile.States.Coins
	elseif currency == "Diamonds" then
		return profile.States.Diamonds
	end
	return nil
end

local function set_currency_balance(profile, currency, value)
	if currency == "Coins" then
		profile.States.Coins = value
	elseif currency == "Diamonds" then
		profile.States.Diamonds = value
	end
end

local function clean_cost(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	value = math.floor(value)
	if value < 0 or value > 1_000_000_000 then
		return nil
	end
	return value
end

function upgrade_service.status(player)
	local profile = data_service.get(player)
	if not profile then
		return nil
	end
	local upgrades = {}
	for _, upgrade in ipairs(config.Upgrades) do
		local level = math.clamp(math.floor(tonumber(level_for(profile, upgrade.Name)) or 1), 1, upgrade.MaxLevel)
		local next_data = upgrade.Levels[level + 1]
		table.insert(upgrades, {
			Name = upgrade.Name,
			Image = upgrade.Image,
			CurrentLevel = level,
			MaxLevel = upgrade.MaxLevel,
			Cost = next_data and clean_cost(next_data.Cost) or 0,
			Currency = upgrade.Currency or "Diamonds",
			Description = next_data and next_data.Description or "Max Level",
			IsMaxLevel = level >= upgrade.MaxLevel,
		})
	end
	return {
		Upgrades = upgrades,
		Coins = profile.States.Coins,
		Diamonds = profile.States.Diamonds,
	}
end

function upgrade_service.buy(player, name)
	if type(name) ~= "string" or #name > 80 then
		return false, "InvalidUpgrade"
	end
	local upgrade = find_upgrade(name)
	if not upgrade then
		return false, "InvalidUpgrade"
	end

	local user_id = player.UserId
	local now = os.clock()
	if purchase_busy[user_id] then
		return false, "Busy"
	end
	if last_purchase[user_id] and now - last_purchase[user_id] < purchase_cooldown then
		return false, "Busy"
	end
	purchase_busy[user_id] = true

	local purchased = false
	local reason = "InvalidUpgrade"
	local receipt
	local ok, mutation_error = pcall(function()
		local mutated = data_service.mutate(player, function(profile)
			local level = math.clamp(math.floor(tonumber(level_for(profile, name)) or 1), 1, upgrade.MaxLevel)
			if level >= upgrade.MaxLevel then
				reason = "MaxLevel"
				return
			end

			local next_level = level + 1
			local next_data = upgrade.Levels[next_level]
			local cost = next_data and clean_cost(next_data.Cost)
			local currency = upgrade.Currency or "Diamonds"
			local before = currency_balance(profile, currency)
			if not next_data or cost == nil or before == nil then
				reason = "InvalidLevel"
				return
			end
			if before < cost then
				reason = currency == "Coins" and "NotEnoughCoins" or "NotEnoughDiamonds"
				return
			end

			local after = before - cost
			set_currency_balance(profile, currency, after)
			set_level(profile, name, next_level)
			purchased = true
			reason = nil
			receipt = {
				Name = name,
				Level = next_level,
				Cost = cost,
				Currency = currency,
				Before = before,
				After = after,
			}
		end)
		if not mutated then
			error("profile mutation failed")
		end
	end)

	purchase_busy[user_id] = nil
	if not ok then
		warn("[upgrade] purchase failed for " .. player.Name .. ": " .. tostring(mutation_error))
		return false, "NoData"
	end
	if purchased then
		last_purchase[user_id] = os.clock()
	end
	return purchased, reason, receipt
end

function upgrade_service.clear_player(player)
	purchase_busy[player.UserId] = nil
	last_purchase[player.UserId] = nil
end

return upgrade_service

