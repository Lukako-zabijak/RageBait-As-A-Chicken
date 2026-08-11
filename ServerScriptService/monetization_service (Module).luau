local marketplace_service = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")

local data_service = require(script.Parent.data_service)
local entitlement_service = require(script.Parent.entitlement_service)
local reward_service = require(script.Parent.reward_service)
local crate_service = require(script.Parent.crate_service)
local session_data = require(script.Parent.SessionData)
local shop_storage = require(script.Parent.ShopHandler.ShopStorage)
local skin_storage = require(script.Parent.SkinServer.Storage)
local daily_config = require(replicated_storage.Modules.DailyRewardsConfig)
local playtime_config = require(replicated_storage.Modules.PlaytimeRewardsConfig)
local crate_config = require(replicated_storage.Modules.CrateConfig)

local monetization_service = {}

local remote_events = replicated_storage:WaitForChild("RemoteEvents")
local shop_event = remote_events:WaitForChild("ShopEvent")
local crate_event = remote_events:WaitForChild("CrateEvent")
local daily_event = remote_events:WaitForChild("DailyRewardsEvent")
local playtime_event = remote_events:WaitForChild("PlaytimeEvent")
local shop_function = replicated_storage.RemoteFunctions:WaitForChild("ShopFunction")

local price_cache = {}
local prompt_times = {}
local receipt_locks = {}
local started = false

local function clean_price(value, fallback)
	local number = tonumber(value)
	if number and number >= 0 and number < math.huge then
		return math.floor(number)
	end
	return fallback
end

local function cached_product_price(id, info_type, fallback)
	local key = tostring(info_type) .. ":" .. tostring(id)
	local cached = price_cache[key]
	if cached and os.clock() - cached.time < 300 then
		return cached.price
	end
	local ok, info = pcall(function()
		return marketplace_service:GetProductInfo(id, info_type)
	end)
	local price = fallback
	if ok and info then
		price = clean_price(info.PriceInRobux, fallback)
	end
	price_cache[key] = {
		price = price,
		time = os.clock(),
	}
	return price
end

function monetization_service.price(category_name, product_name)
	if type(category_name) ~= "string" or type(product_name) ~= "string" then
		return nil
	end
	if category_name == "Gamepasses" then
		local product = shop_storage.Gamepasses[product_name]
		if not product or type(product.ID) ~= "number" then
			return nil
		end
		return cached_product_price(product.ID, Enum.InfoType.GamePass, product.Price)
	elseif category_name == "DevProducts" then
		local product = shop_storage.DevProducts[product_name]
		if not product then
			return nil
		end
		if product_name == "ChickenSkin" then
			return {
				Buy1 = cached_product_price(product.ID1, Enum.InfoType.Product, product.Price.Buy1),
				Buy3 = cached_product_price(product.ID3, Enum.InfoType.Product, product.Price.Buy3),
				Buy9 = cached_product_price(product.ID9, Enum.InfoType.Product, product.Price.Buy9),
			}
		end
		if type(product.ID) == "number" then
			return cached_product_price(product.ID, Enum.InfoType.Product, product.Price)
		end
		return product.Price
	end
	return nil
end

local function can_prompt(player)
	local now = os.clock()
	local last = prompt_times[player.UserId] or 0
	if now - last < 0.4 then
		return false
	end
	prompt_times[player.UserId] = now
	return true
end

local function prune_receipts(profile)
	local entries = {}
	for purchase_id, timestamp in pairs(profile.ProcessedReceipts) do
		table.insert(entries, {
			id = purchase_id,
			time = tonumber(timestamp) or 0,
		})
	end
	if #entries <= 200 then
		return
	end
	table.sort(entries, function(a, b)
		return a.time > b.time
	end)
	for index = 201, #entries do
		profile.ProcessedReceipts[entries[index].id] = nil
	end
end

local function skin_names()
	local result = {}
	for name in pairs(skin_storage.ChickenSkinPrice) do
		table.insert(result, name)
	end
	table.sort(result)
	return result
end

local function resolve_product(product_id)
	if product_id == crate_config.RestockProductId and product_id ~= 0 then
		return "crate_restock"
	end
	if product_id == daily_config.DeveloperProductId and product_id ~= 0 then
		return "daily_unlock"
	end
	if product_id == playtime_config.DeveloperProductId and product_id ~= 0 then
		return "playtime_all"
	end
	local crate = crate_service.find_by_product_id(product_id)
	if crate then
		return "crate", crate
	end
	for name, product in pairs(shop_storage.DevProducts) do
		if name ~= "ChickenSkin" and product.ID == product_id then
			return "currency", product
		end
	end
	local skin_product = shop_storage.DevProducts.ChickenSkin
	if product_id == skin_product.ID1 then
		return "skin_bundle", 1
	elseif product_id == skin_product.ID3 then
		return "skin_bundle", 3
	elseif product_id == skin_product.ID9 then
		return "skin_bundle", 9
	end
	return nil
end

