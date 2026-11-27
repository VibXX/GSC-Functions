-- End-of-match chests. Winners get a Victory Chest, losers a Defeat Chest
-- (fewer drops, worse odds, fewer coins). Each drop is a stack of cards for one sword or ability.

local Chests = {}

Chests.Types = {
	Victory = {
		Name = "Victory Chest",
		Drops = 3,
		Coins = { 60, 90 },
		Weights = { Common = 50, Uncommon = 28, Rare = 14, Epic = 6, Legendary = 1.7, Mythic = 0.3 },
		Color = Color3.fromRGB(255, 196, 70),
	},
	Defeat = {
		Name = "Defeat Chest",
		Drops = 1,
		Coins = { 20, 30 },
		Weights = { Common = 62, Uncommon = 25, Rare = 9.5, Epic = 3, Legendary = 0.45, Mythic = 0.05 },
		Color = Color3.fromRGB(150, 150, 165),
	},
}

-- Cards per drop, by rarity (random in range).
Chests.StackSize = {
	Common = { 4, 8 },
	Uncommon = { 3, 5 },
	Rare = { 2, 3 },
	Epic = { 1, 2 },
	Legendary = { 1, 1 },
	Mythic = { 1, 1 },
}

-- Chance that a drop is a sword (otherwise an ability).
Chests.SwordChance = 0.5

-- When an item of the rolled rarity is picked, this is the chance it is forced to be one you don't own yet
-- (only if you are missing any of that rarity). Keeps collections moving.
Chests.UnownedBias = 0.35

-- Bad-luck protection: guaranteed drop of at least this rarity after N chests without one.
Chests.Pity = {
	Legendary = 40,
	Mythic = 120,
}

return Chests
