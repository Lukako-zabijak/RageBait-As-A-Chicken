-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

-- calculates daily and playtime eligibility on the server and commits claims
-- through the shared profile mutation boundary to prevent client-forged grants.

local replicated_storage = game:GetService("ReplicatedStorage")

local data_service = require(script.Parent.data_service)
local session_data = require(script.Parent.SessionData)
local daily_config = require(replicated_storage.Modules.DailyRewardsConfig)
local playtime_config = require(replicated_storage.Modules.PlaytimeRewardsConfig)

local reward_service = {}

local seconds_per_day = 86400

local function contains(array, value)
	for _, item in ipairs(array) do
		if item == value then
			return true
		end
	end
	return false
end

local function grant_reward(profile, reward)
	local amount = tonumber(reward and reward.Amount)
	if not amount or amount <= 0 or amount == math.huge then
		return false
	end
	if reward.Type == "Coins" then
		profile.States.Coins += math.floor(amount)
		return true
	elseif reward.Type == "Diamonds" then
		profile.States.Diamonds += math.floor(amount)
		return true
	end
	return false
end

function reward_service.on_player_added(player)
	session_data.reset(player.UserId)
	data_service.mutate(player, function(profile)
		profile.PlaytimeRewards.ClaimedRewards = {}
		profile.PlaytimeRewards.SessionStart = os.time()
	end)
end

function reward_service.on_player_removing(player)
	session_data.clear(player.UserId)
end

function reward_service.daily_status(player)
	local profile = data_service.get(player)
	if not profile then
		return nil
	end
	local daily = profile.DailyRewards
	local now = os.time()
	local last_claim = tonumber(daily.LastClaim) or 0
	local days = daily.ClaimedDays
	local all_unlocked = daily.AllUnlocked == true
	local elapsed = now - last_claim
	local days_passed = math.floor(elapsed / seconds_per_day)
	local reset = false

	if days_passed >= 2 and #days > 0 and not all_unlocked then
		reset = true
	elseif #days >= #daily_config.Rewards then
		reset = true
	end
	if reset then
		data_service.mutate(player, function(data)
			data.DailyRewards.LastClaim = 0
			data.DailyRewards.ClaimedDays = {}
			data.DailyRewards.AllUnlocked = false
		end)
		profile = data_service.get(player)
		daily = profile.DailyRewards
		last_claim = daily.LastClaim
		days = daily.ClaimedDays
		all_unlocked = daily.AllUnlocked
		elapsed = now - last_claim
	end

	local current_day = #days + 1
	local can_claim = last_claim == 0 or elapsed >= seconds_per_day
	return {
		CurrentDay = current_day,
		CanClaimNext = can_claim,
		TimeUntilNext = can_claim and 0 or math.max(0, seconds_per_day - elapsed),
		ClaimedDays = table.clone(days),
		AllUnlocked = all_unlocked,
	}
end

function reward_service.claim_daily(player, day_number)
	if type(day_number) ~= "number" or day_number % 1 ~= 0 or not daily_config.Rewards[day_number] then
		return false
	end
	local status = reward_service.daily_status(player)
	if not status then
		return false
	end
	local can_claim = false
	if status.AllUnlocked then
		can_claim = not contains(status.ClaimedDays, day_number)
	else
		can_claim = day_number == status.CurrentDay and status.CanClaimNext and not contains(status.ClaimedDays, day_number)
	end
	if not can_claim then
		return false
	end
	local claimed = false
	local ok = data_service.mutate(player, function(profile)
		local daily = profile.DailyRewards
		if contains(daily.ClaimedDays, day_number) then
			return
		end
		if not grant_reward(profile, daily_config.Rewards[day_number]) then
			return
		end
		table.insert(daily.ClaimedDays, day_number)
		if #daily.ClaimedDays >= #daily_config.Rewards then
			daily.LastClaim = 0
			daily.ClaimedDays = {}
			daily.AllUnlocked = false
		else
			daily.LastClaim = os.time()
		end
		claimed = true
	end)
	return ok and claimed
end

function reward_service.unlock_daily_in_profile(profile)
	if not profile or not profile.DailyRewards then
		return false
	end
	profile.DailyRewards.AllUnlocked = true
	return true
end

function reward_service.playtime_status(player)
	local profile = data_service.get(player)
	if not profile then
		return nil
	end
	local session = session_data.PlayerSessions[player.UserId]
	if not session then
		session = session_data.reset(player.UserId)
	end
	return {
		ClaimedRewards = table.clone(profile.PlaytimeRewards.ClaimedRewards),
		SessionTime = math.max(0, os.time() - session.SessionStart),
		AllUnlocked = session.AllUnlocked == true,
	}
end

function reward_service.claim_playtime(player, reward_index)
	if type(reward_index) ~= "number" or reward_index % 1 ~= 0 or not playtime_config.Rewards[reward_index] then
		return false
	end
	local status = reward_service.playtime_status(player)
	if not status or contains(status.ClaimedRewards, reward_index) then
		return false
	end
	local reward = playtime_config.Rewards[reward_index]
	if not status.AllUnlocked and status.SessionTime < reward.Time then
		return false
	end
	local claimed = false
	local ok = data_service.mutate(player, function(profile)
		if contains(profile.PlaytimeRewards.ClaimedRewards, reward_index) then
			return
		end
		if not grant_reward(profile, reward) then
			return
		end
		table.insert(profile.PlaytimeRewards.ClaimedRewards, reward_index)
		claimed = true
		if #profile.PlaytimeRewards.ClaimedRewards >= #playtime_config.Rewards then
			profile.PlaytimeRewards.ClaimedRewards = {}
			profile.PlaytimeRewards.SessionStart = os.time()
			local session = session_data.PlayerSessions[player.UserId] or session_data.reset(player.UserId)
			session.SessionStart = os.time()
			session.AllUnlocked = false
		end
	end)
	return ok and claimed
end

function reward_service.grant_all_unclaimed_playtime_in_profile(profile)
	if not profile or not profile.States or not profile.PlaytimeRewards then
		return false
	end
	local claimed = profile.PlaytimeRewards.ClaimedRewards
	for index, reward in ipairs(playtime_config.Rewards) do
		if not contains(claimed, index) then
			if not grant_reward(profile, reward) then
				error("invalid playtime reward at index " .. tostring(index))
			end
		end
	end
	local cycle_start = os.time()
	profile.PlaytimeRewards.ClaimedRewards = {}
	profile.PlaytimeRewards.SessionStart = cycle_start
	return true, cycle_start
end

function reward_service.grant_reward_in_profile(profile, reward)
	return grant_reward(profile, reward)
end

return reward_service
