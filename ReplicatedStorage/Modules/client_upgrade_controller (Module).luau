local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")

local ui_util = require(replicated_storage.Modules.ui_util)
local ui_manager = require(replicated_storage.Modules.client_ui_manager)

local controller = {}
local started = false
local player = players.LocalPlayer
local event = replicated_storage.RemoteEvents:WaitForChild("UpgradesEvent")
local click_sound = replicated_storage.Sounds:FindFirstChild("Click")
local hover_sound = replicated_storage.Sounds:FindFirstChild("Hover")

local purchase_pending = false
local purchase_generation = 0

local function clear_cards(main)
	for _, child in ipairs(main:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
end

local function currency_name(upgrade)
	return type(upgrade.Currency) == "string" and upgrade.Currency or "Diamonds"
end

local function render(root, status)
	if type(status) ~= "table" then
		return
	end
	local main = root:WaitForChild("MainFrame")
	local template = main:WaitForChild("Template")
	clear_cards(main)

	for index, upgrade in ipairs(status.Upgrades or {}) do
		local card = template:Clone()
		card.Name = "Upgrade_" .. tostring(upgrade.Name)
		card.LayoutOrder = index
		card.Visible = true
		card.Parent = main

		local image = card:FindFirstChild("Image")
		local name_label = card:FindFirstChild("Name")
		local level = card:FindFirstChild("Level")
		local buy = card:FindFirstChild("BuyButton")
		if image then
			image.Image = upgrade.Image or ""
		end
		if name_label then
			name_label.Text = upgrade.Name
		end
		if level then
			level.Text = upgrade.IsMaxLevel and "Max Level" or ("Level " .. tostring(upgrade.CurrentLevel))
			level.TextColor3 = upgrade.IsMaxLevel and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(0, 255, 0)
		end

		if buy and buy:IsA("TextButton") then
			local normal_text = "Purchase (" .. tostring(upgrade.Cost) .. " " .. currency_name(upgrade) .. ")"
			if upgrade.IsMaxLevel then
				buy.Text = "Max Level"
				buy.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
				buy.TextColor3 = Color3.fromRGB(200, 200, 200)
				buy.Active = false
			else
				buy.Text = purchase_pending and "Purchasing..." or normal_text
				buy.BackgroundColor3 = purchase_pending and Color3.fromRGB(120, 120, 120) or Color3.fromRGB(0, 255, 0)
				buy.TextColor3 = Color3.fromRGB(255, 255, 255)
				buy.Active = not purchase_pending
				ui_util.bind_hover(buy, hover_sound)
				ui_util.bind_click(buy, function()
					if purchase_pending or not buy.Active then
						return
					end
					purchase_pending = true
					purchase_generation += 1
					local generation = purchase_generation
					buy.Active = false
					buy.Text = "Purchasing..."
					buy.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
					event:FireServer("BuyUpgrade", upgrade.Name)
					task.delay(4, function()
						if purchase_pending and generation == purchase_generation then
							purchase_pending = false
							event:FireServer("GetStatus")
						end
					end)
				end, click_sound)
			end
		end
	end
end

function controller.start()
	if started then
		return
	end
	started = true
	local root = player:WaitForChild("PlayerGui"):WaitForChild("GameUI"):WaitForChild("Frames"):WaitForChild("Upgrades")
	root.Visible = false
	local close = root:FindFirstChild("CloseButton")
	if close and close:IsA("GuiButton") then
		close.Activated:Connect(function()
			ui_manager.close(root)
		end)
	end
	local npc = workspace.Map:FindFirstChild("UpgradesNpc") and workspace.Map.UpgradesNpc:FindFirstChild("Npc")
	local npc_root = npc and npc:FindFirstChild("HumanoidRootPart")
	local prompt = npc_root and npc_root:FindFirstChildOfClass("ProximityPrompt")
	if not prompt and npc then
		prompt = npc:FindFirstChildOfClass("ProximityPrompt", true)
	end
	if prompt then
		prompt.Triggered:Connect(function()
			ui_manager.open(root)
			event:FireServer("GetStatus")
		end)
	end
	event.OnClientEvent:Connect(function(action, data)
		if action == "PurchaseSuccess" or action == "PurchaseFailed" then
			purchase_pending = false
			purchase_generation += 1
		elseif action == "UpdateStatus" and type(data) == "table" then
			purchase_pending = false
			render(root, data)
		end
	end)
end

return controller

