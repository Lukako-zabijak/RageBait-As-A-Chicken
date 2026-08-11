-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local storage = {}

local default_profile = {
	DataVersion = 1,
	States = {
		Coins = 0,
		TimeSurvived = 0,
		Diamonds = 0,
	},
	SkinEquipped = "WhiteChicken",
	SkinType = "Chicken",
	TutorialCompleted = false,
	InventoryItems = {
		WhiteChicken = {
			IsSkin = true,
			SkinName = "WhiteChicken",
			SkinType = "Chicken",
		},
	},
	HasClaimedGroupReward = false,
	GamePasses = {},
	GamePassRewards = {},
	ProcessedReceipts = {},
	DailyRewards = {
		LastClaim = 0,
		ClaimedDays = {},
		AllUnlocked = false,
	},
	PlaytimeRewards = {
		ClaimedRewards = {},
		SessionStart = 0,
	},
	CrateStock = {
		Stock = {},
		LastRestock = 0,
	},
	EquippedTool = "",
	Upgrades = {
		InventorySpace = 1,
		MultiRagebait = 1,
	},
}

storage.default = default_profile
storage.PlrData = {
	Default = default_profile,
}
storage.plr_data = storage.PlrData

return storage
