local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")

local data_service = require(script.Parent.data_service)

local character_service = {}

local states = {}
local water_connections = {}
local void_connections = {}
local spawning = {}
local spawn_callbacks = {}
local chase_state_provider

local function state_for(player)
	local state = states[player.UserId]
	if not state then
		state = {
			is_in_water = false,
			water_contacts = {},
		}
		states[player.UserId] = state
	end
	return state
end

local function disconnect_list(list)
	if not list then
		return
	end
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

local function spawn_locations()
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Spawns")
	local result = {}
	if not folder then
		return result
	end
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("SpawnLocation") then
			table.insert(result, descendant)
		end
	end
	return result
end

function character_service.random_spawn_cframe()
	local locations = spawn_locations()
	if #locations == 0 then
		return CFrame.new(0, 10, 0)
	end
	return locations[math.random(1, #locations)].CFrame + Vector3.new(0, 3, 0)
end

function character_service.teleport_to_spawn(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local state = state_for(player)
	state.is_in_water = false
	table.clear(state.water_contacts)
	player:SetAttribute("AntiCheatTeleportUntil", os.clock() + 2)
	root.CFrame = character_service.random_spawn_cframe()
	task.defer(function()
		if player.Parent and player.Character == character then
			character_service.apply_movement(player)
		end
	end)
	return true
end

local function chase_state(player)
	if chase_state_provider then
		local ok, result = pcall(chase_state_provider, player)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function has_equipped_tool(character, tool_name)
	local tool = character and character:FindFirstChild(tool_name)
	return tool ~= nil and tool:IsA("Tool")
end

function character_service.movement_profile(player)
	local character = player.Character
	local state = state_for(player)
	local chase = chase_state(player)
	local caught = chase and chase.HasBeenCaught == true or false
	local chasing = chase and chase.ChaseActive == true or false
	local speed = 16
	local jump_power = 50
	local jump_height = 7.2

	if caught then
		speed = 0
		jump_power = 0
		jump_height = 0
	elseif state.is_in_water then
		speed = chasing and 25.5 or 10
		jump_power = 0
		jump_height = 0
	else
		speed = chasing and 32 or 16
	end

	if not caught and has_equipped_tool(character, "SpeedCoil") then
		speed += 16
	end

	return {
		WalkSpeed = speed,
		JumpPower = jump_power,
		JumpHeight = jump_height,
		IsCaught = caught,
		IsChasing = chasing,
		IsInWater = state.is_in_water,
		HasSpeedCoil = has_equipped_tool(character, "SpeedCoil"),
		HasGravityCoil = has_equipped_tool(character, "GravityCoil"),
	}
end

function character_service.apply_movement(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local profile = character_service.movement_profile(player)
	player:SetAttribute("AntiCheatMovementUntil", os.clock() + 0.5)
	humanoid.WalkSpeed = profile.WalkSpeed
	humanoid.JumpPower = profile.JumpPower
	humanoid.JumpHeight = profile.JumpHeight
	player:SetAttribute("ExpectedWalkSpeed", profile.WalkSpeed)
end

local function setup_physics(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return false
	end
	humanoid.AutoRotate = true
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	if not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant == root then
				descendant.CanCollide = true
				descendant.Massless = false
				descendant.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 1, 1)
			else
				descendant.CanCollide = false
				descendant.Massless = true
			end
		end
	end
	return true
end

local function setup_water(player, character)
	disconnect_list(water_connections[player.UserId])
	water_connections[player.UserId] = {}
	local state = state_for(player)
	state.is_in_water = false
	table.clear(state.water_contacts)

	local map = workspace:FindFirstChild("Map")
	local water = map and map:FindFirstChild("Water")
	if not water then
		return
	end

	local function refresh()
		local count = 0
		for _, amount in pairs(state.water_contacts) do
			count += amount
		end
		local new_value = count > 0
		if state.is_in_water ~= new_value then
			state.is_in_water = new_value
			character_service.apply_movement(player)
		end
	end

	for _, part in ipairs(water:GetDescendants()) do
		if part:IsA("BasePart") then
			local touched = part.Touched:Connect(function(hit)
				if hit and hit:IsDescendantOf(character) then
					state.water_contacts[hit] = (state.water_contacts[hit] or 0) + 1
					refresh()
				end
			end)
			local ended = part.TouchEnded:Connect(function(hit)
				if state.water_contacts[hit] then
					state.water_contacts[hit] = math.max(0, state.water_contacts[hit] - 1)
					if state.water_contacts[hit] == 0 then
						state.water_contacts[hit] = nil
					end
					refresh()
				end
			end)
			table.insert(water_connections[player.UserId], touched)
			table.insert(water_connections[player.UserId], ended)
		end
	end
end

local function setup_void(player, character)
	if void_connections[player.UserId] then
		void_connections[player.UserId]:Disconnect()
		void_connections[player.UserId] = nil
	end
	local void = workspace:FindFirstChild("Void")
	if not void or not void:IsA("BasePart") then
		return
	end
	local debounce = false
	void_connections[player.UserId] = void.Touched:Connect(function(hit)
		if debounce or not hit or not hit:IsDescendantOf(character) then
			return
		end
		debounce = true
		character_service.teleport_to_spawn(player)
		task.delay(1, function()
			debounce = false
		end)
	end)
end

local function notify_spawn(player, character)
	for _, callback in ipairs(spawn_callbacks) do
		task.spawn(function()
			local ok, err = pcall(callback, player, character)
			if not ok then
				warn("[character] spawn callback failed: " .. tostring(err))
			end
		end)
	end
end

function character_service.spawn(player)
	if spawning[player.UserId] then
		return false
	end
	spawning[player.UserId] = true
	local profile = data_service.get(player)
	if not profile then
		spawning[player.UserId] = nil
		return false
	end
	local skin_folder = replicated_storage:FindFirstChild("Skins")
	skin_folder = skin_folder and skin_folder:FindFirstChild(profile.SkinType)
	local template = skin_folder and skin_folder:FindFirstChild(profile.SkinEquipped)
	if not template or not template:IsA("Model") then
		skin_folder = replicated_storage.Skins:FindFirstChild("Chicken")
		template = skin_folder and skin_folder:FindFirstChild("WhiteChicken")
		if not template then
			spawning[player.UserId] = nil
			return false
		end
		data_service.mutate(player, function(data)
			data.SkinEquipped = "WhiteChicken"
			data.SkinType = "Chicken"
		end)
	end

	local old_character = player.Character
	local character = template:Clone()
	character.Name = template.Name
	character:PivotTo(character_service.random_spawn_cframe())
	character.Parent = workspace
	if not setup_physics(character) then
		character:Destroy()
		spawning[player.UserId] = nil
		return false
	end
	player:SetAttribute("AntiCheatTeleportUntil", os.clock() + 3)
	player.Character = character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	if old_character and old_character ~= character then
		old_character.Parent = nil
		task.delay(1, function()
			if old_character then
				old_character:Destroy()
			end
		end)
	end
	setup_water(player, character)
	setup_void(player, character)
	character_service.apply_movement(player)
	notify_spawn(player, character)
	spawning[player.UserId] = nil
	return true
end

function character_service.state(player)
	local state = state_for(player)
	return {
		IsInWater = state.is_in_water,
	}
end

function character_service.is_in_water(player)
	return state_for(player).is_in_water
end

function character_service.set_chase_state_provider(provider)
	chase_state_provider = provider
end

function character_service.on_spawn(callback)
	if type(callback) == "function" then
		table.insert(spawn_callbacks, callback)
	end
end

function character_service.clear_player(player)
	disconnect_list(water_connections[player.UserId])
	water_connections[player.UserId] = nil
	if void_connections[player.UserId] then
		void_connections[player.UserId]:Disconnect()
		void_connections[player.UserId] = nil
	end
	states[player.UserId] = nil
	spawning[player.UserId] = nil
end

return character_service
