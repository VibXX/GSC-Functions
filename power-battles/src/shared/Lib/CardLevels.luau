-- Card inventory rules. Pure functions over the player's data table (no Roblox services),
-- so the same code runs on the server (authoritative) and client (UI previews).
--
-- data.Swords / data.Abilities = { [itemId] = { Level = number, Cards = number } }
-- The first card of an item unlocks it at level 1; further cards count toward the next level.

local Config = script.Parent.Parent.Config
local Progression = require(Config.Progression)
local Catalog = require(script.Parent.Catalog)

local CardLevels = {}

function CardLevels.GetEntry(data, kind: string, id: string)
	local bucket = data[Catalog.DataKey(kind)]
	return bucket and bucket[id]
end

function CardLevels.Owns(data, kind: string, id: string): boolean
	return CardLevels.GetEntry(data, kind, id) ~= nil
end

function CardLevels.Level(data, kind: string, id: string): number
	local entry = CardLevels.GetEntry(data, kind, id)
	return entry and entry.Level or 1
end

-- Adds cards. Returns (entry, unlockedNow).
function CardLevels.AddCards(data, kind: string, id: string, count: number)
	assert(Catalog.Get(kind, id), "Unknown item " .. tostring(kind) .. "/" .. tostring(id))
	local key = Catalog.DataKey(kind)
	data[key] = data[key] or {}
	local entry = data[key][id]
	if not entry then
		entry = { Level = 1, Cards = math.max(0, count - 1) }
		data[key][id] = entry
		return entry, true
	end
	entry.Cards += count
	return entry, false
end

-- { Owned, Level, Cards, CardsNeeded?, CoinsNeeded?, IsMax, CanUpgrade, Reason? }
function CardLevels.UpgradeInfo(data, kind: string, id: string)
	local def = Catalog.Get(kind, id)
	local entry = def and CardLevels.GetEntry(data, kind, id)
	if not entry then
		return { Owned = false, Level = 0, Cards = 0, IsMax = false, CanUpgrade = false, Reason = "Locked" }
	end
	local cardsNeeded = Progression.CardsNeeded(def.Rarity, entry.Level)
	local coinsNeeded = Progression.CoinsNeeded(entry.Level)
	local info = {
		Owned = true,
		Level = entry.Level,
		Cards = entry.Cards,
		CardsNeeded = cardsNeeded,
		CoinsNeeded = coinsNeeded,
		IsMax = cardsNeeded == nil,
		CanUpgrade = false,
	}
	if info.IsMax then
		info.Reason = "Max level"
	elseif entry.Cards < cardsNeeded then
		info.Reason = "Not enough cards"
	elseif (data.Coins or 0) < coinsNeeded then
		info.Reason = "Not enough coins"
	else
		info.CanUpgrade = true
	end
	return info
end

-- Mutates data. Returns (ok, reasonOrNewLevel).
function CardLevels.Upgrade(data, kind: string, id: string)
	local info = CardLevels.UpgradeInfo(data, kind, id)
	if not info.CanUpgrade then
		return false, info.Reason
	end
	local entry = CardLevels.GetEntry(data, kind, id)
	entry.Cards -= info.CardsNeeded
	entry.Level += 1
	data.Coins -= info.CoinsNeeded
	return true, entry.Level
end

return CardLevels
