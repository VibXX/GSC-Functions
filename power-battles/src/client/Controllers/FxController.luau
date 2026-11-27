-- Renders every combat effect the server broadcasts (swings, parries, dashes, hits, abilities).
-- The same functions are reused by Play of the Game, which passes a `resolve` function that maps
-- players to their replay ghosts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local VFX = require(Shared.Lib.VFX)
local Catalog = require(Shared.Lib.Catalog)
local Abilities = require(Shared.Config.Abilities)
local State = require(script.Parent.Parent.ClientState)

local LocalPlayer = Players.LocalPlayer

local FxController = {}

local active = {} -- [key] = { Parts = { [subId] = BasePart }, Conns = {}, Extra = {} }

local function defaultResolve(player: Player?): Model?
	return player and player.Character or nil
end

local function rootOf(model: Model?): BasePart?
	return model and model:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function abilityTheme(id: string)
	local def = Abilities.ById[id]
	return def and def.Theme or { Primary = Color3.new(1, 1, 1), Secondary = Color3.new(1, 1, 1), Preset = "Holy" }
end

function FxController.CharacterTheme(character: Model?)
	local id = character and character:GetAttribute("AbilityId")
	return abilityTheme(id or "Fireball")
end

local function keyOf(payload, replay: boolean?): string
	return (replay and "r" or "") .. tostring(payload.CastId)
end

local function record(key: string)
	local r = active[key]
	if not r then
		r = { Parts = {}, Conns = {}, Extra = {} }
		active[key] = r
	end
	return r
end

local function cleanup(key: string, subId: number?)
	local r = active[key]
	if not r then
		return
	end
	if subId and r.Parts[subId] then
		r.Parts[subId]:Destroy()
		r.Parts[subId] = nil
		if next(r.Parts) then
			return
		end
	end
	for _, part in r.Parts do
		part:Destroy()
	end
	for _, conn in r.Conns do
		conn:Disconnect()
	end
	for _, inst in r.Extra do
		inst:Destroy()
	end
	active[key] = nil
end

local function elapsedOf(payload): number
	if payload.ReplayElapsed then
		return payload.ReplayElapsed
	end
	return math.max(0, State.ServerNow() - (payload.T0 or State.ServerNow()))
end

-- Projectile body shapes so different abilities read differently at a glance.
local function projectileBody(payload, theme): BasePart
	local size = payload.Size or 2
	local def = Abilities.ById[payload.Id]
	local preset = theme.Preset
	if def and def.Stats.Pierce and size >= 4 then
		-- Flying crescent
		local blade = VFX.Part(Vector3.new(size * 1.8, 0.35, size * 0.5), theme.Secondary or theme.Primary)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-size * 0.9, 0, 0)
		a0.Parent = blade
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(size * 0.9, 0, 0)
		a1.Parent = blade
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(theme.Secondary or theme.Primary, theme.Primary)
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.LightEmission = 1
		trail.Lifetime = 0.2
		trail.Parent = blade
		return blade
	elseif preset == "Lightning" or preset == "Water" then
		-- Spear
		local spear = VFX.Part(Vector3.new(size * 0.4, size * 0.4, size * 3.5), theme.Secondary or theme.Primary)
		VFX.Emitter(spear, theme, { Rate = 50, Lifetime = 0.25, Size = size * 0.4, Speed = 2, Rise = 0 })
		local light = Instance.new("PointLight")
		light.Color = theme.Primary
		light.Range = 14
		light.Brightness = 3
		light.Parent = spear
		return spear
	elseif preset == "Earth" then
		local rock = VFX.Part(Vector3.one * size, theme.Primary, Enum.PartType.Ball)
		rock.Material = Enum.Material.Slate
		VFX.Emitter(rock, theme, { Rate = 20, Lifetime = 0.5, Size = 1.2, Speed = 1, Rise = -4 })
		return rock
	end
	return VFX.Projectile(theme, size, payload.Id)
end

local Kinds = {}

