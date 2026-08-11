local config = {}

config.DeveloperProductId = 3571992898
config.PurchaseButtonText = "Claim All For R$49"
config.Rewards = {
	{ Time = 60, Type = "Coins", Amount = 100 },
	{ Time = 300, Type = "Coins", Amount = 250 },
	{ Time = 600, Type = "Diamonds", Amount = 5 },
	{ Time = 900, Type = "Coins", Amount = 500 },
	{ Time = 1800, Type = "Diamonds", Amount = 15 },
	{ Time = 2400, Type = "Coins", Amount = 1000 },
	{ Time = 3000, Type = "Diamonds", Amount = 25 },
	{ Time = 3600, Type = "Diamonds", Amount = 50 },
}

config.developer_product_id = config.DeveloperProductId
config.purchase_button_text = config.PurchaseButtonText
config.rewards = config.Rewards

return config
