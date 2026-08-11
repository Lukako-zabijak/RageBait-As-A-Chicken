local data_store_service = game:GetService("DataStoreService")
local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local run_service = game:GetService("RunService")

local table_util = require(replicated_storage.Modules.table_util)
local storage = require(script.Parent.PlayerDataManager.StorageModule)

local data_service = {}

local profile_store = data_store_service:GetDataStore("PlayerData_V14")
local money_store = data_store_service:GetOrderedDataStore("Money")
local diamonds_store = data_store_service:GetOrderedDataStore("Diamonds")

local session_id = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))
local session_timeout = 300
local heartbeat_interval = 45
local autosave_interval = 90
local max_receipts = 200

local states = {}
local name_cache = {}
local started = false

local function default_profile()
	return table_util.deep_copy(storage.PlrData.Default)
end

local function finite_integer(value, fallback, minimum, maximum)
	if not table_util.is_finite_number(value) then
		return fallback
	end
	value = math.floor(value)
	if minimum then
		value = math.max(minimum, value)
	end
	if maximum then
		value = math.min(maximum, value)
	end
	return value
end

local function clean_string(value, fallback, maximum_length)
	if type(value) ~= "string" then
		return fallback
	end
	if maximum_length and #value > maximum_length then
		return string.sub(value, 1, maximum_length)
	end
	return value
end

local function sanitize_inventory(raw_inventory)
	local inventory = {}
	if type(raw_inventory) ~= "table" then
		return inventory
	end
	local accepted = 0
	for key, raw_item in pairs(raw_inventory) do
		if accepted >= 1000 then
			break
		end
		if type(key) == "string" and #key <= 200 and type(raw_item) == "table" then
			local item = {}
			if raw_item.IsSkin == true then
				local skin_name = clean_string(raw_item.SkinName, nil, 80)
				local skin_type = clean_string(raw_item.SkinType, nil, 40)
				if skin_name and skin_type then
					item.IsSkin = true
					item.SkinName = skin_name
					item.SkinType = skin_type
				end
			elseif raw_item.IsCrate == true then
				local crate_name = clean_string(raw_item.CrateName, nil, 100)
				if crate_name then
					item.IsCrate = true
					item.CrateName = crate_name
					item.Image = clean_string(raw_item.Image, "", 300)
				end
			else
				local display_name = clean_string(raw_item.DisplayName, nil, 100)
				if display_name then
					item.IsCrate = false
					item.DisplayName = display_name
					item.Image = clean_string(raw_item.Image, "", 300)
				end
			end
			if next(item) then
				inventory[key] = item
				accepted += 1
			end
		end
	end
	return inventory
end

local function sanitize_number_array(raw, minimum, maximum, limit)
	local result = {}
	local seen = {}
	if type(raw) ~= "table" then
		return result
	end
	for _, value in ipairs(raw) do
		if #result >= limit then
			break
		end
		if table_util.is_finite_number(value) then
			local integer = math.floor(value)
			if integer >= minimum and integer <= maximum and not seen[integer] then
				seen[integer] = true
				table.insert(result, integer)
			end
		end
	end
	return result
end