function Kinds.Projectile(payload, theme, key)
	local r = record(key)
	local elapsed0 = elapsedOf(payload)
	local start = os.clock() - elapsed0
	local maxT = (payload.Range or 200) / math.max(payload.Speed or 100, 1) + 0.4
	local gravity = payload.Gravity or 0
	for index, dir in payload.Directions or { payload.Direction } do
		local body = projectileBody(payload, theme)
		r.Parts[index] = body
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t > maxT or not body.Parent then
				conn:Disconnect()
				if body.Parent then
					body:Destroy()
				end
				return
			end
			local pos = payload.Origin + dir * payload.Speed * t - Vector3.new(0, 0.5 * gravity * t * t, 0)
			local vel = dir * payload.Speed - Vector3.new(0, gravity * t, 0)
			body.CFrame = CFrame.lookAt(pos, pos + vel)
		end)
		table.insert(r.Conns, conn)
	end
end

function Kinds.Beam(payload, theme)
	local from, to = payload.Origin, payload.End or (payload.Origin + payload.Direction * (payload.Range or 100))
	if theme.Preset == "Lightning" then
		VFX.Lightning(from, to, theme.Secondary or theme.Primary, (payload.Width or 1) * 0.35, 0.3)
		VFX.Lightning(from, to, theme.Primary, (payload.Width or 1) * 0.2, 0.25)
		VFX.BeamLine(from, to, (payload.Width or 1) * 0.5, theme, 0.2)
	else
		VFX.BeamLine(from, to, payload.Width or 2, theme, 0.45)
		VFX.Burst(to, theme, 20, { Speed = 20, Lifetime = 0.5 })
	end
	for _, chain in payload.ChainPoints or {} do
		VFX.Lightning(chain.From, chain.To, theme.Secondary or theme.Primary, 0.4, 0.35)
	end
	VFX.ShakeFrom(from, 3)
end

function Kinds.Charge(payload, theme, key, resolve)
	local character = resolve(payload.Caster)
	local root = rootOf(character)
	if not root then
		return
	end
	local orb = VFX.Part(Vector3.one * 0.5, theme.Secondary or theme.Primary, Enum.PartType.Ball)
	local r = record(key)
	table.insert(r.Extra, orb)
	local duration = payload.Duration or 0.5
	VFX.Tween(orb, duration, { Size = Vector3.one * 3.5 })
	local emitter = VFX.Emitter(orb, theme, { Rate = 80, Lifetime = 0.3, Speed = -8, Size = 0.4 })
	emitter.EmissionDirection = Enum.NormalId.Top
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not orb.Parent or not root.Parent then
			conn:Disconnect()
			return
		end
		orb.CFrame = root.CFrame * CFrame.new(0.8, 1.2, -2.5)
	end)
	table.insert(r.Conns, conn)
	task.delay(duration + 0.05, function()
		cleanup(key)
	end)
end

function Kinds.Nova(payload, theme)
	VFX.Shockwave(payload.Origin - Vector3.new(0, 2.5, 0), payload.Radius or 15, theme.Primary, 0.5)
	VFX.Sphere(payload.Origin, (payload.Radius or 15) * 0.5, theme.Secondary or theme.Primary, 0.3, 0)
end

function Kinds.Cone(payload, theme)
	local origin = payload.Origin + Vector3.new(0, 1, 0)
	local dir = payload.Direction
	local anchor = VFX.Part(Vector3.one * 0.2, theme.Primary)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.lookAt(origin, origin + dir) * CFrame.Angles(-math.rad(90), 0, 0)
	local emitter = VFX.Emitter(anchor, theme, {
		Speed = (payload.Range or 20) * 2.6,
		Lifetime = 0.45,
		Size = 2,
		Spread = (payload.Angle or 50) / 2,
		Rise = 0,
		Drag = 3,
	})
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter:Emit(math.floor(60 * VFX.Quality))
	Debris:AddItem(anchor, 1.5)
	VFX.Shockwave(
		origin + dir * 3,
		5,
		theme.Secondary or theme.Primary,
		0.3,
		CFrame.lookAt(origin + dir * 3, origin + dir * 10) * CFrame.Angles(math.rad(90), 0, 0)
	)
	VFX.ShakeFrom(origin, 4)
end

