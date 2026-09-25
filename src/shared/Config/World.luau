--[[
	The Long Valley: one continuous valley running along +Z, built from
	studded blocks by WorldBuilder at server start.

	Everything here is deterministic (fixed seed), so the server and every
	client agree on ground height, plot positions and zone bounds without
	sending any geometry over the network.
]]

local C = Color3.fromRGB

local World = {}

World.Seed = 1001
World.Tile = 32
World.Length = 3200
World.StartZ = -64

World.Zones = {
	{
		id = "Hub",
		name = "Barnyard Plaza",
		zStart = -64,
		zEnd = 280,
		levelReq = 1,
		hills = 0,
		palette = { ground = C(92, 180, 76), groundAlt = C(100, 190, 82), cliff = C(120, 110, 100), cliffTop = C(80, 160, 70), accent = C(215, 190, 140) },
		trees = 0,
	},
	{
		id = "FarmRow",
		name = "Farm Row",
		zStart = 280,
		zEnd = 820,
		levelReq = 1,
		hills = 0,
		palette = { ground = C(96, 176, 70), groundAlt = C(106, 186, 78), cliff = C(128, 112, 96), cliffTop = C(84, 162, 72), accent = C(210, 184, 130) },
		trees = 10,
	},
	{
		id = "Meadow",
		name = "Meadow Fields",
		zStart = 820,
		zEnd = 1300,
		levelReq = 1,
		hills = 4,
		palette = { ground = C(124, 200, 80), groundAlt = C(136, 210, 90), cliff = C(140, 124, 104), cliffTop = C(110, 190, 80), accent = C(255, 230, 90) },
		trees = 40,
		treeStyle = "Round",
		camps = { count = 7, types = { "Walker", "Walker", "Runner" }, level = { 1, 8 } },
	},
	{
		id = "Woods",
		name = "Whispering Woods",
		zStart = 1300,
		zEnd = 1850,
		levelReq = 10,
		hills = 6,
		palette = { ground = C(52, 110, 60), groundAlt = C(60, 122, 66), cliff = C(90, 84, 80), cliffTop = C(40, 96, 52), accent = C(150, 110, 70) },
		trees = 120,
		treeStyle = "Pine",
		camps = { count = 8, types = { "Walker", "Runner", "Spitter" }, level = { 10, 22 } },
	},
	{
		id = "Canyon",
		name = "Crystal Canyon",
		zStart = 1850,
		zEnd = 2400,
		levelReq = 25,
		hills = 10,
		palette = { ground = C(214, 150, 104), groundAlt = C(224, 162, 114), cliff = C(186, 110, 76), cliffTop = C(230, 180, 130), accent = C(110, 230, 255) },
		trees = 14,
		treeStyle = "Crystal",
		camps = { count = 8, types = { "Runner", "Spitter", "Brute" }, level = { 25, 40 } },
	},
	{
		id = "Volcano",
		name = "Volcano Ridge",
		zStart = 2400,
		zEnd = 2900,
		levelReq = 40,
		hills = 12,
		palette = { ground = C(70, 64, 66), groundAlt = C(84, 76, 78), cliff = C(46, 42, 44), cliffTop = C(100, 60, 50), accent = C(255, 110, 20) },
		trees = 18,
		treeStyle = "Dead",
		camps = { count = 8, types = { "Brute", "Spitter", "Runner" }, level = { 40, 60 } },
	},
	{
		id = "Nest",
		name = "Dragon's Nest",
		zStart = 2900,
		zEnd = 3200,
		levelReq = 50,
		hills = 6,
		palette = { ground = C(70, 40, 90), groundAlt = C(80, 48, 102), cliff = C(40, 26, 50), cliffTop = C(120, 60, 140), accent = C(255, 190, 40) },
		trees = 0,
	},
}

-- Valley half-width control points (z, halfWidth); linearly interpolated.
local WIDTH_POINTS = {
	{ -64, 190 },
	{ 270, 190 },
	{ 300, 262 },
	{ 820, 262 },
	{ 900, 210 },
	{ 1300, 220 },
	{ 1360, 175 },
	{ 1850, 175 },
	{ 1910, 135 },
	{ 2400, 140 },
	{ 2460, 185 },
	{ 2900, 190 },
	{ 2960, 170 },
	{ 3264, 170 },
}

function World.ZoneAt(z: number)
	for i, zone in World.Zones do
		if z < zone.zEnd or i == #World.Zones then
			return zone, i
		end
	end
	return World.Zones[1], 1
end

function World.ZoneById(id: string)
	for i, zone in World.Zones do
		if zone.id == id then
			return zone, i
		end
	end
	return nil, 0
end

