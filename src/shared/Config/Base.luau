--[[
	Player base ("Farm Base"): the conveyor tycoon and the Build & Kill
	defenses. Positions are in plot-local space: +Z toward the road (front),
	-Z toward the cliff (back, where the zombie rift is).
]]

local Base = {}

Base.PlotSize = 110
Base.CoreOffset = Vector3.new(0, 0, 34)
Base.RiftOffset = Vector3.new(0, 0, -48)
Base.SpawnOffset = Vector3.new(0, 0, 48)
Base.IncubatorOffset = Vector3.new(26, 0, 40)
Base.LockButtonOffset = Vector3.new(-12, 0, 48)
Base.WaveButtonOffset = Vector3.new(12, 0, 48)

Base.Core = {
	maxHp = 600,
	regenBetweenWaves = true,
}

-- Conveyor: droppers drop Goo onto the belt, the collector sells it.
Base.Conveyor = {
	start = Vector3.new(-44, 0, -30),
	finish = Vector3.new(-44, 0, 40),
	dropInterval = 2,
	droppers = {
		{ offset = Vector3.new(-50, 0, -22), price = 0, value = 5, mutagen = 0.05 },
		{ offset = Vector3.new(-50, 0, -8), price = 750, value = 8, mutagen = 0.1 },
		{ offset = Vector3.new(-50, 0, 6), price = 6000, value = 25, mutagen = 0.25 },
		{ offset = Vector3.new(-50, 0, 20), price = 50000, value = 90, mutagen = 0.6 },
		{ offset = Vector3.new(-38, 0, -22), price = 400000, value = 350, mutagen = 1.5 },
		{ offset = Vector3.new(-38, 0, -8), price = 3000000, value = 1400, mutagen = 4 },
	},
	dropperUpgradeCost = function(tier: number, level: number): number
		return math.floor((150 * tier ^ 2.2) * 1.6 ^ level)
	end,
	dropperLevelMult = 0.35, -- +35% value per dropper level
	belts = {
		{ price = 0, speed = 1 },
		{ price = 2500, speed = 1.35 },
		{ price = 40000, speed = 1.8 },
		{ price = 900000, speed = 2.5 },
	},
	-- Brainrot Extractor: rolls a Mutation Capsule every `interval`.
	extractorOffset = Vector3.new(-30, 0, 34),
	extractors = {
		{ price = 5000, interval = 180, rarityBias = 0 },
		{ price = 75000, interval = 120, rarityBias = 1 },
		{ price = 1500000, interval = 75, rarityBias = 2 },
	},
}

-- Build & Kill: pads in a ring in front of the core.
Base.BuildPads = {
	Vector3.new(-24, 0, 10),
	Vector3.new(-12, 0, 2),
	Vector3.new(0, 0, -2),
	Vector3.new(12, 0, 2),
	Vector3.new(24, 0, 10),
	Vector3.new(0, 0, 18),
}

-- Tiers a pad upgrades through. Walls block, spikes hurt, turrets shoot.
Base.Defenses = {
	{ id = "HayWall", name = "Hay Wall", price = 400, hp = 250, radius = 5, block = true },
	{ id = "SpikeWall", name = "Spike Wall", price = 3000, hp = 600, radius = 5, block = true, thorns = 8 },
	{ id = "FruitTurret", name = "Fruit Turret", price = 25000, hp = 500, radius = 4, range = 34, damage = 30, fireRate = 1.2 },
	{ id = "BlazeCannon", name = "Blaze Cannon", price = 250000, hp = 900, radius = 4, range = 40, damage = 150, fireRate = 1, splash = 8, burn = true },
}

Base.Lock = {
	duration = 60,
	durationVip = 90,
	cooldown = 90,
}

return Base
