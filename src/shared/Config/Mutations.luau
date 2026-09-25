--[[
	Brainrot Mutations: joke names, real stats.

	Produced by the Brainrot Extractor on your base conveyor, bought from the
	hub Brainrot Belt, or stolen from other players' vaults as Mutation
	Capsules. Applied to a pet in the Mutation Lab for Mutagen.

	Each mutation is pure data. CombatService and PetStats read `stats` and
	`special`; BlockyBuilder reads `accessory`/`tint`/`sizeMult`.

	Memes age fast. Rotate this table with each weekly update: retire a stale
	meme into "Classic" capsules and add the new one. Names here are original
	parodies of slang, never names of real creators or copyrighted characters.
]]

local C = Color3.fromRGB

local Mutations = {}

Mutations.List = {
	SigmaStare = {
		displayName = "Sigma Stare",
		rarity = "Rare",
		emoji = "😎",
		joke = "Doesn't blink. Bosses get nervous.",
		stats = {},
		special = { bossDamage = 1.5 },
		accessory = "Shades",
		weight = 22,
	},
	MewingJaw = {
		displayName = "Mewing Jawline",
		rarity = "Uncommon",
		emoji = "🗿",
		joke = "Jaw so sharp it crits.",
		stats = {},
		special = { critChance = 0.15 },
		accessory = "Jaw",
		weight = 30,
	},
	RizzAura = {
		displayName = "Rizz Aura",
		rarity = "Epic",
		emoji = "💖",
		joke = "Zombies stop to stare. Then get bonked.",
		stats = {},
		special = { charmChance = 0.1, charmDuration = 2.5 },
		accessory = "Hearts",
		weight = 12,
	},
	SixSeven = {
		displayName = "Six Seven",
		rarity = "Legendary",
		emoji = "🤲",
		joke = "Every 67th hit does 67x damage. Don't ask.",
		stats = {},
		special = { everyNthHit = 67, nthMult = 67 },
		accessory = "Hands67",
		weight = 4,
	},
	AbsoluteUnit = {
		displayName = "Absolute Unit",
		rarity = "Epic",
		emoji = "🐘",
		joke = "In awe at the size of this lad.",
		stats = { hp = 1.8, speed = 0.8, power = 1.15 },
		special = {},
		sizeMult = 1.8,
		weight = 12,
	},
	TinyMenace = {
		displayName = "Tiny Menace",
		rarity = "Rare",
		emoji = "🐜",
		joke = "Small. Fast. Unhinged.",
		stats = { attackRate = 1.25, speed = 1.15 },
		special = { dodge = 0.12 },
		sizeMult = 0.55,
		weight = 22,
	},
	EspressoMode = {
		displayName = "Espresso Overload",
		rarity = "Rare",
		emoji = "☕",
		joke = "Seventeen shots. Can hear colours.",
		stats = { attackRate = 1.6 },
		special = { jitter = true },
		accessory = "Cup",
		weight = 22,
	},
	NPCMode = {
		displayName = "NPC Mode",
		rarity = "Uncommon",
		emoji = "🤖",
		joke = "Hello traveler. Tanks like a side quest.",
		stats = { hp = 1.4 },
		special = {},
		tint = C(170, 170, 170),
		weight = 30,
	},
	MainCharacter = {
		displayName = "Main Character",
		rarity = "Legendary",
		emoji = "🌟",
		joke = "The plot armor is real.",
		stats = {},
		special = { taunt = true, damageTaken = 0.6 },
		accessory = "Spotlight",
		weight = 4,
	},
	LagSpike = {
		displayName = "Lag Spike",
		rarity = "Epic",
		emoji = "📶",
		joke = "Hits register twice. Server is sorry.",
		stats = {},
		special = { repeatHit = 0.4 },
		accessory = "Glitch",
		weight = 12,
	},
	TouchGrass = {
		displayName = "Touch Grass",
		rarity = "Uncommon",
		emoji = "🌱",
		joke = "Went outside. Came back healed.",
		stats = {},
		special = { regen = 0.03 },
		accessory = "Grass",
		weight = 30,
	},
	AuraFarmer = {
		displayName = "+1000 Aura",
		rarity = "Mythical",
		emoji = "✨",
		joke = "Every kill farms aura. Aura is damage.",
		stats = {},
		special = { auraPerKill = 1, auraPerStack = 0.02, auraMax = 50 },
		accessory = "AuraGold",
		weight = 1.5,
	},
}

Mutations.Order = {
	"MewingJaw",
	"NPCMode",
	"TouchGrass",
	"SigmaStare",
	"TinyMenace",
	"EspressoMode",
	"RizzAura",
	"AbsoluteUnit",
	"LagSpike",
	"SixSeven",
	"MainCharacter",
	"AuraFarmer",
}

-- Mutagen cost to apply a capsule, by rarity.
Mutations.ApplyCost = {
	Common = 25,
	Uncommon = 50,
	Rare = 150,
	Epic = 500,
	Legendary = 2000,
	Mythical = 8000,
	Secret = 25000,
	Exclusive = 5000,
}

-- Coin price on the hub Brainrot Belt, by rarity.
Mutations.BeltPrice = {
	Common = 500,
	Uncommon = 1500,
	Rare = 6000,
	Epic = 25000,
	Legendary = 120000,
	Mythical = 600000,
	Secret = 2500000,
	Exclusive = 1000000,
}

Mutations.VaultSize = 6
Mutations.VipVaultBonus = 2

return Mutations
