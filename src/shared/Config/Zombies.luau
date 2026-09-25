--[[
	Zombies, bosses and heist guardians. All are server-simulated entities
	rendered client-side from blocks (no Humanoids, no physics), which is
	what keeps 60+ zombies cheap on phones.

	Stats are level-1 values; Zombies.Scale() applies level growth.
]]

local C = Color3.fromRGB

local Zombies = {}

Zombies.Types = {
	Walker = {
		displayName = "Walker",
		hp = 28,
		damage = 3.5,
		speed = 9,
		attackRate = 0.8,
		range = 4,
		aggro = 30,
		coins = 6,
		xp = 4,
		mutagen = 0.2,
		body = {
			template = "Zombie",
			colors = { main = C(110, 170, 90), accent = C(70, 90, 150), detail = C(90, 60, 40) },
		},
	},
	Runner = {
		displayName = "Runner",
		hp = 20,
		damage = 3,
		speed = 17,
		attackRate = 1.2,
		range = 4,
		aggro = 40,
		coins = 7,
		xp = 5,
		mutagen = 0.2,
		body = {
			template = "Zombie",
			scale = 0.85,
			colors = { main = C(150, 190, 110), accent = C(200, 60, 60), detail = C(50, 50, 60) },
		},
	},
	Brute = {
		displayName = "Brute",
		hp = 140,
		damage = 10,
		speed = 7,
		attackRate = 0.6,
		range = 6,
		aggro = 30,
		coins = 25,
		xp = 16,
		mutagen = 1,
		body = {
			template = "Zombie",
			scale = 1.6,
			colors = { main = C(90, 130, 80), accent = C(110, 80, 60), detail = C(60, 40, 30) },
		},
	},
	Spitter = {
		displayName = "Spitter",
		hp = 26,
		damage = 4,
		speed = 8,
		attackRate = 0.7,
		range = 20,
		ranged = true,
		aggro = 36,
		coins = 10,
		xp = 7,
		mutagen = 0.4,
		body = {
			template = "Zombie",
			colors = { main = C(160, 110, 200), accent = C(60, 120, 60), detail = C(200, 255, 80) },
		},
	},

	-- Bosses
	FarmerZed = {
		displayName = "Farmer Zed",
		boss = true,
		hp = 600,
		damage = 14,
		speed = 8,
		attackRate = 0.7,
		range = 8,
		aggro = 60,
		coins = 600,
		xp = 250,
		mutagen = 40,
		fruitDrop = 0.08,
		body = {
			template = "Zombie",
			scale = 2.4,
			colors = { main = C(120, 170, 90), accent = C(70, 110, 190), detail = C(230, 200, 90) },
			extras = { "StrawHat" },
		},
	},
	BrainrotTitan = {
		displayName = "Brainrot Titan",
		boss = true,
		hp = 2600,
		damage = 30,
		speed = 7,
		attackRate = 0.6,
		range = 10,
		aggro = 70,
		coins = 3000,
		xp = 1200,
		mutagen = 200,
		fruitDrop = 0.2,
		body = {
			template = "Zombie",
			scale = 3.4,
			colors = { main = C(255, 90, 210), accent = C(40, 40, 60), detail = C(80, 255, 240) },
			extras = { "Crown" },
			neonDetail = true,
		},
	},

	-- Heist guardians (only visible to the player running the heist)
	CoopGuard = {
		displayName = "Coop Guard",
		guard = true,
		hp = 120,
		damage = 9,
		speed = 19,
		attackRate = 1,
		range = 5,
		aggro = 34,
		coins = 20,
		xp = 20,
		mutagen = 1,
		body = {
			template = "Zombie",
			scale = 1.2,
			colors = { main = C(250, 250, 250), accent = C(200, 40, 40), detail = C(255, 180, 40) },
			extras = { "StrawHat" },
		},
	},
	GiantRooster = {
		displayName = "Giant Rooster",
		boss = true,
		guard = true,
		hp = 900,
		damage = 18,
		speed = 14,
		attackRate = 0.8,
		range = 9,
		aggro = 60,
		coins = 900,
		xp = 400,
		mutagen = 60,
		body = {
			template = "Bird",
			scale = 3.2,
			colors = { main = C(250, 250, 250), accent = C(255, 170, 30), detail = C(230, 30, 30) },
			extras = { "Crest" },
		},
	},
	NestWyvern = {
		displayName = "Nest Wyvern",
		guard = true,
		hp = 150,
		damage = 40,
		speed = 24,
		attackRate = 1,
		range = 7,
		aggro = 45,
		coins = 150,
		xp = 120,
		mutagen = 8,
		body = {
			template = "Quad",
			scale = 1.4,
			colors = { main = C(80, 30, 110), accent = C(255, 120, 40), detail = C(30, 20, 30) },
			ears = "Pointy",
			snout = "Dog",
			tail = "Long",
			extras = { "Wings" },
		},
	},
	NestMother = {
		displayName = "Nest Mother",
		boss = true,
		guard = true,
		hp = 4000,
		damage = 90,
		speed = 16,
		attackRate = 0.7,
		range = 14,
		aggro = 80,
		coins = 20000,
		xp = 6000,
		mutagen = 800,
		fruitDrop = 0.35,
		body = {
			template = "Quad",
			scale = 4,
			colors = { main = C(150, 20, 40), accent = C(255, 190, 40), detail = C(30, 20, 24) },
			ears = "Horns",
			snout = "Dog",
			tail = "Long",
			extras = { "Wings", "Crown" },
			neonDetail = true,
		},
	},
}

-- Level growth. Tuned against pet growth (rarity x level x fruit):
-- zombie HP grows ~64x from Lv1 to Lv55, roughly what a Mythical army
-- gains over a Common one, so every zone stays a fight but never a wall.
-- A fresh 2-pet squad clears waves 1-4; the wave-5 boss wants a wall,
-- a third pet or a fruit.
function Zombies.Scale(typeId: string, level: number)
	local t = Zombies.Types[typeId]
	local l = math.max(1, level) - 1
	return {
		hp = t.hp * (1.08 ^ l),
		damage = t.damage * (1.06 ^ l),
		coins = math.floor(t.coins * (1.12 ^ l)),
		xp = math.floor(t.xp * (1.1 ^ l)),
		mutagen = t.mutagen * (1.08 ^ l),
	}
end

-- Base-defense wave composition.
function Zombies.WaveComposition(wave: number)
	local list = {}
	local count = math.min(4 + wave * 2, 60)
	for i = 1, count do
		local roll = (i * 7919 + wave * 104729) % 100
		if wave >= 4 and roll < 12 then
			table.insert(list, "Brute")
		elseif wave >= 3 and roll < 30 then
			table.insert(list, "Spitter")
		elseif wave >= 2 and roll < 55 then
			table.insert(list, "Runner")
		else
			table.insert(list, "Walker")
		end
	end
	if wave % 10 == 0 then
		table.insert(list, "BrainrotTitan")
	elseif wave % 5 == 0 then
		table.insert(list, "FarmerZed")
	end
	return list
end

-- Zombie level for a base wave (waves ramp faster than the wave number).
function Zombies.WaveLevel(wave: number): number
	return math.max(1, math.floor(wave * 1.5))
end

Zombies.MaxAlivePerPlot = 30
Zombies.WaveSpawnInterval = 1
Zombies.WaveBreak = 25 -- seconds between waves (skippable)

return Zombies
