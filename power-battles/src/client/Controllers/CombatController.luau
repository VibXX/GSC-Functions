-- Local combat input: sword combos (predicted slash VFX + animation), parry, and aimed ability casts.
-- The server is authoritative; this only predicts visuals so it feels instant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Combat = require(Shared.Config.Combat)
local Swords = require(Shared.Config.Swords)
local Abilities = require(Shared.Config.Abilities)
local Animations = require(Shared.Config.Animations)
local Keybinds = require(Shared.Config.Keybinds)
local Anim = require(Shared.Lib.Anim)
local VFX = require(Shared.Lib.VFX)
local Catalog = require(Shared.Lib.Catalog)
local State = require(script.Parent.Parent.ClientState)
local MovementController = require(script.Parent.MovementController)
local FxController = require(script.Parent.FxController)

local LocalPlayer = Players.LocalPlayer

local CombatController = {}

local combo = 0
local lastSwing = 0
local holdingAttack = false

local function character(): Model?
	return LocalPlayer.Character
end

local function canAct(): boolean
	if not State.InMatch() or not State.Match or State.Match.State ~= "Fighting" then
		return false
	end
	local c = character()
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 or MovementController.IsRagdolled() then
		return false
	end
	return (c:GetAttribute("StunnedUntil") or 0) <= Workspace:GetServerTimeNow()
end

local function swordStats()
	local data = State.Data
	local id = data and data.Equipped.Sword or "InitiatesBlade"
	return id, Swords.GetStats(id, 1, true)
end

local function swing()
	if not canAct() then
		return
	end
	local id, stats = swordStats()
	local now = os.clock()
	if now - lastSwing < stats.SwingCooldown then
		return
	end
	if now - lastSwing > Combat.ComboResetTime then
		combo = 0
	end
	combo = combo % stats.ComboLength + 1
	lastSwing = now
	local finisher = combo == stats.ComboLength
	local c = character()
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart
	local animId = Animations.Swings[((combo - 1) % #Animations.Swings) + 1]
	Anim.Play(c, animId, 0.05, 1, 1)
	if root then
		VFX.Slash(root, Catalog.Theme("Sword", id), combo, stats.Range, finisher)
	end
	FxController.EnableTrail(c, 0.25)
	Net.Event("Swing"):FireServer()
end

local function parry()
	if not canAct() or State.CooldownRemaining("Parry") > 0 then
		return
	end
	State.StartCooldown("Parry", Combat.Parry.Cooldown)
	Anim.Play(character(), Animations.Parry, 0.03)
	Net.Event("Parry"):FireServer()
end

-- World point under the crosshair (screen centre, since shift lock is on).
function CombatController.AimPoint(): Vector3
	local camera = Workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if character() then
		table.insert(exclude, character() :: Model)
	end
	local effects = Workspace:FindFirstChild("LocalEffects")
	if effects then
		table.insert(exclude, effects)
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	return result and result.Position or (ray.Origin + ray.Direction * 1000)
end

local function castAbility()
	if not canAct() or (State.Match and State.Match.Abilities == false) then
		return
	end
	if State.CooldownRemaining("Ability") > 0 then
		return
	end
	local data = State.Data
	local id = data and data.Equipped.Ability or "Fireball"
	local def = Abilities.ById[id]
	-- Optimistic cooldown so spamming the key doesn't spam the server; the server's Cooldown
	-- event overwrites this with the real (level-adjusted) value.
	State.StartCooldown("Ability", def and def.Stats.Cooldown * 0.9 or 1)
	local animId = (def and Animations.CastById[def.Id]) or (def and Animations.Cast[def.Kind])
	Anim.Play(character(), animId, 0.05)
	Net.Event("CastAbility"):FireServer(CombatController.AimPoint())
end

function CombatController.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local binds = State.Binds()
		if Keybinds.Matches(input, "Attack", binds) then
			holdingAttack = true
			swing()
		elseif Keybinds.Matches(input, "Parry", binds) then
			parry()
		elseif Keybinds.Matches(input, "Ability", binds) then
			castAbility()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if Keybinds.Matches(input, "Attack", State.Binds()) then
			holdingAttack = false
		end
	end)
	-- Holding attack keeps swinging.
	task.spawn(function()
		while true do
			task.wait(0.05)
			if holdingAttack then
				swing()
			end
		end
	end)
	-- Parried: play the success animation locally.
	Net.Event("ParryFx").OnClientEvent:Connect(function(payload)
		if payload.Success and payload.Victim == LocalPlayer then
			Anim.Play(character(), Animations.ParrySuccess, 0.03)
		elseif payload.Success and payload.Attacker == LocalPlayer then
			Anim.Play(character(), Animations.Stunned, 0.05)
			combo = 0
		end
	end)
end

return CombatController
