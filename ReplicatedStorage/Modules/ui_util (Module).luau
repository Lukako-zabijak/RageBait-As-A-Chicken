local tween_service = game:GetService("TweenService")
local debris = game:GetService("Debris")

local ui_util = {}

function ui_util.play_sound(sound)
	if not sound or not sound:IsA("Sound") then
		return
	end
	local clone = sound:Clone()
	clone.Parent = game:GetService("SoundService")
	clone:Play()
	debris:AddItem(clone, math.max(2, clone.TimeLength + 0.25))
end

function ui_util.bind_hover(gui, sound)
	if not gui or not gui:IsA("GuiObject") then
		return
	end
	local original = gui.Size
	gui.MouseEnter:Connect(function()
		ui_util.play_sound(sound)
		tween_service:Create(gui, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(original.X.Scale * 1.05, original.X.Offset, original.Y.Scale * 1.05, original.Y.Offset),
		}):Play()
	end)
	gui.MouseLeave:Connect(function()
		tween_service:Create(gui, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = original,
		}):Play()
	end)
end

function ui_util.get_click_target(gui)
	if not gui or not gui:IsA("GuiObject") then
		return nil
	end
	if gui:IsA("GuiButton") then
		return gui
	end
	local existing = gui:FindFirstChildWhichIsA("GuiButton")
	if existing then
		return existing
	end
	local button = Instance.new("TextButton")
	button.Name = "_click"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = math.max(gui.ZIndex + 1, 2)
	button.Parent = gui
	return button
end

function ui_util.bind_click(gui, callback, sound)
	local button = ui_util.get_click_target(gui)
	if not button then
		return nil
	end
	local original = gui.Size
	return button.Activated:Connect(function()
		ui_util.play_sound(sound)
		local down = tween_service:Create(gui, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(original.X.Scale * 0.95, original.X.Offset, original.Y.Scale * 0.95, original.Y.Offset),
		})
		down:Play()
		down.Completed:Wait()
		tween_service:Create(gui, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = original,
		}):Play()
		if callback then
			callback()
		end
	end)
end

function ui_util.pop_open(frame, original_size)
	if not frame then
		return
	end
	local target = original_size or frame.Size
	frame.Visible = true
	frame.Size = UDim2.new(0, 0, 0, 0)
	tween_service:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = target,
	}):Play()
end

function ui_util.pop_close(frame, callback)
	if not frame then
		return
	end
	local tween = tween_service:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0),
	})
	tween:Play()
	tween.Completed:Once(function()
		frame.Visible = false
		if callback then
			callback()
		end
	end)
end

function ui_util.format_compact(number)
	local value = tonumber(number) or 0
	local absolute = math.abs(value)
	if absolute >= 1_000_000_000 then
		return string.format("%.1fB", value / 1_000_000_000):gsub("%.0([KMB])", "%1")
	elseif absolute >= 1_000_000 then
		return string.format("%.1fM", value / 1_000_000):gsub("%.0([KMB])", "%1")
	elseif absolute >= 1_000 then
		return string.format("%.1fK", value / 1_000):gsub("%.0([KMB])", "%1")
	end
	return tostring(math.floor(value))
end

return ui_util
