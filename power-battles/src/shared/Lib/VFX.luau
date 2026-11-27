-- Client-side VFX library. Procedural "anime" effects built from Neon parts, Beams, Trails and
-- ParticleEmitters, tinted by each ability's Theme. Every effect first checks for an artist-made
-- override at ReplicatedStorage.Assets.VFX.<AbilityId>.<EffectName> so final VFX can be dropped in
-- without code changes.
--
-- Only call from the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local VFX = {}

VFX.Quality = 1 -- 0.35 Low / 0.7 Medium / 1 High (set from Settings)

local TEX = {
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
}

-- How each preset looks as particles.
local PRESETS = {
	Fire = { Texture = TEX.Fire, Speed = 6, Lifetime = 0.5, Size = 2.2, Rise = 8, Light = true },
	Embers = { Texture = TEX.Spark, Speed = 4, Lifetime = 1, Size = 0.25, Rise = 6, Light = true },
	Earth = { Texture = TEX.Smoke, Speed = 6, Lifetime = 0.9, Size = 2.5, Rise = -10, Light = false },
	Wind = { Texture = TEX.Smoke, Speed = 14, Lifetime = 0.35, Size = 1.6, Rise = 0, Light = false },
	Ice = { Texture = TEX.Spark, Speed = 8, Lifetime = 0.7, Size = 0.6, Rise = -4, Light = true },
	Frost = { Texture = TEX.Spark, Speed = 3, Lifetime = 1, Size = 0.4, Rise = -2, Light = true },
	Lightning = { Texture = TEX.Spark, Speed = 18, Lifetime = 0.25, Size = 0.7, Rise = 0, Light = true },
	Sparks = { Texture = TEX.Spark, Speed = 14, Lifetime = 0.3, Size = 0.4, Rise = 0, Light = true },
	Water = { Texture = TEX.Smoke, Speed = 9, Lifetime = 0.5, Size = 1.2, Rise = -12, Light = false },
	Bubbles = { Texture = TEX.Spark, Speed = 2, Lifetime = 1.2, Size = 0.35, Rise = 4, Light = false },
	Nature = { Texture = TEX.Spark, Speed = 5, Lifetime = 0.9, Size = 0.5, Rise = -3, Light = false },
	Leaves = { Texture = TEX.Spark, Speed = 3, Lifetime = 1.2, Size = 0.4, Rise = -2, Light = false },
	Shadow = { Texture = TEX.Smoke, Speed = 4, Lifetime = 0.8, Size = 2.4, Rise = 3, Light = false },
	Void = { Texture = TEX.Smoke, Speed = -6, Lifetime = 0.8, Size = 2, Rise = 0, Light = true },
	Wisps = { Texture = TEX.Smoke, Speed = 2, Lifetime = 1, Size = 1, Rise = 3, Light = true },
	Holy = { Texture = TEX.Spark, Speed = 8, Lifetime = 0.8, Size = 0.9, Rise = 6, Light = true },
	Blood = { Texture = TEX.Spark, Speed = 10, Lifetime = 0.6, Size = 0.5, Rise = -14, Light = false },
	Poison = { Texture = TEX.Smoke, Speed = 3, Lifetime = 0.9, Size = 1.2, Rise = 2, Light = false },
	Star = { Texture = TEX.Spark, Speed = 10, Lifetime = 1, Size = 1, Rise = 0, Light = true },
	Stars = { Texture = TEX.Spark, Speed = 3, Lifetime = 1, Size = 0.35, Rise = 2, Light = true },
	Prism = { Texture = TEX.Spark, Speed = 6, Lifetime = 1, Size = 0.5, Rise = 2, Light = true },
}

local function preset(name: string?)
	return PRESETS[name or ""] or PRESETS.Sparks
end

local container: Folder?
function VFX.Container(): Folder
	if container and container.Parent then
		return container
	end
	container = Instance.new("Folder")
	container.Name = "LocalEffects"
	container.Parent = Workspace
	return container :: Folder
end

