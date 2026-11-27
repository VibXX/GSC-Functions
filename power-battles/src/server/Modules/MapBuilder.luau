-- Loads a map for a match. Uses ServerStorage.Maps.<Id> if you've built one in Studio; otherwise
-- procedurally generates a fully destructible arena (everything except the base plate breaks).
--
-- Studio-built map requirements:
--   * A part named "Baseplate" (or any parts with attribute Indestructible = true) as the floor.
--   * Folder "Spawns" with folders "Team1" and "Team2" containing spawn Parts.
--   * Everything else should be anchored Block parts for the best destruction (wedges/meshes break
--     off whole instead of being cut).

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModes = require(ReplicatedStorage:WaitForChild("Shared").Config.GameModes)

local MapBuilder = {}

local ARENA = 280
local rgb = Color3.fromRGB

MapBuilder.Styles = {
	Concrete = {
		Floor = { Enum.Material.Concrete, rgb(110, 112, 118) },
		Wall = { Enum.Material.Concrete, rgb(165, 165, 160) },
		Accent = { Enum.Material.Metal, rgb(90, 95, 105) },
		Roof = { Enum.Material.Slate, rgb(80, 80, 85) },
	},
	Brick = {
		Floor = { Enum.Material.Cobblestone, rgb(95, 85, 80) },
		Wall = { Enum.Material.Brick, rgb(150, 82, 62) },
		Accent = { Enum.Material.Wood, rgb(90, 62, 40) },
		Roof = { Enum.Material.Slate, rgb(60, 55, 60) },
	},
	Frost = {
		Floor = { Enum.Material.Snow, rgb(225, 235, 245) },
		Wall = { Enum.Material.Slate, rgb(150, 165, 185) },
		Accent = { Enum.Material.Ice, rgb(170, 215, 255) },
		Roof = { Enum.Material.Snow, rgb(240, 245, 255) },
	},
	Gothic = {
		Floor = { Enum.Material.Cobblestone, rgb(62, 62, 68) },
		Wall = { Enum.Material.Slate, rgb(88, 86, 94) },
		Accent = { Enum.Material.Metal, rgb(45, 45, 50) },
		Roof = { Enum.Material.Slate, rgb(40, 40, 46) },
	},
}

local function block(parent: Instance, size: Vector3, cf: CFrame, look): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = look[1]
	p.Color = look[2]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A wall along local X with optional rectangular openings { {x, width, bottom, height} }.
local function wall(parent: Instance, base: CFrame, length: number, height: number, thickness: number, look, openings)
	openings = openings or {}
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local cursor = -length / 2
	local function segment(x0: number, x1: number, y0: number, y1: number)
		if x1 - x0 > 0.05 and y1 - y0 > 0.05 then
			block(parent, Vector3.new(x1 - x0, y1 - y0, thickness), base * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0), look)
		end
	end
	for _, o in openings do
		local left, right = o[1] - o[2] / 2, o[1] + o[2] / 2
		segment(cursor, left, 0, height)
		segment(left, right, 0, o[3]) -- below opening
		segment(left, right, o[3] + o[4], height) -- above opening
		cursor = right
	end
	segment(cursor, length / 2, 0, height)
end

