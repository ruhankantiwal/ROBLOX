--[[
	Eggs. `odds` are percentages and must sum to 100; the UI shows them
	verbatim (with luck applied) before every hatch, which is what Roblox's
	paid random items policy asks for.

	Shop eggs cost Coins. Coins are never sold for Robux (see
	Monetization.luau), so a coin egg is not a paid random item. Heist eggs
	are stolen in Egg Heists and incubate at your base.
]]

local Eggs = {}

Eggs.List = {
	FarmEgg = {
		displayName = "Farm Egg",
		source = "Shop",
		currency = "Coins",
		price = 250,
		zone = "Hub",
		color = Color3.fromRGB(250, 240, 214),
		spotColor = Color3.fromRGB(176, 122, 72),
		odds = {
			{ pet = "Pup", chance = 28 },
			{ pet = "Kitty", chance = 28 },
			{ pet = "Chick", chance = 20 },
			{ pet = "Piglet", chance = 14 },
			{ pet = "Bunny", chance = 8 },
			{ pet = "Cow", chance = 1.9 },
			{ pet = "Fox", chance = 0.1 },
		},
	},
	MeadowEgg = {
		displayName = "Meadow Egg",
		source = "Shop",
		currency = "Coins",
		price = 3000,
		zone = "Hub",
		color = Color3.fromRGB(150, 230, 110),
		spotColor = Color3.fromRGB(255, 240, 120),
		odds = {
			{ pet = "Cow", chance = 30 },
			{ pet = "Goat", chance = 28 },
			{ pet = "Duck", chance = 22 },
			{ pet = "Sheep", chance = 15 },
			{ pet = "Fox", chance = 4 },
			{ pet = "Owl", chance = 0.9 },
			{ pet = "Bear", chance = 0.1 },
		},
	},
	WoodsEgg = {
		displayName = "Woods Egg",
		source = "Shop",
		currency = "Coins",
		price = 40000,
		zone = "Hub",
		levelReq = 10,
		color = Color3.fromRGB(60, 120, 70),
		spotColor = Color3.fromRGB(140, 96, 60),
		odds = {
			{ pet = "Fox", chance = 32 },
			{ pet = "Wolf", chance = 30 },
			{ pet = "Owl", chance = 22 },
			{ pet = "Boar", chance = 12 },
			{ pet = "Bear", chance = 3.5 },
			{ pet = "Stag", chance = 0.45 },
			{ pet = "Tiger", chance = 0.05 },
		},
	},
	CanyonEgg = {
		displayName = "Crystal Egg",
		source = "Shop",
		currency = "Coins",
		price = 600000,
		zone = "Hub",
		levelReq = 25,
		color = Color3.fromRGB(120, 230, 255),
		spotColor = Color3.fromRGB(200, 120, 255),
		odds = {
			{ pet = "Bear", chance = 35 },
			{ pet = "Stag", chance = 30 },
			{ pet = "Panther", chance = 25 },
			{ pet = "Rhino", chance = 8 },
			{ pet = "Tiger", chance = 1.9 },
			{ pet = "Eagle", chance = 0.1 },
		},
	},

	-- Heist eggs: stolen, carried home, incubated.
	GoldenCoopEgg = {
		displayName = "Golden Coop Egg",
		source = "Heist",
		heist = "ChickenCoop",
		incubateSeconds = 300,
		color = Color3.fromRGB(255, 206, 40),
		spotColor = Color3.fromRGB(255, 255, 200),
		odds = {
			{ pet = "Panther", chance = 40 },
			{ pet = "Tiger", chance = 30 },
			{ pet = "Eagle", chance = 20 },
			{ pet = "Rhino", chance = 9 },
			{ pet = "Griffin", chance = 1 },
		},
	},
	DragonEgg = {
		displayName = "Dragon Egg",
		source = "Heist",
		heist = "DragonNest",
		incubateSeconds = 1200,
		color = Color3.fromRGB(150, 20, 40),
		spotColor = Color3.fromRGB(255, 190, 40),
		neon = true,
		odds = {
			{ pet = "Griffin", chance = 50 },
			{ pet = "Phoenix", chance = 32 },
			{ pet = "Unicorn", chance = 17.5 },
			{ pet = "SigmaCapybara", chance = 0.5 },
		},
	},
}

Eggs.ShopOrder = { "FarmEgg", "MeadowEgg", "WoodsEgg", "CanyonEgg" }

-- Luck multiplies the weight of every entry whose base chance is below
-- this many percent (the egg's "rare pulls"), then odds are renormalised.
-- The UI shows the adjusted odds before every hatch.
Eggs.LuckMaxChance = 5
Eggs.HatchRange = 14 -- studs from the egg stand
Eggs.HatchCooldown = 1.2

return Eggs
