local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")

local controller = {}
local started = false
local player = players.LocalPlayer
local generation = 0
local beam
local highlight
local attachments = {}

local function clear_target()
	if beam then beam:Destroy() beam = nil end
	if highlight then highlight:Destroy() highlight = nil end
	for _, attachment in ipairs(attachments) do
		if attachment and attachment.Parent then attachment:Destroy() end
	end
	table.clear(attachments)
end

local function text_label()
	local game_ui = player:WaitForChild("PlayerGui"):WaitForChild("GameUI")
	return game_ui:WaitForChild("Tutorial")
end

local function typewrite(text, hide_after)
	generation += 1
	local my_generation = generation
	local label = text_label()
	label.Visible = true
	label.Text = ""
	task.spawn(function()
		for index = 1, utf8.len(text) or #text do
			if my_generation ~= generation then return end
			local byte_index = utf8.offset(text, index + 1)
			label.Text = byte_index and string.sub(text, 1, byte_index - 1) or text
			task.wait(0.05)
		end
		if hide_after then
			task.wait(hide_after)
			if my_generation == generation then
				label.Visible = false
			end
		end
	end)
end

local function show_target(npc_name)
	clear_target()
	local character = player.Character
	local player_root = character and character:FindFirstChild("HumanoidRootPart")
	local npc_folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("NPC")
	local npc = npc_folder and npc_folder:FindFirstChild(npc_name)
	local npc_root = npc and npc:FindFirstChild("HumanoidRootPart")
	if not player_root or not npc_root then return end
	local from = Instance.new("Attachment")
	from.Name = "TutorialBeamFrom"
	from.Parent = player_root
	local to = Instance.new("Attachment")
	to.Name = "TutorialBeamTo"
	to.Parent = npc_root
	attachments = { from, to }
	beam = Instance.new("Beam")
	beam.Name = "TutorialBeam"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 0))
	beam.Texture = "rbxassetid://278543077"
	beam.TextureSpeed = 2
	beam.TextureLength = 4
	beam.Width0 = 0.35
	beam.Width1 = 0.35
	beam.FaceCamera = true
	beam.Parent = player_root
	highlight = Instance.new("Highlight")
	highlight.Name = "TutorialHighlight"
	highlight.Adornee = npc
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.FillTransparency = 0.5
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.Parent = npc
end

local function cleanup(hide_text)
	generation += 1
	clear_target()
	if hide_text then
		text_label().Visible = false
	end
end

function controller.start()
	if started then return end
	started = true
	local event = replicated_storage.RemoteEvents:WaitForChild("TutorialEvent")
	event.OnClientEvent:Connect(function(action, data)
		if action == "SkipTutorial" or action == "CompleteTutorial" then
			cleanup(true)
		elseif action == "StartStep" and type(data) == "table" then
			cleanup(false)
			if data.TargetType == "NPC" and type(data.TargetNPC) == "string" then
				show_target(data.TargetNPC)
			end
			typewrite(tostring(data.Text or ""))
		elseif action == "ChaseStartedEvent" or action == "PlayerCaughtEvent" then
			cleanup(true)
		elseif action == "ShowEscapeText" then
			clear_target()
			typewrite("Click to escape!")
		elseif action == "PlayerEscapedTutorial" then
			clear_target()
			typewrite("Congratulations! Enjoy the game!", 3)
		end
	end)
end

return controller
