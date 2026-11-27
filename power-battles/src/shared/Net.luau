-- Every RemoteEvent / RemoteFunction in the game, declared in one place.
-- The server creates them (Net.Setup); clients wait for them.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.Events = {
	-- client -> server
	"Swing",
	"Parry",
	"Dash",
	"CastAbility",
	"DoubleJump",
	"SkipPOTG",
	-- server -> client
	"DataChanged",
	"LobbyState",
	"MapVote",
	"CustomUpdate",
	"MatchState",
	"RoundResult",
	"MatchResult",
	"ChestResult",
	"Notify",
	"KillFeed",
	"Cooldown",
	"SwordFx",
	"ParryFx",
	"DashFx",
	"DoubleJumpFx",
	"HitFx",
	"AbilityFx",
	"AbilityTick",
	"AbilityImpact",
	"Ragdoll",
	"Knockback",
	"POTG",
}

Net.Functions = {
	"GetData",
	"EquipItem",
	"UpgradeItem",
	"SaveSettings",
	"JoinQueue",
	"LeaveQueue",
	"VoteMap",
	"ListCustom",
	"CreateCustom",
	"JoinCustom",
	"LeaveCustom",
	"UpdateCustom",
	"StartCustom",
	"GetShop",
	"Purchase",
}

local folder: Folder

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder
end

function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup is server only")
	local root = getFolder()
	for _, name in Net.Events do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = root
		end
	end
	for _, name in Net.Functions do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = root
		end
	end
end

function Net.Event(name: string): RemoteEvent
	local root = getFolder()
	if RunService:IsServer() then
		return root:FindFirstChild(name) :: RemoteEvent
	end
	return root:WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	local root = getFolder()
	if RunService:IsServer() then
		return root:FindFirstChild(name) :: RemoteFunction
	end
	return root:WaitForChild(name) :: RemoteFunction
end

-- Server helper: fire to a list of players.
function Net.FireList(name: string, players: { Player }, ...)
	local remote = Net.Event(name)
	for _, player in players do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end

return Net
