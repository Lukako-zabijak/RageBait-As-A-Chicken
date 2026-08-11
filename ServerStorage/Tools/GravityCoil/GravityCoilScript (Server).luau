-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local force = Instance.new("BodyForce")
force.Name = "GravityCoilEffect"
force.Archivable = false

local connections = {}

local function disconnect_all()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function update(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local mass = 0
	for _, part in ipairs(root:GetConnectedParts(true)) do
		if part:IsA("BasePart") then
			mass += part:GetMass()
		end
	end
	force.Force = Vector3.new(0, 0.75 * 9.81 * 20 * mass, 0)
end

tool.Equipped:Connect(function()
	local character = tool.Parent
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		return
	end
	disconnect_all()
	update(character)
	force.Parent = handle
	table.insert(connections, character.DescendantAdded:Connect(function()
		update(character)
	end))
	table.insert(connections, character.DescendantRemoving:Connect(function()
		task.defer(update, character)
	end))
end)

tool.Unequipped:Connect(function()
	force.Parent = nil
	disconnect_all()
end)
