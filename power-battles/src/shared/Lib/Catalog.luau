-- Uniform access to swords + abilities ("kinds") for inventory, chests and UI.

local Config = script.Parent.Parent.Config
local Swords = require(Config.Swords)
local Abilities = require(Config.Abilities)
local Rarities = require(Config.Rarities)

local Catalog = {}

Catalog.Kinds = { "Sword", "Ability" }

local SOURCES = {
	Sword = Swords,
	Ability = Abilities,
}

local DATA_KEYS = {
	Sword = "Swords",
	Ability = "Abilities",
}

function Catalog.IsKind(kind: any): boolean
	return typeof(kind) == "string" and SOURCES[kind] ~= nil
end

function Catalog.DataKey(kind: string): string
	return DATA_KEYS[kind]
end

function Catalog.Get(kind: string, id: string)
	local source = SOURCES[kind]
	return source and source.ById[id]
end

function Catalog.List(kind: string)
	return SOURCES[kind].List
end

-- Items of a kind at a rarity, in catalog order.
function Catalog.ByRarity(kind: string, rarity: string)
	local out = {}
	for _, def in SOURCES[kind].List do
		if def.Rarity == rarity then
			table.insert(out, def)
		end
	end
	return out
end

-- Catalog sorted by rarity (then catalog order) - used by the loadout grid.
function Catalog.Sorted(kind: string)
	local list = table.clone(SOURCES[kind].List)
	local order = {}
	for index, def in SOURCES[kind].List do
		order[def.Id] = index
	end
	table.sort(list, function(a, b)
		local ra, rb = Rarities.Index(a.Rarity), Rarities.Index(b.Rarity)
		if ra ~= rb then
			return ra < rb
		end
		return order[a.Id] < order[b.Id]
	end)
	return list
end

-- Colour theme used for VFX tinting (abilities have a Theme; swords derive one from their visuals).
function Catalog.Theme(kind: string, id: string)
	local def = Catalog.Get(kind, id)
	if not def then
		return { Primary = Color3.new(1, 1, 1), Secondary = Color3.new(1, 1, 1), Preset = "Holy" }
	end
	if kind == "Ability" then
		return def.Theme
	end
	return { Primary = def.Visual.Edge, Secondary = def.Visual.Trail[1], Preset = def.Visual.Particles or "Sparks" }
end

return Catalog
