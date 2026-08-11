local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local tween_service = game:GetService("TweenService")
local run_service = game:GetService("RunService")

local controller = {}
local started = false

local player = players.LocalPlayer
local timer_event = replicated_storage:WaitForChild("RemoteEvents"):WaitForChild("TimerEvent")

local dialogue_font = Font.new(
	"rbxasset://fonts/families/ComicNeueAngular.json",
	Enum.FontWeight.Regular,
	Enum.FontStyle.Normal
)

local gui
local status_text
local status_scale
local popup_text
local popup_generation = 0
local layout_top = 24
local layout_connection

local function style_dialogue_text(label)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = dialogue_font
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 1
	label.TextScaled = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.LineHeight = 1
	label.RichText = false

	local stroke = label:FindFirstChild("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "UIStroke"
		stroke.Parent = label
	end
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.Transparency = 0
	stroke.LineJoinMode = Enum.LineJoinMode.Bevel
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
end

local function create_text(parent, name, position, size)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = position
	label.Size = size
	label.Visible = false
	style_dialogue_text(label)
	label.Parent = parent
	return label
end

local function update_layout()
	local desired_absolute_top = 24
	local player_gui = player:FindFirstChildOfClass("PlayerGui")
	local game_ui = player_gui and player_gui:FindFirstChild("GameUI")
	local tutorial = game_ui and game_ui:FindFirstChild("Tutorial")
	if tutorial and tutorial:IsA("GuiObject") and tutorial.Visible then
		desired_absolute_top = math.ceil(tutorial.AbsolutePosition.Y + tutorial.AbsoluteSize.Y + 18)
	end

	local local_origin_y = 0
	if status_text then
		local_origin_y = status_text.AbsolutePosition.Y - status_text.Position.Y.Offset
	end
	layout_top = math.ceil(desired_absolute_top - local_origin_y)
	if status_text then
		status_text.Position = UDim2.new(0.5, 0, 0, layout_top)
	end
	if popup_text and not popup_text.Visible then
		popup_text.Position = UDim2.new(0.5, 0, 0, layout_top + 120)
	end
end

local function ensure_ui()
	if gui and gui.Parent and status_text and status_text.Parent and popup_text and popup_text.Parent then
		return true
	end

	local player_gui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 15)
	if not player_gui then
		warn("[combo] PlayerGui was unavailable")
		return false
	end

	gui = player_gui:FindFirstChild("RageComboGui")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "RageComboGui"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 15
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = player_gui
	end

	for _, legacy_name in ipairs({ "Panel", "Popup", "Progress", "Fill" }) do
		local legacy = gui:FindFirstChild(legacy_name)
		if legacy then
			legacy:Destroy()
		end
	end

	status_text = gui:FindFirstChild("StatusText")
	if not status_text or not status_text:IsA("TextLabel") then
		if status_text then
			status_text:Destroy()
		end
		status_text = create_text(
			gui,
			"StatusText",
			UDim2.new(0.5, 0, 0, 24),
			UDim2.new(0.72, 0, 0, 90)
		)
		local constraint = Instance.new("UISizeConstraint")
		constraint.MaxSize = Vector2.new(460, 90)
		constraint.MinSize = Vector2.new(250, 76)
		constraint.Parent = status_text
	else
		style_dialogue_text(status_text)
	end
	status_text.Text = "RAGE x1\n1 NPC CHASING  •  0s"
	status_text.Visible = false

	status_scale = status_text:FindFirstChildOfClass("UIScale")
	if not status_scale then
		status_scale = Instance.new("UIScale")
		status_scale.Parent = status_text
	end
	status_scale.Scale = 1

	popup_text = gui:FindFirstChild("PopupText")
	if not popup_text or not popup_text:IsA("TextLabel") then
		if popup_text then
			popup_text:Destroy()
		end
		popup_text = create_text(
			gui,
			"PopupText",
			UDim2.new(0.5, 0, 0, 144),
			UDim2.new(0.88, 0, 0, 72)
		)
		local constraint = Instance.new("UISizeConstraint")
		constraint.MaxSize = Vector2.new(640, 72)
		constraint.MinSize = Vector2.new(280, 62)
		constraint.Parent = popup_text
	else
		style_dialogue_text(popup_text)
	end
	popup_text.TextTransparency = 1
	popup_text.Visible = false
	update_layout()

	return true
