-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local tween_service = game:GetService("TweenService")

local controller = {}
local started = false
local player = players.LocalPlayer
local active = {}
local tick_sound = replicated_storage.Sounds:FindFirstChild("DialogueTick")

local function target_head(character_name, is_player)
	if is_player then
		local target_player = players:FindFirstChild(character_name)
		local character = target_player and target_player.Character
		return character and character:FindFirstChild("Head")
	end
	local npc_folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("NPC")
	local npc = npc_folder and npc_folder:FindFirstChild(character_name)
	return npc and npc:FindFirstChild("Head")
end

local function stop_existing(character_name)
	local old = active[character_name]
	if old then
		old.cancelled = true
		if old.gui and old.gui.Parent then old.gui:Destroy() end
		active[character_name] = nil
	end
end

local function show(text, character_name, is_player)
	if type(text) ~= "string" or type(character_name) ~= "string" then
		return
	end
	local head = target_head(character_name, is_player == true)
	if not head then
		return
	end
	stop_existing(character_name)
	local dialogue_gui = player:WaitForChild("PlayerGui"):FindFirstChild("DialogueGui")
	local template = dialogue_gui and dialogue_gui:FindFirstChild("DialogueTemplate")
	if not template then
		return
	end
	local gui = template:Clone()
	gui.Name = "Dialogue_" .. character_name
	gui.Adornee = head
	gui.Enabled = true
	gui.Parent = dialogue_gui
	local frame = gui:FindFirstChild("DialogueFrame")
	local label = frame and frame:FindFirstChild("DialogueText")
	if not frame or not label then
		gui:Destroy()
		return
	end
	local token = { gui = gui, cancelled = false }
	active[character_name] = token
	local original_size = frame.Size
	frame.Size = UDim2.new(0, 0, 0, 0)
	tween_service:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = original_size,
	}):Play()
	label.Text = ""
	task.spawn(function()
		for index = 1, utf8.len(text) or #text do
			if token.cancelled or not gui.Parent then return end
			local byte_index = utf8.offset(text, index + 1)
			label.Text = byte_index and string.sub(text, 1, byte_index - 1) or text
			if tick_sound then
				local sound = tick_sound:Clone()
				sound.Parent = gui
				sound:Play()
				game:GetService("Debris"):AddItem(sound, 1)
			end
			task.wait(0.05)
		end
		if token.cancelled then return end
		task.wait(3)
		if token.cancelled or not gui.Parent then return end
		local goals = { BackgroundTransparency = 1 }
		tween_service:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
		tween_service:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		}):Play()
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			tween_service:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
		task.wait(0.5)
		if active[character_name] == token then active[character_name] = nil end
		if gui.Parent then gui:Destroy() end
	end)
end

function controller.start()
	if started then return end
	started = true
	replicated_storage.RemoteEvents.DialogueEvent.OnClientEvent:Connect(show)
end

return controller
