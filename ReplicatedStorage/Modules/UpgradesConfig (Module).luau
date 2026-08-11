-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local config = {}

config.Upgrades = {
	{
		Name = "Inventory Space",
		Currency = "Diamonds",
		Image = "rbxassetid://18224282235",
		MaxLevel = 4,
		Levels = {
			[1] = { Cost = 0, Description = "5 spaces", Value = 5 },
			[2] = { Cost = 500, Description = "5 → 10 spaces", Value = 10 },
			[3] = { Cost = 1500, Description = "10 → 15 spaces", Value = 15 },
			[4] = { Cost = 5000, Description = "Max spaces reached", Value = 15 },
		},
	},
	{
		Name = "Multi Ragebait",
		Currency = "Diamonds",
		Image = "rbxassetid://75590499344429",
		MaxLevel = 4,
		Levels = {
			[1] = { Cost = 0, Description = "Ragebait 1 NPC", Value = 1 },
			[2] = { Cost = 1000, Description = "Ragebait 2 NPCs", Value = 2 },
			[3] = { Cost = 3000, Description = "Ragebait 3 NPCs", Value = 3 },
			[4] = { Cost = 8000, Description = "Ragebait 4 NPCs", Value = 4 },
		},
	},
}

config.upgrades = config.Upgrades

return config