end

local function pulse()
	if not status_scale then
		return
	end
	status_scale.Scale = 0.88
	tween_service:Create(status_scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function update(data, should_pulse)
	if not ensure_ui() or type(data) ~= "table" then
		return
	end

	update_layout()
	local active = math.max(0, math.floor(tonumber(data.ActiveNPCs) or 0))
	local multiplier = math.max(1, math.floor(tonumber(data.Multiplier) or 1))
	local seconds = math.max(0, math.floor(tonumber(data.StreakSeconds) or 0))
	if active <= 0 then
		status_text.Visible = false
		return
	end

	status_text.Text = "RAGE x" .. tostring(multiplier)
		.. "\n"
		.. tostring(active)
		.. (active == 1 and " NPC CHASING" or " NPCs CHASING")
		.. "  •  "
		.. tostring(seconds)
		.. "s"
	status_text.Visible = true
	if should_pulse then
		pulse()
	end
end

local function show_popup(text)
	if not ensure_ui() then
		return
	end

	update_layout()
	popup_generation += 1
	local generation = popup_generation
	popup_text.Text = text
	popup_text.TextTransparency = 1
	popup_text.Position = UDim2.new(0.5, 0, 0, layout_top + 144)
	popup_text.Visible = true

	tween_service:Create(popup_text, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		Position = UDim2.new(0.5, 0, 0, layout_top + 120),
	}):Play()

	task.delay(1.4, function()
		if generation ~= popup_generation or not popup_text or not popup_text.Parent then
			return
		end
		local tween = tween_service:Create(popup_text, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, layout_top + 106),
		})
		tween:Play()
		tween.Completed:Once(function()
			if generation == popup_generation and popup_text then
				popup_text.Visible = false
			end
		end)
	end)
end

local function attribute_payload()
	return {
		ActiveNPCs = player:GetAttribute("RageNPCs") or 0,
		Multiplier = player:GetAttribute("RageMultiplier") or 1,
		StreakSeconds = player:GetAttribute("RageStreak") or 0,
		NearMisses = player:GetAttribute("RageNearMisses") or 0,
		PeakMultiplier = player:GetAttribute("RagePeakMultiplier") or 1,
	}
end

function controller.start()
	if started then
		return
	end
	started = true
	if not ensure_ui() then
		return
	end
	if not layout_connection then
		layout_connection = run_service.RenderStepped:Connect(function()
			if (status_text and status_text.Visible) or (popup_text and popup_text.Visible) then
				update_layout()
			end
		end)
	end
	task.defer(update_layout)
	update(attribute_payload(), false)

	timer_event.OnClientEvent:Connect(function(action, data)
		if action == "ComboUpdate" then
			update(data, true)
		elseif action == "ComboTick" then
			update(data, false)
		elseif action == "NearMiss" and type(data) == "table" then
			show_popup("NEAR MISS!  +$" .. tostring(data.Coins or 0))
		elseif action == "StreakBonus" and type(data) == "table" then
			local text = tostring(data.Seconds or 0) .. "s RAGE STREAK!  +$" .. tostring(data.Coins or 0)
			if (data.Diamonds or 0) > 0 then
				text ..= "  +" .. tostring(data.Diamonds) .. " DIAMONDS"
			end
			show_popup(text)
		elseif action == "ComboReset" then
			local previous = type(data) == "table" and data or {}
			if previous.Reason == "caught" and ((previous.PeakMultiplier or 1) > 1 or (previous.NearMisses or 0) > 0) then
				show_popup("COMBO BROKEN!")
			end
			if status_text then
				status_text.Visible = false
			end
		end
	end)
end

return controller