local function process_receipt(receipt_info)
	local user_id = receipt_info.PlayerId
	local product_id = receipt_info.ProductId
	local purchase_id = tostring(receipt_info.PurchaseId or "")
	if type(user_id) ~= "number" or type(product_id) ~= "number" or purchase_id == "" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = players:GetPlayerByUserId(user_id)
	local profile = player and data_service.get(player)
	if not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if profile.ProcessedReceipts[purchase_id] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if receipt_locks[purchase_id] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product_kind, product_data = resolve_product(product_id)
	if not product_kind then
		warn("[receipt] unknown developer product id " .. tostring(product_id))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	receipt_locks[purchase_id] = true
	local post_commit
	local playtime_cycle_start
	local transaction_ok, transaction_error = data_service.transaction(player, function(data)
		if data.ProcessedReceipts[purchase_id] then
			return
		end
		if product_kind == "crate_restock" then
			crate_service.force_restock_in_profile(data)
			post_commit = "crate_status"
		elseif product_kind == "daily_unlock" then
			if not reward_service.unlock_daily_in_profile(data) then
				error("daily reward data unavailable")
			end
			post_commit = "daily_status"
		elseif product_kind == "playtime_all" then
			local granted, cycle_start = reward_service.grant_all_unclaimed_playtime_in_profile(data)
			if not granted then
				error("playtime rewards unavailable")
			end
			playtime_cycle_start = cycle_start
			post_commit = "playtime_status"
		elseif product_kind == "crate" then
			if not crate_service.grant_crate_in_profile(data, product_data, purchase_id) then
				error("crate grant failed")
			end
			post_commit = { "crate_purchase", product_data.Name }
		elseif product_kind == "currency" then
			local amount = tonumber(product_data.Amount)
			if not amount or amount <= 0 or amount == math.huge then
				error("invalid currency product amount")
			end
			if product_data.Category == "Cash" then
				data.States.Coins += math.floor(amount)
			elseif product_data.Category == "Diamond" then
				data.States.Diamonds += math.floor(amount)
			else
				error("unsupported currency category")
			end
		elseif product_kind == "skin_bundle" then
			local available = skin_names()
			if #available == 0 then
				error("no purchasable chicken skins configured")
			end
			for index = 1, product_data do
				local skin_name = available[math.random(1, #available)]
				local key = skin_name .. "_receipt_" .. purchase_id .. "_" .. tostring(index)
				data.InventoryItems[key] = {
					IsSkin = true,
					SkinName = skin_name,
					SkinType = "Chicken",
				}
			end
		end
		data.ProcessedReceipts[purchase_id] = os.time()
		prune_receipts(data)
	end)
	receipt_locks[purchase_id] = nil
	if not transaction_ok then
		warn("[receipt] purchase " .. purchase_id .. " could not persist: " .. tostring(transaction_error))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if playtime_cycle_start then
		local session = session_data.PlayerSessions[user_id] or session_data.reset(user_id)
		session.SessionStart = playtime_cycle_start
		session.AllUnlocked = false
	end
	if post_commit == "crate_status" then
		crate_event:FireClient(player, "UpdateStatus", crate_service.status(player))
	elseif post_commit == "daily_status" then
		daily_event:FireClient(player, "UpdateStatus", reward_service.daily_status(player))
	elseif post_commit == "playtime_status" then
		playtime_event:FireClient(player, "UpdateStatus", reward_service.playtime_status(player))
	elseif type(post_commit) == "table" and post_commit[1] == "crate_purchase" then
		crate_event:FireClient(player, "PurchaseSuccess", post_commit[2])
		crate_event:FireClient(player, "UpdateStatus", crate_service.status(player))
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function monetization_service.start()
	if started then
		return
	end
	started = true

	shop_function.OnServerInvoke = function(player, request)
		if type(request) ~= "table" or request.Demand ~= "GetPrice" then
			return nil
		end
		if type(request.Category) ~= "string" or type(request.Name) ~= "string" then
			return nil
		end
		if #request.Category > 80 or #request.Name > 120 then
			return nil
		end
		return monetization_service.price(request.Category, request.Name)
	end

	shop_event.OnServerEvent:Connect(function(player, request)
		if not can_prompt(player) or type(request) ~= "table" or type(request.Demand) ~= "string" then
			return
		end
		if request.Demand == "BuyGamePass" and type(request.Name) == "string" then
			local product = shop_storage.Gamepasses[request.Name]
			if product and product.ID then
				marketplace_service:PromptGamePassPurchase(player, product.ID)
			end
		elseif request.Demand == "BuyDevProduct" and type(request.Name) == "string" then
			local product = shop_storage.DevProducts[request.Name]
			if product and product.ID then
				marketplace_service:PromptProductPurchase(player, product.ID)
			end
		elseif request.Demand == "BuyChickenSkin" then
			local product = shop_storage.DevProducts.ChickenSkin
			if request.Type == "Buy1" then
				marketplace_service:PromptProductPurchase(player, product.ID1)
			elseif request.Type == "Buy3" then
				marketplace_service:PromptProductPurchase(player, product.ID3)
			elseif request.Type == "Buy9" then
				marketplace_service:PromptProductPurchase(player, product.ID9)
			end
		end
	end)

	marketplace_service.PromptGamePassPurchaseFinished:Connect(function(player, pass_id, purchased)
		if not purchased or not player or not player.Parent or not entitlement_service.is_known(pass_id) then
			return
		end
		task.spawn(function()
			if entitlement_service.confirm_ownership(player, pass_id) then
				if not entitlement_service.grant(player, pass_id, true) then
					warn("[gamepass] failed to persist entitlement for " .. player.Name)
				end
			end
		end)
	end)

	marketplace_service.ProcessReceipt = process_receipt
end

function monetization_service.clear_player(player)
	prompt_times[player.UserId] = nil
end

return monetization_service
