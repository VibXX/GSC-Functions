-- Teardown-style destruction for Roblox.
--
-- Explode(): every destructible block part touching the blast sphere is recursively split in half
-- along its longest axis until the pieces are either outside the sphere (they stay anchored as
-- smaller blocks - so walls get real holes) or small/inside (they become physics debris and are
-- flung outward). Afterwards a budgeted support check drops any chunk of the map that is no
-- longer connected to the ground, so towers whose base is blown out collapse.
--
-- Indestructible: the base plate (any part with attribute Indestructible = true, or named "Baseplate").

local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local DestructionService = {}

local MIN_PIECE = 1.6 -- pieces at/below this on every axis become debris
local SPLIT_BUDGET = 260 -- max new parts created per explosion
local DEBRIS_LIFETIME = { 7, 12 }
local MAX_DEBRIS_PER_MATCH = 500
local SUPPORT_CHECK_NODES = 300

local debrisByFolder = {} -- [Folder] = { parts in spawn order }

local function isIndestructible(part: BasePart): boolean
	return part:GetAttribute("Indestructible") == true or part.Name == "Baseplate"
end

local function canSplit(part: BasePart): boolean
	return part.ClassName == "Part" and (part :: Part).Shape == Enum.PartType.Block
end

-- Closest point on an oriented box to the sphere centre.
local function boxSphere(cf: CFrame, size: Vector3, center: Vector3, radius: number)
	local rel = cf:PointToObjectSpace(center)
	local half = size / 2
	local closest = Vector3.new(math.clamp(rel.X, -half.X, half.X), math.clamp(rel.Y, -half.Y, half.Y), math.clamp(rel.Z, -half.Z, half.Z))
	local intersects = (rel - closest).Magnitude <= radius
	local farthest = Vector3.new(math.abs(rel.X) + half.X, math.abs(rel.Y) + half.Y, math.abs(rel.Z) + half.Z)
	local inside = farthest.Magnitude <= radius
	return intersects, inside
end

local function registerDebris(folder: Folder, part: BasePart)
	local list = debrisByFolder[folder]
	if not list then
		list = {}
		debrisByFolder[folder] = list
		folder.Destroying:Connect(function()
			debrisByFolder[folder] = nil
		end)
	end
	table.insert(list, part)
	while #list > MAX_DEBRIS_PER_MATCH do
		local oldest = table.remove(list, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
	task.delay(math.random(DEBRIS_LIFETIME[1] * 10, DEBRIS_LIFETIME[2] * 10) / 10, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(1), { Transparency = 1, Size = part.Size * 0.4 }):Play()
			task.wait(1)
			part:Destroy()
		end
	end)
end

local function makeDebris(part: BasePart, center: Vector3, force: number, folder: Folder)
	part.Anchored = false
	part.CollisionGroup = "Debris"
	part.CanTouch = false
	part.Parent = folder
	local away = part.Position - center
	local dir = away.Magnitude > 0.01 and away.Unit or Vector3.yAxis
	local strength = force * (0.6 + math.random() * 0.6)
	part.AssemblyLinearVelocity = (dir + Vector3.new(0, 0.6, 0)).Unit * strength
	part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
	registerDebris(folder, part)
end

-- Recursively splits `part` against the sphere. Appends parts that should become debris to `out`.
local function split(part: BasePart, center: Vector3, radius: number, out: { BasePart }, budget: { n: number })
	local intersects, inside = boxSphere(part.CFrame, part.Size, center, radius)
	if not intersects then
		return
	end
	local size = part.Size
	local largest = math.max(size.X, size.Y, size.Z)
	if not canSplit(part) then
		-- Wedges / meshes / unions can't be cut: break them off whole if they're small enough.
		if inside or largest <= radius * 1.5 then
			table.insert(out, part)
		end
		return
	end
	if inside or largest <= MIN_PIECE or budget.n <= 0 then
		if inside or largest <= MIN_PIECE * 2 then
			table.insert(out, part)
		end
		return
	end
	budget.n -= 1

	local axis: Vector3
	if largest == size.X then
		axis = Vector3.xAxis
	elseif largest == size.Y then
		axis = Vector3.yAxis
	else
		axis = Vector3.zAxis
	end
	local halfSize = size - axis * (largest / 2)
	local offset = axis * (largest / 4)
	local cf = part.CFrame

	local other = part:Clone()
	for _, child in other:GetChildren() do
		if not (child:IsA("Texture") or child:IsA("Decal") or child:IsA("SurfaceAppearance")) then
			child:Destroy()
		end
	end
	other.Size = halfSize
	other.CFrame = cf * CFrame.new(offset)
	other.Parent = part.Parent

	part.Size = halfSize
	part.CFrame = cf * CFrame.new(-offset)

	split(part, center, radius, out, budget)
	split(other, center, radius, out, budget)
