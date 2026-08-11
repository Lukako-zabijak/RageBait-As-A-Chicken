local starter_gui = game:GetService("StarterGui")

local controller = {}
local started = false

function controller.start()
	if started then return end
	started = true
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				starter_gui:SetCore("ResetButtonCallback", false)
			end)
			if ok then return end
			task.wait(0.25)
		end
	end)
end

return controller