local function tween(obj: Instance, time: number, props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end
VFX.Tween = tween

local function fxPart(size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.Parent = VFX.Container()
	return p
end
VFX.Part = fxPart

-- Artist override lookup: ReplicatedStorage.Assets.VFX.<id>.<name>
function VFX.Custom(id: string?, name: string): Instance?
	if not id then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("VFX")
	local item = folder and folder:FindFirstChild(id)
	local effect = item and item:FindFirstChild(name)
	return effect and effect:Clone() or nil
end

function VFX.Emitter(parent: Instance, theme, opts)
	opts = opts or {}
	local p = preset(opts.Preset or theme.Preset)
	local e = Instance.new("ParticleEmitter")
	e.Texture = p.Texture
	e.Color = ColorSequence.new(theme.Secondary or theme.Primary, theme.Primary)
	e.LightEmission = p.Light and 1 or 0.2
	e.LightInfluence = p.Light and 0 or 1
	local size = (opts.Size or p.Size)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * (opts.EndSize or 0.2)) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	local lifetime = opts.Lifetime or p.Lifetime
	e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	local speed = opts.Speed or p.Speed
	e.Speed = NumberRange.new(math.abs(speed) * 0.5, math.abs(speed))
	e.SpreadAngle = Vector2.new(opts.Spread or 180, opts.Spread or 180)
	e.Acceleration = Vector3.new(0, opts.Rise or p.Rise, 0)
	e.Drag = opts.Drag or 2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Rate = (opts.Rate or 0) * VFX.Quality
	e.LockedToPart = opts.Locked or false
	e.ZOffset = opts.ZOffset or 0
	e.Parent = parent
	return e
end

-- One-shot particle burst at a world position.
function VFX.Burst(position: Vector3, theme, count: number, opts)
	local anchor = fxPart(Vector3.new(0.1, 0.1, 0.1), theme.Primary)
	anchor.Transparency = 1
	anchor.Position = position
	local e = VFX.Emitter(anchor, theme, opts)
	e:Emit(math.max(1, math.floor(count * VFX.Quality)))
	if opts and opts.Smoke then
		local s = VFX.Emitter(
			anchor,
			{ Primary = Color3.fromRGB(40, 40, 40), Secondary = Color3.fromRGB(90, 90, 90) },
			{ Preset = "Earth", Rise = 2, Size = 3, Lifetime = 1.4 }
		)
		s:Emit(math.max(1, math.floor(count * 0.4 * VFX.Quality)))
	end
	Debris:AddItem(anchor, 3)
end

function VFX.Light(position: Vector3, color: Color3, range: number, duration: number)
	local anchor = fxPart(Vector3.new(0.1, 0.1, 0.1), color)
	anchor.Transparency = 1
	anchor.Position = position
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = math.min(60, range)
	light.Brightness = 4
	light.Parent = anchor
	tween(light, duration, { Brightness = 0 })
	Debris:AddItem(anchor, duration + 0.1)
end

function VFX.Shockwave(position: Vector3, radius: number, color: Color3, duration: number?, cframe: CFrame?)
	local t = duration or 0.45
	local ring = fxPart(Vector3.new(0.4, 2, 2), color, Enum.PartType.Cylinder)
	ring.CFrame = (cframe or CFrame.new(position)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.15
	tween(ring, t, { Size = Vector3.new(0.1, radius * 2.2, radius * 2.2), Transparency = 1 })
	Debris:AddItem(ring, t + 0.1)
end

function VFX.Sphere(position: Vector3, radius: number, color: Color3, duration: number?, startTransparency: number?)
	local t = duration or 0.35
	local ball = fxPart(Vector3.new(1, 1, 1), color, Enum.PartType.Ball)
	ball.Position = position
	ball.Transparency = startTransparency or 0.1
	tween(ball, t, { Size = Vector3.one * radius * 2, Transparency = 1 })
	Debris:AddItem(ball, t + 0.1)
end

local shakeUntil, shakeIntensity = 0, 0
function VFX.CameraShake(intensity: number, duration: number)
	shakeIntensity = math.max(shakeIntensity, intensity)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

if RunService:IsClient() then
	RunService:BindToRenderStep("PowerBattlesShake", Enum.RenderPriority.Camera.Value + 2, function()
		if os.clock() < shakeUntil then
			local cam = Workspace.CurrentCamera
			local amount = shakeIntensity * 0.02
			cam.CFrame *= CFrame.Angles((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, 0)
		else
			shakeIntensity = 0
		end
	end)
end

function VFX.ShakeFrom(position: Vector3, strength: number)
	local cam = Workspace.CurrentCamera
	local dist = (cam.CFrame.Position - position).Magnitude
	local falloff = math.clamp(1 - dist / 120, 0, 1)
	if falloff > 0 then
		VFX.CameraShake(strength * falloff, 0.25 + 0.2 * falloff)
	end
end

-- Big anime explosion: core flash, expanding sphere, two shockwave rings, particle burst, light, shake.
function VFX.Explosion(position: Vector3, radius: number, theme, abilityId: string?)
	local custom = VFX.Custom(abilityId, "Impact")
	if custom then
		if custom:IsA("BasePart") then
			custom.Position = position
		elseif custom:IsA("Model") then
			custom:PivotTo(CFrame.new(position))
		end
		custom.Parent = VFX.Container()
		for _, d in custom:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d:Emit(d:GetAttribute("EmitCount") or 20)
			end
		end
		Debris:AddItem(custom, 4)
	else
		VFX.Sphere(position, radius * 0.45, Color3.new(1, 1, 1), 0.12, 0)
		VFX.Sphere(position, radius, theme.Primary, 0.4, 0.05)
		VFX.Shockwave(position, radius, theme.Secondary or theme.Primary, 0.4)
		task.delay(0.06, VFX.Shockwave, position, radius * 1.3, theme.Primary, 0.55)
		VFX.Burst(position, theme, 40, { Speed = radius * 3, Lifetime = 0.7, Size = math.clamp(radius * 0.25, 0.6, 3), Smoke = true })
		VFX.Light(position, theme.Primary, radius * 3, 0.6)
	end
	VFX.ShakeFrom(position, math.clamp(radius / 2, 2, 12))
end

-- Travelling projectile visual. Returns the root part (caller moves it).
function VFX.Projectile(theme, size: number, abilityId: string?): BasePart
	local custom = VFX.Custom(abilityId, "Projectile")
	if custom and custom:IsA("BasePart") then
		custom.Anchored = true
		custom.CanCollide = false
		custom.Parent = VFX.Container()
		return custom
	end
	local core = fxPart(Vector3.one * size, theme.Secondary or theme.Primary, Enum.PartType.Ball)
	local shell = fxPart(Vector3.one * size * 1.6, theme.Primary, Enum.PartType.Ball)
	shell.Transparency = 0.55
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = core
	weld.Part1 = shell
	weld.Parent = core
	shell.Anchored = false
	shell.Parent = core

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.45, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.45, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(theme.Secondary or theme.Primary, theme.Primary)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.LightEmission = 1
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.Parent = core

	VFX.Emitter(core, theme, { Rate = 60, Lifetime = 0.4, Size = size * 0.8, Speed = 1, Rise = 0 })
	local light = Instance.new("PointLight")
	light.Color = theme.Primary
	light.Range = 12 + size * 3
	light.Brightness = 2
	light.Parent = core
	return core
end

-- Straight beam (or carving beam) between two points.
function VFX.BeamLine(from: Vector3, to: Vector3, width: number, theme, duration: number?)
	local t = duration or 0.35
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, to)
	local core = fxPart(Vector3.new(width * 0.45, width * 0.45, length), Color3.new(1, 1, 1), Enum.PartType.Block)
	core.CFrame = cf
	local outer = fxPart(Vector3.new(width, width, length), theme.Primary, Enum.PartType.Block)
	outer.CFrame = cf
	outer.Transparency = 0.35
	tween(core, t, { Size = Vector3.new(0, 0, length), Transparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	tween(outer, t, { Size = Vector3.new(width * 1.6, width * 1.6, length), Transparency = 1 })
	Debris:AddItem(core, t + 0.1)
	Debris:AddItem(outer, t + 0.1)
	VFX.Burst(from, theme, 12, { Speed = 10, Lifetime = 0.3 })
end

-- Jagged lightning between two points.
function VFX.Lightning(from: Vector3, to: Vector3, color: Color3, thickness: number?, duration: number?)
	local segments = math.clamp(math.floor((to - from).Magnitude / 6), 3, 16)
	local last = from
	local w = thickness or 0.35
	for i = 1, segments do
		local alpha = i / segments
		local point = from:Lerp(to, alpha)
		if i < segments then
			point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
		end
		local seg = fxPart(Vector3.new(w, w, (point - last).Magnitude), color)
		seg.CFrame = CFrame.lookAt((last + point) / 2, point)
		tween(seg, duration or 0.25, { Transparency = 1, Size = Vector3.new(0, 0, seg.Size.Z) })
		Debris:AddItem(seg, (duration or 0.25) + 0.1)
		last = point
	end
end

-- Sword slash arc in front of a character (curved Beam between two attachments).
function VFX.Slash(root: BasePart, theme, comboIndex: number, range: number, finisher: boolean?)
	local holder = fxPart(Vector3.new(0.1, 0.1, 0.1), theme.Primary)
	holder.Transparency = 1
	local tilt = ({ 20, -20, 70, -70, 0 })[((comboIndex - 1) % 5) + 1]
	holder.CFrame = root.CFrame * CFrame.new(0, 0.6, -range * 0.35) * CFrame.Angles(0, 0, math.rad(tilt))
	local width = range * (finisher and 1.25 or 0.95)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-width / 2, 0, 0)
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(width / 2, 0, 0)
	a1.Parent = holder
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.CurveSize0 = -range * 0.55
	beam.CurveSize1 = range * 0.55
	beam.Width0 = finisher and 2.6 or 1.6
	beam.Width1 = 0.1
	beam.Color = ColorSequence.new(theme.Secondary or Color3.new(1, 1, 1), theme.Primary)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Segments = 24
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.05),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	beam.Parent = holder
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local alpha = (os.clock() - start) / 0.22
		if alpha >= 1 then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, math.clamp(alpha, 0.05, 1)),
			NumberSequenceKeypoint.new(1, 1),
		})
	end)
	if finisher then
		VFX.Shockwave(root.Position - Vector3.new(0, 2.5, 0), range * 0.8, theme.Primary, 0.35)
	end
