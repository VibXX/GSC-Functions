-- Server-authoritative melee combat: sword combos + hitboxes, parry, dash i-frames, damage,
-- status effects, sword passives and kill credit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Combat = require(Shared.Config.Combat)
local Swords = require(Shared.Config.Swords)
local CardLevels = require(Shared.Lib.CardLevels)

local CombatService = {}
local S -- services

local states = {} -- [Player] = state table
local lastAttacker = {} -- [Player] = { Player, Time, Source }

local function newState()
	return {
		LastSwing = 0,
		Combo = 0,
		ParryUntil = 0,
		ParryReadyAt = 0,
		IFrameUntil = 0,
		DashReadyAt = 0,
		AbilityReadyAt = 0,
		StunnedUntil = 0,
		Vulnerable = nil, -- { Mult, Until }
	}
end

function CombatService.GetState(player: Player)
	local st = states[player]
	if not st then
		st = newState()
		states[player] = st
	end
	return st
end

function CombatService.ResetState(player: Player)
	states[player] = newState()
	lastAttacker[player] = nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function CombatService.IsAlive(player: Player): boolean
	local humanoid = humanoidOf(player)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Can this player act (swing / cast / dash / parry) right now?
function CombatService.CanAct(player: Player): boolean
	if not S.MatchService.CanFight(player) or not CombatService.IsAlive(player) then
		return false
	end
	local st = CombatService.GetState(player)
	if os.clock() < st.StunnedUntil then
		return false
	end
	return not S.RagdollService.IsRagdolled(player.Character)
end

-- Equipped sword/ability + their levels. normalized = card levels disabled in this match.
function CombatService.GetLoadout(player: Player)
	local data = S.DataService.Get(player)
	local match = S.MatchService.GetMatch(player)
	local normalized = match ~= nil and match.Settings.CardLevels == false
	local swordId = data and data.Equipped.Sword or "InitiatesBlade"
	local abilityId = data and data.Equipped.Ability or "Fireball"
	return {
		Sword = swordId,
		SwordLevel = data and CardLevels.Level(data, "Sword", swordId) or 1,
		Ability = abilityId,
		AbilityLevel = data and CardLevels.Level(data, "Ability", abilityId) or 1,
		Normalized = normalized,
	}
end

function CombatService.Knockback(victim: Player, velocity: Vector3)
	Net.Event("Knockback"):FireClient(victim, velocity)
end

function CombatService.Stun(player: Player, duration: number)
	local st = CombatService.GetState(player)
	st.StunnedUntil = math.max(st.StunnedUntil, os.clock() + duration)
	if player.Character then
		player.Character:SetAttribute("StunnedUntil", Workspace:GetServerTimeNow() + duration)
	end
end

function CombatService.GetLastAttacker(victim: Player)
	local info = lastAttacker[victim]
	if info and os.clock() - info.Time <= Combat.LastHitCreditTime and info.Player.Parent then
		return info.Player, info.Source
	end
	return nil
end

-- Returns true if `victim` parried an attack from `attacker`.
-- melee: the attacker gets stunned. Parries only work if the victim roughly faces the attack.
function CombatService.TryParry(victim: Player, attacker: Player?, fromPosition: Vector3, melee: boolean): boolean
	local st = CombatService.GetState(victim)
	if os.clock() > st.ParryUntil then
		return false
	end
	local root = rootOf(victim)
	if not root then
		return false
	end
	local toAttack = fromPosition - root.Position
	toAttack = Vector3.new(toAttack.X, 0, toAttack.Z)
	if toAttack.Magnitude > 0.1 and root.CFrame.LookVector:Dot(toAttack.Unit) < Combat.Parry.FacingDot then
		return false
	end
	st.ParryUntil = 0
	st.ParryReadyAt = 0 -- successful parry refunds the cooldown
	Net.Event("Cooldown"):FireClient(victim, "Parry", 0)
	if melee and attacker then
		CombatService.Stun(attacker, Combat.Parry.StunAttacker)
	end
	Net.Event("ParryFx"):FireAllClients({ Victim = victim, Attacker = attacker, Success = true, Position = root.Position })
	local match = S.MatchService.GetMatch(victim)
	if match then
		S.POTGService.Log(match, { Type = "Parry", Actor = victim.UserId, Target = attacker and attacker.UserId })
		match:AddStat(victim, "Parries", 1)
	end
	return true
