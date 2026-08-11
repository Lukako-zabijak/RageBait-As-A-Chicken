local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local tween_service = game:GetService("TweenService")

local ui_util = require(replicated_storage.Modules.ui_util)

local controller = {}
local started = false
local player = players.LocalPlayer

local function animate_number(label, previous, current, prefix)
	if not label then
		return
	end
	local difference = current - previous
	if difference ~= 0 then
		label.TextColor3 = difference > 0 and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
		tween_service:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextColor3 = Color3.fromRGB(255, 255, 255),
		}):Play()
	end
	local generation = os.clock()
	label:SetAttribute("number_generation", generation)
	task.spawn(function()
		for step = 1, 20 do
			if label:GetAttribute("number_generation") ~= generation then
				return
			end
			local alpha = step / 20
			local value = math.floor(previous + difference * alpha + 0.5)
			label.Text = (prefix or "") .. ui_util.format_compact(value)
			task.wait(0.02)
		end
	end)
end

function controller.start()
	if started then
		return
	end
	started = true
	local game_ui = player:WaitForChild("PlayerGui"):WaitForChild("GameUI")
	local coins_label = game_ui:WaitForChild("CoinsFrame"):WaitForChild("Coins")
	local diamonds_label = game_ui:WaitForChild("DiamondsFrame"):WaitForChild("Diamonds")
	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins")
	local diamonds = leaderstats:WaitForChild("Diamonds")
	local last_coins = coins.Value
	local last_diamonds = diamonds.Value
	coins_label.Text = "$" .. ui_util.format_compact(last_coins)
	diamonds_label.Text = ui_util.format_compact(last_diamonds)
	coins:GetPropertyChangedSignal("Value"):Connect(function()
		local current = coins.Value
		animate_number(coins_label, last_coins, current, "$")
		last_coins = current
	end)
	diamonds:GetPropertyChangedSignal("Value"):Connect(function()
		local current = diamonds.Value
		animate_number(diamonds_label, last_diamonds, current, "")
		last_diamonds = current
	end)
end

return controller
