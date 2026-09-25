--[[
	Pet species. Every pet is built from blocks at runtime by Art/BlockyBuilder,
	so adding a species is data only: no meshes, no textures, no uploads.

	role:
		Tank     draws aggro (taunt pulse), takes reduced damage
		Striker  hunts the weakest target, bonus crit
		Ranged   attacks from distance with projectiles, kites
		Support  heals the squad, stays near the owner

	base stats are level-1 values before the rarity multiplier:
		power       damage per hit
		hp          max health
		speed       studs per second
		attackRate  hits per second
		range       attack reach in studs
]]

local C = Color3.fromRGB

local Pets = {}

Pets.Roles = {
	Tank = { damageTaken = 0.8, tauntRadius = 14, tauntEvery = 6 },
	Striker = { critBonus = 0.1 },
	Ranged = { keepDistance = 0.75 },
	Support = { healPct = 0.06, healEvery = 4, healRadius = 26 },
}

Pets.Species = {
	-- COMMON ------------------------------------------------------------
	Pup = {
		displayName = "Farm Pup",
		rarity = "Common",
		role = "Striker",
		emoji = "🐶",
		base = { power = 5, hp = 50, speed = 24, attackRate = 1.3, range = 5 },
		body = {
			template = "Quad",
			colors = { main = C(176, 122, 72), accent = C(236, 206, 164), detail = C(96, 62, 36) },
			ears = "Floppy",
			snout = "Dog",
			tail = "Short",
		},
	},
	Kitty = {
		displayName = "Barn Kitty",
		rarity = "Common",
		role = "Striker",
		emoji = "🐱",
		base = { power = 5.5, hp = 42, speed = 26, attackRate = 1.4, range = 5 },
		body = {
			template = "Quad",
			size = Vector3.new(2, 1.6, 2.8),
			colors = { main = C(244, 152, 62), accent = C(255, 244, 230), detail = C(204, 104, 40) },
			ears = "Pointy",
			snout = "Cat",
			tail = "Long",
		},
	},
	Chick = {
		displayName = "Chick",
		rarity = "Common",
		role = "Ranged",
		emoji = "🐤",
		base = { power = 4, hp = 35, speed = 22, attackRate = 1.1, range = 18 },
		body = {
			template = "Bird",
			colors = { main = C(255, 222, 72), accent = C(255, 150, 40), detail = C(255, 196, 40) },
			tail = "Fan",
		},
	},
	Piglet = {
		displayName = "Piglet",
		rarity = "Common",
		role = "Tank",
		emoji = "🐷",
		base = { power = 3.5, hp = 90, speed = 20, attackRate = 1.0, range = 5 },
		body = {
			template = "Quad",
			size = Vector3.new(2.4, 1.8, 2.8),
			colors = { main = C(255, 168, 180), accent = C(255, 126, 146), detail = C(232, 120, 140) },
			ears = "Pointy",
			snout = "Pig",
			tail = "Curly",
		},
	},
	Bunny = {
		displayName = "Bunny",
		rarity = "Common",
		role = "Support",
		emoji = "🐰",
		base = { power = 3, hp = 45, speed = 26, attackRate = 1.0, range = 5 },
		body = {
			template = "Quad",
			size = Vector3.new(1.8, 1.6, 2.2),
			legLen = 0.8,
			colors = { main = C(244, 244, 244), accent = C(255, 182, 196), detail = C(220, 220, 220) },
			ears = "Long",
			snout = "Cat",
			tail = "Fluffy",
		},
	},

	-- UNCOMMON ----------------------------------------------------------
	Cow = {
		displayName = "Moo Cow",
		rarity = "Uncommon",
		role = "Tank",
		emoji = "🐮",
		base = { power = 4, hp = 110, speed = 19, attackRate = 0.9, range = 5 },
		body = {
			template = "Quad",
			size = Vector3.new(2.6, 2.2, 3.6),
			colors = { main = C(248, 248, 248), accent = C(255, 186, 186), detail = C(30, 30, 30) },
			ears = "Horns",
			snout = "Muzzle",
			tail = "Long",
			extras = { "Spots" },
		},
	},
	Goat = {
		displayName = "Grumpy Goat",
		rarity = "Uncommon",
		role = "Striker",
		emoji = "🐐",
		base = { power = 6.5, hp = 55, speed = 24, attackRate = 1.2, range = 5 },
		body = {
			template = "Quad",
			colors = { main = C(214, 210, 200), accent = C(240, 236, 228), detail = C(120, 104, 90) },
			ears = "Horns",
			snout = "Dog",
			tail = "Short",
			extras = { "Beard" },
		},
	},
	Duck = {
		displayName = "Pond Duck",
		rarity = "Uncommon",
		role = "Ranged",
		emoji = "🦆",
		base = { power = 5, hp = 45, speed = 22, attackRate = 1.1, range = 20 },
		body = {
			template = "Bird",
			colors = { main = C(250, 250, 250), accent = C(255, 150, 30), detail = C(60, 150, 90) },
			tail = "Fan",
		},
	},
	Sheep = {
		displayName = "Fluffy Sheep",
		rarity = "Uncommon",
		role = "Support",
		emoji = "🐑",
		base = { power = 3.5, hp = 70, speed = 21, attackRate = 1.0, range = 5 },
		body = {
			template = "Quad",
			size = Vector3.new(2.6, 2.2, 3),
			colors = { main = C(250, 250, 244), accent = C(40, 40, 44), detail = C(230, 230, 222) },
			ears = "Floppy",
			tail = "Fluffy",
			extras = { "Wool" },
			headColor = C(40, 40, 44),
		},
	},

	-- RARE --------------------------------------------------------------
	Fox = {
		displayName = "Valley Fox",
		rarity = "Rare",
		role = "Striker",
		emoji = "🦊",
		base = { power = 7, hp = 55, speed = 28, attackRate = 1.4, range = 5 },
		body = {
			template = "Quad",
			colors = { main = C(236, 110, 36), accent = C(255, 246, 236), detail = C(40, 30, 30) },
			ears = "Pointy",
			snout = "Dog",
			tail = "Fluffy",
		},
	},
	Wolf = {
		displayName = "Grey Wolf",
		rarity = "Rare",
		role = "Striker",
		emoji = "🐺",
		base = { power = 8, hp = 65, speed = 27, attackRate = 1.3, range = 5 },
		body = {
			template = "Quad",
			size = Vector3.new(2.3, 2, 3.4),
			colors = { main = C(128, 134, 146), accent = C(214, 218, 226), detail = C(70, 74, 84) },
			ears = "Pointy",
			snout = "Dog",
			tail = "Fluffy",
		},
	},
	Owl = {
		displayName = "Night Owl",
		rarity = "Rare",
		role = "Ranged",
		emoji = "🦉",
		base = { power = 6.5, hp = 50, speed = 24, attackRate = 1.2, range = 22 },
		body = {
			template = "Bird",
			colors = { main = C(140, 96, 60), accent = C(255, 200, 60), detail = C(222, 196, 160) },
			ears = "Pointy",
			tail = "Fan",
			extras = { "Wings" },
		},
	},
	Boar = {
		displayName = "Wild Boar",
		rarity = "Rare",
		role = "Tank",
		emoji = "🐗",
		base = { power = 5, hp = 130, speed = 21, attackRate = 1.0, range = 5 },
		body = {
			template = "Quad",
			size = Vector3.new(2.6, 2.2, 3.2),
			colors = { main = C(96, 66, 46), accent = C(160, 120, 96), detail = C(250, 246, 230) },
			ears = "Pointy",
			snout = "Pig",
			tail = "Short",
			extras = { "Tusks", "Mane" },
		},
	},

	-- EPIC --------------------------------------------------------------
	Bear = {
		displayName = "Grizzly",
		rarity = "Epic",
		role = "Tank",
		emoji = "🐻",
		base = { power = 7, hp = 170, speed = 20, attackRate = 0.9, range = 6 },
		body = {
			template = "Quad",
			size = Vector3.new(3, 2.6, 3.6),
			headSize = Vector3.new(2.2, 2, 1.9),
			colors = { main = C(124, 80, 46), accent = C(196, 150, 104), detail = C(84, 52, 30) },
			ears = "Round",
			snout = "Muzzle",
			tail = "Short",
		},
	},
	Stag = {
		displayName = "Spirit Stag",
		rarity = "Epic",
		role = "Support",
		emoji = "🦌",
		base = { power = 6, hp = 95, speed = 28, attackRate = 1.1, range = 6 },
		body = {
			template = "Quad",
			size = Vector3.new(2.2, 2, 3.4),
			legLen = 1.8,
			colors = { main = C(170, 110, 64), accent = C(250, 236, 214), detail = C(236, 220, 180) },
			ears = "Antlers",
			snout = "Dog",
			tail = "Short",
		},
	},
	Panther = {
		displayName = "Shadow Panther",
		rarity = "Epic",
		role = "Striker",
		emoji = "🐈‍⬛",
		base = { power = 10, hp = 75, speed = 30, attackRate = 1.5, range = 5 },
		body = {
			template = "Quad",
			size = Vector3.new(2.2, 1.8, 3.6),
			colors = { main = C(34, 34, 42), accent = C(58, 58, 70), detail = C(255, 220, 40) },
			ears = "Pointy",
			snout = "Cat",
			tail = "Long",
			eyeColor = C(255, 220, 40),
		},
	},

	-- LEGENDARY ---------------------------------------------------------
	Tiger = {
		displayName = "Blaze Tiger",
		rarity = "Legendary",
		role = "Striker",
		emoji = "🐯",
		base = { power = 12, hp = 95, speed = 30, attackRate = 1.5, range = 6 },
		body = {
			template = "Quad",
			size = Vector3.new(2.6, 2.2, 3.8),
			colors = { main = C(250, 140, 30), accent = C(255, 246, 236), detail = C(30, 24, 24) },
			ears = "Round",
			snout = "Cat",
			tail = "Long",
			extras = { "Stripes" },
		},
	},
	Rhino = {
		displayName = "Iron Rhino",
		rarity = "Legendary",
		role = "Tank",
		emoji = "🦏",
		base = { power = 9, hp = 240, speed = 21, attackRate = 0.9, range = 6 },
		body = {
			template = "Quad",
			size = Vector3.new(3.2, 2.6, 4.2),
			colors = { main = C(150, 156, 164), accent = C(186, 190, 196), detail = C(236, 232, 220) },
			ears = "Pointy",
			snout = "Muzzle",
			tail = "Short",
			extras = { "Horn" },
		},
	},
	Eagle = {
		displayName = "Storm Eagle",
		rarity = "Legendary",
		role = "Ranged",
		emoji = "🦅",
		base = { power = 11, hp = 80, speed = 30, attackRate = 1.3, range = 26 },
		body = {
			template = "Bird",
			size = Vector3.new(2, 2, 2.6),
			colors = { main = C(110, 72, 40), accent = C(255, 196, 30), detail = C(250, 250, 250) },
			tail = "Fan",
			extras = { "Wings" },
			headColor = C(250, 250, 250),
		},
	},

	-- MYTHICAL ----------------------------------------------------------
	Griffin = {
		displayName = "Royal Griffin",
		rarity = "Mythical",
		role = "Striker",
		emoji = "🦁",
		base = { power = 15, hp = 140, speed = 32, attackRate = 1.4, range = 7 },
		body = {
			template = "Quad",
			size = Vector3.new(2.8, 2.4, 3.8),
			colors = { main = C(232, 180, 76), accent = C(255, 150, 30), detail = C(250, 250, 250) },
			ears = "Pointy",
			snout = "Beak",
			tail = "Long",
			extras = { "Wings" },
			headColor = C(250, 250, 250),
		},
	},
	Phoenix = {
		displayName = "Phoenix Chick",
		rarity = "Mythical",
		role = "Ranged",
		emoji = "🔥",
		base = { power = 16, hp = 110, speed = 32, attackRate = 1.4, range = 28 },
		body = {
			template = "Bird",
			colors = { main = C(255, 76, 36), accent = C(255, 210, 40), detail = C(255, 140, 20) },
			tail = "Fan",
			extras = { "Wings", "Crest" },
			neonDetail = true,
		},
	},
	Unicorn = {
		displayName = "Starlight Unicorn",
		rarity = "Mythical",
		role = "Support",
		emoji = "🦄",
		base = { power = 11, hp = 160, speed = 34, attackRate = 1.2, range = 6 },
		body = {
			template = "Quad",
			size = Vector3.new(2.4, 2.2, 3.6),
			legLen = 1.8,
			colors = { main = C(252, 248, 255), accent = C(255, 170, 230), detail = C(150, 220, 255) },
			ears = "Pointy",
			snout = "Muzzle",
			tail = "Fluffy",
			extras = { "Horn", "Mane" },
		},
	},

	-- SECRET ------------------------------------------------------------
	SigmaCapybara = {
		displayName = "Sigma Capybara",
		rarity = "Secret",
		role = "Tank",
		emoji = "🦫",
		base = { power = 22, hp = 320, speed = 30, attackRate = 1.2, range = 7 },
		body = {
			template = "Quad",
			size = Vector3.new(2.8, 2.2, 3.6),
			headSize = Vector3.new(2, 1.8, 2.2),
			legLen = 0.9,
			colors = { main = C(156, 108, 66), accent = C(186, 138, 92), detail = C(20, 20, 20) },
			ears = "Round",
			snout = "Muzzle",
			tail = "None",
			extras = { "Shades" },
		},
	},

	-- EXCLUSIVE (VIP / events, never in eggs) ---------------------------
	GoldenAlphaWolf = {
		displayName = "Golden Alpha Wolf",
		rarity = "Exclusive",
		role = "Striker",
		emoji = "👑",
		exclusive = "VIP",
		base = { power = 16, hp = 150, speed = 34, attackRate = 1.4, range = 6 },
		body = {
			template = "Quad",
			size = Vector3.new(2.6, 2.2, 3.8),
			colors = { main = C(255, 204, 64), accent = C(255, 240, 180), detail = C(200, 140, 20) },
			ears = "Pointy",
			snout = "Dog",
			tail = "Fluffy",
			extras = { "Crown", "Mane" },
		},
	},
	PumpkinHound = {
		displayName = "Pumpkin Hound",
		rarity = "Exclusive",
		role = "Striker",
		emoji = "🎃",
		exclusive = "Halloween",
		base = { power = 15, hp = 140, speed = 32, attackRate = 1.4, range = 6 },
		body = {
			template = "Quad",
			size = Vector3.new(2.4, 2, 3.4),
			colors = { main = C(40, 36, 44), accent = C(255, 120, 20), detail = C(255, 150, 20) },
			ears = "Pointy",
			snout = "Dog",
			tail = "Long",
			headColor = C(255, 120, 20),
			eyeColor = C(255, 240, 60),
			neonDetail = true,
		},
	},
}

-- Hatch-time variants (Pet Simulator style). Golden/Rainbow are crafted.
Pets.Variants = {
	Normal = { mult = 1, label = "" },
	Shiny = { mult = 1.5, label = "✨ Shiny", hatchChance = 1 / 250 },
	Golden = { mult = 1.6, label = "🟡 Golden", craftFrom = "Normal", craftCount = 5 },
	Rainbow = { mult = 2.6, label = "🌈 Rainbow", craftFrom = "Golden", craftCount = 5 },
}

-- Global balance knobs applied on top of every species' base stats.
Pets.GlobalTuning = { power = 1.5, hp = 1.6 }

Pets.BaseEquipSlots = 3
Pets.MaxEquipSlots = 8
Pets.BaseInventory = 60
Pets.FaintSeconds = 8
Pets.MaxMutationSlots = 2
Pets.SecondMutationSlotLevel = 15

return Pets
