-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

-- scores server-observed movement violations over time instead of trusting
-- client reports or removing a player after one noisy physics sample.

local players = game:GetService("Players")
local run_service = game:GetService("RunService")

local character_service = require(script.Parent.character_service)

local anti_cheat_service = {}

local check_interval = 0.2
local teleport_attribute = "AntiCheatTeleportUntil"
local flag_count_attribute = "AntiCheatFlags"
local flag_reason_attribute = "AntiCheatLastReason"
local kick_score = 10
local score_decay_per_second = 0.12
local rolling_window_time = 1.5
local speed_tolerance = 0.4
local ping_speed_tolerance_cap = 0.2
local airborne_grace = 3.5

local trackers = {}
local character_connections = {}
local started = false

local suspicious_force_classes = {
	BodyVelocity = true,
	BodyPosition = true,
	BodyGyro = true,
	BodyAngularVelocity = true,
	LinearVelocity = true,
	AngularVelocity = true,
	VectorForce = true,
	AlignPosition = true,
	AlignOrientation = true,
	RocketPropulsion = true,
}

local function disconnect_all(connections)
	if not connections then
		return
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function network_ping(player)
	local ping = 0
	pcall(function()
		ping = player:GetNetworkPing()
	end)
	return math.clamp(tonumber(ping) or 0, 0, 0.75)
end

local function decay_score(tracker, now)
	local elapsed = math.max(0, now - (tracker.last_score_update or now))
	tracker.score = math.max(0, (tracker.score or 0) - elapsed * score_decay_per_second)
	tracker.last_score_update = now
end

local function flag(player, tracker, reason, weight)
	local now = os.clock()
	decay_score(tracker, now)
	tracker.score += weight or 1
	tracker.flags += 1
	tracker.last_reason = reason
	player:SetAttribute(flag_count_attribute, tracker.flags)
	player:SetAttribute(flag_reason_attribute, reason)

	local last_warning = tracker.warning_times[reason] or 0
	if now - last_warning >= 2 then
		tracker.warning_times[reason] = now
		warn(string.format("[anti-cheat] %s flagged: %s (score %.2f)", player.Name, reason, tracker.score))
	end

	if tracker.score >= kick_score and not run_service:IsStudio() and player.Parent then
		player:Kick("Unauthorized movement was detected.")
	end
end

local function position_is_finite(position)
	return position.X == position.X
		and position.Y == position.Y
		and position.Z == position.Z
		and math.abs(position.X) < 1e6
		and math.abs(position.Y) < 1e6
		and math.abs(position.Z) < 1e6
end

local function reset_movement(tracker, position, now)
	tracker.last_position = position
	tracker.last_valid_position = position
	tracker.last_check = now
	tracker.window_distance = 0
	tracker.window_expected_distance = 0
	tracker.window_time = 0
	tracker.suspicious_windows = 0
	tracker.airborne_time = 0
	tracker.hover_samples = 0
	tracker.upward_samples = 0
end

local function rubber_band(player, tracker, root, reason, weight)
	if not root or not root.Parent or not tracker.last_valid_position then
		return
	end
	local now = os.clock()
	if now < (tracker.last_rubber_band or 0) + 0.75 then
		return
	end
	tracker.last_rubber_band = now
	flag(player, tracker, reason, weight or 2)
	player:SetAttribute(teleport_attribute, now + 1.25)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.new(tracker.last_valid_position) * root.CFrame.Rotation
	reset_movement(tracker, root.Position, now)
end

local function force_is_allowed(object)
	if object:GetAttribute("AntiCheatAllowed") == true then
		return true
	end
	if object:IsA("BodyForce") and object.Name == "GravityCoilEffect" then
		local tool = object:FindFirstAncestorOfClass("Tool")
		return tool ~= nil and tool.Name == "GravityCoil"
	end
	return false
end

local function remove_suspicious_force(player, tracker, object)
	if not object or not object.Parent or not suspicious_force_classes[object.ClassName] or force_is_allowed(object) then
		return
	end
	flag(player, tracker, "unauthorized physics mover: " .. object.ClassName, 2)
	object:Destroy()
end