end

-- Ghost copies of the character's limbs, fading out (dash afterimage).
function VFX.Afterimage(character: Model, color: Color3)
	for _, d in character:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
			local ghost = fxPart(d.Size, color)
			ghost.CFrame = d.CFrame
			ghost.Transparency = 0.45
			ghost.Material = Enum.Material.ForceField
			tween(ghost, 0.35, { Transparency = 1 })
			Debris:AddItem(ghost, 0.4)
		end
	end
end

function VFX.DoubleJump(character: Model, theme)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then
		return
	end
	local feet = root.Position - Vector3.new(0, 3, 0)
	VFX.Shockwave(feet, 4, theme.Primary, 0.35)
	task.delay(0.05, VFX.Shockwave, feet - Vector3.new(0, 0.5, 0), 6, theme.Secondary or theme.Primary, 0.45)
	VFX.Burst(feet, theme, 18, { Speed = 12, Lifetime = 0.45, Spread = 60 })
end

-- Persistent aura on a character (main menu + optional in-match idle glow). Returns a cleanup function.
function VFX.Aura(character: Model, theme, intensity: number?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then
		return function() end
	end
	local k = intensity or 1
	local items = {}
	local base = Instance.new("Attachment")
	base.Name = "AuraAttachment"
	base.Position = Vector3.new(0, -2.6, 0)
	base.Parent = root
	table.insert(items, base)

	local rising = VFX.Emitter(base, theme, { Rate = 30 * k, Lifetime = 1.4, Size = 0.35, Speed = 2, Rise = 7, Spread = 25, EndSize = 0 })
	rising.Shape = Enum.ParticleEmitterShape.Cylinder
	rising.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	rising.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	local flames = VFX.Emitter(base, theme, { Rate = 14 * k, Lifetime = 0.9, Size = 2.2, Speed = 1, Rise = 6, Spread = 15 })
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	flames.Shape = Enum.ParticleEmitterShape.Cylinder

	local light = Instance.new("PointLight")
	light.Color = theme.Primary
	light.Range = 14
	light.Brightness = 1.4 * k
	light.Parent = root
	table.insert(items, light)

	return function()
		for _, item in items do
			item:Destroy()
		end
	end
end

function VFX.Flash(character: Model, color: Color3?, duration: number?)
	local h = Instance.new("Highlight")
	h.FillColor = color or Color3.new(1, 1, 1)
	h.FillTransparency = 0.2
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = character
	tween(h, duration or 0.18, { FillTransparency = 1 })
	Debris:AddItem(h, (duration or 0.18) + 0.05)
end

-- Floating text (damage numbers, "PARRY!", "DODGE").
function VFX.Text(position: Vector3, text: string, color: Color3, scale: number?)
	local anchor = fxPart(Vector3.new(0.1, 0.1, 0.1), color)
	anchor.Transparency = 1
	anchor.Position = position + Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160 * (scale or 1), 50 * (scale or 1))
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	tween(gui, 0.7, { StudsOffset = Vector3.new(0, 5, 0) })
	task.delay(0.35, function()
		tween(label, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(anchor, 0.8)
end

return VFX
