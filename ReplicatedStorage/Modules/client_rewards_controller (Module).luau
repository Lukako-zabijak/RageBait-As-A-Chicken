local players = game:GetService("Players")
local marketplace_service = game:GetService("MarketplaceService")
local replicated_storage = game:GetService("ReplicatedStorage")

local ui_util = require(replicated_storage.Modules.ui_util)
local daily_config = require(replicated_storage.Modules.DailyRewardsConfig)
local playtime_config = require(replicated_storage.Modules.PlaytimeRewardsConfig)

local controller = {}
local started = false
local player = players.LocalPlayer
local click_sound = replicated_storage.Sounds:FindFirstChild("Click")
local hover_sound = replicated_storage.Sounds:FindFirstChild("Hover")

local daily_event = replicated_storage.RemoteEvents:WaitForChild("DailyRewardsEvent")
local playtime_event = replicated_storage.RemoteEvents:WaitForChild("PlaytimeEvent")

local daily_status
local playtime_status
local playtime_received_at = os.clock()

local function claimed(array, index)
	for _, value in ipairs(array or {}) do
		if value == index then return true end
	end
	return false
end

local function bind(gui, callback)
	if not gui or not gui:IsA("GuiObject") then return end
	ui_util.bind_hover(gui, hover_sound)
	ui_util.bind_click(gui, callback, click_sound)
end

