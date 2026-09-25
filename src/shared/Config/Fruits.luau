--[[
	Beast Fruits: fed to a pet (not eaten by the player). One fruit per pet;
	feeding a new fruit replaces the old one, Blox Fruits style.

	stats        multipliers applied to the pet's computed stats
	onHit        passive effect rolled on every basic attack
	abilities    auto-cast by the Pet AI once the pet's fruit mastery reaches
	             `mastery`. `kind` selects the generic handler in PetAIService:
	               Burst  AoE around the pet
	               Cone   AoE in front of the pet toward its target
	               Chain  hop between nearby targets
	               Dash   leap to the densest cluster, then Burst
	               Meme   random pick from `memeEffects`
	awaken       mastery milestone that upgrades stats + visuals
	look         how BlockyBuilder mutates the pet's body
	spawnWeight  weight for world spawns and the coin Fruit Dealer
	robuxWeight  weight for the Robux Fruit Roll (paid random item: odds are
	             displayed in the UI and gated by PolicyService)

	Statuses (resolved in CombatService):
	  Burn   {dps = fraction of attacker power per second, duration}
	  Chill  {slow = 0..1, duration}
	  Freeze {duration}              stunned + blue tint
	  Shock  {duration}              short stun
	  Launch {height}                knock-up, lands for bonus damage
]]

local C = Color3.fromRGB

local Fruits = {}

Fruits.Categories = {
	Elemental = { color = C(90, 180, 255), label = "Elemental" },
	Beast = { color = C(255, 120, 40), label = "Beast" },
	Meme = { color = C(255, 80, 200), label = "Meme / Brainrot" },
}

