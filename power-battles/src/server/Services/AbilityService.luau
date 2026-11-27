-- Server-authoritative abilities. Projectiles are simulated on the server with spherecasts (no
-- physical parts); clients only render them from the cast data (AbilityFx / AbilityTick /
-- AbilityImpact). Every ability is aimed at the point the player's crosshair is on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Abilities = require(Shared.Config.Abilities)

local AbilityService = {}
local S

local castCounter = 0
local MAX_AIM_DISTANCE = 1200

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart
end

-- Raycast params that ignore the caster, their team, debris and effects.
local function worldParams(match, caster: Player, includeEnemies: boolean): RaycastParams
	local exclude = { match.DebrisFolder }
	for _, player in match.Players do
		if player.Character and (player == caster or not includeEnemies or not S.MatchService.AreEnemies(caster, player)) then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return params
end

local function playerFromPart(part: Instance?): Player?
	local model = part and part:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model) or nil
end

local function groundBelow(match, position: Vector3, caster: Player): Vector3
	local result = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -200, 0), worldParams(match, caster, false))
	return result and result.Position or position
end

-- Damage + ragdoll every enemy in a sphere. Returns total damage dealt.
local function blast(cast, position: Vector3, radius: number, damage: number, opts)
	opts = opts or {}
	local stats, caster, match = cast.Stats, cast.Caster, cast.Match
	local impact = {
		CastId = cast.CastId,
		Id = cast.Id,
		Position = position,
		Radius = radius,
		Final = opts.Final ~= false,
		Small = opts.Small,
		SubId = opts.SubId,
	}
	Net.FireList("AbilityImpact", match.Players, impact)
	S.POTGService.Log(match, { Type = "Impact", Actor = caster.UserId, Fx = impact })
	if match.Settings.Destruction and (opts.DestructionRadius or stats.Destruction or 0) > 0 then
		S.DestructionService.Explode(
			position,
			opts.DestructionRadius or stats.Destruction,
			40 + (stats.Knockback or 50) * 0.4,
			match.Map,
			match.DebrisFolder
		)
	end
	local total = 0
	for _, enemy in match:EnemiesOf(caster) do
		local root = rootOf(enemy)
		if root and not (opts.Exclude and opts.Exclude[enemy]) and S.CombatService.IsAlive(enemy) then
			local offset = root.Position - position
			local dist = offset.Magnitude
			if dist <= radius + 2 then
				local falloff = 1 - 0.5 * math.clamp(dist / math.max(radius, 1), 0, 1)
				local dir = dist > 0.1 and offset.Unit or cast.Direction
				local velocity = (Vector3.new(dir.X, 0, dir.Z).Unit * (stats.Knockback or 50))
					+ Vector3.new(0, (stats.Knockback or 50) * (opts.Lift or 0.55), 0)
				if velocity ~= velocity then -- NaN guard (dir straight up/down)
					velocity = Vector3.new(0, stats.Knockback or 50, 0)
				end
				local amount = damage * falloff
				local result = S.CombatService.Damage(caster, enemy, amount, {
					Type = "Ability",
					Id = cast.Id,
					Position = position,
					Parryable = opts.Parryable == true,
					Ragdoll = opts.NoRagdoll and 0 or stats.Ragdoll,
					Velocity = velocity,
					Status = stats.Status,
				})
				if result == "Hit" then
					total += amount
					if opts.HitSet then
						opts.HitSet[enemy] = true
					end
				end
			end
		end
	end
	if stats.Lifesteal and total > 0 then
		S.CombatService.Heal(caster, total * stats.Lifesteal)
	end
	return total
end

local function startFx(cast, extra)
	local payload = {
		CastId = cast.CastId,
		Id = cast.Id,
		Kind = cast.Kind,
		Caster = cast.Caster,
		Origin = cast.Origin,
		Direction = cast.Direction,
		T0 = Workspace:GetServerTimeNow(),
		Speed = cast.Stats.Speed,
		Size = cast.Stats.Size,
		Gravity = cast.Stats.Gravity,
		Range = cast.Stats.Range,
		Width = cast.Stats.Width,
		Radius = cast.Stats.Radius,
		Delay = cast.Stats.Delay,
		Duration = cast.Stats.Duration,
		Angle = cast.Stats.Angle,
	}
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	Net.FireList("AbilityFx", cast.Match.Players, payload)
	S.POTGService.Log(cast.Match, { Type = "Ability", Actor = cast.Caster.UserId, Fx = payload })