local function movement_profile(player)
	local ok, profile = pcall(character_service.movement_profile, player)
	if ok and type(profile) == "table" then
		return profile
	end
	return {
		WalkSpeed = 16,
		JumpPower = 50,
		JumpHeight = 7.2,
		IsCaught = false,
		IsChasing = false,
		IsInWater = false,
		HasSpeedCoil = false,
		HasGravityCoil = false,
	}
end

local function enforce_properties(player, tracker)
	if tracker.correcting or not tracker.character or player.Character ~= tracker.character then
		return
	end
	local humanoid = tracker.humanoid
	local root = tracker.root
	if not humanoid or not root or not humanoid.Parent or not root.Parent then
		return
	end

	local profile = movement_profile(player)
	local expected_speed = tonumber(profile.WalkSpeed) or 16
	local expected_jump_power = tonumber(profile.JumpPower) or 50
	local expected_jump_height = tonumber(profile.JumpHeight) or 7.2
	local now = os.clock()
	local server_transition_until = tonumber(player:GetAttribute("AntiCheatMovementUntil")) or 0
	local transition_active = now < math.max(tracker.movement_transition_until or 0, server_transition_until)
	tracker.correcting = true

	local current_speed = humanoid.WalkSpeed
	if math.abs(current_speed - expected_speed) > 0.05 then
		if current_speed > expected_speed + 0.05 and not transition_active then
			flag(player, tracker, string.format("walkspeed %.2f while allowed %.2f", current_speed, expected_speed), 1.25)
		end
		humanoid.WalkSpeed = expected_speed
	end
	if humanoid.JumpPower > expected_jump_power + 0.1 and not transition_active then
		flag(player, tracker, string.format("jumppower %.2f while allowed %.2f", humanoid.JumpPower, expected_jump_power), 1.25)
	end
	if math.abs(humanoid.JumpPower - expected_jump_power) > 0.1 then
		humanoid.JumpPower = expected_jump_power
	end
	if humanoid.JumpHeight > expected_jump_height + 0.1 and not transition_active then
		flag(player, tracker, string.format("jumpheight %.2f while allowed %.2f", humanoid.JumpHeight, expected_jump_height), 1.25)
	end
	if math.abs(humanoid.JumpHeight - expected_jump_height) > 0.1 then
		humanoid.JumpHeight = expected_jump_height
	end
	if root.CanCollide ~= true then
		flag(player, tracker, "root collision disabled", 1.5)
		root.CanCollide = true
	end
	if root.Massless ~= false then
		flag(player, tracker, "root made massless", 1.5)
		root.Massless = false
	end
	if root.Anchored then
		flag(player, tracker, "character root anchored", 1.5)
		root.Anchored = false
	end
	if tracker.root_size and (root.Size - tracker.root_size).Magnitude > 0.05 then
		flag(player, tracker, "character root size modified", 1.5)
		root.Size = tracker.root_size
	end
	if tracker.hip_height and math.abs(humanoid.HipHeight - tracker.hip_height) > 0.5 then
		flag(player, tracker, "humanoid hip height modified", 1.25)
		humanoid.HipHeight = tracker.hip_height
	end

	player:SetAttribute("ExpectedWalkSpeed", expected_speed)
	tracker.correcting = false
end

local function queue_enforcement(player, tracker)
	if tracker.enforcement_pending then
		return
	end
	tracker.enforcement_pending = true
	task.defer(function()
		tracker.enforcement_pending = false
		if trackers[player.UserId] == tracker then
			local ok, err = pcall(enforce_properties, player, tracker)
			if not ok then
				tracker.correcting = false
				tracker.grace_until = os.clock() + 1
				warn("[anti-cheat] property enforcement error for " .. player.Name .. ": " .. tostring(err))
			end
		end
	end)
end

local function grounded(character, root, humanoid)
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { character }
	parameters.IgnoreWater = false
	return workspace:Raycast(root.Position, Vector3.new(0, -6, 0), parameters) ~= nil
end

