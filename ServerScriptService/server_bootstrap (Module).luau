-- composition root for server systems. all client requests enter through the
-- validated and rate-limited adapters configured in this module.

local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local server_storage = game:GetService("ServerStorage")

local rate_limiter = require(replicated_storage.Modules.rate_limiter)
local table_util = require(replicated_storage.Modules.table_util)
local data_service = require(script.Parent.data_service)
local economy_service = require(script.Parent.economy_service)
local entitlement_service = require(script.Parent.entitlement_service)
local inventory_service = require(script.Parent.inventory_service)
local reward_service = require(script.Parent.reward_service)
local crate_service = require(script.Parent.crate_service)
local character_service = require(script.Parent.character_service)
local chase_service = require(script.Parent.chase_service)
local anti_cheat_service = require(script.Parent.anti_cheat_service)
local upgrade_service = require(script.Parent.upgrade_service)
local skin_shop_service = require(script.Parent.skin_shop_service)
local monetization_service = require(script.Parent.monetization_service)
local shop_storage = require(script.Parent.ShopHandler.ShopStorage)

local server_bootstrap = {}

local started = false
local setting_up = {}
local removing = {}
local respawn_connections = {}
local group_cooldowns = {}
local limiter = rate_limiter.new()
local profile_lock_retry_time = 20
local join_watchdog_time = 60

local remote_events = replicated_storage:WaitForChild("RemoteEvents")
local remote_functions = replicated_storage:WaitForChild("RemoteFunctions")
local bindable_events = server_storage:WaitForChild("BindableEvents")
local bindable_functions = server_storage:WaitForChild("BindableFunctions")

local function ensure_bindable_function(name)
	local object = bindable_functions:FindFirstChild(name)
	if object and object:IsA("BindableFunction") then
		return object
	end
	if object then
		object:Destroy()
	end
	object = Instance.new("BindableFunction")
	object.Name = name
	object.Parent = bindable_functions
	return object
end

local function bind_character_respawn(player, character)
	if respawn_connections[player.UserId] then
		respawn_connections[player.UserId]:Disconnect()
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	respawn_connections[player.UserId] = humanoid.Died:Connect(function()
		task.delay(3, function()
			if player.Parent and data_service.get(player) and player.Character == character then
				character_service.spawn(player)
			end
		end)
	end)
end

local function safe_join_step(player, name, callback)
	local ok, result = xpcall(callback, debug.traceback)
	if not ok then
		warn(string.format("[join] %s failed for %s: %s", name, player.Name, tostring(result)))
	end
	return ok, result
end

local function load_profile_for_join(player)
	local deadline = os.clock() + profile_lock_retry_time
	local last_reason
	repeat
		local loaded, reason = data_service.load(player)
		if loaded then
			return true
		end
		last_reason = reason
		if reason ~= "locked" or os.clock() >= deadline then
			break
		end
		player:SetAttribute("JoinState", "WaitingForPreviousServer")
		task.wait(2)
	until not player.Parent
	return false, last_reason
end

local function spawn_join_character(player)
	for attempt = 1, 3 do
		if not player.Parent then
			return false
		end
		local ok, spawned = safe_join_step(player, "character spawn", function()
			return character_service.spawn(player)
		end)
		if ok and spawned == true and player.Character then
			return true
		end
		if attempt == 1 then
			data_service.mutate(player, function(profile)
				profile.SkinEquipped = "WhiteChicken"
				profile.SkinType = "Chicken"
			end)
		end
		task.wait(0.5 * attempt)
	end
	return false
end

local function setup_player(player)
	local user_id = player.UserId
	if setting_up[user_id] then
		return
	end
	if data_service.get(player) and player.Character then
		player:SetAttribute("DataLoaded", true)
		player:SetAttribute("CharacterReady", true)
		player:SetAttribute("JoinState", "Ready")
		return
	end

	setting_up[user_id] = true
	player:SetAttribute("DataLoaded", data_service.get(player) ~= nil)
	player:SetAttribute("CharacterReady", false)
	player:SetAttribute("JoinState", "LoadingData")

	local ok, err = xpcall(function()
		if not data_service.get(player) then
			local loaded, reason = load_profile_for_join(player)
			if not loaded then
				if player.Parent then
					if reason == "locked" then
						player:Kick("Your profile is still active on another server. Please rejoin in a moment.")
					else
						player:Kick("Your data could not be loaded safely. Please rejoin.")
					end
				end
				return
			end
		end
		if not player.Parent then
			return
		end

		player:SetAttribute("DataLoaded", true)
		player:SetAttribute("JoinState", "SpawningCharacter")
		safe_join_step(player, "anti-cheat tracking", function()
			anti_cheat_service.track(player)
		end)
		if not spawn_join_character(player) then
			error("character could not be spawned after three attempts")
		end

		player:SetAttribute("CharacterReady", true)
		player:SetAttribute("JoinState", "Ready")
		print("Data loaded and character ready for: " .. player.Name)

		safe_join_step(player, "reward initialization", function()
			reward_service.on_player_added(player)
		end)
		safe_join_step(player, "crate initialization", function()
			crate_service.on_player_added(player)
		end)
		safe_join_step(player, "chase initialization", function()
			chase_service.on_player_added(player)
		end)
		task.spawn(function()
			safe_join_step(player, "entitlement reconciliation", function()
				entitlement_service.reconcile(player)
			end)
		end)
	end, debug.traceback)

	setting_up[user_id] = nil
	if not ok then
		warn("[join] setup failed for " .. player.Name .. ": " .. tostring(err))
		if player.Parent then
			player:Kick("Your character could not be initialized safely. Please rejoin.")
		end
	end