end

local Handlers = {}

-- Simulates one projectile. Explodes on terrain; non-piercing projectiles also explode on players.
local function simulateProjectile(cast, direction: Vector3, subId: number)
	local stats, match, caster = cast.Stats, cast.Match, cast.Caster
	local position = cast.Origin
	local velocity = direction * stats.Speed
	local traveled = 0
	local radius = (stats.Size or 1.5) / 2
	local pierced = {}
	local params = worldParams(match, caster, true)
	local connection
	local function finish(at: Vector3)
		connection:Disconnect()
		blast(cast, at, stats.Radius, stats.Damage, { Exclude = pierced, Parryable = false, Final = true, SubId = subId })
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		if not match.Active then
			connection:Disconnect()
			return
		end
		if stats.Gravity then
			velocity -= Vector3.new(0, stats.Gravity * dt, 0)
		end
		local step = velocity * dt
		local result = Workspace:Spherecast(position, radius, step, params)
		if result then
			local victim = playerFromPart(result.Instance)
			if victim and S.MatchService.AreEnemies(caster, victim) then
				if S.CombatService.TryParry(victim, caster, result.Position, false) then
					connection:Disconnect()
					local impact = {
						CastId = cast.CastId,
						Id = cast.Id,
						Position = result.Position,
						Radius = 2,
						Final = true,
						Parried = true,
						SubId = subId,
					}
					Net.FireList("AbilityImpact", match.Players, impact)
					S.POTGService.Log(match, { Type = "Impact", Actor = caster.UserId, Fx = impact })
					return
				end
				if stats.Pierce then
					pierced[victim] = true
					local dir = velocity.Unit
					S.CombatService.Damage(caster, victim, stats.Damage, {
						Type = "Ability",
						Id = cast.Id,
						Position = result.Position,
						Parryable = false,
						Ragdoll = stats.Ragdoll,
						Velocity = dir * stats.Knockback + Vector3.new(0, stats.Knockback * 0.4, 0),
						Status = stats.Status,
					})
					-- keep flying; ignore this character from now on
					local filter = params.FilterDescendantsInstances
					table.insert(filter, victim.Character)
					params.FilterDescendantsInstances = filter
					position += step
					traveled += step.Magnitude
					return
				end
			end
			finish(result.Position)
			return
		end
		position += step
		traveled += step.Magnitude
		if traveled >= stats.Range then
			finish(position)
		end
	end)
end

function Handlers.Projectile(cast)
	local stats = cast.Stats
	local count = stats.Count or 1
	local directions = {}
	local base = CFrame.lookAt(Vector3.zero, cast.Direction)
	for i = 1, count do
		local yaw = 0
		if count > 1 then
			yaw = math.rad((i - (count + 1) / 2) * (stats.Spread or 5))
		end
		table.insert(directions, (base * CFrame.Angles(0, yaw, 0)).LookVector)
	end
	startFx(cast, { Directions = directions })
	for i, dir in directions do
		simulateProjectile(cast, dir, i)
	end
end