local function bind_character(player, character)
	local tracker = trackers[player.UserId]
	if not tracker then
		return
	end
	disconnect_all(tracker.connections)
	tracker.connections = {}
	tracker.character = character
	tracker.humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	tracker.root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	tracker.grace_until = os.clock() + 3
	tracker.movement_transition_until = os.clock() + 3

	local humanoid = tracker.humanoid
	local root = tracker.root
	if not humanoid or not root then
		return
	end
	tracker.root_size = root.Size
	tracker.hip_height = humanoid.HipHeight
	reset_movement(tracker, root.Position, os.clock())

	for _, property_name in ipairs({ "WalkSpeed", "JumpPower", "JumpHeight", "HipHeight" }) do
		table.insert(tracker.connections, humanoid:GetPropertyChangedSignal(property_name):Connect(function()
			queue_enforcement(player, tracker)
		end))
	end
	for _, property_name in ipairs({ "CanCollide", "Massless", "Anchored", "Size" }) do
		table.insert(tracker.connections, root:GetPropertyChangedSignal(property_name):Connect(function()
			queue_enforcement(player, tracker)
		end))
	end
	local function note_tool_transition(object)
		if object and object:IsA("Tool") and (object.Name == "SpeedCoil" or object.Name == "GravityCoil") then
			tracker.movement_transition_until = os.clock() + 0.75
			task.delay(0.1, function()
				if trackers[player.UserId] == tracker then
					queue_enforcement(player, tracker)
				end
			end)
		end
	end
	table.insert(tracker.connections, character.ChildAdded:Connect(note_tool_transition))
	table.insert(tracker.connections, character.ChildRemoved:Connect(note_tool_transition))
	table.insert(tracker.connections, character.DescendantAdded:Connect(function(object)
		task.defer(remove_suspicious_force, player, tracker, object)
	end))

	for _, object in ipairs(character:GetDescendants()) do
		remove_suspicious_force(player, tracker, object)
	end
	queue_enforcement(player, tracker)
end

local function inspect_movement(player, tracker, now)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or character ~= tracker.character or not root or not humanoid or humanoid.Health <= 0 then
		tracker.last_position = nil
		tracker.last_valid_position = nil
		tracker.last_check = now
		return
	end
	tracker.root = root
	tracker.humanoid = humanoid
	enforce_properties(player, tracker)

	local position = root.Position
	if not position_is_finite(position) then
		flag(player, tracker, "invalid character position", 4)
		if tracker.last_valid_position then
			player:SetAttribute(teleport_attribute, now + 1.25)
			root.CFrame = CFrame.new(tracker.last_valid_position)
		end
		return
	end

	local teleport_until = tonumber(player:GetAttribute(teleport_attribute)) or 0
	if now < tracker.grace_until or now < teleport_until then
		reset_movement(tracker, position, now)
		return
	end
	if not tracker.last_position then
		reset_movement(tracker, position, now)
		return
	end

	local dt = now - tracker.last_check
	if dt <= 0 or dt > 1.25 then
		reset_movement(tracker, position, now)
		return
	end
	local profile = movement_profile(player)
	local expected_speed = math.max(0, tonumber(profile.WalkSpeed) or 16)
	local server_transition_until = tonumber(player:GetAttribute("AntiCheatMovementUntil")) or 0
	if now < math.max(tracker.movement_transition_until or 0, server_transition_until) then
		reset_movement(tracker, position, now)
		return
	end
	local delta = position - tracker.last_position
	local horizontal_distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local ping = network_ping(player)
	local burst_limit = math.max(35, expected_speed * dt + 12 + expected_speed * ping)

	if horizontal_distance > burst_limit then
		rubber_band(player, tracker, root, string.format("impossible displacement %.1f studs", horizontal_distance), 3)
		return
	end

	tracker.window_distance += horizontal_distance
	tracker.window_expected_distance += expected_speed * dt
	tracker.window_time += dt
	if tracker.window_time >= rolling_window_time then
		local average_speed = tracker.window_distance / math.max(tracker.window_time, 0.01)
		local expected_average = tracker.window_expected_distance / math.max(tracker.window_time, 0.01)
		local allowed_average = expected_average + speed_tolerance + math.min(ping_speed_tolerance_cap, ping * 0.5)
		if average_speed > allowed_average then
			tracker.suspicious_windows += 1
			flag(player, tracker, string.format("sustained movement %.1f while allowed %.1f", average_speed, expected_average), 1.25)
			if tracker.suspicious_windows >= 2 then
				rubber_band(player, tracker, root, "repeated speed bypass", 2)
				return
			end
		else
			tracker.suspicious_windows = math.max(0, tracker.suspicious_windows - 1)
			tracker.last_valid_position = position
		end
		tracker.window_distance = 0
		tracker.window_expected_distance = 0
		tracker.window_time = 0
	end

	if profile.IsCaught or profile.IsInWater or profile.HasGravityCoil then
		tracker.airborne_time = 0
		tracker.hover_samples = 0
		tracker.upward_samples = 0
	elseif grounded(character, root, humanoid) then
		tracker.airborne_time = 0
		tracker.hover_samples = 0
		tracker.upward_samples = 0
	else
		tracker.airborne_time += dt
		local vertical_speed = root.AssemblyLinearVelocity.Y
		if vertical_speed > 95 then
			tracker.upward_samples += 1
			if tracker.upward_samples >= 2 then
				rubber_band(player, tracker, root, "impossible upward velocity", 2.5)
				return
			end
		else
			tracker.upward_samples = math.max(0, tracker.upward_samples - 1)
		end
		if tracker.airborne_time > airborne_grace and math.abs(vertical_speed) < 8 then
			tracker.hover_samples += 1
			if tracker.hover_samples >= 4 then
				rubber_band(player, tracker, root, "sustained hovering", 2.5)
				return
			end
		else
			tracker.hover_samples = math.max(0, tracker.hover_samples - 1)
		end
	end

	tracker.last_position = position
	tracker.last_check = now
