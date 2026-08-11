local rig = script.Parent
local humanoid = rig:FindFirstChildOfClass("Humanoid") or rig:WaitForChild("Humanoid", 5)
if not humanoid then return end
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local function animation(path, fallback)
	local current = script
	for segment in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(segment)
	end
	return current and current:IsA("Animation") and current.AnimationId ~= "" and current.AnimationId or fallback
end

local function load(id, priority, looped)
	if not id or id == "" then return nil end
	local object = Instance.new("Animation")
	object.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, object)
	object:Destroy()
	if not ok then return nil end
	track.Priority = priority
	track.Looped = looped
	return track
end

local idle = load(animation("idle.Animation1", "rbxassetid://507766666"), Enum.AnimationPriority.Idle, true)
local walk = load(animation("walk.WalkAnim", "rbxassetid://507777826"), Enum.AnimationPriority.Movement, true)
local run = load(animation("run.RunAnim", "rbxassetid://507767714"), Enum.AnimationPriority.Movement, true)
local jump = load(animation("jump.JumpAnim", "rbxassetid://507765000"), Enum.AnimationPriority.Action, false)
local fall = load(animation("fall.FallAnim", "rbxassetid://507767968"), Enum.AnimationPriority.Movement, true)
local current

local function play(track, fade, speed)
	if not track then return end
	if current == track and track.IsPlaying then
		if speed then track:AdjustSpeed(speed) end
		return
	end
	if current then current:Stop(fade or 0.1) end
	current = track
	track:Play(fade or 0.1)
	if speed then track:AdjustSpeed(speed) end
end

humanoid.Running:Connect(function(speed)
	if speed > 14 then
		play(run, 0.1, math.max(0.1, speed / 16))
	elseif speed > 0.1 then
		play(walk, 0.1, math.max(0.1, speed / 8))
	else
		play(idle, 0.15, 1)
	end
end)
humanoid.Jumping:Connect(function(active)
	if active then play(jump, 0.05, 1) end
end)
humanoid.FreeFalling:Connect(function(active)
	if active then play(fall, 0.15, 1) end
end)
play(idle, 0, 1)
