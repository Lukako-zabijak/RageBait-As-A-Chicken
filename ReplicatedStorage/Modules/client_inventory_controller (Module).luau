-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local run_service = game:GetService("RunService")

local ui_util = require(replicated_storage.Modules.ui_util)

local controller = {}
local started = false
local player = players.LocalPlayer
local inventory_event = replicated_storage.RemoteEvents:WaitForChild("InventoryEvent")
local crate_open_event = replicated_storage.RemoteEvents:WaitForChild("CrateOpenEvent")
local skin_event = replicated_storage.RemoteEvents:WaitForChild("SkinEvent")
local click_sound = replicated_storage.Sounds:FindFirstChild("Click")
local hover_sound = replicated_storage.Sounds:FindFirstChild("Hover")

local status
local selected
local selected_frame
local preview_connection
local skin_request_pending = false

local function clear_viewport(viewport)
	if preview_connection then preview_connection:Disconnect() preview_connection = nil end
	if not viewport then return end
	for _, child in ipairs(viewport:GetChildren()) do
		if not child:IsA("UIStroke") then child:Destroy() end
	end
end

local function preview_model(viewport, source, rotate)
	clear_viewport(viewport)
	if not viewport or not source or not source:IsA("Model") then return end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local model = source:Clone()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.Anchored = true end
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then descendant:Destroy() end
	end
	model.Parent = world
	model:PivotTo(CFrame.new())
	local _, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local radius = rotate and 8 or math.max(3, size.Magnitude * 0.8)
	local height = rotate and 2 or math.max(1.5, size.Y * 0.35)
	local angle = 0
	local function update()
		camera.CFrame = CFrame.lookAt(Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius), Vector3.new(0, height * 0.3, 0))
	end
	update()
	if rotate then
		preview_connection = run_service.RenderStepped:Connect(function()
			if not viewport.Parent then
				preview_connection:Disconnect()
				preview_connection = nil
				return
			end
			angle += 0.01
			update()
		end)
	end
end

local function item_key(item)
	return item.ID or item.Name
end

local function inventory_count()
	return status and #status.InventoryItems or 0
end

local function skin_is_equipped(item)
	return status
		and item
		and item.IsSkin
		and status.SkinEquipped == (item.DisplayName or item.Name)
		and status.SkinType == (item.SkinType or "Chicken")
end

local function request_skin_change(item)
	if skin_request_pending or not item or not item.IsSkin then
		return
	end
	local skin_name = item.DisplayName or item.Name
	local skin_type = item.SkinType or "Chicken"
	local key = item_key(item)
	if type(skin_name) ~= "string" or type(skin_type) ~= "string" or type(key) ~= "string" then
		return
	end
	if skin_is_equipped(item) or (player.Character and player.Character.Name == skin_name) then
		return
	end
	skin_request_pending = true
	skin_event:FireServer("ChangeSkin", skin_name, skin_type, key)
	task.delay(2, function()
		skin_request_pending = false
	end)
end

local function set_selected_visual(frame)
	if selected_frame and selected_frame.Parent then
		local previous_skin = selected_frame:GetAttribute("SkinName")
		local previous_type = selected_frame:GetAttribute("SkinType")
		local remains_equipped = previous_skin
			and status
			and status.SkinEquipped == previous_skin
			and status.SkinType == previous_type
		selected_frame.BackgroundColor3 = remains_equipped and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 255, 255)
	end
	selected_frame = frame
	if selected_frame then selected_frame.BackgroundColor3 = Color3.fromRGB(0, 255, 0) end
end

local function show_selected(root, item, frame)
	selected = item
	set_selected_visual(frame)
	local side = root:WaitForChild("SideFrame")
	local image = side:WaitForChild("ItemImage")
	local name = side:WaitForChild("ItemName")
	local action = side:WaitForChild("ActionButton")
	local viewport = side:WaitForChild("ItemViewport")
	local delete = side:WaitForChild("DeleteButton")
	clear_viewport(viewport)
	image.Visible = false
	viewport.Visible = false
	delete.Visible = not item.IsCrate
	if item.IsSkin then
		name.Text = item.DisplayName or item.Name
		viewport.Visible = true
		local skins = replicated_storage.Skins:FindFirstChild(item.SkinType or "Chicken")
		preview_model(viewport, skins and skins:FindFirstChild(item.DisplayName or ""), true)
		local equipped = skin_is_equipped(item) or (player.Character and player.Character.Name == item.DisplayName)
		action.Text = equipped and "Equipped" or "Equip"
		action.BackgroundColor3 = equipped and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(0, 255, 0)
	elseif item.IsCrate then
		name.Text = item.CrateName or item.Name
		viewport.Visible = true
		local source = replicated_storage:FindFirstChild("Crates") and replicated_storage.Crates:FindFirstChild(item.CrateName or "")
		preview_model(viewport, source, false)
		local full = status and inventory_count() >= status.MaxSpace
		action.Text = full and "No Space!" or "Open"
		action.BackgroundColor3 = full and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(0, 200, 255)
	else
		name.Text = item.DisplayName or item.Name
		image.Visible = true
		image.Image = item.Image or ""
		local equipped = status and status.EquippedTool == item.Name
		action.Text = equipped and "Unequip" or "Equip"
		action.BackgroundColor3 = equipped and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 255, 0)
	end
