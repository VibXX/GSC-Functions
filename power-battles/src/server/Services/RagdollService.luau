-- R15 ragdolls. The server swaps Motor6Ds for BallSocketConstraints (replicates to everyone); the
-- owning client puts its Humanoid into the Physical state and applies the launch velocity
-- (the client owns its character's physics, so the impulse must be applied there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Combat = require(Shared.Config.Combat)

local RagdollService = {}

local SKIP_MOTORS = { RootJoint = true, Root = true, SwordGrip = true }

local function enable(character: Model)
	if character:GetAttribute("RagdollBuilt") then
		return
	end
	character:SetAttribute("RagdollBuilt", true)
	for _, motor in character:GetDescendants() do
		if motor:IsA("Motor6D") and not SKIP_MOTORS[motor.Name] and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 55
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -40
			socket.TwistUpperAngle = 40
			socket.Parent = motor.Parent
			motor.Enabled = false
		end
	end
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part:SetAttribute("RagdollCollide", part.CanCollide)
			part.CanCollide = true
		end
	end
end

local function disable(character: Model)
	if not character:GetAttribute("RagdollBuilt") then
		return
	end
	character:SetAttribute("RagdollBuilt", nil)
	for _, d in character:GetDescendants() do
		if d.Name == "RagdollSocket" or d.Name == "RagdollA0" or d.Name == "RagdollA1" then
			d:Destroy()
		elseif d:IsA("Motor6D") then
			d.Enabled = true
		end
	end
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("RagdollCollide") ~= nil then
			part.CanCollide = part:GetAttribute("RagdollCollide")
			part:SetAttribute("RagdollCollide", nil)
		end
	end
end

function RagdollService.Setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.Died:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
			enable(character)
			character:SetAttribute("Ragdolled", true)
			-- Dead characters: hand physics to the server so the corpse settles for everyone.
			if root and root:CanSetNetworkOwnership() then
				root:SetNetworkOwner(nil)
			end
		end)
	end
end

function RagdollService.IsRagdolled(character: Model?): boolean
	return character ~= nil and character:GetAttribute("Ragdolled") == true
end

-- Ragdoll a living player for `duration` seconds, launched with `velocity`.
-- Returns false if they're immune (just stood up).
function RagdollService.Ragdoll(player: Player, duration: number, velocity: Vector3): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	if (character:GetAttribute("RagdollImmuneUntil") or 0) > now then
		Net.Event("Knockback"):FireClient(player, velocity * 0.5)
		return false
	end
	duration = math.min(duration, Combat.Ragdoll.MaxDuration)
	local token = (character:GetAttribute("RagdollToken") or 0) + 1
	character:SetAttribute("RagdollToken", token)
	enable(character)
	character:SetAttribute("Ragdolled", true)
	character:SetAttribute("RagdollUntil", now + duration)
	Net.Event("Ragdoll"):FireClient(player, true, duration, velocity)

	task.delay(duration, function()
		if character.Parent == nil or character:GetAttribute("RagdollToken") ~= token then
			return
		end
		if humanoid.Health <= 0 then
			return
		end
		disable(character)
		character:SetAttribute("Ragdolled", false)
		character:SetAttribute("RagdollImmuneUntil", Workspace:GetServerTimeNow() + Combat.Ragdoll.ImmunityAfter)
		Net.Event("Ragdoll"):FireClient(player, false, 0, Vector3.zero)
	end)
	return true
end

function RagdollService.Release(player: Player)
	local character = player.Character
	if character then
		disable(character)
		character:SetAttribute("Ragdolled", false)
	end
end

function RagdollService.Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(RagdollService.Setup)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(RagdollService.Setup)
		if player.Character then
			RagdollService.Setup(player.Character)
		end
	end
end

return RagdollService