function World.HalfWidth(z: number): number
	for i = 1, #WIDTH_POINTS - 1 do
		local a, b = WIDTH_POINTS[i], WIDTH_POINTS[i + 1]
		if z <= b[1] then
			local t = math.clamp((z - a[1]) / (b[1] - a[1]), 0, 1)
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return WIDTH_POINTS[#WIDTH_POINTS][2]
end

-- Gentle meander once you leave the farms, so the valley reads as "long"
-- and you never see the end from the start.
function World.CenterX(z: number): number
	local ramp = math.clamp((z - 880) / 300, 0, 1)
	return math.sin((z - 880) / 260) * 80 * ramp
end

local function isFlat(x: number, z: number): boolean
	if z < 830 then
		return true
	end
	-- Gate plazas, heist yards and the dungeon entrance stay flat.
	for _, zone in World.Zones do
		if math.abs(z - zone.zStart) < 24 and zone.levelReq > 1 then
			return true
		end
	end
	for _, heist in World.Heists do
		if math.abs(z - heist.center.Z) < 90 and math.abs(x - World.CenterX(heist.center.Z) - heist.center.X) < 90 then
			return true
		end
	end
	local e = World.Dungeon.entrance
	if math.abs(z - e.Z) < 40 and math.abs(x - World.CenterX(e.Z) - e.X) < 40 then
		return true
	end
	return false
end

-- Height of the walkable top surface at (x, z). Quantised to 1 stud so the
-- block terrain has small steps characters can walk up.
function World.GroundHeight(x: number, z: number): number
	local tile = World.Tile
	local ix = math.floor(x / tile)
	local iz = math.floor(z / tile)
	local tx = (ix + 0.5) * tile
	local tz = (iz + 0.5) * tile
	local d = math.abs(tx - World.CenterX(tz))
	local hw = World.HalfWidth(tz)
	if d > hw then
		return World.CliffHeight(ix, iz)
	end
	if isFlat(tx, tz) then
		return 0
	end
	local zone = World.ZoneAt(tz)
	local n = math.noise(ix * 0.09, iz * 0.09, World.Seed * 0.001)
	local h = (n + 0.5) * zone.hills
	local edge = d - (hw - 48)
	if edge > 0 then
		h += edge * 0.12
	end
	return math.max(0, math.floor(h + 0.5))
end

function World.CliffHeight(ix: number, iz: number): number
	local n = math.noise(ix * 0.21 + 7.3, iz * 0.17 - 2.1, World.Seed * 0.002)
	return 46 + math.floor((n + 0.5) * 40)
end

function World.IsInsideValley(x: number, z: number, margin: number?): boolean
	local m = margin or 0
	if z < World.StartZ + m or z > World.Length - m then
		return false
	end
	return math.abs(x - World.CenterX(z)) < World.HalfWidth(z) - m
end

-- Clamp a position to the walkable valley floor (used by entity movement).
function World.ClampToValley(x: number, z: number, margin: number): (number, number)
	z = math.clamp(z, World.StartZ + margin, World.Length - margin)
	local cx = World.CenterX(z)
	local hw = World.HalfWidth(z) - margin
	x = math.clamp(x, cx - hw, cx + hw)
	return x, z
end

-- Valley features are authored as (offset from the meandering centre line,
-- y ignored, z). Resolve turns one into a world position on the ground.
function World.Resolve(v: Vector3): Vector3
	local x = World.CenterX(v.Z) + v.X
	return Vector3.new(x, World.GroundHeight(x, v.Z), v.Z)
end

-- Player bases: 4 per side of the Farm Row road.
World.PlotCount = 8
function World.PlotCFrame(index: number): CFrame
	local side = if index % 2 == 1 then -1 else 1
	local row = math.floor((index - 1) / 2)
	local center = Vector3.new(150 * side, 0, 360 + row * 125)
	-- Plot-local +Z faces the road (front), -Z faces the cliff (back).
	local towardRoad = Vector3.new(-side, 0, 0)
	return CFrame.lookAt(center, center - towardRoad)
end

World.HubSpawn = Vector3.new(0, 0, 150)

World.EggStands = {
	FarmEgg = Vector3.new(-66, 0, 210),
	MeadowEgg = Vector3.new(-22, 0, 222),
	WoodsEgg = Vector3.new(22, 0, 222),
	CanyonEgg = Vector3.new(66, 0, 210),
}

World.FruitDealer = Vector3.new(-120, 0, 130)
World.RebirthStatue = Vector3.new(120, 0, 130)
World.BrainrotBelt = { from = Vector3.new(-110, 0, 40), to = Vector3.new(110, 0, 40) }

World.Heists = {
	ChickenCoop = {
		name = "Chicken Coop Heist",
		center = Vector3.new(130, 0, 1190), -- offset from CenterX, see Resolve
		egg = "GoldenCoopEgg",
		guards = { "CoopGuard", "CoopGuard", "CoopGuard", "CoopGuard" },
		boss = "GiantRooster",
		level = 8,
		ticket = false,
		cooldown = 600,
		pursuitLeash = 260,
	},
	DragonNest = {
		name = "Dragon's Nest Heist",
		center = Vector3.new(0, 0, 3080),
		egg = "DragonEgg",
		guards = { "NestWyvern", "NestWyvern", "NestWyvern", "NestWyvern", "NestWyvern" },
		boss = "NestMother",
		level = 55,
		ticket = true,
		cooldown = 0,
		pursuitLeash = 520,
	},
}

World.Dungeon = {
	name = "The Hollow Stump",
	entrance = Vector3.new(0, 0, 1640), -- x is offset from CenterX at build time
	arena = Vector3.new(0, -600, 1640),
	waves = 4,
	levelOffset = 3,
	cooldown = 300,
}

-- Deterministic list of zombie camps along the valley.
function World.Camps()
	local camps = {}
	local rng = Random.new(World.Seed + 17)
	for _, zone in World.Zones do
		if zone.camps then
			for i = 1, zone.camps.count do
				local z = zone.zStart + 60 + (zone.zEnd - zone.zStart - 120) * ((i - 0.5) / zone.camps.count)
				local hw = World.HalfWidth(z) - 60
				local x = World.CenterX(z) + rng:NextNumber(-hw, hw)
				local lvl = math.floor(zone.camps.level[1] + (zone.camps.level[2] - zone.camps.level[1]) * ((i - 1) / math.max(1, zone.camps.count - 1)))
				table.insert(camps, {
					id = zone.id .. i,
					zone = zone.id,
					position = Vector3.new(x, World.GroundHeight(x, z), z),
					types = zone.camps.types,
					level = lvl,
					size = 6 + (i % 4), -- hordes, not handfuls: kills are the clip
				})
			end
		end
	end
	return camps
end

return World
