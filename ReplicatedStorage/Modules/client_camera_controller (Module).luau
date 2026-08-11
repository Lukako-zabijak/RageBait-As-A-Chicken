-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local tween_service = game:GetService("TweenService")

local controller = {}
local started = false

local player = players.LocalPlayer
local camera_event = replicated_storage.RemoteEvents:WaitForChild("CameraEvent")

local function restore_camera(character)
	local camera = workspace.CurrentCamera
	local humanoid = character and (character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5))
	if not camera or not humanoid then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
end

function controller.start()
	if started then
		return
	end
	started = true

	camera_event.OnClientEvent:Connect(function(action, value)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if action == "HookCamera" and typeof(value) == "CFrame" then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = value
		elseif action == "IncreaseFOV" and type(value) == "number" then
			tween_service:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = camera.FieldOfView + value,
			}):Play()
		elseif action == "DecreaseFOV" and type(value) == "number" then
			tween_service:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = camera.FieldOfView - value,
			}):Play()
		end
	end)

	player.CharacterAdded:Connect(function(character)
		task.defer(restore_camera, character)
	end)
	if player.Character then
		task.defer(restore_camera, player.Character)
	end
end

return controller