end

local function clear_generated(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Template" then child:Destroy() end
	end
end

local function populate(root)
	if not status then return end
	selected = nil
	selected_frame = nil
	clear_viewport(root.SideFrame.ItemViewport)
	root.Storage.Text = tostring(#status.InventoryItems) .. "/" .. tostring(status.MaxSpace)
	local tool_frame = root.MainFrame
	local crate_frame = root.CrateFrame
	local skin_frame = root.SkinFrame
	clear_generated(tool_frame)
	clear_generated(crate_frame)
	clear_generated(skin_frame)

	for _, item in ipairs(status.InventoryItems) do
		local parent = item.IsSkin and skin_frame or (item.IsCrate and crate_frame or tool_frame)
		local template = parent:FindFirstChild("Template")
		if template then
			local card = template:Clone()
			card.Name = "Item_" .. tostring(item_key(item))
			card.Visible = true
			card.Parent = parent
			if item.IsSkin then
				card:SetAttribute("SkinName", item.DisplayName or item.Name)
				card:SetAttribute("SkinType", item.SkinType or "Chicken")
				if skin_is_equipped(item) then
					card.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
				end
				local label = card:FindFirstChild("SkinName")
				if label then label.Text = item.DisplayName or "Skin" end
				local viewport = card:FindFirstChild("ViewportFrame")
				if viewport then
					local skins = replicated_storage.Skins:FindFirstChild(item.SkinType or "Chicken")
					preview_model(viewport, skins and skins:FindFirstChild(item.DisplayName or ""), false)
				end
			elseif item.IsCrate then
				local label = card:FindFirstChild("CrateName")
				if label then label.Text = item.CrateName or "Crate" end
				local viewport = card:FindFirstChild("ToolPort")
				if viewport then
					local source = replicated_storage:FindFirstChild("Crates") and replicated_storage.Crates:FindFirstChild(item.CrateName or "")
					preview_model(viewport, source, false)
				end
			else
				local label = card:FindFirstChild("ToolName")
				local image = card:FindFirstChild("ToolImage")
				if label then label.Text = item.DisplayName or item.Name end
				if image then image.Image = item.Image or "" end
			end
			ui_util.bind_click(card, function()
				show_selected(root, item, card)
				if item.IsSkin then
					request_skin_change(item)
				end
			end, click_sound)
		end
	end
end

local function show_tab(root, name)
	root.MainFrame.Visible = name == "Tools"
	root.CrateFrame.Visible = name == "Crates"
	root.SkinFrame.Visible = name == "Skins"
end

function controller.start()
	if started then return end
	started = true
	local root = player:WaitForChild("PlayerGui"):WaitForChild("GameUI"):WaitForChild("Frames"):WaitForChild("Inventory")
	local side = root:WaitForChild("SideFrame")
	local action = side:WaitForChild("ActionButton")
	local delete = side:WaitForChild("DeleteButton")
	for name, frame_name in pairs({ ToolsButton = "Tools", CratesButton = "Crates", SkinsButton = "Skins" }) do
		local container = root.SideButtonsFrame:FindFirstChild(name)
		local button = container and container:FindFirstChild("Button")
		if button then
			ui_util.bind_hover(container, hover_sound)
			button.MouseButton1Click:Connect(function()
				ui_util.play_sound(click_sound)
				show_tab(root, frame_name)
			end)
		end
	end
	show_tab(root, "Tools")
	ui_util.bind_hover(action, hover_sound)
	action.MouseButton1Click:Connect(function()
		ui_util.play_sound(click_sound)
		if not selected or not status then return end
		if selected.IsSkin then
			request_skin_change(selected)
		elseif selected.IsCrate then
			if inventory_count() < status.MaxSpace then
				crate_open_event:FireServer("OpenCrate", item_key(selected))
			end
		else
			if status.EquippedTool == selected.Name then
				inventory_event:FireServer("UnequipTool")
			else
				inventory_event:FireServer("EquipTool", selected.Name)
			end
		end
	end)
	ui_util.bind_hover(delete, hover_sound)
	delete.MouseButton1Click:Connect(function()
		ui_util.play_sound(click_sound)
		if selected and not selected.IsCrate then
			inventory_event:FireServer("DeleteTool", item_key(selected))
		end
	end)
	skin_event.OnClientEvent:Connect(function(action_name, success, skin_name, data)
		if action_name ~= "SkinChanged" then
			return
		end
		skin_request_pending = false
		if type(data) == "table" then
			status = data
			populate(root)
			if success and type(skin_name) == "string" then
				for _, item in ipairs(status.InventoryItems) do
					if item.IsSkin and item.DisplayName == skin_name then
						local card = root.SkinFrame:FindFirstChild("Item_" .. tostring(item_key(item)))
						if card then
							show_selected(root, item, card)
						end
						break
					end
				end
			end
		end
	end)

	inventory_event.OnClientEvent:Connect(function(action_name, data)
		if action_name == "UpdateStatus" and type(data) == "table" then
			status = data
			populate(root)
		end
	end)
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		if root.Visible then inventory_event:FireServer("GetStatus") end
	end)
	inventory_event:FireServer("GetStatus")
end

return controller