local function house(parent: Instance, origin: CFrame, w: number, d: number, floors: number, style, rng: Random)
	local model = Instance.new("Model")
	model.Name = "House"
	model.Parent = parent
	local storey = 12
	local t = 1.5
	for f = 0, floors - 1 do
		local y = f * storey
		local base = origin * CFrame.new(0, y, 0)
		local door = f == 0 and { { rng:NextNumber(-w / 4, w / 4), 5, 0, 8 } } or { { rng:NextNumber(-w / 4, w / 4), 5, 3, 5 } }
		wall(model, base * CFrame.new(0, 0, -d / 2), w, storey, t, style.Wall, door)
		wall(model, base * CFrame.new(0, 0, d / 2), w, storey, t, style.Wall, { { 0, 6, 4, 4 } })
		wall(
			model,
			base * CFrame.new(-w / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
			d - t,
			storey,
			t,
			style.Wall,
			{ { rng:NextNumber(-d / 5, d / 5), 5, 4, 4 } }
		)
		wall(
			model,
			base * CFrame.new(w / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
			d - t,
			storey,
			t,
			style.Wall,
			{ { rng:NextNumber(-d / 5, d / 5), 5, 4, 4 } }
		)
		-- Floor slab above this storey (last one is the roof)
		local look = (f == floors - 1) and style.Roof or style.Accent
		block(model, Vector3.new(w + t, 1.2, d + t), base * CFrame.new(0, storey + 0.6, 0), look)
	end
end

local function tower(parent: Instance, origin: CFrame, size: number, floors: number, style)
	local model = Instance.new("Model")
	model.Name = "Tower"
	model.Parent = parent
	local storey = 10
	for f = 0, floors - 1 do
		local base = origin * CFrame.new(0, f * storey, 0)
		for side = 0, 3 do
			local cf = base * CFrame.Angles(0, math.rad(90 * side), 0) * CFrame.new(0, 0, -size / 2)
			wall(model, cf, size, storey, 1.5, style.Wall, { { 0, 4, f == 0 and side == 0 and 0 or 3.5, f == 0 and side == 0 and 7 or 3 } })
		end
		block(model, Vector3.new(size + 1.5, 1, size + 1.5), base * CFrame.new(0, storey + 0.5, 0), style.Accent)
	end
	-- Battlements
	local top = origin * CFrame.new(0, floors * storey + 1, 0)
	for side = 0, 3 do
		for i = -1, 1 do
			local cf = top * CFrame.Angles(0, math.rad(90 * side), 0) * CFrame.new(i * size / 3, 1.5, -size / 2)
			block(model, Vector3.new(2, 3, 1.5), cf, style.Wall)
		end
	end
end

local function coverWall(parent: Instance, origin: CFrame, length: number, style)
	block(parent, Vector3.new(length, 5, 2), origin * CFrame.new(0, 2.5, 0), style.Wall)
end

local function pillar(parent: Instance, origin: CFrame, height: number, style)
	block(parent, Vector3.new(3, height, 3), origin * CFrame.new(0, height / 2, 0), style.Accent)
	block(parent, Vector3.new(4, 1, 4), origin * CFrame.new(0, height + 0.5, 0), style.Wall)
end

local function bridge(parent: Instance, origin: CFrame, length: number, style)
	local model = Instance.new("Model")
	model.Name = "Bridge"
	model.Parent = parent
	local height = 16
	pillar(model, origin * CFrame.new(-length / 2, 0, -5), height, style)
	pillar(model, origin * CFrame.new(-length / 2, 0, 5), height, style)
	pillar(model, origin * CFrame.new(length / 2, 0, -5), height, style)
	pillar(model, origin * CFrame.new(length / 2, 0, 5), height, style)
	-- Deck split into planks so it collapses piece by piece.
	local planks = math.floor(length / 6)
	for i = 0, planks - 1 do
		local x = -length / 2 + (i + 0.5) * (length / planks)
		block(model, Vector3.new(length / planks, 1.2, 14), origin * CFrame.new(x, height + 1.6, 0), style.Accent)
	end
	block(model, Vector3.new(length, 3, 1), origin * CFrame.new(0, height + 3.7, -7), style.Wall)
	block(model, Vector3.new(length, 3, 1), origin * CFrame.new(0, height + 3.7, 7), style.Wall)
end

function MapBuilder.Generate(mapInfo): Model
	local style = MapBuilder.Styles[mapInfo.Style] or MapBuilder.Styles.Concrete
	local rng = Random.new(mapInfo.Seed or 1)
	local map = Instance.new("Model")
	map.Name = mapInfo.Id

	local floor = block(map, Vector3.new(ARENA, 4, ARENA), CFrame.new(0, -2, 0), style.Floor)
	floor.Name = "Baseplate"
	floor:SetAttribute("Indestructible", true)

	-- Invisible boundary walls
	for side = 0, 3 do
		local cf = CFrame.Angles(0, math.rad(90 * side), 0) * CFrame.new(0, 60, -ARENA / 2 - 1)
		local barrier = block(map, Vector3.new(ARENA + 4, 120, 2), cf, style.Floor)
		barrier.Name = "Boundary"
		barrier.Transparency = 1
		barrier:SetAttribute("Indestructible", true)
	end

	local structures = Instance.new("Folder")
	structures.Name = "Structures"
	structures.Parent = map

	-- Symmetric layout: generate one half (x < 0) and mirror it so both teams get the same map.
	local placements = {}
	local half = ARENA / 2 - 20
	local plots = {
		Vector3.new(-90, 0, -80),
		Vector3.new(-90, 0, 0),
		Vector3.new(-90, 0, 80),
		Vector3.new(-45, 0, -100),
		Vector3.new(-45, 0, -40),
		Vector3.new(-45, 0, 40),
		Vector3.new(-45, 0, 100),
	}
	for _, plot in plots do
		local roll = rng:NextNumber()
		local kind
		if roll < 0.4 then
			kind = { "House", rng:NextInteger(18, 26), rng:NextInteger(16, 22), rng:NextInteger(1, 2) }
		elseif roll < 0.6 then
			kind = { "Tower", rng:NextInteger(10, 14), rng:NextInteger(2, 4) }
		elseif roll < 0.85 then
			kind = { "Cover", rng:NextInteger(14, 24) }
		else
			kind = { "Pillars", rng:NextInteger(10, 18) }
		end
		local jitter = Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
		table.insert(placements, { Position = plot + jitter, Kind = kind, Yaw = rng:NextInteger(0, 3) * 90 })
	end

	local function build(p, mirror: boolean)
		local pos = mirror and Vector3.new(-p.Position.X, 0, -p.Position.Z) or p.Position
		local yaw = p.Yaw + (mirror and 180 or 0)
		local origin = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
		local k = p.Kind
		if k[1] == "House" then
			house(structures, origin, k[2], k[3], k[4], style, rng)
		elseif k[1] == "Tower" then
			tower(structures, origin, k[2], k[3], style)
		elseif k[1] == "Cover" then
			coverWall(structures, origin, k[2], style)
			coverWall(structures, origin * CFrame.new(0, 0, 8) * CFrame.Angles(0, math.rad(90), 0), k[2] * 0.6, style)
		else
			for i = 0, 3 do
				pillar(structures, origin * CFrame.new((i % 2) * 10 - 5, 0, math.floor(i / 2) * 10 - 5), k[2], style)
			end
		end
	end
	for _, p in placements do
		build(p, false)
		build(p, true)
	end

	-- Centre piece: a long bridge with cover underneath.
	bridge(structures, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 70, style)
	coverWall(structures, CFrame.new(-12, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 18, style)
	coverWall(structures, CFrame.new(12, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 18, style)

	-- Spawns
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = map
	for team = 1, 2 do
		local folder = Instance.new("Folder")
		folder.Name = "Team" .. team
		folder.Parent = spawns
		local x = (team == 1 and -1 or 1) * (half + 4)
		for i = 1, 5 do
			local spawnPart = Instance.new("Part")
			spawnPart.Name = "Spawn"
			spawnPart.Anchored = true
			spawnPart.CanCollide = false
			spawnPart.CanQuery = false
			spawnPart.Transparency = 1
			spawnPart.Size = Vector3.new(4, 1, 4)
			spawnPart.CFrame = CFrame.lookAt(Vector3.new(x, 3, (i - 3) * 14), Vector3.new(0, 3, (i - 3) * 14))
			spawnPart.Parent = folder
		end
	end

	map.PrimaryPart = floor
	return map
end

-- Returns a fresh map Model pivoted so its base plate centre sits at `origin`.
function MapBuilder.Load(mapId: string, origin: Vector3): Model
	local info = GameModes.MapsById[mapId] or GameModes.Maps[1]
	local templates = ServerStorage:FindFirstChild("Maps")
	local template = templates and templates:FindFirstChild(info.Id)
	local map: Model
	if template and template:IsA("Model") then
		map = template:Clone()
		local floor = map:FindFirstChild("Baseplate", true) :: BasePart
		if floor then
			map.PrimaryPart = floor
			floor:SetAttribute("Indestructible", true)
		end
	else
		map = MapBuilder.Generate(info)
	end
	-- Pivot is the base plate's centre; drop it by half its height so the walkable top is at origin.Y.
	local floor = map.PrimaryPart
	local drop = floor and floor.Size.Y / 2 or 0
	map:PivotTo(CFrame.new(origin - Vector3.new(0, drop, 0)))
	return map
end

return MapBuilder
