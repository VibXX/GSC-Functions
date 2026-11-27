-- Rolls and applies chest rewards. Pure logic; pass a Random for deterministic tests.

local Config = script.Parent.Parent.Config
local Chests = require(Config.Chests)
local Rarities = require(Config.Rarities)
local Catalog = require(script.Parent.Catalog)
local CardLevels = require(script.Parent.CardLevels)

local ChestRoller = {}

local function rollRarity(weights, rng: Random): string
	local total = 0
	for _, rarity in Rarities.Order do
		total += weights[rarity] or 0
	end
	local roll = rng:NextNumber() * total
	for _, rarity in Rarities.Order do
		roll -= weights[rarity] or 0
		if roll <= 0 then
			return rarity
		end
	end
	return Rarities.Order[1]
end

local function pickItem(kind: string, rarity: string, data, rng: Random)
	local pool = Catalog.ByRarity(kind, rarity)
	local unowned = {}
	for _, def in pool do
		if not CardLevels.Owns(data, kind, def.Id) then
			table.insert(unowned, def)
		end
	end
	if #unowned > 0 and rng:NextNumber() < Chests.UnownedBias then
		return unowned[rng:NextInteger(1, #unowned)]
	end
	return pool[rng:NextInteger(1, #pool)]
end

-- Percent odds per rarity for display in the shop / chest screen.
function ChestRoller.GetOdds(chestType: string)
	local weights = Chests.Types[chestType].Weights
	local total = 0
	for _, w in weights do
		total += w
	end
	local odds = {}
	for _, rarity in Rarities.Order do
		odds[rarity] = (weights[rarity] or 0) / total * 100
	end
	return odds
end

-- Rolls a chest. Mutates data.Pity (pity counters are part of the roll). Does NOT grant anything.
function ChestRoller.Roll(chestType: string, data, rng: Random?)
	local chest = assert(Chests.Types[chestType], "Unknown chest " .. tostring(chestType))
	local random = rng or Random.new()
	data.Pity = data.Pity or { Legendary = 0, Mythic = 0 }
	local pity = data.Pity
	pity.Legendary += 1
	pity.Mythic += 1

	local result = {
		Chest = chestType,
		Coins = random:NextInteger(chest.Coins[1], chest.Coins[2]),
		Drops = {},
	}

	for dropIndex = 1, chest.Drops do
		local rarity = rollRarity(chest.Weights, random)
		if dropIndex == 1 then
			if pity.Mythic >= Chests.Pity.Mythic then
				rarity = "Mythic"
			elseif pity.Legendary >= Chests.Pity.Legendary and Rarities.Index(rarity) < Rarities.Index("Legendary") then
				rarity = "Legendary"
			end
		end
		if rarity == "Mythic" then
			pity.Mythic = 0
			pity.Legendary = 0
		elseif rarity == "Legendary" then
			pity.Legendary = 0
		end

		local kind = random:NextNumber() < Chests.SwordChance and "Sword" or "Ability"
		local def = pickItem(kind, rarity, data, random)
		local stack = Chests.StackSize[rarity]
		table.insert(result.Drops, {
			Kind = kind,
			Id = def.Id,
			Name = def.Name,
			Rarity = rarity,
			Cards = random:NextInteger(stack[1], stack[2]),
		})
	end

	-- Show the best drop last (the reveal builds up).
	table.sort(result.Drops, function(a, b)
		return Rarities.Index(a.Rarity) < Rarities.Index(b.Rarity)
	end)
	return result
end

-- Grants a rolled result into data. Annotates each drop with Unlocked / Level / Cards / CardsNeeded.
function ChestRoller.Apply(result, data, coinMultiplier: number?)
	local coins = math.floor(result.Coins * (coinMultiplier or 1) + 0.5)
	result.Coins = coins
	data.Coins = (data.Coins or 0) + coins
	for _, drop in result.Drops do
		local entry, unlocked = CardLevels.AddCards(data, drop.Kind, drop.Id, drop.Cards)
		local info = CardLevels.UpgradeInfo(data, drop.Kind, drop.Id)
		drop.Unlocked = unlocked
		drop.Level = entry.Level
		drop.TotalCards = entry.Cards
		drop.CardsNeeded = info.CardsNeeded
	end
	return result
end

return ChestRoller
