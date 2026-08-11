-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local replicated_storage = game:GetService("ReplicatedStorage")

local economy_service = require(script.Parent.economy_service)

local combo_service = {}

local timer_event = replicated_storage:WaitForChild("RemoteEvents"):WaitForChild("TimerEvent")

local near_miss_enter_distance = 7
local near_miss_escape_distance = 13
local streak_interval = 15
local near_miss_base_coins = 25
local streak_base_coins = 20
local streak_base_diamonds = 1

local states = {}

local function multiplier_for_count(count)
	count = math.max(0, math.floor(tonumber(count) or 0))
	if count >= 4 then
		return 8
	elseif count == 3 then
		return 4
	elseif count == 2 then
		return 2
	end
	return 1
end

local function state_for(player)
	local state = states[player.UserId]
	if not state then
		state = {
			active_npcs = {},
			near_misses = {},
			active_count = 0,
			multiplier = 1,
			streak_seconds = 0,
			next_streak_bonus = streak_interval,
			total_near_misses = 0,
			peak_multiplier = 1,
		}
		states[player.UserId] = state
	end
	return state
end

local function fire(player, action, data)
	if player.Parent then
		timer_event:FireClient(player, action, data)
	end
end

local function sync_attributes(player, state)
	player:SetAttribute("RageNPCs", state.active_count)
	player:SetAttribute("RageMultiplier", state.multiplier)
	player:SetAttribute("RageStreak", state.streak_seconds)
	player:SetAttribute("RageNearMisses", state.total_near_misses)
	player:SetAttribute("RagePeakMultiplier", state.peak_multiplier)
end

local function make_payload(state)
	return {
		ActiveNPCs = state.active_count,
		Multiplier = state.multiplier,
		StreakSeconds = state.streak_seconds,
		NearMisses = state.total_near_misses,
		PeakMultiplier = state.peak_multiplier,
	}
end

local function update_multiplier(player, state, active_count)
	state.active_count = math.max(0, math.floor(tonumber(active_count) or 0))
	state.multiplier = multiplier_for_count(state.active_count)
	state.peak_multiplier = math.max(state.peak_multiplier, state.multiplier)
	sync_attributes(player, state)
	fire(player, "ComboUpdate", make_payload(state))
end

function combo_service.on_player_added(player)
	states[player.UserId] = nil
	local state = state_for(player)
	sync_attributes(player, state)
	fire(player, "ComboReset", make_payload(state))
end

function combo_service.on_chase_started(player, npc, active_count)
	local state = state_for(player)
	if state.active_count <= 0 then
		state.streak_seconds = 0
		state.next_streak_bonus = streak_interval
		state.total_near_misses = 0
		state.peak_multiplier = 1
	end
	state.active_npcs[npc] = true
	state.near_misses[npc] = {
		entered_danger = false,
		awarded = false,
		closest_distance = math.huge,
	}
	update_multiplier(player, state, active_count)
end

function combo_service.on_chase_ended(player, npc, reason, active_count)
	local state = state_for(player)
	state.active_npcs[npc] = nil
	state.near_misses[npc] = nil
	active_count = math.max(0, math.floor(tonumber(active_count) or 0))

	local combo_broken = (reason == "caught" and active_count <= 0) or reason == "death"
	if combo_broken or active_count <= 0 then
		local previous = make_payload(state)
		state.active_npcs = {}
		state.near_misses = {}
		state.active_count = 0
		state.multiplier = 1
		state.streak_seconds = 0
		state.next_streak_bonus = streak_interval
		state.total_near_misses = 0
		state.peak_multiplier = 1
		sync_attributes(player, state)
		previous.Reason = reason
		fire(player, "ComboReset", previous)
		return
	end

	update_multiplier(player, state, active_count)
end

function combo_service.sample_near_miss(player, npc, distance)
	if type(distance) ~= "number" or distance ~= distance then
		return
	end
	local state = state_for(player)
	local near = state.near_misses[npc]
	if not near or near.awarded then
		return
	end

	near.closest_distance = math.min(near.closest_distance, distance)
	if distance <= near_miss_enter_distance then
		near.entered_danger = true
		return
	end
	if not near.entered_danger or distance < near_miss_escape_distance then
		return
	end

	near.awarded = true
	state.total_near_misses += 1
	local requested_coins = near_miss_base_coins * state.multiplier
	local ok, actual_coins = economy_service.add_combo_reward(player, requested_coins, 0)
	if not ok then
		return
	end
	sync_attributes(player, state)
	fire(player, "NearMiss", {
		Coins = actual_coins or requested_coins,
		Diamonds = 0,
		Multiplier = state.multiplier,
		ClosestDistance = near.closest_distance,
		NearMisses = state.total_near_misses,
	})
end

function combo_service.tick(player)
	local state = state_for(player)
	if state.active_count <= 0 then
		return
	end
	state.streak_seconds += 1
	sync_attributes(player, state)
	fire(player, "ComboTick", make_payload(state))

	if state.streak_seconds < state.next_streak_bonus then
		return
	end
	state.next_streak_bonus += streak_interval
	local requested_coins = streak_base_coins * state.multiplier
	local requested_diamonds = streak_base_diamonds * state.multiplier
	local ok, actual_coins, actual_diamonds = economy_service.add_combo_reward(player, requested_coins, requested_diamonds)
	if not ok then
		return
	end
	fire(player, "StreakBonus", {
		Seconds = state.streak_seconds,
		Coins = actual_coins or requested_coins,
		Diamonds = actual_diamonds or requested_diamonds,
		Multiplier = state.multiplier,
	})
end

function combo_service.multiplier(player)
	return state_for(player).multiplier
end

function combo_service.status(player)
	return make_payload(state_for(player))
end

function combo_service.reset(player, reason)
	local state = state_for(player)
	local previous = make_payload(state)
	states[player.UserId] = nil
	local fresh = state_for(player)
	sync_attributes(player, fresh)
	previous.Reason = reason or "reset"
	fire(player, "ComboReset", previous)
end

function combo_service.remove_player(player)
	states[player.UserId] = nil
end

return combo_service
