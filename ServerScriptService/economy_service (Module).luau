-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local data_service = require(script.Parent.data_service)
local shop_storage = require(script.Parent.ShopHandler.ShopStorage)
local table_util = require(game:GetService("ReplicatedStorage").Modules.table_util)

local economy_service = {}

local money_pass_id = shop_storage.Gamepasses["2X Money"].ID
local diamond_pass_id = shop_storage.Gamepasses["2X Diamond"].ID

local function clean_amount(value, allow_negative)
	if not table_util.is_finite_number(value) then
		return nil
	end
	value = math.floor(value)
	if not allow_negative and value < 0 then
		return nil
	end
	if math.abs(value) > 9e12 then
		return nil
	end
	return value
end

function economy_service.add_coins(player, amount)
	amount = clean_amount(amount, true)
	if not amount then
		return false
	end
	local ok = data_service.mutate(player, function(profile)
		profile.States.Coins = math.max(0, profile.States.Coins + amount)
	end)
	return ok
end

function economy_service.add_diamonds(player, amount)
	amount = clean_amount(amount, true)
	if not amount then
		return false
	end
	local ok = data_service.mutate(player, function(profile)
		profile.States.Diamonds = math.max(0, profile.States.Diamonds + amount)
	end)
	return ok
end

function economy_service.spend_coins(player, amount)
	amount = clean_amount(amount, false)
	if not amount then
		return false, "invalid_amount"
	end
	local purchased = false
	local ok = data_service.mutate(player, function(profile)
		if profile.States.Coins < amount then
			return
		end
		profile.States.Coins -= amount
		purchased = true
	end)
	if not ok then
		return false, "profile_unavailable"
	end
	return purchased, purchased and nil or "not_enough_coins"
end

function economy_service.spend_diamonds(player, amount)
	amount = clean_amount(amount, false)
	if not amount then
		return false, "invalid_amount"
	end
	local purchased = false
	local ok = data_service.mutate(player, function(profile)
		if profile.States.Diamonds < amount then
			return
		end
		profile.States.Diamonds -= amount
		purchased = true
	end)
	if not ok then
		return false, "profile_unavailable"
	end
	return purchased, purchased and nil or "not_enough_diamonds"
end

function economy_service.add_survival_time(player, time_value)
	time_value = clean_amount(time_value, false)
	if not time_value or time_value <= 0 then
		return false
	end
	local ok = data_service.mutate(player, function(profile)
		local gamepasses = profile.GamePasses
		local coin_multiplier = table.find(gamepasses, money_pass_id) and 4 or 2
		local diamond_multiplier = table.find(gamepasses, diamond_pass_id) and 2 or 1
		profile.States.TimeSurvived += time_value
		profile.States.Coins += time_value * coin_multiplier
		profile.States.Diamonds += time_value * diamond_multiplier
	end)
	return ok
end

function economy_service.add_combo_reward(player, coins, diamonds)
	coins = clean_amount(coins, false)
	diamonds = clean_amount(diamonds, false)
	if coins == nil or diamonds == nil then
		return false
	end
	local actual_coins = 0
	local actual_diamonds = 0
	local ok = data_service.mutate(player, function(profile)
		local gamepasses = profile.GamePasses
		local coin_multiplier = table.find(gamepasses, money_pass_id) and 2 or 1
		local diamond_multiplier = table.find(gamepasses, diamond_pass_id) and 2 or 1
		actual_coins = coins * coin_multiplier
		actual_diamonds = diamonds * diamond_multiplier
		profile.States.Coins += actual_coins
		profile.States.Diamonds += actual_diamonds
	end)
	return ok, actual_coins, actual_diamonds
end

function economy_service.get_stats(player)
	local profile = data_service.get(player)
	if not profile then
		return nil
	end
	return {
		Coins = profile.States.Coins,
		TimeSurvived = profile.States.TimeSurvived,
		Diamonds = profile.States.Diamonds,
	}
end

return economy_service
