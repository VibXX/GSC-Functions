-- Builds a sword model for an item id. Uses ReplicatedStorage.Assets.Swords.<Id> if an artist-made
-- model exists (must contain a BasePart named "Handle" at the grip, blade along +Y), otherwise
-- generates a procedural one from the Visual table in Config/Swords.
--
-- Every sword gets attachments "BladeBase" + "BladeTip" on the Handle (used for trails / slash VFX).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = script.Parent.Parent.Config
local Swords = require(Config.Swords)
local Rarities = require(Config.Rarities)

local SwordBuilder = {}

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function material(name: string?): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name or "Metal"]
	end)
	return ok and value or Enum.Material.Metal
end

local function build(def): Model
	local v = def.Visual
	local model = Instance.new("Model")
	model.Name = def.Id

	local gripLength = 1.1
	local handle = part("Handle", Vector3.new(0.28, gripLength, 0.28), v.Grip, Enum.Material.Fabric, model)
	handle.Shape = Enum.PartType.Block

	local origin = CFrame.new()
	local function place(p: BasePart, cf: CFrame)
		p.CFrame = origin * cf
		weld(handle, p)
	end

	-- Pommel
	local pommel = part("Pommel", Vector3.new(0.42, 0.42, 0.42), v.Guard, Enum.Material.Metal, model)
	pommel.Shape = Enum.PartType.Ball
	place(pommel, CFrame.new(0, -gripLength / 2 - 0.12, 0))

	-- Guard
	local guard = part("Guard", Vector3.new(v.GuardWidth, 0.2, 0.36), v.Guard, Enum.Material.Metal, model)
	place(guard, CFrame.new(0, gripLength / 2 + 0.1, 0))

	-- Blade (main slab + tapered tip made from two wedges)
	local bladeBaseY = gripLength / 2 + 0.2
	local tipLength = math.min(0.9, v.Length * 0.2)
	local bodyLength = v.Length - tipLength
	local blade = part("Blade", Vector3.new(v.Width, bodyLength, 0.12), v.Blade, material(v.Material), model)
	blade.Transparency = v.Transparency or 0
	blade.Reflectance = (v.Material == "Metal" or v.Material == "Foil") and 0.15 or 0
	place(blade, CFrame.new(0, bladeBaseY + bodyLength / 2, 0))

	local tipY = bladeBaseY + bodyLength + tipLength / 2
	for side = -1, 1, 2 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Tip"
		wedge.Size = Vector3.new(0.12, tipLength, v.Width / 2)
		wedge.Color = v.Blade
		wedge.Material = material(v.Material)
		wedge.Transparency = v.Transparency or 0
		wedge.CanCollide, wedge.CanQuery, wedge.CanTouch, wedge.Massless, wedge.CastShadow = false, false, false, true, false
		wedge.Parent = model
		-- A wedge's tall face is on its local +Z; turn it to face the blade's centre line so the
		-- two halves meet in a point at the top.
		place(wedge, CFrame.new(side * v.Width / 4, tipY, 0) * CFrame.Angles(0, math.rad(-90 * side), 0))
	end

	-- Glowing edge (fuller line) for anything with Glow > 0
	if (v.Glow or 0) > 0 then
		local edge = part("Edge", Vector3.new(math.max(0.06, v.Width * 0.18), bodyLength * 0.92, 0.14), v.Edge, Enum.Material.Neon, model)
		edge.Transparency = 1 - math.clamp(v.Glow, 0.1, 1) * 0.85
		place(edge, CFrame.new(0, bladeBaseY + bodyLength * 0.5, 0))
		if v.Glow >= 0.5 then
			local light = Instance.new("PointLight")
			light.Color = v.Edge
			light.Range = 6 + v.Glow * 4
			light.Brightness = 0.6 + v.Glow
			light.Shadows = false
			light.Parent = edge
		end
	end

	-- Rarity gem in the guard
	local rarity = Rarities.Info[def.Rarity]
	if rarity.Index >= 3 then
		local gem = part("Gem", Vector3.new(0.22, 0.22, 0.22), rarity.Color, Enum.Material.Neon, model)
		gem.Shape = Enum.PartType.Ball
		place(gem, CFrame.new(0, gripLength / 2 + 0.1, 0.16))
	end

	-- Attachments for trails
	local base = Instance.new("Attachment")
	base.Name = "BladeBase"
	base.Position = Vector3.new(0, bladeBaseY, 0)
	base.Parent = handle
	local tip = Instance.new("Attachment")
	tip.Name = "BladeTip"
	tip.Position = Vector3.new(0, bladeBaseY + v.Length, 0)
	tip.Parent = handle

	model.PrimaryPart = handle
	return model
end

local function addTrail(model: Model, def)
	local handle = model:FindFirstChild("Handle") :: BasePart
	local base = handle:FindFirstChild("BladeBase") :: Attachment
	local tip = handle:FindFirstChild("BladeTip") :: Attachment
	if not (base and tip) then
		return
	end
	local colors = def.Visual.Trail
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Color = ColorSequence.new(colors[1], colors[2])
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = (def.Visual.Glow or 0) > 0.3 and 1 or 0.4
	trail.Lifetime = 0.18
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.Enabled = false -- turned on by the client during swings
	trail.Parent = handle
end

function SwordBuilder.Build(id: string): Model
	local def = Swords.ById[id] or Swords.ById.InitiatesBlade
	local model: Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local custom = assets and assets:FindFirstChild("Swords") and assets.Swords:FindFirstChild(def.Id)
	if custom and custom:IsA("Model") and custom:FindFirstChild("Handle") then
		model = custom:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide, d.CanQuery, d.CanTouch, d.Massless, d.Anchored = false, false, false, true, false
			end
		end
		model.PrimaryPart = model:FindFirstChild("Handle") :: BasePart
	else
		model = build(def)
	end
	model.Name = "Sword"
	model:SetAttribute("SwordId", def.Id)
	addTrail(model, def)
	return model
end

-- Welds a built sword into a character's right hand. Returns the Motor6D (animatable as "SwordGrip").
function SwordBuilder.Attach(character: Model, sword: Model, offset: CFrame?): Motor6D?
	local hand = character:FindFirstChild("RightHand") :: BasePart
	if not hand then
		return nil
	end
	local gripAttachment = hand:FindFirstChild("RightGripAttachment") :: Attachment
	local handle = sword.PrimaryPart :: BasePart
	local motor = Instance.new("Motor6D")
	motor.Name = "SwordGrip"
	motor.Part0 = hand
	motor.Part1 = handle
	motor.C0 = (gripAttachment and gripAttachment.CFrame or CFrame.new(0, -0.15, 0)) * (offset or CFrame.new())
	motor.C1 = CFrame.new()
	sword.Parent = character
	motor.Parent = hand
	return motor
end

return SwordBuilder