function Kinds.Meteor(payload, theme, key)
	local r = record(key)
	local elapsed0 = elapsedOf(payload)
	local delay = payload.Delay or 1
	local interval = payload.Interval or 0
	local flat = Vector3.new(payload.Direction.X, 0, payload.Direction.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.zAxis
	for i, target in payload.Targets or {} do
		local arrive = delay + (i - 1) * interval
		-- Ground warning ring
		local ring = VFX.Part(Vector3.new(0.2, (payload.Radius or 8) * 2, (payload.Radius or 8) * 2), theme.Primary, Enum.PartType.Cylinder)
		ring.CFrame = CFrame.new(target + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.65
		table.insert(r.Extra, ring)
		-- Falling body
		local body = VFX.Projectile(theme, payload.Size or 4, payload.Id)
		table.insert(r.Extra, body)
		local skyStart = target - flat * 40 + Vector3.new(0, 110, 0)
		local start = os.clock() - elapsed0
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			local alpha = math.clamp(t / arrive, 0, 1)
			if not body.Parent then
				conn:Disconnect()
				return
			end
			local pos = skyStart:Lerp(target, alpha * alpha)
			body.CFrame = CFrame.lookAt(pos, target)
			ring.Transparency = 0.45 + 0.3 * math.abs(math.sin(t * 10))
			if alpha >= 1 then
				conn:Disconnect()
				body:Destroy()
				ring:Destroy()
			end
		end)
		table.insert(r.Conns, conn)
	end
end

function Kinds.Line(payload, theme, key)
	-- Telegraph: faint markers along the path; the eruptions themselves come in AbilityImpact.
	for _, target in payload.Targets or {} do
		local mark = VFX.Part(Vector3.new(0.2, 3, 3), theme.Primary, Enum.PartType.Cylinder)
		mark.CFrame = CFrame.new(target + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		mark.Transparency = 0.6
		VFX.Tween(mark, 0.6, { Transparency = 1 })
		Debris:AddItem(mark, 0.7)
	end
end

function Kinds.Blink(payload, theme, key, resolve)
	local character = resolve(payload.Caster)
	local root = rootOf(character)
	if character and root then
		-- Afterimage left at the origin.
		for _, part in character:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
				local ghost = VFX.Part(part.Size, theme.Primary)
				ghost.Material = Enum.Material.ForceField
				ghost.CFrame = part.CFrame - root.Position + payload.From
				ghost.Transparency = 0.3
				VFX.Tween(ghost, 0.5, { Transparency = 1 })
				Debris:AddItem(ghost, 0.55)
			end
		end
	end
	VFX.BeamLine(payload.From, payload.To, 1.6, theme, 0.3)
	VFX.Burst(payload.From, theme, 30, { Speed = 12, Lifetime = 0.6, Smoke = true })
end

function Kinds.Vortex(payload, theme, key)
	local r = record(key)
	local size = payload.Size or 4
	local core = VFX.Part(Vector3.one * size, theme.Secondary or theme.Primary, Enum.PartType.Ball)
	local field = VFX.Part(Vector3.one * (payload.Radius or 12) * 1.4, theme.Primary, Enum.PartType.Ball)
	field.Material = Enum.Material.ForceField
	field.Transparency = 0.2
	r.Parts[1] = core
	table.insert(r.Extra, field)
	local ring =
		VFX.Part(Vector3.new(0.3, (payload.Radius or 12) * 1.6, (payload.Radius or 12) * 1.6), theme.Primary, Enum.PartType.Cylinder)
	ring.Transparency = 0.5
	table.insert(r.Extra, ring)
	local pull = VFX.Emitter(core, theme, { Rate = 90, Lifetime = 0.6, Speed = -(payload.Radius or 12) * 1.5, Size = 0.8, Rise = 0 })
	pull.Shape = Enum.ParticleEmitterShape.Sphere
	pull.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	local light = Instance.new("PointLight")
	light.Color = theme.Primary
	light.Range = 24
	light.Brightness = 3
	light.Parent = core

	-- Predict forward movement until the server's first tick arrives, then follow the ticks
	-- (the server stops the vortex when it hits a wall).
	local position = payload.Origin
	r.Target = nil
	local elapsed0 = elapsedOf(payload)
	position += payload.Direction * (payload.Speed or 30) * math.min(elapsed0, payload.Duration or 3)
	local spin = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not core.Parent then
			conn:Disconnect()
			return
		end
		if r.Target then
			position = position:Lerp(r.Target, math.clamp(dt * 8, 0, 1))
		else
			position += payload.Direction * (payload.Speed or 30) * dt
		end
		spin += dt * 6
		core.CFrame = CFrame.new(position)
		field.CFrame = CFrame.new(position) * CFrame.Angles(spin * 0.3, spin, 0)
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, spin, math.rad(90) + math.sin(spin) * 0.3)
	end)
	table.insert(r.Conns, conn)
	-- Safety cleanup if the final impact never arrives.
	task.delay((payload.Duration or 3) + 2, function()
		cleanup(key)
	end)