end

-- Core damage entry point. source = {
--   Type = "Sword" | "Ability" | "Status", Id, Position (where the hit came from),
--   Parryable (default true for swords), Unavoidable (skip i-frames/parry),
--   Ragdoll (seconds), Velocity (launch / knockback), Status (table), Melee
-- }
-- Returns "Hit" | "Parried" | "Dodged" | "None"
function CombatService.Damage(attacker: Player?, victim: Player, amount: number, source)
	local humanoid = humanoidOf(victim)
	local root = rootOf(victim)
	if not humanoid or not root or humanoid.Health <= 0 then
		return "None"
	end
	if attacker and not S.MatchService.AreEnemies(attacker, victim) then
		return "None"
	end
	local st = CombatService.GetState(victim)
	local now = os.clock()
	local fromPosition = source.Position or root.Position

	if not source.Unavoidable then
		if now < st.IFrameUntil then
			Net.Event("HitFx"):FireAllClients({ Type = "Dodge", Victim = victim, Position = root.Position })
			return "Dodged"
		end
		if source.Parryable ~= false and CombatService.TryParry(victim, attacker, fromPosition, source.Melee == true) then
			return "Parried"
		end
	end

	if st.Vulnerable and now < st.Vulnerable.Until then
		amount *= st.Vulnerable.Mult
	end
	amount = math.max(0, amount)
	humanoid.Health = math.max(0, humanoid.Health - amount)

	if attacker then
		lastAttacker[victim] = { Player = attacker, Time = now, Source = source }
	end
	Net.Event("HitFx"):FireAllClients({
		Type = "Hit",
		Victim = victim,
		Attacker = attacker,
		Amount = amount,
		Source = source.Type,
		Id = source.Id,
		Position = root.Position,
		Label = source.Label,
	})

	local match = S.MatchService.GetMatch(victim)
	if match and attacker then
		match:AddStat(attacker, "Damage", amount)
		S.POTGService.Log(
			match,
			{ Type = "Damage", Actor = attacker.UserId, Target = victim.UserId, Amount = amount, Source = source.Type, Id = source.Id }
		)
	end

	if humanoid.Health > 0 then
		if source.Ragdoll and source.Ragdoll > 0 then
			S.RagdollService.Ragdoll(victim, source.Ragdoll, source.Velocity or Vector3.zero)
		elseif source.Velocity then
			CombatService.Knockback(victim, source.Velocity)
		end
		if source.Status then
			CombatService.ApplyStatus(attacker, victim, source.Status)
		end
	end
	return "Hit"
end

function CombatService.Heal(player: Player, amount: number)
	local humanoid = humanoidOf(player)
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

-- Status effects: DoT (burn / bleed / poison), Slow, Root, Vulnerable.
function CombatService.ApplyStatus(attacker: Player?, victim: Player, status)
	local character = victim.Character
	if not character then
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	if status.Type == "DoT" then
		task.spawn(function()
			for _ = 1, status.Ticks do
				task.wait(status.Interval)
				if not CombatService.IsAlive(victim) or victim.Character ~= character then
					return
				end
				CombatService.Damage(attacker, victim, status.Damage, { Type = "Status", Unavoidable = true, Label = status.Label })
			end
		end)
	elseif status.Type == "Slow" then
		character:SetAttribute("SlowMult", status.Mult)
		character:SetAttribute("SlowUntil", serverNow + status.Duration)
	elseif status.Type == "Root" then
		character:SetAttribute("RootedUntil", serverNow + status.Duration)
	elseif status.Type == "Vulnerable" then
		CombatService.GetState(victim).Vulnerable = { Mult = status.Mult, Until = os.clock() + status.Duration }
	end
