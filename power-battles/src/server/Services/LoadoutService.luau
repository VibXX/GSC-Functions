-- Equipping / upgrading swords + abilities, and putting the equipped sword in the character's hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Combat = require(Shared.Config.Combat)
local Catalog = require(Shared.Lib.Catalog)
local CardLevels = require(Shared.Lib.CardLevels)
local SwordBuilder = require(Shared.Lib.SwordBuilder)

local LoadoutService = {}
local S

-- Rebuilds the sword in the character's hand + sets attributes clients use for VFX theming.
function LoadoutService.Dress(player: Player, inMenu: boolean)
	local character = player.Character
	local data = S.DataService.Get(player)
	if not character or not data then
		return
	end
	local old = character:FindFirstChild("Sword")
	if old then
		old:Destroy()
	end
	local hand = character:FindFirstChild("RightHand")
	local oldGrip = hand and hand:FindFirstChild("SwordGrip")
	if oldGrip then
		oldGrip:Destroy()
	end
	local sword = SwordBuilder.Build(data.Equipped.Sword)
	SwordBuilder.Attach(character, sword, inMenu and Combat.MenuGripOffset or Combat.SwordGripOffset)
	character:SetAttribute("SwordId", data.Equipped.Sword)
	character:SetAttribute("AbilityId", data.Equipped.Ability)
end

function LoadoutService.Init(services)
	S = services
end

function LoadoutService.Start()
	Net.Function("EquipItem").OnServerInvoke = function(player, kind, id)
		if not Catalog.IsKind(kind) or typeof(id) ~= "string" or not Catalog.Get(kind, id) then
			return { ok = false, err = "Unknown item" }
		end
		if S.MatchService.GetMatch(player) then
			return { ok = false, err = "Can't change loadout during a match" }
		end
		local ok = S.DataService.Update(player, function(data)
			if not CardLevels.Owns(data, kind, id) then
				return false
			end
			data.Equipped[kind] = id
			return true
		end)
		if not ok then
			return { ok = false, err = "You don't own that yet" }
		end
		LoadoutService.Dress(player, true)
		return { ok = true }
	end

	Net.Function("UpgradeItem").OnServerInvoke = function(player, kind, id)
		if not Catalog.IsKind(kind) or typeof(id) ~= "string" or not Catalog.Get(kind, id) then
			return { ok = false, err = "Unknown item" }
		end
		local ok, result = false, "No data"
		S.DataService.Update(player, function(data)
			ok, result = CardLevels.Upgrade(data, kind, id)
		end)
		if ok then
			return { ok = true, level = result }
		end
		return { ok = false, err = result }
	end
end

return LoadoutService