end

function FxController.AbilityStart(payload, resolve, replay: boolean?)
	resolve = resolve or defaultResolve
	local theme = abilityTheme(payload.Id)
	local handler = Kinds[payload.Kind]
	if handler then
		handler(payload, theme, keyOf(payload, replay), resolve)
	end
end

function FxController.AbilityTick(payload, replay: boolean?)
	local r = active[keyOf(payload, replay)]
	if r then
		r.Target = payload.Position
	end
end

function FxController.AbilityImpact(payload, replay: boolean?)
	local theme = abilityTheme(payload.Id)
	local key = keyOf(payload, replay)
	if payload.Parried then
		VFX.Burst(
			payload.Position,
			{ Primary = Color3.fromRGB(255, 210, 90), Secondary = Color3.new(1, 1, 1), Preset = "Sparks" },
			30,
			{ Speed = 30, Lifetime = 0.35 }
		)
		VFX.Text(payload.Position, "DEFLECTED", Color3.fromRGB(255, 215, 110), 1)
	elseif payload.Small then
		-- Ground eruption (spikes / pillars)
		local height = (payload.Radius or 5) * 1.6
		local spike = VFX.Part(Vector3.new(2.2, height, 2.2), theme.Secondary or theme.Primary)
		if theme.Preset == "Ice" then
			spike.Material = Enum.Material.Ice
			spike.Transparency = 0.15
		end
		local tilt = CFrame.Angles(math.rad(math.random(-20, 20)), math.rad(math.random(0, 360)), math.rad(math.random(-20, 20)))
		spike.CFrame = CFrame.new(payload.Position - Vector3.new(0, height / 2, 0)) * tilt
		VFX.Tween(
			spike,
			0.12,
			{ CFrame = CFrame.new(payload.Position + Vector3.new(0, height / 2 - 0.5, 0)) * tilt },
			Enum.EasingStyle.Back
		)
		task.delay(1.1, function()
			VFX.Tween(spike, 0.4, { Transparency = 1, Size = spike.Size * 0.3 })
		end)
		Debris:AddItem(spike, 1.6)
		VFX.Burst(payload.Position, theme, 14, { Speed = 16, Lifetime = 0.5, Smoke = true })
		VFX.ShakeFrom(payload.Position, 3)
	else
		VFX.Explosion(payload.Position, payload.Radius or 8, theme, payload.Id)
	end
	if payload.Final then
		cleanup(key, payload.SubId)
	elseif payload.SubId then
		cleanup(key, payload.SubId)
	end
end

local function enableTrail(character: Model?, duration: number)
	local sword = character and character:FindFirstChild("Sword")
	local handle = sword and sword:FindFirstChild("Handle")
	local trail = handle and handle:FindFirstChild("SwingTrail") :: Trail
	if trail then
		trail.Enabled = true
		task.delay(duration, function()
			if trail.Parent then
				trail.Enabled = false
			end
		end)
	end
end
FxController.EnableTrail = enableTrail

function FxController.SwordSwing(payload, resolve)
	resolve = resolve or defaultResolve
	local character = resolve(payload.Player)
	local root = rootOf(character)
	if not root then
		return
	end
	local theme = Catalog.Theme("Sword", payload.Sword)
	VFX.Slash(root, theme, payload.Combo, payload.Range or 7, payload.Finisher)
	enableTrail(character, 0.25)
end

function FxController.Dash(character: Model?)
	if not character then
		return
	end
	local theme = FxController.CharacterTheme(character)
	for i = 0, 2 do
		task.delay(i * 0.05, VFX.Afterimage, character, theme.Primary)
	end
	local root = rootOf(character)
	if root then
		VFX.Burst(root.Position - Vector3.new(0, 2.5, 0), theme, 10, { Speed = 8, Lifetime = 0.35, Smoke = true })
	end
end

function FxController.DoubleJump(character: Model?)
	if character then
		VFX.DoubleJump(character, FxController.CharacterTheme(character))
	end
end