end

local function watch_join(player)
	task.delay(join_watchdog_time, function()
		if player.Parent and player:GetAttribute("CharacterReady") ~= true then
			warn("[join] watchdog removed stalled player " .. player.Name .. " in state " .. tostring(player:GetAttribute("JoinState")))
			player:Kick("Joining took too long. Please reconnect.")
		end
	end)
end

local function remove_player(player)
	if removing[player.UserId] then
		return
	end
	removing[player.UserId] = true
	chase_service.on_player_removing(player)
	crate_service.on_player_removing(player)
	reward_service.on_player_removing(player)
	inventory_service.clear_player(player)
	character_service.clear_player(player)
	anti_cheat_service.untrack(player)
	monetization_service.clear_player(player)
	if respawn_connections[player.UserId] then
		respawn_connections[player.UserId]:Disconnect()
		respawn_connections[player.UserId] = nil
	end
	local saved = data_service.save_with_retry(player, true, 3)
	if not saved then
		warn("[data] critical: failed to save " .. player.Name .. " after 3 attempts")
	else
		data_service.publish_leaderboards(player)
	end
	data_service.remove(player)
	group_cooldowns[player.UserId] = nil
	limiter:clear_prefix("data:" .. tostring(player.UserId))
	limiter:clear_prefix("timer:" .. tostring(player.UserId))
	limiter:clear_prefix("inventory:" .. tostring(player.UserId))
	limiter:clear_prefix("skin:" .. tostring(player.UserId))
	limiter:clear_prefix("daily:" .. tostring(player.UserId))
	limiter:clear_prefix("playtime:" .. tostring(player.UserId))
	limiter:clear_prefix("crate:" .. tostring(player.UserId))
	limiter:clear_prefix("crate_open:" .. tostring(player.UserId))
	limiter:clear_prefix("upgrade:" .. tostring(player.UserId))
	removing[player.UserId] = nil
end

