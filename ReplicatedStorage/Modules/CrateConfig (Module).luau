-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local config = {}

config.RestockTime = 180
config.RestockButtonText = "Restock For R$39"
config.RestockProductId = 3573051994
config.Crates = {
	{
		Name = "Wooden Crate",
		Order = 1,
		CoinPrice = 500,
		RobuxPrice = 49,
		DeveloperProductId = 0,
		Stock = 5,
		Rewards = {
			{ ToolName = "GravityCoil", Chance = 70 },
			{ ToolName = "SpeedCoil", Chance = 30 },
		},
	},
	{
		Name = "Golden Crate",
		Order = 2,
		CoinPrice = 1500,
		RobuxPrice = 99,
		DeveloperProductId = 0,
		Stock = 3,
		Rewards = {
			{ ToolName = "GravityCoil", Chance = 60 },
			{ ToolName = "SpeedCoil", Chance = 40 },
		},
	},
	{
		Name = "Diamond Crate",
		Order = 3,
		CoinPrice = 5000,
		RobuxPrice = 199,
		DeveloperProductId = 0,
		Stock = 1,
		Rewards = {
			{ ToolName = "GravityCoil", Chance = 50 },
			{ ToolName = "SpeedCoil", Chance = 50 },
		},
	},
}

config.restock_time = config.RestockTime
config.restock_product_id = config.RestockProductId
config.crates = config.Crates

return config
