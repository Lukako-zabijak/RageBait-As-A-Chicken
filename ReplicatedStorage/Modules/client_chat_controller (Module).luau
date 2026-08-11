local players = game:GetService("Players")
local marketplace_service = game:GetService("MarketplaceService")
local text_chat_service = game:GetService("TextChatService")

local controller = {}
local started = false
local player = players.LocalPlayer
local group_id = 263486617
local vip_pass_id = 1791582691

local role
local vip_fallback = false

local function refresh_local_status()
	pcall(function()
		role = player:GetRoleInGroup(group_id)
	end)
	pcall(function()
		vip_fallback = marketplace_service:UserOwnsGamePassAsync(player.UserId, vip_pass_id)
	end)
end

function controller.start()
	if started then return end
	started = true
	refresh_local_status()
	text_chat_service.OnIncomingMessage = function(message)
		local source = message.TextSource
		if not source or source.UserId ~= player.UserId then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		local prefix = message.PrefixText
		if role == "Owner" then
			properties.PrefixText = '<font color="rgb(255,0,0)">[Owner]</font> ' .. prefix
		elseif role == "Lead Developer" then
			properties.PrefixText = '<font color="rgb(130,0,206)">[🔨Lead Developer]</font> ' .. prefix
		elseif player:GetAttribute("HasVIP") == true or vip_fallback then
			properties.PrefixText = '<font color="rgb(255,255,0)">[VIP]</font> ' .. prefix
		else
			return nil
		end
		return properties
	end
end

return controller