local function setup_bindables()
	local data_update = bindable_events:WaitForChild("DataUpdateEvent")
	local player_data_function = bindable_functions:WaitForChild("PlayerDataFunctionBin")
	local chicken_function = bindable_functions:WaitForChild("ChickenHandler")
	local npc_function = bindable_functions:WaitForChild("NpcHandler")
	local save_function = ensure_bindable_function("SavePlayerDataFunction")
	local gamepass_function = ensure_bindable_function("GrantGamePassFunction")

	player_data_function.OnInvoke = function(player, demand)
		if demand == "Stats" then
			return economy_service.get_stats(player)
		end
		return nil
	end
	chicken_function.OnInvoke = function(player)
		return character_service.state(player)
	end
	npc_function.OnInvoke = function(player)
		return chase_service.state(player)
	end
	save_function.OnInvoke = function(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false
		end
		return data_service.save(player, false, true)
	end
	gamepass_function.OnInvoke = function(player, pass_id)
		return entitlement_service.grant(player, pass_id, true)
	end

	data_update.Event:Connect(function(player, action, value)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not data_service.get(player) then
			return
		end
		if action == "ChangeTime" then
			economy_service.add_survival_time(player, value)
		elseif action == "ChangeMoney" then
			economy_service.add_coins(player, value)
		elseif action == "ChangeDiamond" then
			economy_service.add_diamonds(player, value)
		elseif action == "AddItem" and type(value) == "table" and type(value.ID) == "string" and type(value.Data) == "table" then
			inventory_service.add_item(player, value.ID, table_util.deep_copy(value.Data))
		elseif action == "AddGamePass" and type(value) == "number" and entitlement_service.is_known(value) then
			entitlement_service.grant(player, value, false)
		end
	end)
end

local function setup_remote_functions()
	local data_function = remote_functions:WaitForChild("DataFunction")
	local timer_function = remote_functions:WaitForChild("TimerFunction")

	data_function.OnServerInvoke = function(player, action, request)
		if not limiter:allow("data:" .. tostring(player.UserId), 0.15) then
			return nil
		end
		if action ~= "Get" or type(request) ~= "string" then
			return nil
		end
		if request == "Inventory" then
			return inventory_service.status(player)
		elseif request == "Stats" then
			return economy_service.get_stats(player)
		end
		return nil
	end

	timer_function.OnServerInvoke = function(player)
		if not limiter:allow("timer:" .. tostring(player.UserId), 0.15) then
			return nil
		end
		return character_service.state(player)
	end
end

local function setup_inventory_remote()
	local event = remote_events:WaitForChild("InventoryEvent")
	event.OnServerEvent:Connect(function(player, action, item_key)
		local interval = action == "GetStatus" and 0.15 or 0.25
		if not limiter:allow("inventory:" .. tostring(player.UserId), interval) then
			return
		end
		if action == "GetStatus" then
			event:FireClient(player, "UpdateStatus", inventory_service.status(player))
		elseif action == "EquipTool" then
			inventory_service.equip_tool(player, item_key)
			event:FireClient(player, "UpdateStatus", inventory_service.status(player))
		elseif action == "UnequipTool" then
			inventory_service.unequip_tool(player)
			event:FireClient(player, "UpdateStatus", inventory_service.status(player))
		elseif action == "DeleteTool" then
			inventory_service.delete_item(player, item_key)
			event:FireClient(player, "UpdateStatus", inventory_service.status(player))
		end
	end)
end

local function setup_skin_remote()
	local event = remote_events:WaitForChild("SkinEvent")
	event.OnServerEvent:Connect(function(player, action, skin_name, skin_type, skin_key)
		if not limiter:allow("skin:" .. tostring(player.UserId), 0.4) then
			return
		end
		if action == "ChangeSkin" then
			local changed = inventory_service.change_skin(player, skin_name, skin_type, skin_key)
			event:FireClient(player, "SkinChanged", changed, skin_name, inventory_service.status(player))
		end
	end)
end

local function setup_daily_remote()
	local event = remote_events:WaitForChild("DailyRewardsEvent")
	event.OnServerEvent:Connect(function(player, action, day_number)
		if not limiter:allow("daily:" .. tostring(player.UserId), 0.25) then
			return
		end
		if action == "GetStatus" then
			event:FireClient(player, "UpdateStatus", reward_service.daily_status(player))
		elseif action == "ClaimReward" then
			if reward_service.claim_daily(player, day_number) then
				event:FireClient(player, "ClaimSuccess", day_number)
			end
			event:FireClient(player, "UpdateStatus", reward_service.daily_status(player))
		end
	end)
end

local function setup_playtime_remote()
	local event = remote_events:WaitForChild("PlaytimeEvent")
	event.OnServerEvent:Connect(function(player, action, reward_index)
		if not limiter:allow("playtime:" .. tostring(player.UserId), 0.25) then
			return
		end
		if action == "GetStatus" then
			event:FireClient(player, "UpdateStatus", reward_service.playtime_status(player))
		elseif action == "ClaimReward" then
			if reward_service.claim_playtime(player, reward_index) then
				event:FireClient(player, "ClaimSuccess", reward_index)
			end
			event:FireClient(player, "UpdateStatus", reward_service.playtime_status(player))
		end
	end)
end

local function setup_crate_remotes()
	local event = remote_events:WaitForChild("CrateEvent")
	local open_event = remote_events:WaitForChild("CrateOpenEvent")

	event.OnServerEvent:Connect(function(player, action, value)
		local interval = action == "GetStatus" and 0.15 or 0.25
		if not limiter:allow("crate:" .. tostring(player.UserId), interval) then
			return
		end
		if action == "GetStatus" then
			event:FireClient(player, "UpdateStatus", crate_service.status(player))
		elseif action == "BuyCrateCoins" then
			local success, reason = crate_service.buy_with_coins(player, value)
			if success then
				event:FireClient(player, "PurchaseSuccess", value)
			else
				event:FireClient(player, "PurchaseFailed", reason)
			end
			event:FireClient(player, "UpdateStatus", crate_service.status(player))
		elseif action == "OpenCrate" then
			local reward, reason = crate_service.open(player, value)
			if reward then
				event:FireClient(player, "OpenSuccess", reward)
			else
				event:FireClient(player, "OpenFailed", reason)
			end
		end
	end)

	open_event.OnServerEvent:Connect(function(player, action, crate_key)
		if not limiter:allow("crate_open:" .. tostring(player.UserId), 0.12) then
			return
		end
		if action == "OpenCrate" then
			if type(crate_key) ~= "string" or #crate_key > 200 then
				return
			end
			local profile = data_service.get(player)
			local item = profile and profile.InventoryItems[crate_key]
			local crate_name = item and item.IsCrate and item.CrateName
			local reward = crate_service.open(player, crate_key)
			if reward and crate_name then
				crate_service.set_pending(player, reward)
				open_event:FireClient(player, "StartOpen", {
					CrateName = crate_name,
					ToolName = reward.ToolName,
					Image = reward.Image,
					Chance = reward.Chance,
				})
			end
		elseif action == "RequestReward" then
			local reward = crate_service.take_pending(player)
			if reward then
				open_event:FireClient(player, "RewardResult", reward)
				remote_events.InventoryEvent:FireClient(player, "UpdateStatus", inventory_service.status(player))
			end
		end
	end)
end

local function setup_upgrade_remote()
	local event = remote_events:WaitForChild("UpgradesEvent")
	event.OnServerEvent:Connect(function(player, action, value)
		if not limiter:allow("upgrade:" .. tostring(player.UserId), 0.3) then
			return
		end
		if action == "GetStatus" then
			event:FireClient(player, "UpdateStatus", upgrade_service.status(player))
		elseif action == "BuyUpgrade" then
			local success, reason = upgrade_service.buy(player, value)
			if success then
				event:FireClient(player, "PurchaseSuccess", value)
			else
				event:FireClient(player, "PurchaseFailed", reason)
			end
			event:FireClient(player, "UpdateStatus", upgrade_service.status(player))
		end
	end)
end

local function setup_group_reward()
	local trigger = workspace.Map:WaitForChild("GroupRewardTrigger")
	local message_event = remote_events:WaitForChild("MessageEvent")
	trigger.Touched:Connect(function(part)
		local character = part and part:FindFirstAncestorOfClass("Model")
		local player = character and players:GetPlayerFromCharacter(character)
		if not player or not data_service.get(player) then
			return
		end
		local now = os.clock()
		if group_cooldowns[player.UserId] and now - group_cooldowns[player.UserId] < 3 then
			return
		end
		group_cooldowns[player.UserId] = now
		local profile = data_service.get(player)
		if profile.HasClaimedGroupReward then
			message_event:FireClient(player, "Already claimed")
			return
		end
		local in_group = false
		pcall(function()
			in_group = player:IsInGroupAsync(263486617)
		end)
		if not in_group then
			message_event:FireClient(player, "Join the group to claim your reward")
			return
		end
		local money_pass_id = shop_storage.Gamepasses["2X Money"].ID
		data_service.mutate(player, function(data)
			if data.HasClaimedGroupReward then
				return
			end
			data.HasClaimedGroupReward = true
			data.States.Coins += table.find(data.GamePasses, money_pass_id) and 400 or 200
		end)
	end)
end

function server_bootstrap.start()
	if started then
		return
	end
	started = true
	players.CharacterAutoLoads = false
	setup_bindables()
	setup_remote_functions()
	setup_inventory_remote()
	setup_skin_remote()
	setup_daily_remote()
	setup_playtime_remote()
	setup_crate_remotes()
	setup_upgrade_remote()
	setup_group_reward()

	character_service.set_chase_state_provider(chase_service.state)
	inventory_service.set_skin_changed_callback(character_service.spawn)
	character_service.on_spawn(function(player, character)
		chase_service.on_character_spawned(player)
		bind_character_respawn(player, character)
		task.delay(1.5, function()
			if player.Parent and player.Character == character then
				inventory_service.restore_equipped_tool(player)
			end
		end)
	end)

	chase_service.start()
	anti_cheat_service.start()
	skin_shop_service.start()
	monetization_service.start()
	data_service.start_background_tasks()

	players.PlayerAdded:Connect(function(player)
		watch_join(player)
		task.spawn(setup_player, player)
	end)
	players.PlayerRemoving:Connect(remove_player)
	for _, player in ipairs(players:GetPlayers()) do
		watch_join(player)
		task.spawn(setup_player, player)
	end

	game:BindToClose(function()
		local remaining = 0
		for _, player in ipairs(players:GetPlayers()) do
			if data_service.get(player) then
				remaining += 1
				task.spawn(function()
					data_service.save_with_retry(player, true, 2)
					remaining -= 1
				end)
			end
		end
		local started_at = os.clock()
		while remaining > 0 and os.clock() - started_at < 25 do
			task.wait(0.1)
		end
	end)
end

return server_bootstrap