local function daily_time(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local days = math.floor(seconds / 86400)
	if days > 0 then return tostring(days) .. (days == 1 and " Day" or " Days") end
	local hours = math.floor(seconds / 3600)
	if hours > 0 then return tostring(hours) .. (hours == 1 and " Hour" or " Hours") end
	local minutes = math.max(1, math.floor(seconds / 60))
	return tostring(minutes) .. (minutes == 1 and " Minute" or " Minutes")
end

local function playtime_time(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return minutes > 0 and string.format("%dm %ds", minutes, secs) or string.format("%ds", secs)
end

local function daily_frame(root, index)
	if index == 7 then
		local seven = root:FindFirstChild("7DayFrame")
		return seven and seven:FindFirstChild("Day7")
	end
	local six = root:FindFirstChild("6DayFrame")
	return six and six:FindFirstChild("Day" .. tostring(index))
end

local function update_daily(root)
	local status = daily_status
	if not status then return end
	for index, reward in ipairs(daily_config.Rewards) do
		local frame = daily_frame(root, index)
		if frame then
			local image = frame:FindFirstChild("RewardImage")
			local name = frame:FindFirstChild("RewardName")
			local action = frame:FindFirstChild("ActionButton")
			if image and image:IsA("ImageLabel") then image.Image = reward.Image or "" end
			if name and name:IsA("TextLabel") then name.Text = reward.Name or "" end
			if action and action:IsA("GuiObject") then
				local is_claimed = claimed(status.ClaimedDays, index)
				if is_claimed then
					action.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
					if action:IsA("TextButton") then action.Text = "Claimed" end
				elseif status.AllUnlocked or (index == status.CurrentDay and status.CanClaimNext) then
					action.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
					if action:IsA("TextButton") then action.Text = "Claim!" end
				elseif index == status.CurrentDay then
					action.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
					if action:IsA("TextButton") then action.Text = daily_time(status.TimeUntilNext) end
				else
					action.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
					local remaining = math.max(1, index - status.CurrentDay)
					if action:IsA("TextButton") then action.Text = tostring(remaining) .. (remaining == 1 and " Day" or " Days") end
				end
			end
		end
	end
end

local function estimated_playtime()
	if not playtime_status then return 0 end
	return math.max(0, (playtime_status.SessionTime or 0) + (os.clock() - playtime_received_at))
end

local function update_playtime(root, button)
	local status = playtime_status
	if not status then return end
	local session_time = estimated_playtime()
	local claimable = false
	local rewards_frame = root:FindFirstChild("RewardsFrame")
	if not rewards_frame then return end
	for index, reward in ipairs(playtime_config.Rewards) do
		local frame = rewards_frame:FindFirstChild("Reward" .. tostring(index))
		if frame then
			local action = frame:FindFirstChild("ActionButton")
			local name = frame:FindFirstChild("RewardName")
			local is_claimed = claimed(status.ClaimedRewards, index)
			local available = not is_claimed and (status.AllUnlocked or session_time >= reward.Time)
			if action and action:IsA("GuiObject") then
				if is_claimed then
					action.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
					if action:IsA("TextButton") then action.Text = "Claimed" end
				elseif available then
					action.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
					if action:IsA("TextButton") then action.Text = "Claim!" end
					claimable = true
				else
					action.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
					if action:IsA("TextButton") then action.Text = playtime_time(reward.Time - session_time) end
				end
			end
			if name and name:IsA("TextLabel") then
				if is_claimed then
					name.Text = reward.Type == "Coins" and ("+" .. reward.Amount .. " Cash") or ("+" .. reward.Amount .. " Diamonds")
				else
					name.Text = "???"
				end
			end
		end
	end
	local alert = button and button:FindFirstChild("AlertFrame")
	if alert and alert:IsA("GuiObject") then alert.Visible = claimable end
end

function controller.start()
	if started then return end
	started = true
	local game_ui = player:WaitForChild("PlayerGui"):WaitForChild("GameUI")
	local frames = game_ui:WaitForChild("Frames")
	local buttons = game_ui:WaitForChild("ButtonsFrame")
	local daily_root = frames:WaitForChild("DailyRewards")
	local playtime_root = frames:WaitForChild("PlayTimeRewards")
	local playtime_button = buttons:WaitForChild("PlayTimeRewards")

	local daily_purchase = daily_root:FindFirstChild("PurchaseButton")
	if daily_purchase then
		if daily_purchase:IsA("TextButton") then daily_purchase.Text = daily_config.PurchaseButtonText end
		bind(daily_purchase, function()
			if daily_config.DeveloperProductId ~= 0 then marketplace_service:PromptProductPurchase(player, daily_config.DeveloperProductId) end
		end)
	end
	for index = 1, #daily_config.Rewards do
		local frame = daily_frame(daily_root, index)
		local action = frame and frame:FindFirstChild("ActionButton")
		if action then bind(action, function() daily_event:FireServer("ClaimReward", index) end) end
	end

	local playtime_purchase = playtime_root:FindFirstChild("PurchaseButton")
	if playtime_purchase then
		if playtime_purchase:IsA("TextButton") then playtime_purchase.Text = playtime_config.PurchaseButtonText end
		bind(playtime_purchase, function()
			if playtime_config.DeveloperProductId ~= 0 then marketplace_service:PromptProductPurchase(player, playtime_config.DeveloperProductId) end
		end)
	end
	local reward_frames = playtime_root:WaitForChild("RewardsFrame")
	for index = 1, #playtime_config.Rewards do
		local frame = reward_frames:FindFirstChild("Reward" .. tostring(index))
		local action = frame and frame:FindFirstChild("ActionButton")
		if action then bind(action, function() playtime_event:FireServer("ClaimReward", index) end) end
	end

	daily_event.OnClientEvent:Connect(function(action, data)
		if action == "UpdateStatus" and type(data) == "table" then
			daily_status = data
			update_daily(daily_root)
		end
	end)
	playtime_event.OnClientEvent:Connect(function(action, data)
		if action == "UpdateStatus" and type(data) == "table" then
			playtime_status = data
			playtime_received_at = os.clock()
			update_playtime(playtime_root, playtime_button)
		end
	end)

	daily_event:FireServer("GetStatus")
	playtime_event:FireServer("GetStatus")
	task.spawn(function()
		local daily_elapsed = 0
		while true do
			task.wait(1)
			update_playtime(playtime_root, playtime_button)
			daily_elapsed += 1
			if daily_elapsed >= 10 then
				daily_elapsed = 0
				if daily_root.Visible then daily_event:FireServer("GetStatus") end
			end
			if playtime_root.Visible then playtime_event:FireServer("GetStatus") end
		end
	end)
end

return controller