end

local function applySwordPassive(attacker: Player, victim: Player, passive, damage: number, finisher: boolean, match)
	if not passive then
		return
	end
	local kind = passive.Type
	if kind == "DoT" or kind == "Slow" or kind == "Vulnerable" then
		CombatService.ApplyStatus(attacker, victim, passive)
	elseif kind == "Lifesteal" then
		CombatService.Heal(attacker, damage * passive.Percent)
	elseif kind == "Knockback" and finisher then
		local aRoot, vRoot = rootOf(attacker), rootOf(victim)
		if aRoot and vRoot then
			local dir = (vRoot.Position - aRoot.Position) * Vector3.new(1, 0, 1)
			if dir.Magnitude > 0.01 then
				S.RagdollService.Ragdoll(victim, 0.8, dir.Unit * passive.Force + Vector3.new(0, passive.Force * 0.5, 0))
			end
		end
	elseif kind == "Chain" then
		local vRoot = rootOf(victim)
		if not vRoot then
			return
		end
		local best, bestDist = nil, passive.Range
		for _, other in match:EnemiesOf(attacker) do
			if other ~= victim and CombatService.IsAlive(other) then
				local oRoot = rootOf(other)
				local dist = oRoot and (oRoot.Position - vRoot.Position).Magnitude or math.huge
				if dist < bestDist then
					best, bestDist = other, dist
				end
			end
		end
		if best then
			local bRoot = rootOf(best) :: BasePart
			Net.Event("HitFx"):FireAllClients({ Type = "Chain", From = vRoot.Position, To = bRoot.Position, Attacker = attacker })
			CombatService.Damage(attacker, best, damage * passive.Percent, { Type = "Sword", Parryable = false, Position = vRoot.Position })
		end
	end
end

local function onSwing(player: Player)
	if not CombatService.CanAct(player) then
		return
	end
	local match = S.MatchService.GetMatch(player)
	local st = CombatService.GetState(player)
	local loadout = CombatService.GetLoadout(player)
	local stats = Swords.GetStats(loadout.Sword, loadout.SwordLevel, loadout.Normalized)
	local now = os.clock()
	if now - st.LastSwing < stats.SwingCooldown * 0.85 then
		return
	end
	if now - st.LastSwing > Combat.ComboResetTime then
		st.Combo = 0
	end
	st.Combo = st.Combo % stats.ComboLength + 1
	st.LastSwing = now
	st.ParryUntil = 0 -- attacking cancels a parry
	local combo = st.Combo
	local finisher = combo == stats.ComboLength
	local character = player.Character

	Net.Event("SwordFx"):FireAllClients({ Player = player, Combo = combo, Finisher = finisher, Sword = loadout.Sword, Range = stats.Range })
	S.POTGService.Log(
		match,
		{ Type = "Swing", Actor = player.UserId, Combo = combo, Finisher = finisher, Sword = loadout.Sword, Range = stats.Range }
	)

	task.delay(stats.HitDelay, function()
		if player.Character ~= character or not CombatService.CanAct(player) then
			return
		end
		local root = rootOf(player)
		if not root then
			return
		end
		local enemyCharacters = {}
		for _, enemy in match:EnemiesOf(player) do
			if enemy.Character then
				table.insert(enemyCharacters, enemy.Character)
			end
		end
		if #enemyCharacters == 0 then
			return
		end
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = enemyCharacters
		local boxCf = root.CFrame * CFrame.new(0, 0, -stats.Range / 2)
		local boxSize = Vector3.new(stats.Range * 0.9, Combat.HitboxHeight, stats.Range)
		local hitPlayers = {}
		for _, part in Workspace:GetPartBoundsInBox(boxCf, boxSize, params) do
			local victim = Players:GetPlayerFromCharacter(part:FindFirstAncestorOfClass("Model"))
			if victim and not hitPlayers[victim] then
				hitPlayers[victim] = true
			end
		end
		local multiplier = 1
		if finisher then
			multiplier = stats.FinisherMultiplier
			if stats.Passive and stats.Passive.Type == "FinisherBoost" then
				multiplier += stats.Passive.Bonus
			end
		end
		for victim in hitPlayers do
			local damage = stats.Damage * multiplier
			local velocity = finisher and (root.CFrame.LookVector * 35 + Vector3.new(0, 12, 0)) or (root.CFrame.LookVector * 8)
			local result = CombatService.Damage(player, victim, damage, {
				Type = "Sword",
				Id = loadout.Sword,
				Melee = true,
				Position = root.Position,
				Velocity = velocity,
			})
			if result == "Hit" then
				applySwordPassive(player, victim, stats.Passive, damage, finisher, match)
			end
		end
	end)
