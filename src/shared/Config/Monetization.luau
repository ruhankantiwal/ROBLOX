--[[
	Game passes, developer products and the VIP subscription.

	IDs of 0 are unconfigured. In Studio, buying an unconfigured item grants
	it for free so every flow can be tested before anything is published.
	In a live server, unconfigured items are hidden.

	Compliance (Roblox paid random items policy):
	  * `randomItem = true` marks anything bought with Robux that produces a
	    random outcome or changes odds (rolls, luck boosts, heist tickets that
	    lead to egg rolls). The UI shows exact odds before purchase, and
	    MonetizationService hides these for players whose PolicyService says
	    ArePaidRandomItemsRestricted.
	  * Coins are never sold for Robux, so coin-bought eggs stay non-paid.
	    Gems (premium) buy only deterministic items: cosmetics, skips, slots.
]]

local Monetization = {}

Monetization.GamePasses = {
	FruitNotifier = {
		id = 0,
		price = 449,
		name = "Fruit Notifier",
		icon = "🔔",
		desc = "Pings you the moment a Beast Fruit spawns and draws a beam to it.",
	},
	DoubleConveyor = {
		id = 0,
		price = 249,
		name = "2x Conveyor Speed",
		icon = "⏩",
		desc = "Your belts run twice as fast, forever. Doubles base income.",
	},
	ExtraEquip = {
		id = 0,
		price = 199,
		name = "+1 Pet Equip",
		icon = "➕",
		desc = "Bring one more pet into your army.",
	},
	FruitStorage = {
		id = 0,
		price = 149,
		name = "+10 Fruit Storage",
		icon = "🧺",
		desc = "Store ten more Beast Fruits.",
	},
	TripleHatch = {
		id = 0,
		price = 349,
		name = "Triple Hatch",
		icon = "🥚",
		desc = "Hatch three eggs at once.",
	},
	LuckyHatch = {
		id = 0,
		price = 399,
		name = "Lucky Hatch",
		icon = "🍀",
		desc = "Every pet under 5% odds is 1.5x more likely. Adjusted odds shown on every egg.",
		randomItem = true,
		luck = 1.5,
	},
	MountBoost = {
		id = 0,
		price = 179,
		name = "Turbo Mount",
		icon = "🏇",
		desc = "Your Alpha mount runs 30% faster. Great for heist escapes.",
	},
	VIP = {
		id = 0,
		price = 499,
		name = "VIP (Lifetime)",
		icon = "👑",
		desc = "All VIP perks, one-time purchase.",
	},
}

Monetization.PassOrder = {
	"VIP",
	"FruitNotifier",
	"DoubleConveyor",
	"ExtraEquip",
	"LuckyHatch",
	"TripleHatch",
	"MountBoost",
	"FruitStorage",
}

Monetization.Products = {
	HeistTicket1 = {
		id = 0,
		price = 49,
		name = "1 Heist Ticket",
		icon = "🎟️",
		grant = { heistTickets = 1 },
		randomItem = true,
		oddsFrom = "DragonEgg",
	},
	HeistTicket5 = {
		id = 0,
		price = 199,
		name = "5 Heist Tickets",
		icon = "🎟️",
		grant = { heistTickets = 5 },
		randomItem = true,
		oddsFrom = "DragonEgg",
	},
	FruitRoll = {
		id = 0,
		price = 99,
		name = "Beast Fruit Roll",
		icon = "🎲",
		grant = { fruitRoll = 1 },
		randomItem = true,
		oddsFrom = "FruitRobux",
	},
	ServerLuck = {
		id = 0,
		price = 149,
		name = "Server Luck x2 (15 min)",
		icon = "🌟",
		grant = { serverLuck = 900 },
		randomItem = true,
		announce = true,
	},
	ZombieNuke = {
		id = 0,
		price = 99,
		name = "Zombie Nuke",
		icon = "☢️",
		grant = { nuke = 1 },
		announce = true,
	},
	Gems100 = { id = 0, price = 80, name = "100 Gems", icon = "💎", grant = { gems = 100 } },
	Gems550 = { id = 0, price = 400, name = "550 Gems", icon = "💎", grant = { gems = 550 } },
	Gems1400 = { id = 0, price = 950, name = "1,400 Gems", icon = "💎", grant = { gems = 1400 } },
}

Monetization.ProductOrder = {
	"ZombieNuke",
	"HeistTicket1",
	"HeistTicket5",
	"FruitRoll",
	"ServerLuck",
	"Gems100",
	"Gems550",
	"Gems1400",
}

-- Experience Subscription (create it in Creator Hub, paste the EXP- id).
Monetization.Subscription = {
	id = "",
	priceUsd = 4.99,
	name = "Beast Valley VIP",
	perks = {
		"+1 pet equip slot",
		"1.5x coins from every source",
		"2 free Dragon's Nest tickets per day",
		"8h offline conveyor earnings (vs 2h)",
		"+2 capsule vault slots, longer base lock",
		"Monthly exclusive pet (Golden Alpha Wolf)",
		"VIP chat tag + gold name",
	},
}

-- Deterministic Gem shop (never random).
Monetization.GemShop = {
	SkipIncubation = { gems = 40, name = "Finish incubation now" },
	RepairCore = { gems = 15, name = "Repair Barn Heart instantly" },
	ExtraVaultSlot = { gems = 250, name = "+1 capsule vault slot", max = 4 },
}

Monetization.VipCoinMult = 1.5
Monetization.VipDailyTickets = 2

return Monetization
