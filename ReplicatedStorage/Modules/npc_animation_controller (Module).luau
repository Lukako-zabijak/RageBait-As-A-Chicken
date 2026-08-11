local npc_animation_controller = {}

local idle_assets = {
	{ id = "rbxassetid://180435571", weight = 9 },
	{ id = "rbxassetid://180435792", weight = 1 },
}

local assets = {
	walk = "rbxassetid://180426354",
	jump = "rbxassetid://125750702",
	fall = "rbxassetid://180436148",
	climb = "rbxassetid://180436334",
	sit = "rbxassetid://178130996",
	toolnone = "rbxassetid://182393478",
	toolslash = "rbxassetid://129967390",
	toollunge = "rbxassetid://129967478",
	wave = "rbxassetid://128777973",
	point = "rbxassetid://128853357",
	laugh = "rbxassetid://129423131",
	cheer = "rbxassetid://129423030",
}

local dances = {
	dance1 = { "rbxassetid://182435998", "rbxassetid://182491037", "rbxassetid://182491065" },
	dance2 = { "rbxassetid://182436842", "rbxassetid://182491248", "rbxassetid://182491277" },
	dance3 = { "rbxassetid://182436935", "rbxassetid://182491368", "rbxassetid://182491423" },
}

local function choose_idle()
	return math.random(1, 10) <= 9 and idle_assets[1].id or idle_assets[2].id
end

local function load_track(animator, animation_id, priority, looped)
	local animation = Instance.new("Animation")
	animation.AnimationId = animation_id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	animation:Destroy()
	if not ok then
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

function npc_animation_controller.start(rig)
	if not rig or not rig:IsA("Model") or rig:GetAttribute("new_npc_animation_running") then
		return
	end
	rig:SetAttribute("new_npc_animation_running", true)
	local humanoid = rig:FindFirstChildOfClass("Humanoid") or rig:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local current
	local current_name
	local jump_until = 0
	local dead = false

	local function stop_current(fade)
		if current then
			current:Stop(fade or 0.1)
			current = nil
			current_name = nil
		end
	end

	local function play(name, id, priority, looped, fade, speed)
		if dead then
			return nil
		end
		if current_name == name and current and current.IsPlaying then
			if speed then current:AdjustSpeed(speed) end
			return current
		end
		stop_current(fade or 0.1)
		local track = load_track(animator, id, priority, looped)
		if not track then
			return nil
		end
		current = track
		current_name = name
		track:Play(fade or 0.1)
		if speed then
			track:AdjustSpeed(speed)
		end
		return track
	end

	local function idle()
		play("idle", choose_idle(), Enum.AnimationPriority.Idle, true, 0.1, 1)
	end

	local function move(speed)
		if dead or os.clock() < jump_until then
			return
		end
		if speed > 0.01 then
			play("walk", assets.walk, Enum.AnimationPriority.Movement, true, 0.1, math.max(0.1, speed / 14.5))
		else
			idle()
		end
	end

	humanoid.Running:Connect(move)
	humanoid.Jumping:Connect(function(active)
		if active then
			jump_until = os.clock() + 0.3
			play("jump", assets.jump, Enum.AnimationPriority.Action, false, 0.1, 1)
		end
	end)
	humanoid.FreeFalling:Connect(function(active)
		if active then
			task.delay(math.max(0, jump_until - os.clock()), function()
				if not dead and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
					play("fall", assets.fall, Enum.AnimationPriority.Movement, true, 0.3, 1)
				end
			end)
		end
	end)
	humanoid.Climbing:Connect(function(speed)
		if math.abs(speed) > 0.01 then
			play("climb", assets.climb, Enum.AnimationPriority.Movement, true, 0.1, math.max(0.1, math.abs(speed) / 12))
		end
	end)
	humanoid.Seated:Connect(function(active)
		if active then
			play("sit", assets.sit, Enum.AnimationPriority.Action, true, 0.1, 1)
		end
	end)
	humanoid.Died:Connect(function()
		dead = true
		stop_current(0)
	end)

	local play_emote = rig:FindFirstChild("PlayEmote", true)
	if play_emote and play_emote:IsA("BindableFunction") then
		play_emote.OnInvoke = function(emote)
			if dead or type(emote) ~= "string" then
				return false
			end
			local id = assets[emote]
			local looped = false
			if dances[emote] then
				local choices = dances[emote]
				id = choices[math.random(1, #choices)]
				looped = true
			end
			if not id then
				return false
			end
			local track = play("emote:" .. emote, id, Enum.AnimationPriority.Action, looped, 0.1, 1)
			if track and not looped then
				track.Stopped:Once(function()
					if not dead then idle() end
				end)
			end
			return track ~= nil
		end
	end

	idle()
end

return npc_animation_controller
