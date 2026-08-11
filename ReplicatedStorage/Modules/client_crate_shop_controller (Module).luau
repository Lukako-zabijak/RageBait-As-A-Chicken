local players = game:GetService("Players")
local marketplace_service = game:GetService("MarketplaceService")
local replicated_storage = game:GetService("ReplicatedStorage")

local ui_util = require(replicated_storage.Modules.ui_util)
local ui_manager = require(replicated_storage.Modules.client_ui_manager)
local config = require(replicated_storage.Modules.CrateConfig)

local controller = {}
local started = false
local player = players.LocalPlayer
local crate_event = replicated_storage.RemoteEvents:WaitForChild("CrateEvent")
local click_sound = replicated_storage.Sounds:FindFirstChild("Click")
local hover_sound = replicated_storage.Sounds:FindFirstChild("Hover")
local status
local status_received_at = os.clock()

local function format_time(seconds)
	seconds = math.max(0, math.floor(seconds))
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", minutes, secs)
end

local function clear_viewport(viewport)
	for _, child in ipairs(viewport:GetChildren()) do
		child:Destroy()
	end
end

local function show_model(viewport, source)
	clear_viewport(viewport)
	if not source or not source:IsA("Model") then return end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local clone = source:Clone()
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.Anchored = true end
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then descendant:Destroy() end
	end
	clone.Parent = world
	clone:PivotTo(CFrame.new())
	local _, size = clone:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local distance = math.max(3.5, size.Magnitude * 0.8)
	camera.CFrame = CFrame.lookAt(Vector3.new(distance, math.max(1.5, size.Y * 0.35), distance), Vector3.new(0, size.Y * 0.15, 0))
end

local function clear_cards(scrolling)
	for _, child in ipairs(scrolling:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Template" then child:Destroy() end
	end
end

local function clear_info(info)
	for _, child in ipairs(info.MainFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Template" then child:Destroy() end
	end
end

local function open_info(info, crate)
	clear_info(info)
	info.CrateName.Text = tostring(crate.Name) .. " Rewards"
	for index, reward in ipairs(crate.Rewards or {}) do
		local template = info.MainFrame:FindFirstChild("Template")
		if template then
			local card = template:Clone()
			card.Name = "Reward" .. tostring(index)
			card.Visible = true
			card.Parent = info.MainFrame
			local chance = card:FindFirstChild("Chance")
			local image = card:FindFirstChild("RewardImage")
			if chance then chance.Text = tostring(reward.Chance) .. "%" end
			if image then image.Image = reward.Image or "" end
		end
	end
	ui_manager.open(info)
end

local function render(shop, info)
	if not status then return end
	status_received_at = os.clock()
	local scrolling = shop:WaitForChild("ScrollingFrame")
	clear_cards(scrolling)
	local template = scrolling:WaitForChild("Template")
	for _, crate in ipairs(status.Crates or {}) do
		local card = template:Clone()
		card.Name = "Crate_" .. crate.Name
		card.LayoutOrder = crate.Order or 0
		card.Visible = true
		card.Parent = scrolling
		card.CrateAmount.Text = "Stock: " .. tostring(crate.Stock or 0) .. "x"
		card.CrateName.Text = crate.Name
		card.CoinsBuy.Text = "$" .. tostring(crate.CoinPrice or 0)
		card.RobuxBuy.Text = tostring(crate.RobuxPrice or 0) .. "R$"
		local crate_source = replicated_storage:FindFirstChild("Crates") and replicated_storage.Crates:FindFirstChild(crate.Name)
		show_model(card.ViewportFrame, crate_source)
		ui_util.bind_hover(card.CoinsBuy, hover_sound)
		ui_util.bind_click(card.CoinsBuy, function()
			crate_event:FireServer("BuyCrateCoins", crate.Name)
		end, click_sound)
		ui_util.bind_hover(card.QuestionButton, hover_sound)
		ui_util.bind_click(card.QuestionButton, function()
			open_info(info, crate)
		end, click_sound)
		if crate.DeveloperProductId and crate.DeveloperProductId ~= 0 then
			ui_util.bind_hover(card.RobuxBuy, hover_sound)
			ui_util.bind_click(card.RobuxBuy, function()
				marketplace_service:PromptProductPurchase(player, crate.DeveloperProductId)
			end, click_sound)
		else
			card.RobuxBuy.Active = false
			card.RobuxBuy.AutoButtonColor = false
		end
	end
end

function controller.start()
	if started then return end
	started = true
	local frames = player:WaitForChild("PlayerGui"):WaitForChild("GameUI"):WaitForChild("Frames")
	local shop = frames:WaitForChild("CrateShop")
	local info = frames:WaitForChild("InfoFrame")
	shop.Visible = false
	info.Visible = false
	local restock = shop:WaitForChild("RestockButton")
	restock.Text = config.RestockButtonText
	ui_util.bind_hover(restock, hover_sound)
	ui_util.bind_click(restock, function()
		if config.RestockProductId ~= 0 then marketplace_service:PromptProductPurchase(player, config.RestockProductId) end
	end, click_sound)
	local close = shop.TopFrame:FindFirstChild("CloseButton")
	if close then close.MouseButton1Click:Connect(function() ui_manager.close(shop) end) end
	local info_close = info:FindFirstChild("CloseButton")
	if info_close then info_close.MouseButton1Click:Connect(function() ui_manager.close(info) end) end

	local npc = workspace.Map:FindFirstChild("ShopNpc") and workspace.Map.ShopNpc:FindFirstChild("Npc")
	local root = npc and npc:FindFirstChild("HumanoidRootPart")
	local prompt = root and root:FindFirstChildOfClass("ProximityPrompt")
	if not prompt and npc then prompt = npc:FindFirstChildOfClass("ProximityPrompt", true) end
	if prompt then
		prompt.Triggered:Connect(function()
			ui_manager.open(shop)
			crate_event:FireServer("GetStatus")
		end)
	end

	crate_event.OnClientEvent:Connect(function(action, data)
		if action == "UpdateStatus" and type(data) == "table" then
			status = data
			render(shop, info)
		elseif action == "PurchaseSuccess" then
			crate_event:FireServer("GetStatus")
		end
	end)
	crate_event:FireServer("GetStatus")

	task.spawn(function()
		while true do
			task.wait(1)
			if status then
				local remaining = math.max(0, (status.TimeUntilRestock or 0) - (os.clock() - status_received_at))
				shop.TopFrame.ResetText.Text = "Restock in " .. format_time(remaining)
				if remaining <= 0 and shop.Visible then crate_event:FireServer("GetStatus") end
			end
		end
	end)
end

return controller
