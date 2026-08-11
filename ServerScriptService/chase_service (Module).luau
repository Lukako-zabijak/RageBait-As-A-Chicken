local players = game:GetService("Players")
local pathfinding_service = game:GetService("PathfindingService")
local replicated_storage = game:GetService("ReplicatedStorage")
local server_storage = game:GetService("ServerStorage")
local debris = game:GetService("Debris")

local data_service = require(script.Parent.data_service)
local economy_service = require(script.Parent.economy_service)
local combo_service = require(script.Parent.combo_service)
local personality_config = require(script.Parent.npc_personality_config)
local character_service = require(script.Parent.character_service)
local upgrades_config = require(replicated_storage.Modules.UpgradesConfig)

local chase_service = {}

local rage_threshold = 5
local rage_decay_time = 10
local chase_delay = 2
local dialogue_delay = 1.5
local interaction_debounce = 3.5
local path_refresh_interval = 0.35
local target_repath_distance = 5
local waypoint_reached_distance = 3
local stuck_distance = 1
local stuck_repath_time = 1
local stuck_recovery_time = 1.8
local recovery_duration = 0.55
local escape_click_min_interval = 0.03
local escape_click_reset_time = 2.5
local escape_clicks_required = 5
local angry_face_id = "rbxassetid://110991019542836"
local normal_face_id = "rbxasset://textures/face.png"

local remote_events = replicated_storage:WaitForChild("RemoteEvents")
local hook_event = remote_events:WaitForChild("HookUpEvent")
local timer_event = remote_events:WaitForChild("TimerEvent")
local camera_event = remote_events:WaitForChild("CameraEvent")
local tutorial_event = remote_events:WaitForChild("TutorialEvent")
local dialogue_event = remote_events:WaitForChild("DialogueEvent")

local npc_folder = workspace.Map:WaitForChild("NPC")
local stick_folder = workspace.Map:WaitForChild("StickParts")

local player_states = {}
local npc_rage = {}
local npc_origins = {}
local npc_default_speeds = {}
local npc_personality_tags = {}
local npc_prompts = {}
local prompt_connections = {}
local active_chases = {}
local active_counts = {}
local tutorials = {}
local captures = {}
local timer_tokens = {}
local started = false

local tutorial_steps = {
	{ type = "RagebaitNPC", text = "Talk to an NPC", count = 1 },
	{ type = "RagebaitNPC", text = "Keep talking to them...", count = 2 },
	{ type = "RagebaitNPC", text = "One more time...", count = 3 },
	{ type = "RagebaitNPC", text = "They're getting angry!", count = 4 },
	{ type = "RagebaitNPC", text = "One last time!", count = 5 },
	{ type = "Run", text = "RUN!" },
	{ type = "GetCaught", text = "Get caught by the NPC" },
}

local dialogue = {
	[1] = { npc = "Hello there!", player = "Hi!" },
	[2] = { npc = "Can I help you?", player = "Just looking around..." },
	[3] = { npc = "You again?", player = "Hehe..." },
	[4] = { npc = "Stop bothering me!", player = "But I'm bored!" },
	[5] = { npc = "THAT'S IT! GET BACK HERE!", player = "Uh oh... RUN!" },
}

local path_settings = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	AgentJumpHeight = 10,
	AgentMaxSlope = 45,
	WaypointSpacing = 3,
}

local function personality_for(player, npc)
	local tutorial = tutorials[player.UserId]
	if tutorial and tutorial.active then
		return personality_config.classic()
	end
	return personality_config.for_npc(npc.Name)
end

local function ensure_personality_tag(npc)
	local existing = npc_personality_tags[npc]
	if existing and existing.Parent then
		return existing
	end
	local head = npc:FindFirstChild("Head") or npc:FindFirstChild("HumanoidRootPart")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local billboard = head:FindFirstChild("PersonalityTag")
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "PersonalityTag"
		billboard.Adornee = head
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 90
		billboard.Size = UDim2.fromOffset(190, 38)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
		billboard.Enabled = false
		billboard.Parent = head

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.FontFace = Font.new(
			"rbxasset://fonts/families/ComicNeueAngular.json",
			Enum.FontWeight.Regular,
			Enum.FontStyle.Normal
		)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 1
		label.TextScaled = true
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Parent = billboard

		local stroke = Instance.new("UIStroke")
		stroke.Name = "UIStroke"
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 3
		stroke.Transparency = 0
		stroke.LineJoinMode = Enum.LineJoinMode.Bevel
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
	end
	npc_personality_tags[npc] = billboard
	return billboard
end