function FxController.Parry(payload, resolve)
	resolve = resolve or defaultResolve
	local character = resolve(payload.Victim)
	if not character then
		return
	end
	if payload.Success then
		local pos = payload.Position or (rootOf(character) and (rootOf(character) :: BasePart).Position) or Vector3.zero
		local gold = { Primary = Color3.fromRGB(255, 200, 80), Secondary = Color3.new(1, 1, 1), Preset = "Sparks" }
		VFX.Burst(pos + Vector3.new(0, 1, 0), gold, 40, { Speed = 35, Lifetime = 0.4 })
		VFX.Shockwave(pos, 7, gold.Primary, 0.35)
		VFX.Flash(character, Color3.fromRGB(255, 230, 150), 0.3)
		VFX.Text(pos + Vector3.new(0, 2, 0), "PARRY!", gold.Primary, 1.4)
		VFX.ShakeFrom(pos, 5)
		local attacker = resolve(payload.Attacker)
		if attacker then
			VFX.Flash(attacker, Color3.fromRGB(120, 120, 140), 0.9)
		end
	else
		VFX.Flash(character, Color3.fromRGB(255, 240, 200), 0.15)
	end
end

function FxController.Hit(payload, resolve)
	resolve = resolve or defaultResolve
	local settings = State.Settings()
	if payload.Type == "Dodge" then
		VFX.Text(payload.Position + Vector3.new(0, 2, 0), "DODGE", Color3.fromRGB(180, 220, 255), 0.9)
		return
	elseif payload.Type == "Chain" then
		local theme = Catalog.Theme("Sword", "Stormfang")
		VFX.Lightning(payload.From, payload.To, theme.Primary, 0.3, 0.3)
		return
	end
	local character = resolve(payload.Victim)
	if character then
		VFX.Flash(character, Color3.new(1, 1, 1), 0.12)
	end
	local isLocalInvolved = payload.Attacker == LocalPlayer or payload.Victim == LocalPlayer
	if settings.DamageNumbers and isLocalInvolved and payload.Position then
		local color = payload.Victim == LocalPlayer and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 240, 200)
		if payload.Label then
			color = Color3.fromRGB(255, 160, 80)
		end
		VFX.Text(
			payload.Position + Vector3.new(0, 2.5, 0),
			tostring(math.floor(payload.Amount + 0.5)),
			color,
			payload.Source == "Status" and 0.7 or 1
		)
	end
	if payload.Source == "Sword" and payload.Position then
		local theme = { Primary = Color3.fromRGB(255, 255, 255), Secondary = Color3.fromRGB(255, 220, 180), Preset = "Sparks" }
		VFX.Burst(payload.Position + Vector3.new(0, 1, 0), theme, 12, { Speed = 22, Lifetime = 0.25 })
	end
	if payload.Victim == LocalPlayer and settings.ScreenShake then
		VFX.CameraShake(payload.Source == "Ability" and 6 or 3, 0.2)
	end
end

function FxController.Init()
	local function apply()
		local q = State.Settings().VfxQuality
		VFX.Quality = (q == "Low" and 0.35) or (q == "Medium" and 0.7) or 1
	end
	State.DataChanged:Connect(apply)
	apply()

	Net.Event("SwordFx").OnClientEvent:Connect(function(payload)
		if payload.Player ~= LocalPlayer then
			FxController.SwordSwing(payload)
		end
	end)
	Net.Event("ParryFx").OnClientEvent:Connect(function(payload)
		FxController.Parry(payload)
	end)
	Net.Event("DashFx").OnClientEvent:Connect(function(player)
		FxController.Dash(player.Character)
	end)
	Net.Event("DoubleJumpFx").OnClientEvent:Connect(function(player)
		FxController.DoubleJump(player.Character)
	end)
	Net.Event("HitFx").OnClientEvent:Connect(function(payload)
		FxController.Hit(payload)
	end)
	Net.Event("AbilityFx").OnClientEvent:Connect(function(payload)
		FxController.AbilityStart(payload)
	end)
	Net.Event("AbilityTick").OnClientEvent:Connect(function(payload)
		FxController.AbilityTick(payload)
	end)
	Net.Event("AbilityImpact").OnClientEvent:Connect(function(payload)
		FxController.AbilityImpact(payload)
	end)
end

-- Clears every running effect (used when a round ends / POTG starts).
function FxController.ClearAll()
	for key in active do
		cleanup(key)
	end
	local container = Workspace:FindFirstChild("LocalEffects")
	if container then
		container:ClearAllChildren()
	end
end

return FxController
