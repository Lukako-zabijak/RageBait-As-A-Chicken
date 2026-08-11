-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")

local ui_util = require(replicated_storage.Modules.ui_util)

local controller = {}
local started = false
local player = players.LocalPlayer
local shop_event = replicated_storage.RemoteEvents:WaitForChild("ShopEvent")
local shop_function = replicated_storage.RemoteFunctions:WaitForChild("ShopFunction")
local click_sound = replicated_storage.Sounds:FindFirstChild("Click")
local hover_sound = replicated_storage.Sounds:FindFirstChild("Hover")

local gamepasses = {
	["2X Money"] = true,
	["2X Diamond"] = true,
	VIP = true,
}

local dev_products = {
	["1000 Cash"] = true,
	["10000 Cash"] = true,
	["100000 Cash"] = true,
	["100 Diamonds"] = true,
	["1000 Diamonds"] = true,
	["10000 Diamonds"] = true,
}

local function request_price(category, name)
	local ok, result = pcall(function()
		return shop_function:InvokeServer({
			Demand = "GetPrice",
			Category = category,
			Name = name,
		})
	end)
	return ok and result or nil
end

local function bind_button(button, callback)
	if not button or not button:IsA("GuiButton") then return end
	ui_util.bind_hover(button, hover_sound)
	ui_util.bind_click(button, callback, click_sound)
end

local function setup_standard(frame, category, demand)
	local buy = frame:FindFirstChild("Buy")
	if not buy or not buy:IsA("TextButton") then return end
	local price = request_price(category, frame.Name)
	if price ~= nil then
		buy.Text = "Buy " .. tostring(price)
	end
	bind_button(buy, function()
		shop_event:FireServer({ Demand = demand, Name = frame.Name })
	end)
end

local function setup_skin_bundle(frame)
	local prices = request_price("DevProducts", "ChickenSkin")
	for _, option in ipairs({ "Buy1", "Buy3", "Buy9" }) do
		local button = frame:FindFirstChild(option)
		if button and button:IsA("TextButton") then
			if type(prices) == "table" and prices[option] then
				button.Text = "Buy " .. tostring(prices[option])
			end
			bind_button(button, function()
				shop_event:FireServer({ Demand = "BuyChickenSkin", Type = option })
			end)
		end
	end
end

function controller.start()
	if started then return end
	started = true
	local shop = player:WaitForChild("PlayerGui"):WaitForChild("GameUI"):WaitForChild("Frames"):WaitForChild("Shop")
	local scrolling = shop:WaitForChild("ScrollingFrame")
	for _, frame in ipairs(scrolling:GetChildren()) do
		if frame:IsA("GuiObject") then
			if gamepasses[frame.Name] then
				setup_standard(frame, "Gamepasses", "BuyGamePass")
			elseif dev_products[frame.Name] then
				setup_standard(frame, "DevProducts", "BuyDevProduct")
			elseif frame.Name == "ChickenSkin" then
				setup_skin_bundle(frame)
			end
		end
	end
end

return controller
