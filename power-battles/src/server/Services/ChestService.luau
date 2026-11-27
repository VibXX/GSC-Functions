-- Grants end-of-match chests (and chests bought in the shop).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local ChestRoller = require(Shared.Lib.ChestRoller)

local ChestService = {}
local S

-- Rolls + grants a chest. Returns the result (also sent to the client for the opening animation).
function ChestService.Grant(player: Player, chestType: string, reason: string?)
	local coinMultiplier = 1 + (S.ShopService.CoinBonus(player) or 0)
	local result = S.DataService.Update(player, function(data)
		local rolled = ChestRoller.Roll(chestType, data)
		return ChestRoller.Apply(rolled, data, coinMultiplier)
	end)
	if result then
		result.Reason = reason
		Net.Event("ChestResult"):FireClient(player, result)
	end
	return result
end

function ChestService.Init(services)
	S = services
end

return ChestService
