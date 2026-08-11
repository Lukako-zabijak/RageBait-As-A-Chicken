local storage = {}

storage.DinoSkinRarities = {
	Common = { Chance = 50 },
	Uncommon = { Chance = 30 },
	Rare = { Chance = 15 },
	Legendary = { Chance = 5 },
}

storage.ChickenSkinPrice = {
	BrownChicken = 50,
	BlackChicken = 25,
	BuilderChicken = 150,
	FireChicken = 250,
	IceChicken = 250,
	KingChicken = 10000,
	NinjaChicken = 500,
	RichChicken = 5000,
	RobotChicken = 2500,
}

storage.AllSkins = {}
storage.chicken_skin_price = storage.ChickenSkinPrice

return storage