local function set_personality_tag(npc, profile, enabled, override_text)
	local billboard = ensure_personality_tag(npc)
	if not billboard then
		return
	end
	billboard.Enabled = enabled == true
	if not profile then
		return
	end
	local label = billboard:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = override_text or string.upper(profile.Name)
		label.TextColor3 = profile.Color
		local stroke = label:FindFirstChild("Stroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Color = profile.Color
		end
	end
end

local function state_for(player)
	local state = player_states[player.UserId]
	if not state then
		state = {
			IsBeingChased = false,
			ChaseActive = false,
			HasBeenCaught = false,
		}
		player_states[player.UserId] = state
	end
	return state
end

local function active_count(player)
	return active_counts[player.UserId] or 0
end

local function set_active_count(player, value)
	active_counts[player.UserId] = math.max(0, value)
end

local function multi_ragebait_limit(player)
	local profile = data_service.get(player)
	if not profile then
		return 1
	end
	local level = math.clamp(tonumber(profile.Upgrades.MultiRagebait) or 1, 1, 4)
	for _, upgrade in ipairs(upgrades_config.Upgrades) do
		if upgrade.Name == "Multi Ragebait" then
			local data = upgrade.Levels[level]
			return data and data.Value or 1
		end
	end
	return 1
end

local function npc_models()
	local result = {}
	for _, child in ipairs(npc_folder:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") and child:FindFirstChild("HumanoidRootPart") then
			table.insert(result, child)
		end
	end
	return result
end

local function set_prompt(npc, enabled)
	local prompt = npc_prompts[npc]
	if prompt then
		prompt.Enabled = enabled
	end
end

local function set_all_prompts(enabled)
	for npc, prompt in pairs(npc_prompts) do
		if npc.Parent and prompt.Parent then
			prompt.Enabled = enabled
		end
	end
end

local function nearest_npc(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best
	local best_distance = math.huge
	for _, npc in ipairs(npc_models()) do
		local npc_root = npc:FindFirstChild("HumanoidRootPart")
		if npc_root then
			local distance = (npc_root.Position - root.Position).Magnitude
			if distance < best_distance then
				best_distance = distance
				best = npc
			end
		end
	end
	return best
end

local function tutorial_step(player)
	local tutorial = tutorials[player.UserId]
	if not tutorial or not tutorial.active then
		return nil
	end
	return tutorial_steps[tutorial.step]
end

local function emit_tutorial_step(player)
	local tutorial = tutorials[player.UserId]
	local step = tutorial_step(player)
	if not tutorial or not step then
		return
	end
	if step.type == "RagebaitNPC" then
		if not tutorial.target or not tutorial.target.Parent then
			tutorial.target = nearest_npc(player.Character)
		end
		set_all_prompts(false)
		if tutorial.target then
			set_prompt(tutorial.target, true)
			tutorial_event:FireClient(player, "StartStep", {
				Text = step.text,
				TargetType = "NPC",
				TargetNPC = tutorial.target.Name,
			})
		end
	elseif step.type == "Run" then
		tutorial_event:FireClient(player, "StartStep", {
			Text = step.text,
			TargetType = "Run",
		})
	elseif step.type == "GetCaught" then
		tutorial_event:FireClient(player, "StartStep", {
			Text = step.text,
			TargetType = "GetCaught",
		})
	end
end

local function advance_tutorial(player)
	local tutorial = tutorials[player.UserId]
	if not tutorial or not tutorial.active then
		return
	end
	tutorial.step += 1
	if tutorial.step <= #tutorial_steps then
		emit_tutorial_step(player)
	end
end

local function complete_tutorial(player)
	local tutorial = tutorials[player.UserId]
	if not tutorial or not tutorial.active then
		return
	end
	tutorial.active = false
	data_service.mutate(player, function(profile)
		profile.TutorialCompleted = true
	end)
	set_all_prompts(true)
	tutorial_event:FireClient(player, "CompleteTutorial")
end

local function start_tutorial(player)
	local profile = data_service.get(player)
	if not profile then
		return
	end
	if profile.TutorialCompleted then
		tutorials[player.UserId] = nil
		set_all_prompts(true)
		tutorial_event:FireClient(player, "SkipTutorial")
		return
	end
	tutorials[player.UserId] = {
		step = 1,
		ragebait_count = 0,
		target = nearest_npc(player.Character),
		active = true,
		waiting_for_catch = false,
		waiting_for_escape = false,
	}
	emit_tutorial_step(player)
end

local function return_npc(npc)
	local origin = npc_origins[npc]
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not origin or not humanoid or not root then
		return
	end
	for _ = 1, 3 do
		local path = pathfinding_service:CreatePath(path_settings)
		local ok = pcall(function()
			path:ComputeAsync(root.Position, origin.Position)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local success = true
			for _, waypoint in ipairs(path:GetWaypoints()) do
				if not npc.Parent then
					return
				end
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				humanoid:MoveTo(waypoint.Position)
				local reached = false
				local finished = false
				local connection
				connection = humanoid.MoveToFinished:Connect(function(value)
					reached = value
					finished = true
				end)
				local started_at = os.clock()
				while not finished and os.clock() - started_at < 5 do
					task.wait(0.05)
				end
				connection:Disconnect()
				if not reached then
					success = false
					break
				end
			end
			if success then
				root.CFrame = origin
				return
			end
		end
		task.wait(0.2)
	end
	root.CFrame = origin
end

local function normal_face(npc)
	local head = npc:FindFirstChild("Head")
	local face = head and head:FindFirstChild("face")
	if face and face:IsA("Decal") then
		face.Texture = normal_face_id
	end
end

local function angry_face(npc)
	local head = npc:FindFirstChild("Head")
	local face = head and head:FindFirstChild("face")
	if face and face:IsA("Decal") then
		face.Texture = angry_face_id
	end
end

local function stop_timer(player)
	local token = timer_tokens[player.UserId]
	if token then
		token.running = false
	end
end

local function start_timer(player)
	if timer_tokens[player.UserId] and timer_tokens[player.UserId].running then
		return
	end
	local token = { running = true }
	timer_tokens[player.UserId] = token
	timer_event:FireClient(player, "StartTimer")
	task.spawn(function()
		local earned_time = 0
		while token.running and player.Parent and state_for(player).ChaseActive do
			task.wait(1)
			if not token.running or not state_for(player).ChaseActive then
				break
			end
			local rage_multiplier = combo_service.multiplier(player)
			local water_multiplier = character_service.is_in_water(player) and 2 or 1
			earned_time += water_multiplier * rage_multiplier
			combo_service.tick(player)
		end
		if timer_tokens[player.UserId] == token then
			timer_tokens[player.UserId] = nil
		end
		timer_event:FireClient(player, "StopTimer")
		if earned_time > 0 and player.Parent and data_service.get(player) then
			economy_service.add_survival_time(player, earned_time)
		end
	end)
end

local function stop_chase_visuals_if_last(player, was_caught)
	if active_count(player) > 0 then
		return
	end
	local state = state_for(player)
	state.IsBeingChased = false
	state.ChaseActive = false
	state.HasBeenCaught = was_caught == true
	camera_event:FireClient(player, "DecreaseFOV", 20)
	stop_timer(player)
	character_service.apply_movement(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local music = root:FindFirstChild("ChaseMusic")
		if music and music:IsA("Sound") then
			music:Stop()
			music:Destroy()
		end
	end
end

local function release_capture(player, escaped)
	local capture = captures[player.UserId]
	if not capture then
		return
	end
	captures[player.UserId] = nil
	if capture.weld and capture.weld.Parent then
		capture.weld:Destroy()
	end
	if capture.point and capture.point.Parent then
		capture.point:SetAttribute("Occupied", false)
		if capture.generated then
			capture.point:Destroy()
		end
	end
	if escaped and player.Parent then
		local state = state_for(player)
		state.IsBeingChased = false
		state.ChaseActive = false
		state.HasBeenCaught = false
		set_active_count(player, 0)
		character_service.teleport_to_spawn(player)
		character_service.apply_movement(player)
		hook_event:FireClient(player, "Escaped")
		set_all_prompts(true)
		local tutorial = tutorials[player.UserId]
		if tutorial and tutorial.active then
			tutorial.waiting_for_escape = false
			tutorial_event:FireClient(player, "PlayerEscapedTutorial")
			task.delay(3, function()
				if player.Parent then
					complete_tutorial(player)
				end
			end)
		end
	end
end

local function capture_point()
	for _, point in ipairs(stick_folder:GetChildren()) do
		if point:IsA("BasePart") and point:GetAttribute("Occupied") ~= true then
			return point, false
		end
	end
	local template = stick_folder:FindFirstChildWhichIsA("BasePart")
	if not template then
		return nil, false
	end
	local clone = template:Clone()
	clone.Name = "StickPart_Runtime"
	clone:SetAttribute("Occupied", false)
	local index = #stick_folder:GetChildren()
	clone.CFrame = template.CFrame * CFrame.new((index % 4) * 4, 0, math.floor(index / 4) * 4)
	clone.Parent = stick_folder
	return clone, true
end

local function hook_player(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local point, generated = capture_point()
	if not point then
		warn("[chase] no capture point available for " .. player.Name)
		character_service.teleport_to_spawn(player)
		hook_event:FireClient(player, "Escaped")
		return
	end
	hook_event:FireClient(player, "BlackScreen", 5)
	task.wait(0.5)
	if not player.Parent or player.Character ~= character then
		return
	end
	point:SetAttribute("Occupied", true)
	player:SetAttribute("AntiCheatTeleportUntil", os.clock() + 2)
	root.CFrame = point.CFrame
	local weld = Instance.new("Weld")
	weld.Name = "CaptureWeld"
	weld.Part0 = root
	weld.Part1 = point
	weld.Parent = point
	captures[player.UserId] = {
		point = point,
		weld = weld,
		generated = generated,
		clicks = 0,
		last_click = 0,
	}
	hook_event:FireClient(player, "ButtonClick", 5)
	local tutorial = tutorials[player.UserId]
	if tutorial and tutorial.active then
		tutorial.waiting_for_escape = true
		task.wait(0.8)
		if captures[player.UserId] then
			tutorial_event:FireClient(player, "ShowEscapeText")
		end
	end
end

local function catch_player(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local state = state_for(player)
	state.IsBeingChased = false
	state.ChaseActive = false
	state.HasBeenCaught = true
	character_service.apply_movement(player)
	camera_event:FireClient(player, "DecreaseFOV", 20)
	stop_timer(player)
	tutorial_event:FireClient(player, "PlayerCaughtEvent")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local music = root:FindFirstChild("ChaseMusic")
		if music and music:IsA("Sound") then
			music:Stop()
			music:Destroy()
		end
		local caught_sound = replicated_storage:FindFirstChild("Sounds") and replicated_storage.Sounds:FindFirstChild("CaughtSound")
		if caught_sound then
			local clone = caught_sound:Clone()
			clone.Parent = root
			clone:Play()
			debris:AddItem(clone, math.max(2, clone.TimeLength + 1))
		end
	end
	task.spawn(hook_player, player)
end

local function finish_chase(player, npc, controller, reason)
	if controller.finished then
		return
	end
	controller.finished = true
	controller.running = false
	if controller.blocked_connection then
		controller.blocked_connection:Disconnect()
	end
	if controller.hit_connection then
		controller.hit_connection:Disconnect()
	end
	if controller.death_connection then
		controller.death_connection:Disconnect()
	end
	if controller.hitbox and controller.hitbox.Parent then
		controller.hitbox:Destroy()
	end
	local player_chases = active_chases[player.UserId]
	if player_chases and player_chases[npc] == controller then
		player_chases[npc] = nil
	end
	set_active_count(player, active_count(player) - 1)
	combo_service.on_chase_ended(player, npc, reason, active_count(player))
	local npc_humanoid = npc:FindFirstChildOfClass("Humanoid")
	if npc_humanoid then
		npc_humanoid.WalkSpeed = npc_default_speeds[npc] or 26
	end
	npc:SetAttribute("ActivePersonality", nil)
	npc:SetAttribute("CurrentChaseSpeed", nil)
	npc:SetAttribute("PredictionLead", nil)
	set_personality_tag(npc, nil, false)
	normal_face(npc)
	set_prompt(npc, true)
	task.delay(0.5, function()
		if npc.Parent then
			return_npc(npc)
		end
	end)
	if reason == "caught" and active_count(player) <= 0 then
		catch_player(player)
	elseif reason == "death" and active_count(player) <= 0 then
		stop_chase_visuals_if_last(player, false)
	end
end

local function chase_npc(player, npc)
	if not player.Parent or not npc.Parent then
		return
	end
	if active_count(player) >= multi_ragebait_limit(player) then
		return
	end
	active_chases[player.UserId] = active_chases[player.UserId] or {}
	if active_chases[player.UserId][npc] then
		return
	end
	local character = player.Character
	local target_root = character and character:FindFirstChild("HumanoidRootPart")
	local player_humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local npc_humanoid = npc:FindFirstChildOfClass("Humanoid")
	local npc_root = npc:FindFirstChild("HumanoidRootPart")
	if not target_root or not player_humanoid or not npc_humanoid or not npc_root then
		return
	end

	local personality = personality_for(player, npc)
	npc:SetAttribute("ActivePersonality", personality.Name)
	npc_humanoid.WalkSpeed = personality.WakeDelay and 0 or personality.BaseSpeed
	set_personality_tag(npc, personality, true)

	local first_chase = active_count(player) == 0
	set_active_count(player, active_count(player) + 1)
	local state = state_for(player)
	state.IsBeingChased = true
	state.ChaseActive = true
	state.HasBeenCaught = false
	combo_service.on_chase_started(player, npc, active_count(player))
	character_service.apply_movement(player)
	angry_face(npc)
	set_prompt(npc, false)
	tutorial_event:FireClient(player, "ChaseStartedEvent")

	if first_chase then
		camera_event:FireClient(player, "IncreaseFOV", 20)
		local music_source = replicated_storage:FindFirstChild("Sounds") and replicated_storage.Sounds:FindFirstChild("ChaseMusic")
		if music_source then
			local music = music_source:Clone()
			music.Name = "ChaseMusic"
			music.Looped = true
			music.Parent = target_root
			music:Play()
		end
		start_timer(player)
	end

	local tutorial = tutorials[player.UserId]
	if tutorial and tutorial.active then
		local step = tutorial_step(player)
		if step and step.type == "Run" then
			advance_tutorial(player)
		end
	end

	local started_at = os.clock()
	local controller = {
		running = true,
		finished = false,
		personality = personality,
		started_at = started_at,
		wake_until = personality.WakeDelay and (started_at + personality.WakeDelay) or 0,
		call_attempted = false,
		next_fakeout = personality.FakeOutInterval and (started_at + personality.FakeOutInterval) or math.huge,
		fakeout_pause_until = 0,
		fakeout_burst_until = 0,
		path = pathfinding_service:CreatePath(path_settings),
		waypoints = {},
		waypoint_index = 1,
		path_blocked = true,
		last_compute = 0,
		last_target = target_root.Position,
		last_progress_position = npc_root.Position,
		last_progress_time = os.clock(),
		last_stuck_repath = 0,
		recovery_until = 0,
		recovery_goal = nil,
	}
	active_chases[player.UserId][npc] = controller
	controller.blocked_connection = controller.path.Blocked:Connect(function(blocked_waypoint_index)
		if blocked_waypoint_index >= controller.waypoint_index then
			controller.path_blocked = true
		end
	end)

	local function npc_is_busy(candidate)
		for _, player_chases in pairs(active_chases) do
			local existing = player_chases and player_chases[candidate]
			if existing and not existing.finished then
				return true
			end
		end
		return false
	end

	local function call_for_help(now)
		if not personality.CallDelay or controller.call_attempted or now - controller.started_at < personality.CallDelay then
			return
		end
		controller.call_attempted = true
		if active_count(player) >= multi_ragebait_limit(player) then
			return
		end

		local best_npc
		local best_distance = personality.CallRadius or 60
		for _, candidate in ipairs(npc_models()) do
			if candidate ~= npc and candidate.Parent and not npc_is_busy(candidate) then
				local candidate_root = candidate:FindFirstChild("HumanoidRootPart")
				local candidate_humanoid = candidate:FindFirstChildOfClass("Humanoid")
				if candidate_root and candidate_humanoid and candidate_humanoid.Health > 0 then
					local distance = (candidate_root.Position - npc_root.Position).Magnitude
					if distance <= best_distance then
						best_distance = distance
						best_npc = candidate
					end
				end
			end
		end

		if not best_npc then
			return
		end
		set_personality_tag(npc, personality, true, "CALLING HELP!")
		task.delay(0.8, function()
			if controller.running and npc.Parent then
				set_personality_tag(npc, personality, true)
			end
		end)
		task.delay(0.35, function()
			if controller.running and player.Parent and best_npc.Parent and active_count(player) < multi_ragebait_limit(player) then
				chase_npc(player, best_npc)
			end
		end)
	end

	local hitbox = Instance.new("Part")
	hitbox.Name = "NPCChaseHitbox"
	hitbox.Size = Vector3.new(5, 5, 5)
	hitbox.Transparency = 0.8
	hitbox.Anchored = false
	hitbox.CanCollide = false
	hitbox.CanTouch = true
	hitbox.Massless = true
	hitbox.CFrame = npc_root.CFrame
	hitbox.Parent = workspace
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hitbox
	weld.Part1 = npc_root
	weld.Parent = hitbox
	controller.hitbox = hitbox

	controller.hit_connection = hitbox.Touched:Connect(function(part)
		local touched_character = part and part:FindFirstAncestorOfClass("Model")
		if touched_character ~= player.Character then
			return
		end
		if not touched_character:FindFirstChildOfClass("Humanoid") then
			return
		end
		finish_chase(player, npc, controller, "caught")
	end)

	controller.death_connection = player_humanoid.Died:Connect(function()
		finish_chase(player, npc, controller, "death")
	end)

	local function direct_path_clear(from_position, to_position)
		local origin = from_position
		local ignored = { npc, character }
		for _ = 1, 8 do
			local direction = to_position - origin
			if direction.Magnitude <= 0.1 then
				return true
			end
			local parameters = RaycastParams.new()
			parameters.FilterType = Enum.RaycastFilterType.Exclude
			parameters.FilterDescendantsInstances = ignored
			parameters.IgnoreWater = true
			local result = workspace:Raycast(origin, direction, parameters)
			if not result then
				return true
			end
			local obstacle = result.Instance
			if not obstacle:IsA("BasePart") or obstacle.CanCollide then
				return false
			end
			table.insert(ignored, obstacle)
			origin = result.Position + direction.Unit * 0.05
		end
		return false
	end

	local function choose_recovery_goal(target_position)
		local flat_offset = Vector3.new(target_position.X - npc_root.Position.X, 0, target_position.Z - npc_root.Position.Z)
		if flat_offset.Magnitude <= 0.1 then
			return npc_root.Position
		end
		local forward = flat_offset.Unit
		local right = Vector3.new(-forward.Z, 0, forward.X)
		local candidates = {
			npc_root.Position + right * 7 + forward * 3,
			npc_root.Position - right * 7 + forward * 3,
			npc_root.Position + right * 5 - forward * 2,
			npc_root.Position - right * 5 - forward * 2,
		}
		for _, candidate in ipairs(candidates) do
			if direct_path_clear(npc_root.Position + Vector3.new(0, 2, 0), candidate + Vector3.new(0, 2, 0)) then
				return candidate
			end
		end
		return candidates[math.random(1, 2)]
	end

	local function compute_path(target_position)
		controller.last_compute = os.clock()
		controller.last_target = target_position
		local ok = pcall(function()
			controller.path:ComputeAsync(npc_root.Position, target_position)
		end)
		if ok and controller.path.Status == Enum.PathStatus.Success then
			controller.waypoints = controller.path:GetWaypoints()
			controller.waypoint_index = 1
			while controller.waypoint_index <= #controller.waypoints
				and (controller.waypoints[controller.waypoint_index].Position - npc_root.Position).Magnitude <= waypoint_reached_distance do
				controller.waypoint_index += 1
			end
		else
			controller.waypoints = {}
			controller.waypoint_index = 1
		end
		controller.path_blocked = false
	end

	task.spawn(function()
		while controller.running and player.Parent and npc.Parent and state_for(player).ChaseActive do
			character = player.Character
			target_root = character and character:FindFirstChild("HumanoidRootPart")
			player_humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not target_root or not player_humanoid or not npc_root.Parent or not npc_humanoid.Parent then
				break
			end
			local now = os.clock()
			local elapsed = math.max(0, now - controller.started_at)
			local desired_speed = personality.BaseSpeed
			local paused = false

			if personality.SpeedGainPerSecond then
				desired_speed = math.min(personality.MaximumSpeed or desired_speed, desired_speed + elapsed * personality.SpeedGainPerSecond)
			end
			if personality.WakeDelay and now < controller.wake_until then
				desired_speed = 0
				paused = true
			end
			if personality.FakeOutInterval then
				if now < controller.fakeout_pause_until then
					desired_speed = 0
					paused = true
				elseif now < controller.fakeout_burst_until then
					desired_speed = personality.BurstSpeed or desired_speed
				elseif now >= controller.next_fakeout then
					controller.fakeout_pause_until = now + (personality.PauseDuration or 0.5)
					controller.fakeout_burst_until = controller.fakeout_pause_until + (personality.BurstDuration or 1)
					controller.next_fakeout = controller.fakeout_burst_until + personality.FakeOutInterval
					desired_speed = 0
					paused = true
				end
			end
			npc_humanoid.WalkSpeed = desired_speed
			npc:SetAttribute("CurrentChaseSpeed", desired_speed)
			call_for_help(now)

			local target_velocity = target_root.AssemblyLinearVelocity
			local flat_velocity = Vector3.new(target_velocity.X, 0, target_velocity.Z)
			local directed_velocity = player_humanoid.MoveDirection * player_humanoid.WalkSpeed
			if directed_velocity.Magnitude > flat_velocity.Magnitude then
				flat_velocity = Vector3.new(directed_velocity.X, 0, directed_velocity.Z)
			end
			if flat_velocity.Magnitude > 45 then
				flat_velocity = flat_velocity.Unit * 45
			end
			local target_position = target_root.Position + flat_velocity * (personality.PredictionSeconds or 0)
			npc:SetAttribute("PredictionLead", (target_position - target_root.Position).Magnitude)
			combo_service.sample_near_miss(player, npc, (npc_root.Position - target_root.Position).Magnitude)
			local eye_offset = Vector3.new(0, 2, 0)
			local recovering = controller.recovery_goal and now < controller.recovery_until

			if paused then
				npc_humanoid:MoveTo(npc_root.Position)
				controller.last_progress_position = npc_root.Position
				controller.last_progress_time = now
				task.wait(0.1)
				continue
			elseif recovering then
				npc_humanoid:MoveTo(controller.recovery_goal)
			else
				controller.recovery_goal = nil
				local direct_clear = direct_path_clear(npc_root.Position + eye_offset, target_position + eye_offset)
				if direct_clear then
					controller.waypoints = {}
					controller.waypoint_index = 1
					npc_humanoid:MoveTo(target_position)
				else
					local target_moved = (target_position - controller.last_target).Magnitude >= target_repath_distance
					local path_finished = controller.waypoint_index > #controller.waypoints
					local refresh_interval = personality.RepathInterval or path_refresh_interval
					if controller.path_blocked or path_finished or now - controller.last_compute >= refresh_interval or target_moved then
						compute_path(target_position)
					end

					while controller.waypoint_index <= #controller.waypoints
						and (controller.waypoints[controller.waypoint_index].Position - npc_root.Position).Magnitude <= waypoint_reached_distance do
						controller.waypoint_index += 1
					end
					local waypoint = controller.waypoints[controller.waypoint_index]
					if waypoint then
						if waypoint.Action == Enum.PathWaypointAction.Jump then
							npc_humanoid.Jump = true
						end
						npc_humanoid:MoveTo(waypoint.Position)
					else
						npc_humanoid:MoveTo(target_position)
						controller.path_blocked = true
					end
				end
			end

			if (npc_root.Position - controller.last_progress_position).Magnitude >= stuck_distance then
				controller.last_progress_position = npc_root.Position
				controller.last_progress_time = now
				controller.last_stuck_repath = 0
			elseif now - controller.last_progress_time >= stuck_repath_time then
				if now - controller.last_stuck_repath >= 0.75 then
					controller.path_blocked = true
					controller.last_compute = 0
					controller.last_stuck_repath = now
				end
				if now - controller.last_progress_time >= stuck_recovery_time and now >= controller.recovery_until then
					controller.recovery_goal = choose_recovery_goal(target_position)
					controller.recovery_until = now + recovery_duration
					npc_humanoid.Jump = true
					npc_humanoid:MoveTo(controller.recovery_goal)
					controller.last_progress_position = npc_root.Position
					controller.last_progress_time = now
				end
			end
			task.wait(0.1)
		end
		if not controller.finished then
			finish_chase(player, npc, controller, "death")
		end
	end)
end

local function talk(player, npc)
	local rage_table = npc_rage[npc]
	if not rage_table then
		rage_table = {}
		npc_rage[npc] = rage_table
	end
	local now = os.clock()
	local rage = rage_table[player.UserId]
	if not rage or now - rage.last_interaction > rage_decay_time then
		rage = { level = 0, last_interaction = 0 }
		rage_table[player.UserId] = rage
	end
	rage.level += 1
	rage.last_interaction = now

	local profile = data_service.get(player)
	local tutorial = tutorials[player.UserId]
	local tutorial_active = tutorial and tutorial.active
	local dialogue_level = math.clamp(rage.level, 1, 5)
	if profile and profile.TutorialCompleted then
		dialogue_level = 5
		rage.level = rage_threshold
	end
	local lines = dialogue[dialogue_level]
	dialogue_event:FireClient(player, lines.npc, npc.Name)
	task.wait(dialogue_delay)
	if player.Parent then
		dialogue_event:FireClient(player, lines.player, player.Name, true)
	end

	if tutorial_active then
		tutorial.ragebait_count += 1
		local step = tutorial_step(player)
		if step and step.type == "RagebaitNPC" and tutorial.ragebait_count >= step.count then
			task.wait(0.5)
			advance_tutorial(player)
		end
	end

	if rage.level >= rage_threshold then
		rage_table[player.UserId] = nil
		task.wait(chase_delay)
		if player.Parent and npc.Parent and active_count(player) < multi_ragebait_limit(player) then
			chase_npc(player, npc)
		end
	end
end

local interaction_times = {}

local function on_prompt(player, npc)
	if not data_service.get(player) then
		return
	end
	if active_count(player) >= multi_ragebait_limit(player) then
		return
	end
	local tutorial = tutorials[player.UserId]
	if tutorial and tutorial.active then
		local step = tutorial_step(player)
		if not step or step.type ~= "RagebaitNPC" or tutorial.target ~= npc then
			return
		end
	end
	local key = tostring(player.UserId) .. ":" .. npc.Name
	local now = os.clock()
	if interaction_times[key] and now - interaction_times[key] < interaction_debounce then
		return
	end
	interaction_times[key] = now
	task.spawn(talk, player, npc)
end

local function setup_npc(npc)
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	npc_origins[npc] = root.CFrame
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		npc_default_speeds[npc] = humanoid.WalkSpeed
	end
	local assigned_personality = personality_config.for_npc(npc.Name)
	npc:SetAttribute("Personality", assigned_personality.Name)
	npc:SetAttribute("PersonalityDescription", assigned_personality.Description)
	npc:SetAttribute("PersonalityBaseSpeed", assigned_personality.BaseSpeed)
	set_personality_tag(npc, assigned_personality, false)
	local prompt = npc:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = npc
	end
	prompt.ActionText = "Talk"
	prompt.ObjectText = assigned_personality.Name .. " NPC"
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 10)
	npc_prompts[npc] = prompt
	if prompt_connections[npc] then
		prompt_connections[npc]:Disconnect()
	end
	prompt_connections[npc] = prompt.Triggered:Connect(function(player)
		on_prompt(player, npc)
	end)
end

function chase_service.state(player)
	return state_for(player)
end

function chase_service.active_count(player)
	return active_count(player)
end

function chase_service.on_player_added(player)
	state_for(player)
	combo_service.on_player_added(player)
	active_chases[player.UserId] = {}
	set_active_count(player, 0)
	task.delay(2, function()
		if player.Parent then
			start_tutorial(player)
		end
	end)
end

function chase_service.on_character_spawned(player)
	combo_service.reset(player, "respawn")
	local player_chases = active_chases[player.UserId]
	if player_chases then
		for npc, controller in pairs(player_chases) do
			if controller and not controller.finished then
				finish_chase(player, npc, controller, "death")
			end
		end
	end
	active_chases[player.UserId] = {}
	set_active_count(player, 0)
	local state = state_for(player)
	state.IsBeingChased = false
	state.ChaseActive = false
	state.HasBeenCaught = false
	release_capture(player, false)
	character_service.apply_movement(player)
end

function chase_service.on_player_removing(player)
	stop_timer(player)
	release_capture(player, false)
	local player_chases = active_chases[player.UserId]
	if player_chases then
		for npc, controller in pairs(player_chases) do
			if controller and not controller.finished then
				controller.running = false
				controller.finished = true
				if controller.blocked_connection then controller.blocked_connection:Disconnect() end
				if controller.hit_connection then controller.hit_connection:Disconnect() end
				if controller.death_connection then controller.death_connection:Disconnect() end
				if controller.hitbox and controller.hitbox.Parent then controller.hitbox:Destroy() end
				local npc_humanoid = npc:FindFirstChildOfClass("Humanoid")
				if npc_humanoid then
					npc_humanoid.WalkSpeed = npc_default_speeds[npc] or 26
				end
				npc:SetAttribute("ActivePersonality", nil)
				npc:SetAttribute("CurrentChaseSpeed", nil)
				npc:SetAttribute("PredictionLead", nil)
				set_personality_tag(npc, nil, false)
				normal_face(npc)
				set_prompt(npc, true)
				task.spawn(return_npc, npc)
			end
		end
	end
	for npc, rage_table in pairs(npc_rage) do
		rage_table[player.UserId] = nil
	end
	local id_string = tostring(player.UserId)
	for key in pairs(interaction_times) do
		if string.find(key, id_string, 1, true) == 1 then
			interaction_times[key] = nil
		end
	end
	player_states[player.UserId] = nil
	active_chases[player.UserId] = nil
	active_counts[player.UserId] = nil
	tutorials[player.UserId] = nil
	timer_tokens[player.UserId] = nil
	combo_service.remove_player(player)
end

function chase_service.start()
	if started then
		return
	end
	started = true
	for _, npc in ipairs(npc_models()) do
		setup_npc(npc)
	end
	npc_folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(setup_npc, child)
		end
	end)

	hook_event.OnServerEvent:Connect(function(player, action)
		if action ~= "EscapeClick" then
			return
		end
		local capture = captures[player.UserId]
		if not capture or not capture.weld or not capture.weld.Parent then
			return
		end
		local now = os.clock()
		local time_since_last_click = now - capture.last_click
		if capture.last_click > 0 and time_since_last_click < escape_click_min_interval then
			return
		end
		if capture.last_click > 0 and time_since_last_click > escape_click_reset_time then
			capture.clicks = 0
		end
		capture.last_click = now
		capture.clicks += 1
		if capture.clicks >= escape_clicks_required then
			release_capture(player, true)
		end
	end)
end

return chase_service
