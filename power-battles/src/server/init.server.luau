-- Power Battles server bootstrap. Loads every service, calls Init(services) on all of them,
-- then Start() on all of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

Players.CharacterAutoLoads = false

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.Setup()

local ORDER = {
	"DataService",
	"DestructionService",
	"RagdollService",
	"CombatService",
	"AbilityService",
	"POTGService",
	"ChestService",
	"ShopService",
	"LoadoutService",
	"MatchService",
}

local services = {}
for _, name in ORDER do
	services[name] = require(script.Services[name])
end
for _, name in ORDER do
	local service = services[name]
	if service.Init then
		service.Init(services)
	end
end
for _, name in ORDER do
	local service = services[name]
	if service.Start then
		task.spawn(service.Start)
	end
end

print("[PowerBattles] server ready")
