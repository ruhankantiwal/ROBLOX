--[[
	Rarity tiers shared by pets, fruits, mutations and capsules.

	rank        ordering used for sorting, luck boosts and announcements
	statMult    multiplier applied on top of species base stats
	maxLevel    pet level cap for this tier
	sizeMult    visual scale, rarer pets read as "bigger" on screen
	announce    "none" | "server" | "global" (cross-server via MessagingService)
]]

local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Secret", "Exclusive" }

Rarity.Info = {
	Common = {
		rank = 1,
		color = Color3.fromRGB(176, 184, 192),
		statMult = 1.0,
		maxLevel = 25,
		sizeMult = 1.0,
		sellValue = 10,
		announce = "none",
	},
	Uncommon = {
		rank = 2,
		color = Color3.fromRGB(88, 214, 104),
		statMult = 1.35,
		maxLevel = 30,
		sizeMult = 1.0,
		sellValue = 40,
		announce = "none",
	},
	Rare = {
		rank = 3,
		color = Color3.fromRGB(64, 156, 255),
		statMult = 1.9,
		maxLevel = 40,
		sizeMult = 1.05,
		sellValue = 200,
		announce = "none",
	},
	Epic = {
		rank = 4,
		color = Color3.fromRGB(176, 92, 255),
		statMult = 2.8,
		maxLevel = 50,
		sizeMult = 1.1,
		sellValue = 1200,
		announce = "none",
	},
	Legendary = {
		rank = 5,
		color = Color3.fromRGB(255, 184, 36),
		statMult = 4.2,
		maxLevel = 60,
		sizeMult = 1.2,
		sellValue = 8000,
		announce = "server",
	},
	Mythical = {
		rank = 6,
		color = Color3.fromRGB(255, 72, 120),
		statMult = 6.5,
		maxLevel = 75,
		sizeMult = 1.3,
		sellValue = 50000,
		announce = "server",
	},
	Secret = {
		rank = 7,
		color = Color3.fromRGB(20, 20, 24),
		rainbow = true,
		statMult = 11,
		maxLevel = 100,
		sizeMult = 1.4,
		sellValue = 500000,
		announce = "global",
	},
	Exclusive = {
		rank = 8,
		color = Color3.fromRGB(255, 226, 120),
		statMult = 7.5,
		maxLevel = 80,
		sizeMult = 1.3,
		sellValue = 0,
		announce = "server",
	},
}

function Rarity.Rank(name: string): number
	local info = Rarity.Info[name]
	return if info then info.rank else 0
end

function Rarity.Color(name: string): Color3
	local info = Rarity.Info[name]
	return if info then info.color else Color3.new(1, 1, 1)
end

return Rarity