local function sanitize_profile(raw)
	local profile = default_profile()
	if type(raw) ~= "table" then
		return profile
	end

	profile.DataVersion = 1
	local states_raw = type(raw.States) == "table" and raw.States or {}
	profile.States.Coins = finite_integer(states_raw.Coins, 0, 0, 9e15)
	profile.States.Diamonds = finite_integer(states_raw.Diamonds, 0, 0, 9e15)
	profile.States.TimeSurvived = finite_integer(states_raw.TimeSurvived, 0, 0, 9e15)

	profile.SkinEquipped = clean_string(raw.SkinEquipped, "WhiteChicken", 80)
	profile.SkinType = clean_string(raw.SkinType, "Chicken", 40)
	profile.TutorialCompleted = raw.TutorialCompleted == true
	profile.HasClaimedGroupReward = raw.HasClaimedGroupReward == true
	profile.EquippedTool = clean_string(raw.EquippedTool, "", 200)
	profile.InventoryItems = sanitize_inventory(raw.InventoryItems)
	if not profile.InventoryItems.WhiteChicken then
		profile.InventoryItems.WhiteChicken = {
			IsSkin = true,
			SkinName = "WhiteChicken",
			SkinType = "Chicken",
		}
	end

	profile.GamePasses = sanitize_number_array(raw.GamePasses, 1, 9e15, 50)
	profile.GamePassRewards = {}
	if type(raw.GamePassRewards) == "table" then
		for key, value in pairs(raw.GamePassRewards) do
			if type(key) == "string" and #key <= 64 and value == true then
				profile.GamePassRewards[key] = true
			end
		end
	end

	profile.ProcessedReceipts = {}
	if type(raw.ProcessedReceipts) == "table" then
		local receipts = {}
		for purchase_id, timestamp in pairs(raw.ProcessedReceipts) do
			if type(purchase_id) == "string" and #purchase_id <= 160 then
				table.insert(receipts, {
					id = purchase_id,
					time = finite_integer(timestamp, 0, 0, 9e15),
				})
			end
		end
		table.sort(receipts, function(a, b)
			return a.time > b.time
		end)
		for index = 1, math.min(max_receipts, #receipts) do
			profile.ProcessedReceipts[receipts[index].id] = receipts[index].time
		end
	end

	local daily = type(raw.DailyRewards) == "table" and raw.DailyRewards or {}
	profile.DailyRewards.LastClaim = finite_integer(daily.LastClaim, 0, 0, 9e15)
	profile.DailyRewards.ClaimedDays = sanitize_number_array(daily.ClaimedDays, 1, 7, 7)
	profile.DailyRewards.AllUnlocked = daily.AllUnlocked == true

	local playtime = type(raw.PlaytimeRewards) == "table" and raw.PlaytimeRewards or {}
	profile.PlaytimeRewards.ClaimedRewards = sanitize_number_array(playtime.ClaimedRewards, 1, 8, 8)
	profile.PlaytimeRewards.SessionStart = finite_integer(playtime.SessionStart, 0, 0, 9e15)

	local stock = type(raw.CrateStock) == "table" and raw.CrateStock or {}
	profile.CrateStock.Stock = {}
	if type(stock.Stock) == "table" then
		for crate_name, amount in pairs(stock.Stock) do
			if type(crate_name) == "string" and #crate_name <= 100 then
				profile.CrateStock.Stock[crate_name] = finite_integer(amount, 0, 0, 1000)
			end
		end
	end
	profile.CrateStock.LastRestock = finite_integer(stock.LastRestock, 0, 0, 9e15)

	local upgrades = type(raw.Upgrades) == "table" and raw.Upgrades or {}
	profile.Upgrades.InventorySpace = finite_integer(upgrades.InventorySpace, 1, 1, 4)
	profile.Upgrades.MultiRagebait = finite_integer(upgrades.MultiRagebait, 1, 1, 4)

	return profile
end

local function get_state(user_id)
	local state = states[user_id]
	if not state then
		state = {
			mutation_busy = false,
			save_busy = false,
			dirty = false,
			revision = 0,
			loaded = false,
		}
		states[user_id] = state
	end
	return state
end

local function acquire_mutation(user_id)
	local state = get_state(user_id)
	while state.mutation_busy do
		task.wait()
	end
	state.mutation_busy = true
	return state
end

local function release_mutation(state)
	state.mutation_busy = false
end

local function sync_leaderstats(player)
	local profile = storage.PlrData[player.UserId]
	if not profile then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local values = {
		Coins = profile.States.Coins,
		["Time Survived"] = profile.States.TimeSurvived,
		Diamonds = profile.States.Diamonds,
	}
	for name, value in pairs(values) do
		local object = leaderstats:FindFirstChild(name)
		if not object then
			object = Instance.new("IntValue")
			object.Name = name
			object.Parent = leaderstats
		end
		object.Value = value
	end
end

function data_service.get(player_or_user_id)
	local user_id = typeof(player_or_user_id) == "Instance" and player_or_user_id.UserId or player_or_user_id
	return storage.PlrData[user_id]
end

function data_service.snapshot(player_or_user_id)
	local profile = data_service.get(player_or_user_id)
	return profile and table_util.deep_copy(profile) or nil
end

function data_service.mutate(player_or_user_id, callback)
	local user_id = typeof(player_or_user_id) == "Instance" and player_or_user_id.UserId or player_or_user_id
	local profile = storage.PlrData[user_id]
	if not profile or type(callback) ~= "function" then
		return false, "profile_unavailable"
	end
	local state = acquire_mutation(user_id)
	local ok, result_a, result_b, result_c = xpcall(function()
		return callback(profile)
	end, debug.traceback)
	if ok then
		state.revision += 1
		state.dirty = true
	end
	release_mutation(state)
	if not ok then
		warn("[data] mutation failed for " .. tostring(user_id) .. ": " .. tostring(result_a))
		return false, result_a
	end
	local player = players:GetPlayerByUserId(user_id)
	if player then
		sync_leaderstats(player)
	end
	return true, result_a, result_b, result_c
end

function data_service.mark_dirty(player_or_user_id)
	local user_id = typeof(player_or_user_id) == "Instance" and player_or_user_id.UserId or player_or_user_id
	local state = get_state(user_id)
	state.revision += 1
	state.dirty = true
end

function data_service.load(player)
	local user_id = player.UserId
	local state = get_state(user_id)
	if state.loaded and storage.PlrData[user_id] then
		return true
	end

	if run_service:IsStudio() then
		storage.PlrData[user_id] = default_profile()
		state.loaded = true
		state.dirty = false
		state.revision = 0
		sync_leaderstats(player)
		print("Studio session using isolated temporary data for " .. player.Name)
		return true
	end

	local last_error
	for attempt = 1, 3 do
		local claimed_profile
		local locked = false
		local ok, err = pcall(function()
			profile_store:UpdateAsync(tostring(user_id), function(current)
				local current_session = type(current) == "table" and type(current._Session) == "table" and current._Session or nil
				if current_session then
					local owner = current_session.JobId
					local last_seen = tonumber(current_session.LastSeen) or 0
					if owner and owner ~= session_id and os.time() - last_seen < session_timeout then
						locked = true
						return nil
					end
				end
				local profile = sanitize_profile(current)
				profile._Session = {
					JobId = session_id,
					LastSeen = os.time(),
				}
				claimed_profile = table_util.deep_copy(profile)
				return profile
			end)
		end)
		if ok and locked then
			return false, "locked"
		end
		if ok and claimed_profile then
			claimed_profile._Session = nil
			storage.PlrData[user_id] = sanitize_profile(claimed_profile)
			state.loaded = true
			state.dirty = false
			state.revision = 0
			sync_leaderstats(player)
			return true
		end
		last_error = err
		if attempt < 3 then
			task.wait(attempt)
		end
	end
	return false, tostring(last_error or "load_failed")
end

local function build_snapshot(user_id)
	local state = acquire_mutation(user_id)
	local profile = storage.PlrData[user_id]
	if not profile then
		release_mutation(state)
		return nil
	end
	local snapshot = sanitize_profile(profile)
	local revision = state.revision
	release_mutation(state)
	return snapshot, revision
end

function data_service.save(player, release_session, force)
	local user_id = player.UserId
	local state = get_state(user_id)
	if not storage.PlrData[user_id] then
		return false
	end
	if run_service:IsStudio() then
		return true
	end
	if not force and not state.dirty and not release_session then
		return true
	end
	while state.save_busy do
		task.wait(0.05)
	end
	state.save_busy = true

	local snapshot, revision = build_snapshot(user_id)
	if not snapshot then
		state.save_busy = false
		return false
	end

	local ok, err = pcall(function()
		profile_store:UpdateAsync(tostring(user_id), function(current)
			local session = type(current) == "table" and type(current._Session) == "table" and current._Session or nil
			if session then
				local owner = session.JobId
				local last_seen = tonumber(session.LastSeen) or 0
				if owner and owner ~= session_id and os.time() - last_seen < session_timeout then
					error("profile session belongs to another live server")
				end
			end
			if release_session then
				snapshot._Session = nil
			else
				snapshot._Session = {
					JobId = session_id,
					LastSeen = os.time(),
				}
			end
			return snapshot
		end)
	end)

	if ok then
		if state.revision == revision then
			state.dirty = false
		end
	else
		warn("[data] save failed for " .. player.Name .. ": " .. tostring(err))
	end
	state.save_busy = false
	return ok
end

function data_service.save_with_retry(player, release_session, attempts)
	attempts = attempts or 3
	for attempt = 1, attempts do
		if data_service.save(player, release_session, true) then
			return true
		end
		if attempt < attempts then
			task.wait(attempt)
		end
	end
	return false
end

function data_service.transaction(player, callback)
	if type(callback) ~= "function" then
		return false, "invalid_callback"
	end
	local user_id = player.UserId
	local state = get_state(user_id)
	if not storage.PlrData[user_id] then
		return false, "profile_unavailable"
	end
	while state.save_busy do
		task.wait(0.05)
	end
	state.save_busy = true
	state = acquire_mutation(user_id)
	local profile = storage.PlrData[user_id]
	local before = table_util.deep_copy(profile)
	local ok, result_a, result_b = xpcall(function()
		return callback(profile)
	end, debug.traceback)
	if not ok then
		storage.PlrData[user_id] = before
		release_mutation(state)
		state.save_busy = false
		warn("[data] transaction callback failed for " .. player.Name .. ": " .. tostring(result_a))
		return false, result_a
	end
	state.revision += 1
	state.dirty = true
	local snapshot = sanitize_profile(profile)

	local saved = true
	local save_error
	if not run_service:IsStudio() then
		saved, save_error = pcall(function()
			profile_store:UpdateAsync(tostring(user_id), function(current)
				local session = type(current) == "table" and type(current._Session) == "table" and current._Session or nil
				if session then
					local owner = session.JobId
					local last_seen = tonumber(session.LastSeen) or 0
					if owner and owner ~= session_id and os.time() - last_seen < session_timeout then
						error("profile session belongs to another live server")
					end
				end
				snapshot._Session = {
					JobId = session_id,
					LastSeen = os.time(),
				}
				return snapshot
			end)
		end)
	end

	if saved then
		state.dirty = false
	else
		storage.PlrData[user_id] = before
		state.revision += 1
		state.dirty = true
	end
	release_mutation(state)
	state.save_busy = false
	sync_leaderstats(player)
	if not saved then
		warn("[data] transaction persistence failed for " .. player.Name .. ": " .. tostring(save_error))
		return false, save_error
	end
	return true, result_a, result_b
end

function data_service.heartbeat(player)
	if run_service:IsStudio() or not storage.PlrData[player.UserId] then
		return true
	end
	local user_id = player.UserId
	local ok = pcall(function()
		profile_store:UpdateAsync(tostring(user_id), function(current)
			if type(current) ~= "table" then
				return nil
			end
			local session = type(current._Session) == "table" and current._Session or nil
			if session and session.JobId and session.JobId ~= session_id then
				return nil
			end
			current._Session = {
				JobId = session_id,
				LastSeen = os.time(),
			}
			return current
		end)
	end)
	return ok
end

function data_service.publish_leaderboards(player)
	if run_service:IsStudio() then
		return
	end
	local profile = storage.PlrData[player.UserId]
	if not profile then
		return
	end
	task.spawn(function()
		pcall(function()
			money_store:SetAsync(tostring(player.UserId), profile.States.Coins)
		end)
	end)
	task.spawn(function()
		pcall(function()
			diamonds_store:SetAsync(tostring(player.UserId), profile.States.Diamonds)
		end)
	end)
end

local function player_name(user_id)
	if name_cache[user_id] then
		return name_cache[user_id]
	end
	local ok, name = pcall(players.GetNameFromUserIdAsync, players, tonumber(user_id))
	if ok and name then
		name_cache[user_id] = name
		return name
	end
	return "User " .. tostring(user_id)
end

local function compact(value)
	if value >= 1_000_000 then
		return string.format("%.1fm", value / 1_000_000)
	elseif value >= 1_000 then
		return string.format("%.1fk", value / 1_000)
	end
	return tostring(value)
end

local function render_board(store, scrolling_frame)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 100)
	end)
	if not ok or not pages then
		return
	end
	for _, child in ipairs(scrolling_frame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local template = replicated_storage.Stuff:FindFirstChild("LeaderboardTemplate")
	if not template then
		return
	end
	for rank, entry in ipairs(pages:GetCurrentPage()) do
		local frame = template:Clone()
		frame.Name = tostring(entry.key)
		frame.Rank.Text = "#" .. tostring(rank)
		frame.Username.Text = player_name(entry.key)
		frame.Score.Text = compact(entry.value)
		frame.Parent = scrolling_frame
	end
end

function data_service.refresh_global_leaderboards()
	if run_service:IsStudio() then
		return
	end
	local map = workspace:FindFirstChild("Map")
	local board = map and map:FindFirstChild("Leaderboard")
	if not board then
		return
	end
	local money_frame = board:FindFirstChild("MoneyLeaderboard")
	local diamond_frame = board:FindFirstChild("DiamondLeaderboard")
	local money_scroll = money_frame and money_frame:FindFirstChild("SurfaceGui") and money_frame.SurfaceGui:FindFirstChild("Frame") and money_frame.SurfaceGui.Frame:FindFirstChild("ScrollingFrame")
	local diamond_scroll = diamond_frame and diamond_frame:FindFirstChild("SurfaceGui") and diamond_frame.SurfaceGui:FindFirstChild("Frame") and diamond_frame.SurfaceGui.Frame:FindFirstChild("ScrollingFrame")
	if money_scroll then
		render_board(money_store, money_scroll)
	end
	if diamond_scroll then
		render_board(diamonds_store, diamond_scroll)
	end
end

function data_service.remove(player)
	storage.PlrData[player.UserId] = nil
	states[player.UserId] = nil
end

function data_service.sync_leaderstats(player)
	sync_leaderstats(player)
end

function data_service.start_background_tasks()
	if started then
		return
	end
	started = true

	task.spawn(function()
		while true do
			task.wait(heartbeat_interval)
			for index, player in ipairs(players:GetPlayers()) do
				task.delay((index - 1) * 0.35, function()
					if player.Parent and storage.PlrData[player.UserId] then
						data_service.heartbeat(player)
					end
				end)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(autosave_interval)
			for index, player in ipairs(players:GetPlayers()) do
				task.delay((index - 1) * 0.75, function()
					if player.Parent and storage.PlrData[player.UserId] then
						data_service.save(player, false, false)
					end
				end)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(120)
			for index, player in ipairs(players:GetPlayers()) do
				task.delay((index - 1) * 0.25, function()
					if player.Parent then
						data_service.publish_leaderboards(player)
					end
				end)
			end
			data_service.refresh_global_leaderboards()
		end
	end)
end

return data_service
