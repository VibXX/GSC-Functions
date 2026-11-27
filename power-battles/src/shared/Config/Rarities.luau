-- Rarity tiers shared by swords and abilities.
-- StatScale is the "power budget" multiplier applied to sword archetype stats.
-- Abilities have their numbers authored per item (see Abilities.luau), already following this curve.

local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Rarities.Info = {
	Common = { Index = 1, Color = Color3.fromRGB(176, 180, 186), StatScale = 1.00 },
	Uncommon = { Index = 2, Color = Color3.fromRGB(86, 204, 120), StatScale = 1.04 },
	Rare = { Index = 3, Color = Color3.fromRGB(72, 152, 255), StatScale = 1.08 },
	Epic = { Index = 4, Color = Color3.fromRGB(176, 92, 255), StatScale = 1.12 },
	Legendary = { Index = 5, Color = Color3.fromRGB(255, 176, 48), StatScale = 1.16 },
	Mythic = { Index = 6, Color = Color3.fromRGB(255, 64, 96), StatScale = 1.20 },
}

function Rarities.Get(name: string)
	return Rarities.Info[name]
end

function Rarities.Index(name: string): number
	local info = Rarities.Info[name]
	return info and info.Index or 0
end

return Rarities