end

local function overlapParams(include: { Instance }): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.MaxParts = 600
	return params
end

-- Drop anchored map chunks near the blast that are no longer connected to anything grounded.
local function supportCheck(map: Instance, center: Vector3, radius: number, folder: Folder)
	local params = overlapParams({ map })
	local candidates = Workspace:GetPartBoundsInRadius(center, radius * 2.2, params)
	local settled = {} -- [part] = true when known supported or already dropped
	local nodes = 0

	for _, start in candidates do
		if settled[start] or not start.Anchored or isIndestructible(start) then
			continue
		end
		-- Flood fill through touching anchored parts until we reach something grounded.
		local visited = { [start] = true }
		local queue = { start }
		local cluster = {}
		local grounded = false
		while #queue > 0 and not grounded do
			local part = table.remove(queue)
			table.insert(cluster, part)
			nodes += 1
			if nodes > SUPPORT_CHECK_NODES then
				return -- out of budget: assume the rest is supported
			end
			local touching = Workspace:GetPartBoundsInBox(part.CFrame, part.Size + Vector3.one * 0.25, params)
			for _, other in touching do
				if other == part or visited[other] or not other.Anchored then
					continue
				end
				if isIndestructible(other) or other:GetAttribute("Grounded") or settled[other] == "supported" then
					grounded = true
					break
				end
				visited[other] = true
				table.insert(queue, other)
			end
		end
		for _, part in cluster do
			settled[part] = grounded and "supported" or "dropped"
		end
		if not grounded then
			for _, part in cluster do
				makeDebris(part, center, 4, folder)
			end
		end
	end
end

-- center/radius: blast sphere. force: launch speed of debris. map: the match's map Model.
-- folder: where debris goes (cleaned up with the match).
function DestructionService.Explode(center: Vector3, radius: number, force: number, map: Instance, folder: Folder)
	if radius <= 0 or not map or not map.Parent then
		return
	end
	local hits = Workspace:GetPartBoundsInRadius(center, radius, overlapParams({ map, folder }))
	local out = {}
	local budget = { n = SPLIT_BUDGET }
	for _, part in hits do
		if part.Parent == folder then
			-- Already debris: just give it a shove.
			local away = part.Position - center
			if away.Magnitude > 0.01 then
				part.AssemblyLinearVelocity += away.Unit * force * 0.5
			end
		elseif not isIndestructible(part) and part.Anchored then
			split(part, center, radius, out, budget)
		end
	end
	for _, part in out do
		makeDebris(part, center, force, folder)
	end
	if #out > 0 then
		task.defer(supportCheck, map, center, radius, folder)
	end
end

-- Damage along a line (carving beams): several smaller blasts.
function DestructionService.Carve(from: Vector3, to: Vector3, radius: number, force: number, map: Instance, folder: Folder)
	local length = (to - from).Magnitude
	local step = math.max(radius * 1.4, 2)
	local count = math.clamp(math.floor(length / step), 1, 40)
	for i = 0, count do
		DestructionService.Explode(from:Lerp(to, i / count), radius, force, map, folder)
	end
end

function DestructionService.Init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Debris")
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Characters")
	end)
	-- Debris collides with the world but not with players (keeps movement smooth in 5v5 chaos).
	PhysicsService:CollisionGroupSetCollidable("Debris", "Characters", false)
end

return DestructionService
