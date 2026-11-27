-- Local lighting presets. Lighting is global per client, so the client switches between the
-- dark gothic menu look and each map's style.

local Lighting = game:GetService("Lighting")

local Atmosphere = {}

local rgb = Color3.fromRGB

local PRESETS = {
	Menu = {
		ClockTime = 0.2,
		Brightness = 0.6,
		Ambient = rgb(20, 22, 28),
		OutdoorAmbient = rgb(28, 30, 38),
		FogColor = rgb(14, 16, 20),
		FogEnd = 220,
		FogStart = 20,
		Atmosphere = { Density = 0.55, Haze = 2.6, Glare = 0, Color = rgb(70, 78, 92), Decay = rgb(30, 32, 40) },
		Color = { Brightness = -0.03, Contrast = 0.22, Saturation = -0.55, TintColor = rgb(205, 215, 235) },
		Bloom = { Intensity = 0.8, Size = 30, Threshold = 1.4 },
	},
	Concrete = {
		ClockTime = 14.5,
		Brightness = 2.2,
		Ambient = rgb(70, 70, 75),
		OutdoorAmbient = rgb(120, 120, 128),
		FogColor = rgb(170, 175, 185),
		FogEnd = 1200,
		FogStart = 200,
		Atmosphere = { Density = 0.3, Haze = 1, Glare = 0.2, Color = rgb(190, 195, 205), Decay = rgb(110, 115, 125) },
		Color = { Brightness = 0, Contrast = 0.08, Saturation = -0.1, TintColor = rgb(255, 255, 255) },
		Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.6 },
	},
	Brick = {
		ClockTime = 17.8,
		Brightness = 1.6,
		Ambient = rgb(70, 50, 45),
		OutdoorAmbient = rgb(120, 90, 80),
		FogColor = rgb(150, 100, 80),
		FogEnd = 900,
		FogStart = 150,
		Atmosphere = { Density = 0.38, Haze = 1.6, Glare = 0.5, Color = rgb(210, 150, 120), Decay = rgb(110, 70, 60) },
		Color = { Brightness = 0, Contrast = 0.12, Saturation = 0, TintColor = rgb(255, 235, 220) },
		Bloom = { Intensity = 0.8, Size = 28, Threshold = 1.4 },
	},
	Frost = {
		ClockTime = 11,
		Brightness = 2.4,
		Ambient = rgb(90, 100, 120),
		OutdoorAmbient = rgb(150, 165, 190),
		FogColor = rgb(200, 215, 235),
		FogEnd = 800,
		FogStart = 100,
		Atmosphere = { Density = 0.42, Haze = 2, Glare = 0.1, Color = rgb(215, 228, 245), Decay = rgb(150, 170, 200) },
		Color = { Brightness = 0.02, Contrast = 0.1, Saturation = -0.15, TintColor = rgb(235, 245, 255) },
		Bloom = { Intensity = 0.7, Size = 24, Threshold = 1.5 },
	},
	Gothic = {
		ClockTime = 0.5,
		Brightness = 1.2,
		Ambient = rgb(40, 42, 52),
		OutdoorAmbient = rgb(70, 74, 92),
		FogColor = rgb(40, 44, 56),
		FogEnd = 700,
		FogStart = 80,
		Atmosphere = { Density = 0.45, Haze = 2.2, Glare = 0, Color = rgb(90, 96, 115), Decay = rgb(40, 42, 55) },
		Color = { Brightness = 0, Contrast = 0.16, Saturation = -0.35, TintColor = rgb(215, 222, 240) },
		Bloom = { Intensity = 0.9, Size = 30, Threshold = 1.3 },
	},
}

local function ensure(className: string, name: string)
	local existing = Lighting:FindFirstChild(name)
	if existing then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function Atmosphere.Apply(name: string)
	local p = PRESETS[name] or PRESETS.Concrete
	Lighting.ClockTime = p.ClockTime
	Lighting.Brightness = p.Brightness
	Lighting.Ambient = p.Ambient
	Lighting.OutdoorAmbient = p.OutdoorAmbient
	Lighting.FogColor = p.FogColor
	Lighting.FogEnd = p.FogEnd
	Lighting.FogStart = p.FogStart
	local atmosphere = ensure("Atmosphere", "PBAtmosphere") :: Atmosphere
	for k, v in p.Atmosphere do
		(atmosphere :: any)[k] = v
	end
	local color = ensure("ColorCorrectionEffect", "PBColor") :: ColorCorrectionEffect
	for k, v in p.Color do
		(color :: any)[k] = v
	end
	local bloom = ensure("BloomEffect", "PBBloom") :: BloomEffect
	for k, v in p.Bloom do
		(bloom :: any)[k] = v
	end
end

return Atmosphere
