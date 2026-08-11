-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local replicated_storage = game:GetService("ReplicatedStorage")

local inventory_service = require(script.Parent.inventory_service)
local skin_storage = require(script.Parent.SkinServer.Storage)

local skin_shop_service = {}

local message_event = replicated_storage.RemoteEvents:WaitForChild("MessageEvent")
local connections = {}
local started = false

local function setup_model(model)
	if not model:IsA("Model") then
		return
	end
	local price = skin_storage.ChickenSkinPrice[model.Name]
	if not price then
		return
	end
	local prompt = model:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = model
	end
	prompt.ActionText = "Buy"
	prompt.ObjectText = "Skin"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10

	local old_gui = model:FindFirstChild("ChickenInfo")
	if old_gui then
		old_gui:Destroy()
	end
	local template = replicated_storage.Stuff:FindFirstChild("ChickenInfo")
	if template then
		local gui = template:Clone()
		gui.Name = "ChickenInfo"
		gui.Enabled = true
		gui.Parent = model
		local name_label = gui:FindFirstChild("Name")
		local price_label = gui:FindFirstChild("Price")
		if name_label and name_label:IsA("TextLabel") then
			name_label.Text = model.Name
		end
		if price_label and price_label:IsA("TextLabel") then
			price_label.Text = "$" .. tostring(price)
		end
	end

	if connections[model] then
		connections[model]:Disconnect()
	end
	connections[model] = prompt.Triggered:Connect(function(player)
		local purchased, reason = inventory_service.buy_skin(player, model.Name)
		if purchased then
			message_event:FireClient(player, "Bought 1x " .. model.Name)
		elseif reason == "owned" then
			message_event:FireClient(player, "Skin already owned")
		end
	end)
end

function skin_shop_service.start()
	if started then
		return
	end
	started = true
	local chickens = workspace.Map:WaitForChild("Chickens")
	for _, model in ipairs(chickens:GetChildren()) do
		setup_model(model)
	end
	chickens.ChildAdded:Connect(function(model)
		task.defer(setup_model, model)
	end)
end

return skin_shop_service