function Handlers.Beam(cast)
	local stats, match, caster = cast.Stats, cast.Match, cast.Caster
	local function fire()
		local origin, dir = cast.Origin, cast.Direction
		local endPoint = origin + dir * stats.Range
		if not stats.Carve then
			local result = Workspace:Spherecast(origin, stats.Width / 2, dir * stats.Range, worldParams(match, caster, false))
			if result then
				endPoint = result.Position
			end
		end
		-- Players along the beam.
		local hit = {}
		local length = (endPoint - origin).Magnitude
		for _, enemy in match:EnemiesOf(caster) do
			local root = rootOf(enemy)
			if root and S.CombatService.IsAlive(enemy) then
				local rel = root.Position - origin
				local along = rel:Dot(dir)
				if along >= 0 and along <= length then
					local perpendicular = (rel - dir * along).Magnitude
					if perpendicular <= stats.Width / 2 + 2.5 then
						local result = S.CombatService.Damage(caster, enemy, stats.Damage, {
							Type = "Ability",
							Id = cast.Id,
							Position = origin,
							Parryable = false,
							Ragdoll = stats.Ragdoll,
							Velocity = dir * stats.Knockback + Vector3.new(0, stats.Knockback * 0.35, 0),
							Status = stats.Status,
						})
						if result == "Hit" then
							hit[enemy] = true
						end
					end
				end
			end
		end
		-- Chain lightning bounces.
		local chainPoints = {}
		if stats.Chain then
			local current = next(hit)
			local damage = stats.Damage
			for _ = 1, stats.Chain.Count do
				if not current then
					break
				end
				local fromRoot = rootOf(current)
				local best, bestDist = nil, stats.Chain.Range
				for _, enemy in match:EnemiesOf(caster) do
					local root = rootOf(enemy)
					if root and fromRoot and not hit[enemy] and S.CombatService.IsAlive(enemy) then
						local dist = (root.Position - fromRoot.Position).Magnitude
						if dist < bestDist then
							best, bestDist = enemy, dist
						end
					end
				end
				if not best then
					break
				end
				damage *= stats.Chain.Falloff
				local bestRoot = rootOf(best) :: BasePart
				table.insert(chainPoints, { From = (fromRoot :: BasePart).Position, To = bestRoot.Position })
				S.CombatService.Damage(caster, best, damage, {
					Type = "Ability",
					Id = cast.Id,
					Position = (fromRoot :: BasePart).Position,
					Parryable = false,
					Ragdoll = stats.Ragdoll * 0.6,
					Velocity = Vector3.new(0, 25, 0),
				})
				hit[best] = true
				current = best
			end
		end
		startFx(cast, { End = endPoint, ChainPoints = chainPoints })
		if match.Settings.Destruction and stats.Carve then
			S.DestructionService.Carve(origin + dir * 4, endPoint, stats.Destruction, 70, match.Map, match.DebrisFolder)
		end
		blast(cast, endPoint, stats.Radius or stats.Width, stats.Damage * 0.5, { Exclude = hit })
	end
	if (stats.Delay or 0) > 0 then
		Net.FireList("AbilityFx", match.Players, {
			CastId = cast.CastId,
			Id = cast.Id,
			Kind = "Charge",
			Caster = caster,
			Origin = cast.Origin,
			Direction = cast.Direction,
			Duration = stats.Delay,
		})
		task.delay(stats.Delay, function()
			if match.Active and S.CombatService.IsAlive(caster) then
				fire()
			end
		end)
	else
		fire()
	end
end

function Handlers.Nova(cast)
	local root = rootOf(cast.Caster)
	if not root then
		return
	end
	startFx(cast, { Origin = root.Position })
	blast(cast, root.Position, cast.Stats.Radius, cast.Stats.Damage, { Lift = 0.7 })
end

function Handlers.Cone(cast)
	local stats, match, caster = cast.Stats, cast.Match, cast.Caster
	local root = rootOf(caster)
	if not root then
		return
	end
	local flatDir = Vector3.new(cast.Direction.X, 0, cast.Direction.Z)
	flatDir = flatDir.Magnitude > 0.01 and flatDir.Unit or root.CFrame.LookVector
	startFx(cast, { Origin = root.Position, Direction = flatDir })
	local cosAngle = math.cos(math.rad(stats.Angle / 2))
	for _, enemy in match:EnemiesOf(caster) do
		local eRoot = rootOf(enemy)
		if eRoot and S.CombatService.IsAlive(enemy) then
			local rel = eRoot.Position - root.Position
			local flat = Vector3.new(rel.X, 0, rel.Z)
			if flat.Magnitude <= stats.Range and (flat.Magnitude < 2 or flatDir:Dot(flat.Unit) >= cosAngle) then
				S.CombatService.Damage(caster, enemy, stats.Damage, {
					Type = "Ability",
					Id = cast.Id,
					Position = root.Position,
					Parryable = false,
					Ragdoll = stats.Ragdoll,
					Velocity = flatDir * stats.Knockback + Vector3.new(0, stats.Knockback * 0.45, 0),
					Status = stats.Status,
				})
			end
		end
	end
	if match.Settings.Destruction then
		S.DestructionService.Explode(root.Position + flatDir * stats.Range * 0.55, stats.Destruction, 80, match.Map, match.DebrisFolder)
	end
