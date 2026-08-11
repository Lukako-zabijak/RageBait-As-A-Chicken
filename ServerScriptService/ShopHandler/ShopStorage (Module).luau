-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local storage = {}

storage.Gamepasses = {
	["2X Money"] = {
		ID = 1791762659,
		Price = 99,
	},
	["2X Diamond"] = {
		ID = 1791854598,
		Price = 129,
	},
	VIP = {
		ID = 1791582691,
		Price = 159,
		Money = 500,
		Diamond = 100,
		Skin = "VIPChicken",
	},
}

storage.DevProducts = {
	["1000 Cash"] = {
		ID = 3572174265,
		Price = 49,
		Category = "Cash",
		Amount = 1000,
	},
	["10000 Cash"] = {
		ID = 3572174457,
		Price = 99,
		Category = "Cash",
		Amount = 10000,
	},
	["100000 Cash"] = {
		ID = 3572174823,
		Price = 299,
		Category = "Cash",
		Amount = 100000,
	},
	["100 Diamonds"] = {
		ID = 3572174969,
		Price = 49,
		Category = "Diamond",
		Amount = 100,
	},
	["1000 Diamonds"] = {
		ID = 3572175368,
		Price = 99,
		Category = "Diamond",
		Amount = 1000,
	},
	["10000 Diamonds"] = {
		ID = 3572175535,
		Price = 299,
		Category = "Diamond",
		Amount = 10000,
	},
	ChickenSkin = {
		Price = {
			Buy1 = 99,
			Buy3 = 99,
			Buy9 = 99,
		},
		ID1 = 3572239350,
		ID3 = 3572239460,
		ID9 = 3572239546,
	},
}

storage.gamepasses = storage.Gamepasses
storage.dev_products = storage.DevProducts

return storage