Fruits.List = {
	Blaze = {
		displayName = "Blaze Fruit",
		category = "Elemental",
		element = "Fire",
		rarity = "Rare",
		emoji = "🔥",
		color = C(255, 96, 32),
		tagline = "Your pet becomes a walking campfire.",
		stats = { power = 1.3, hp = 1.0, speed = 1.05, attackRate = 1.0 },
		onHit = { status = "Burn", chance = 1, dps = 0.3, duration = 3 },
		abilities = {
			{
				id = "FlamePounce",
				name = "Flame Pounce",
				mastery = 0,
				kind = "Dash",
				cooldown = 9,
				dashRange = 26,
				radius = 10,
				damageMult = 3,
				status = { status = "Burn", dps = 0.5, duration = 4 },
				minTargets = 1,
				fx = "FireBurst",
			},
			{
				id = "InfernoRing",
				name = "Inferno Ring",
				mastery = 150,
				kind = "Burst",
				cooldown = 20,
				radius = 20,
				damageMult = 6,
				status = { status = "Burn", dps = 0.6, duration = 5 },
				minTargets = 3,
				fx = "FireRing",
			},
		},
		awaken = { mastery = 500, stats = { power = 1.25 } },
		look = {
			palette = { main = C(255, 110, 40), accent = C(255, 210, 60), detail = C(120, 20, 10) },
			tint = 0.55,
			aura = "Fire",
			parts = { "FlameMane", "EmberTail" },
			sizeMult = 1.05,
		},
		spawnWeight = 34,
		robuxWeight = 30,
	},

	Frost = {
		displayName = "Frost Fruit",
		category = "Elemental",
		element = "Ice",
		rarity = "Rare",
		emoji = "❄️",
		color = C(120, 220, 255),
		tagline = "Every bite leaves zombies frozen solid.",
		stats = { power = 1.15, hp = 1.2, speed = 1.0, attackRate = 1.0 },
		onHit = { status = "Chill", chance = 1, slow = 0.35, duration = 2 },
		abilities = {
			{
				id = "GlacierHowl",
				name = "Glacier Howl",
				mastery = 0,
				kind = "Cone",
				cooldown = 10,
				range = 20,
				angle = 55,
				damageMult = 2.5,
				status = { status = "Freeze", duration = 2.5 },
				minTargets = 2,
				fx = "IceCone",
			},
			{
				id = "Blizzard",
				name = "Blizzard",
				mastery = 150,
				kind = "Burst",
				cooldown = 22,
				radius = 22,
				damageMult = 4,
				status = { status = "Freeze", duration = 3 },
				minTargets = 3,
				fx = "IceRing",
			},
		},
		awaken = { mastery = 500, stats = { hp = 1.3 } },
		look = {
			palette = { main = C(170, 230, 255), accent = C(240, 252, 255), detail = C(40, 120, 200) },
			tint = 0.6,
			aura = "Ice",
			parts = { "IceSpikes" },
			sizeMult = 1.05,
		},
		spawnWeight = 34,
		robuxWeight = 30,
	},

	Volt = {
		displayName = "Volt Fruit",
		category = "Elemental",
		element = "Lightning",
		rarity = "Epic",
		emoji = "⚡",
		color = C(255, 232, 40),
		tagline = "Chain lightning through the whole horde.",
		stats = { power = 1.25, hp = 1.0, speed = 1.2, attackRate = 1.25 },
		onHit = { status = "Chain", chance = 0.25, jumps = 2, jumpRange = 14, damageMult = 0.5 },
		abilities = {
			{
				id = "ChainZap",
				name = "Chain Zap",
				mastery = 0,
				kind = "Chain",
				cooldown = 8,
				jumps = 6,
				jumpRange = 16,
				damageMult = 3,
				status = { status = "Shock", duration = 0.6 },
				minTargets = 2,
				fx = "Lightning",
			},
			{
				id = "ThunderStomp",
				name = "Thunder Stomp",
				mastery = 150,
				kind = "Burst",
				cooldown = 18,
				radius = 18,
				damageMult = 5,
				status = { status = "Shock", duration = 1.5 },
				minTargets = 3,
				fx = "VoltRing",
			},
		},
		awaken = { mastery = 500, stats = { attackRate = 1.25 } },
		look = {
			palette = { main = C(255, 236, 80), accent = C(255, 255, 220), detail = C(60, 60, 80) },
			tint = 0.5,
			aura = "Volt",
			parts = { "BoltSpikes" },
			sizeMult = 1.0,
		},
		spawnWeight = 20,
		robuxWeight = 24,
	},

	Dragon = {
		displayName = "Dragon Fruit",
		category = "Beast",
		element = "Dragon",
		rarity = "Legendary",
		emoji = "🐉",
		color = C(220, 30, 50),
		tagline = "Any pet becomes a winged Dragon-beast.",
		stats = { power = 1.45, hp = 1.5, speed = 1.1, attackRate = 1.0 },
		onHit = { status = "Burn", chance = 1, dps = 0.25, duration = 2, splash = 6, splashMult = 0.3 },
		abilities = {
			{
				id = "DragonBreath",
				name = "Dragon Breath",
				mastery = 0,
				kind = "Cone",
				cooldown = 9,
				range = 24,
				angle = 50,
				damageMult = 4,
				status = { status = "Burn", dps = 0.6, duration = 4 },
				minTargets = 1,
				fx = "DragonBreath",
			},
			{
				id = "SkyDive",
				name = "Sky Dive",
				mastery = 150,
				kind = "Dash",
				cooldown = 16,
				dashRange = 42,
				radius = 16,
				damageMult = 7,
				status = { status = "Launch", height = 14 },
				minTargets = 3,
				fx = "SkyDive",
			},
		},
		awaken = { mastery = 500, stats = { power = 1.2, hp = 1.2 } },
		look = {
			palette = { main = C(200, 30, 46), accent = C(255, 196, 60), detail = C(30, 20, 24) },
			tint = 0.7,
			aura = "Dragon",
			parts = { "DragonWings", "DragonHorns", "SpikeTail" },
			sizeMult = 1.25,
		},
		spawnWeight = 10,
		robuxWeight = 13,
	},

	Ohio = {
		displayName = "Ohio Fruit",
		category = "Meme",
		element = "Brainrot",
		rarity = "Mythical",
		emoji = "🌀",
		color = C(255, 70, 210),
		tagline = "Only in Ohio. Nobody knows what it does next.",
		stats = { power = 1.55, hp = 1.2, speed = 1.15, attackRate = 1.1 },
		-- "SIX SEVEN!" crit: 6.7% chance to deal 6.7x damage.
		onHit = { status = "SixSeven", chance = 0.067, mult = 6.7 },
		abilities = {
			{
				id = "OnlyInOhio",
				name = "Only In Ohio",
				mastery = 0,
				kind = "Meme",
				cooldown = 14,
				radius = 22,
				minTargets = 2,
				memeEffects = {
					{ id = "GravityFlip", weight = 30, damageMult = 5, status = { status = "Launch", height = 22 } },
					{ id = "BruhFreeze", weight = 30, damageMult = 1.5, status = { status = "Freeze", duration = 3 } },
					{ id = "ConfettiNuke", weight = 25, damageMult = 7 },
					{ id = "GigaMode", weight = 15, buff = { size = 2.5, power = 2, duration = 8 } },
				},
				fx = "Glitch",
			},
			{
				id = "AuraFarm",
				name = "Aura Farm",
				mastery = 150,
				kind = "Burst",
				cooldown = 24,
				radius = 26,
				damageMult = 8,
				minTargets = 4,
				grantsAura = 25,
				fx = "Aura",
			},
		},
		awaken = { mastery = 500, stats = { power = 1.3, speed = 1.2 } },
		look = {
			palette = { main = C(255, 90, 220), accent = C(80, 255, 240), detail = C(255, 240, 60) },
			tint = 0.45,
			aura = "Glitch",
			parts = { "GlitchHalo" },
			sizeMult = 1.1,
			rainbow = true,
		},
		spawnWeight = 2,
		robuxWeight = 3,
	},
}

Fruits.Order = { "Blaze", "Frost", "Volt", "Dragon", "Ohio" }

-- World spawn rules (FruitService)
Fruits.SpawnInterval = 360 -- seconds between spawn attempts per server
Fruits.MaxWorldFruits = 4
Fruits.Despawn = 900
Fruits.BaseStorage = 5
Fruits.DealerCost = 15000
Fruits.DealerCooldown = 3600

return Fruits