end

local function onParry(player: Player)
	if not CombatService.CanAct(player) then
		return
	end
	local st = CombatService.GetState(player)
	local now = os.clock()
	if now < st.ParryReadyAt then
		return
	end
	st.ParryUntil = now + Combat.Parry.Window + Combat.Parry.LatencyGrace
	st.ParryReadyAt = now + Combat.Parry.Cooldown
	Net.Event("Cooldown"):FireClient(player, "Parry", Combat.Parry.Cooldown)
	Net.Event("ParryFx"):FireAllClients({ Victim = player, Success = false })
end

local function onDash(player: Player, direction: any)
	if not CombatService.CanAct(player) then
		return
	end
	local st = CombatService.GetState(player)
	local now = os.clock()
	if now < st.DashReadyAt then
		return
	end
	st.IFrameUntil = now + Combat.Dash.IFrames + 0.05
	st.DashReadyAt = now + Combat.Dash.Cooldown * 0.9
	Net.Event("Cooldown"):FireClient(player, "Dash", Combat.Dash.Cooldown)
	if typeof(direction) ~= "Vector3" then
		direction = Vector3.zero
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.Event("DashFx"):FireClient(other, player)
		end
	end
	S.POTGService.Log(S.MatchService.GetMatch(player), { Type = "Dash", Actor = player.UserId })
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid
	if not humanoid then
		return
	end
	humanoid.MaxHealth = Combat.MaxHealth
	humanoid.Health = Combat.MaxHealth
	character.Archivable = true -- lets clients clone it for Play of the Game
	local function setGroup(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Characters"
		end
	end
	for _, d in character:GetDescendants() do
		setGroup(d)
	end
	character.DescendantAdded:Connect(setGroup)
	-- Remove default regen: health only changes through combat.
	local regen = character:FindFirstChild("Health")
	if regen and regen:IsA("Script") then
		regen:Destroy()
	end
end

function CombatService.Init(services)
	S = services
end

function CombatService.Start()
	Net.Event("Swing").OnServerEvent:Connect(onSwing)
	Net.Event("Parry").OnServerEvent:Connect(onParry)
	Net.Event("Dash").OnServerEvent:Connect(onDash)
	Net.Event("DoubleJump").OnServerEvent:Connect(function(player)
		for _, other in Players:GetPlayers() do
			if other ~= player then
				Net.Event("DoubleJumpFx"):FireClient(other, player)
			end
		end
		S.POTGService.Log(S.MatchService.GetMatch(player), { Type = "DoubleJump", Actor = player.UserId })
	end)

	local function onPlayer(player: Player)
		CombatService.GetState(player)
		player.CharacterAdded:Connect(function(character)
			CombatService.ResetState(player)
			setupCharacter(player, character)
		end)
		if player.Character then
			setupCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		lastAttacker[player] = nil
	end)
end

return CombatService
