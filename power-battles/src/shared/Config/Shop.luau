-- Monetisation. Fill in the real Developer Product / Game Pass IDs from the Creator Dashboard.
-- An Id of 0 means "not configured": the item shows in the shop but can't be bought yet.
--
-- Roblox policy: paid random items (the Victory Chest Key) must show their odds before purchase,
-- and must be hidden for players where PolicyService reports ArePaidRandomItemsRestricted.
-- ShopService + ShopScreen both handle that.

local Shop = {}

Shop.Products = {
	{
		Key = "Coins_500",
		Type = "DevProduct",
		Id = 0,
		Name = "Pouch of Coins",
		Description = "500 coins",
		PriceHint = 49,
		Grants = { Coins = 500 },
	},
	{
		Key = "Coins_1500",
		Type = "DevProduct",
		Id = 0,
		Name = "Chest of Coins",
		Description = "1,500 coins (+20% bonus)",
		PriceHint = 129,
		Grants = { Coins = 1500 },
	},
	{
		Key = "Coins_5000",
		Type = "DevProduct",
		Id = 0,
		Name = "Vault of Coins",
		Description = "5,000 coins (+40% bonus)",
		PriceHint = 349,
		Grants = { Coins = 5000 },
	},
	{
		Key = "ChestKey",
		Type = "DevProduct",
		Id = 0,
		Name = "Victory Chest Key",
		Description = "Open a Victory Chest right now.",
		PriceHint = 75,
		Grants = { Chest = "Victory" },
		Random = true,
	},
}

Shop.GamePasses = {
	{
		Key = "VIP",
		Id = 0,
		Name = "VIP",
		Description = "+25% coins from every chest and a gold nameplate.",
		PriceHint = 299,
		CoinBonus = 0.25,
	},
}

Shop.ByKey = {}
for _, item in Shop.Products do
	Shop.ByKey[item.Key] = item
end
for _, item in Shop.GamePasses do
	item.Type = "GamePass"
	Shop.ByKey[item.Key] = item
end

return Shop
