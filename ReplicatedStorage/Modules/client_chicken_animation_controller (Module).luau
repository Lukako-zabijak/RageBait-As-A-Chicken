-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local players = game:GetService("Players")
local run_service = game:GetService("RunService")

local controller = {}
local started = false
local player = players.LocalPlayer

local animation_ids = {
	walk = "rbxassetid://107168986152792",
	run = "rbxassetid://136156131848090",
	jump = "rbxassetid://97087954508013",
}

local generation = 0

local function load(animator, name, id, priority, looped)
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	animation:Destroy()
	if not ok then
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

local function bind(character)
	generation += 1
	local my_generation = generation
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if not animator then
		return
	end

	local walk = load(animator, "ChickenWalk", animation_ids.walk, Enum.AnimationPriority.Movement, true)
	local run = load(animator, "ChickenRun", animation_ids.run, Enum.AnimationPriority.Movement, true)
	local jump = load(animator, "ChickenJump", animation_ids.jump, Enum.AnimationPriority.Action, false)
	if not walk or not run or not jump then
		return
	end

	local current
	local airborne = false
	local function stop_movement(fade)
		if current then
			current:Stop(fade or 0.08)
			current = nil
		end
	end

	local function play_movement(track)
		if current == track and track.IsPlaying then
			return
		end
		stop_movement(0.08)
		current = track
		track:Play(0.08)
		track:AdjustSpeed(1)
	end

	local state_connection = humanoid.StateChanged:Connect(function(_, new_state)
		if new_state == Enum.HumanoidStateType.Jumping or new_state == Enum.HumanoidStateType.Freefall then
			airborne = true
			stop_movement(0.05)
			if not jump.IsPlaying then
				jump:Play(0.03)
			end
		elseif new_state == Enum.HumanoidStateType.Running or new_state == Enum.HumanoidStateType.RunningNoPhysics or new_state == Enum.HumanoidStateType.Landed then
			airborne = false
			if jump.IsPlaying then
				jump:Stop(0.05)
			end
		end
	end)

	local heartbeat_connection
	heartbeat_connection = run_service.Heartbeat:Connect(function()
		if my_generation ~= generation or not character.Parent or humanoid.Health <= 0 then
			heartbeat_connection:Disconnect()
			state_connection:Disconnect()
			stop_movement(0)
			jump:Stop(0)
			return
		end
		if airborne then
			return
		end
		local magnitude = humanoid.MoveDirection.Magnitude
		local speed = humanoid.WalkSpeed * magnitude
		if speed > 16 then
			play_movement(run)
		elseif speed > 1 then
			play_movement(walk)
		else
			stop_movement(0.08)
		end
	end)
end

function controller.start()
	if started then
		return
	end
	started = true
	player.CharacterAdded:Connect(bind)
	if player.Character then
		task.defer(bind, player.Character)
	end
end

return controller