end

function anti_cheat_service.track(player)
	if trackers[player.UserId] then
		return
	end
	local now = os.clock()
	local tracker = {
		connections = {},
		last_position = nil,
		last_valid_position = nil,
		last_check = now,
		window_distance = 0,
		window_expected_distance = 0,
		window_time = 0,
		suspicious_windows = 0,
		airborne_time = 0,
		hover_samples = 0,
		upward_samples = 0,
		grace_until = now + 3,
		movement_transition_until = now + 3,
		last_rubber_band = 0,
		score = 0,
		flags = 0,
		last_score_update = now,
		last_reason = "",
		warning_times = {},
		correcting = false,
		enforcement_pending = false,
	}
	trackers[player.UserId] = tracker
	player:SetAttribute(flag_count_attribute, 0)
	player:SetAttribute(flag_reason_attribute, "")
	character_connections[player.UserId] = player.CharacterAdded:Connect(function(character)
		bind_character(player, character)
	end)
	if player.Character then
		task.defer(bind_character, player, player.Character)
	end
end

function anti_cheat_service.untrack(player)
	local tracker = trackers[player.UserId]
	if tracker then
		disconnect_all(tracker.connections)
	end
	trackers[player.UserId] = nil
	if character_connections[player.UserId] then
		character_connections[player.UserId]:Disconnect()
		character_connections[player.UserId] = nil
	end
end

function anti_cheat_service.status(player)
	local tracker = trackers[player.UserId]
	if not tracker then
		return nil
	end
	local profile = movement_profile(player)
	return {
		Flags = tracker.flags,
		Score = tracker.score,
		LastReason = tracker.last_reason,
		ExpectedWalkSpeed = profile.WalkSpeed,
		IsChasing = profile.IsChasing,
		IsCaught = profile.IsCaught,
		IsInWater = profile.IsInWater,
		HasSpeedCoil = profile.HasSpeedCoil,
		HasGravityCoil = profile.HasGravityCoil,
	}
end

function anti_cheat_service.start()
	if started then
		return
	end
	started = true
	for _, player in ipairs(players:GetPlayers()) do
		anti_cheat_service.track(player)
	end
	task.spawn(function()
		while true do
			task.wait(check_interval)
			local now = os.clock()
			for _, player in ipairs(players:GetPlayers()) do
				local tracker = trackers[player.UserId]
				if not tracker then
					anti_cheat_service.track(player)
				else
					decay_score(tracker, now)
					local ok, err = pcall(inspect_movement, player, tracker, now)
					if not ok then
						tracker.correcting = false
						tracker.grace_until = now + 1
						warn("[anti-cheat] inspection error for " .. player.Name .. ": " .. tostring(err))
					end
				end
			end
		end
	end)
	print("[anti-cheat] authoritative movement validation active")
end

return anti_cheat_service