end

local function aimGroundPoint(cast): Vector3
	local stats, match, caster = cast.Stats, cast.Match, cast.Caster
	local result = Workspace:Raycast(cast.Origin, cast.Direction * stats.Range, worldParams(match, caster, false))
	local point = result and result.Position or (cast.Origin + cast.Direction * stats.Range)
	return groundBelow(match, point, caster)
end

function Handlers.Meteor(cast)
	local stats, match = cast.Stats, cast.Match
	local center = aimGroundPoint(cast)
	local rng = Random.new(cast.CastId)
	local targets = {}
	for i = 1, stats.Count or 1 do
		local point = center
		if i > 1 or (stats.Count or 1) > 1 then
			local angle = rng:NextNumber() * math.pi * 2
			local dist = math.sqrt(rng:NextNumber()) * (stats.Spread or 0)
			point = groundBelow(match, center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist), cast.Caster)
		end
		table.insert(targets, point)
	end
	startFx(cast, { Targets = targets, Interval = stats.Interval or 0 })
	for i, point in targets do
		task.delay(stats.Delay + (i - 1) * (stats.Interval or 0), function()
			if match.Active then
				blast(cast, point, stats.Radius, stats.Damage, { Final = i == #targets, Lift = 0.4 })
			end
		end)
	end
end

function Handlers.Line(cast)
	local stats, match, caster = cast.Stats, cast.Match, cast.Caster
	local root = rootOf(caster)
	if not root then
		return
	end
	local flatDir = Vector3.new(cast.Direction.X, 0, cast.Direction.Z)
	flatDir = flatDir.Magnitude > 0.01 and flatDir.Unit or root.CFrame.LookVector
	local feet = groundBelow(match, root.Position, caster)
	local targets = {}
	for i = 1, stats.Count do
		table.insert(targets, groundBelow(match, feet + flatDir * (i * stats.Range / stats.Count), caster))
	end
	startFx(cast, { Targets = targets, Interval = stats.Interval })
	local hitSet = {}
	for i, point in targets do
		task.delay(i * stats.Interval, function()
			if match.Active then
				blast(
					cast,
					point,
					stats.Radius,
					stats.Damage,
					{ Exclude = hitSet, HitSet = hitSet, Lift = 1.2, Small = true, Final = i == #targets }
				)
			end
		end)
	end
end

function Handlers.Blink(cast)
	local stats, match, caster = cast.Stats, cast.Match, cast.Caster
	local character = caster.Character
	local root = rootOf(caster)
	if not root or not character then
		return
	end
	local result = Workspace:Raycast(cast.Origin, cast.Direction * stats.Range, worldParams(match, caster, false))
	local target = result and (result.Position - cast.Direction * 3) or (cast.Origin + cast.Direction * stats.Range)
	target = groundBelow(match, target, caster) + Vector3.new(0, 3, 0)
	local from = root.Position
	local st = S.CombatService.GetState(caster)
	st.IFrameUntil = math.max(st.IFrameUntil, os.clock() + 0.35)
	startFx(cast, { From = from, To = target })
	local flat = Vector3.new(cast.Direction.X, 0, cast.Direction.Z)
	local look = flat.Magnitude > 0.01 and flat.Unit or root.CFrame.LookVector
	character:PivotTo(CFrame.lookAt(target, target + look))
	task.delay(0.08, function()
		if match.Active then
			blast(cast, target, stats.Radius, stats.Damage, { Lift = 0.8 })
		end
	end)
end

function Handlers.Vortex(cast)
	local stats, match, caster = cast.Stats, cast.Match, cast.Caster
	startFx(cast)
	local position = cast.Origin
	local dir = cast.Direction
	local params = worldParams(match, caster, false)
	local elapsed, sinceTick, sinceBroadcast, sinceDestroy = 0, 0, 0, 0
	local stopped = false
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not match.Active then
			connection:Disconnect()
			return
		end
		elapsed += dt
		sinceTick += dt
		sinceBroadcast += dt
		sinceDestroy += dt
		if not stopped then
			local step = dir * stats.Speed * dt
			local result = Workspace:Spherecast(position, (stats.Size or 3) / 2, step, params)
			if result then
				position = result.Position
				stopped = true
			else
				position += step
			end
		end
		if sinceBroadcast >= 0.2 then
			sinceBroadcast = 0
			Net.FireList("AbilityTick", match.Players, { CastId = cast.CastId, Position = position })
		end
		if sinceTick >= (stats.TickRate or 0.25) then
			sinceTick = 0
			for _, enemy in match:EnemiesOf(caster) do
				local root = rootOf(enemy)
				if root and S.CombatService.IsAlive(enemy) then
					local offset = position - root.Position
					if offset.Magnitude <= stats.Radius then
						if (stats.Pull or 0) > 0 and offset.Magnitude > 2 then
							S.CombatService.Knockback(enemy, offset.Unit * stats.Pull + Vector3.new(0, 6, 0))
						end
						if (stats.TickDamage or 0) > 0 then
							S.CombatService.Damage(
								caster,
								enemy,
								stats.TickDamage,
								{ Type = "Ability", Id = cast.Id, Position = position, Parryable = false }
							)
						end
					end
				end
			end
		end
		if match.Settings.Destruction and sinceDestroy >= 0.5 then
			sinceDestroy = 0
			S.DestructionService.Explode(position, stats.Destruction * 0.45, 30, match.Map, match.DebrisFolder)
		end
		if elapsed >= stats.Duration then
			connection:Disconnect()
			blast(cast, position, stats.Radius * 0.8, stats.Damage, { Final = true, Lift = 0.8 })
		end
	end)
end

local function onCast(player: Player, aimPoint: any)
	if typeof(aimPoint) ~= "Vector3" or aimPoint ~= aimPoint then
		return
	end
	if not S.CombatService.CanAct(player) then
		return
	end
	local match = S.MatchService.GetMatch(player)
	if not match or not match.Settings.Abilities then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	local loadout = S.CombatService.GetLoadout(player)
	local def = Abilities.ById[loadout.Ability]
	if not def then
		return
	end
	local stats = Abilities.GetStats(def.Id, loadout.AbilityLevel, loadout.Normalized)
	local st = S.CombatService.GetState(player)
	local now = os.clock()
	if now < st.AbilityReadyAt - 0.1 then
		return
	end
	st.AbilityReadyAt = now + stats.Cooldown
	st.ParryUntil = 0
	Net.Event("Cooldown"):FireClient(player, "Ability", stats.Cooldown)

	-- Clamp the aim point so exploiters can't target across the map instantly.
	local offset = aimPoint - root.Position
	if offset.Magnitude > MAX_AIM_DISTANCE then
		aimPoint = root.Position + offset.Unit * MAX_AIM_DISTANCE
	end
	local origin = root.Position + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector * 2.5
	local direction = aimPoint - origin
	direction = direction.Magnitude > 1 and direction.Unit or root.CFrame.LookVector

	castCounter += 1
	local cast = {
		CastId = castCounter,
		Id = def.Id,
		Kind = def.Kind,
		Caster = player,
		Match = match,
		Stats = stats,
		Origin = origin,
		Direction = direction,
	}
	match:AddStat(player, "AbilitiesCast", 1)
	local handler = Handlers[def.Kind]
	if handler then
		handler(cast)
	else
		warn("[AbilityService] no handler for kind " .. tostring(def.Kind))
	end
end

function AbilityService.Init(services)
	S = services
end

function AbilityService.Start()
	Net.Event("CastAbility").OnServerEvent:Connect(onCast)
end

return AbilityService
