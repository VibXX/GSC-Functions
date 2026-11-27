-- Card levelling (Clash Royale style): collect duplicate cards of an item, then spend
-- cards + coins to level it up. Every level is a small buff.

local Progression = {}

Progression.MaxLevel = 10
Progression.DamageBonusPerLevel = 0.02 -- +2% damage per level above 1 (level 10 = +18%)
Progression.CooldownReductionPerLevel = 0.01 -- abilities only (level 10 = -9% cooldown)

Progression.StartingCoins = 100
Progression.StarterSword = "InitiatesBlade"
Progression.StarterAbility = "Fireball"

-- Cards needed to go from level N to N+1 (index = current level).
Progression.CardsToUpgrade = {
	Common = { 2, 4, 10, 20, 40, 80, 150, 250, 400 },
	Uncommon = { 2, 4, 8, 15, 30, 60, 100, 160, 250 },
	Rare = { 1, 2, 4, 8, 15, 30, 50, 80, 120 },
	Epic = { 1, 2, 3, 5, 8, 12, 18, 26, 36 },
	Legendary = { 1, 1, 2, 3, 4, 6, 8, 10, 14 },
	Mythic = { 1, 1, 1, 2, 2, 3, 4, 5, 6 },
}

-- Coins needed to go from level N to N+1 (same for every rarity).
Progression.CoinsToUpgrade = { 20, 50, 150, 400, 1000, 2000, 4000, 8000, 15000 }

local function clampLevel(level: number?): number
	return math.clamp(level or 1, 1, Progression.MaxLevel)
end

function Progression.DamageMultiplier(level: number?): number
	return 1 + (clampLevel(level) - 1) * Progression.DamageBonusPerLevel
end

function Progression.CooldownMultiplier(level: number?): number
	return 1 - (clampLevel(level) - 1) * Progression.CooldownReductionPerLevel
end

-- Returns nil when the item is already max level.
function Progression.CardsNeeded(rarity: string, level: number): number?
	if level >= Progression.MaxLevel then
		return nil
	end
	return Progression.CardsToUpgrade[rarity][level]
end

function Progression.CoinsNeeded(level: number): number?
	if level >= Progression.MaxLevel then
		return nil
	end
	return Progression.CoinsToUpgrade[level]
end

return Progression
