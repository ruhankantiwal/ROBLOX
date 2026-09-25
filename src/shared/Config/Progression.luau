--[[
	Player levels, pet levels, rebirths, daily rewards, quests and codes.
]]

local Progression = {}

-- Player XP needed to go from `level` to `level + 1`.
function Progression.PlayerXpToNext(level: number): number
	return math.floor(60 * level ^ 1.55)
end

-- Pet XP needed to go from `level` to `level + 1`.
function Progression.PetXpToNext(level: number): number
	return math.floor(25 * level ^ 1.45)
end

Progression.PetStatPerLevel = 0.045 -- +4.5% power/hp per pet level

-- Rebirth ("Evolve Farm"): resets coins + conveyor, keeps pets/fruits.
Progression.Rebirth = {
	baseCost = 1000000,
	costGrowth = 3,
	coinBonusPerRebirth = 0.25,
	equipSlotAt = { [1] = true, [3] = true, [6] = true },
}

function Progression.RebirthCost(rebirths: number): number
	return Progression.Rebirth.baseCost * Progression.Rebirth.costGrowth ^ rebirths
end

-- Seven-day login streak, loops. Day 7 is the big one.
Progression.DailyRewards = {
	{ coins = 500 },
	{ mutagen = 50 },
	{ coins = 2500 },
	{ heistTickets = 1 },
	{ coins = 10000, mutagen = 150 },
	{ capsule = "Rare" },
	{ fruit = "Random", heistTickets = 1 },
}

-- Daily quests: three are picked each day from this pool.
Progression.QuestPool = {
	{ id = "Kill", stat = "zombiesKilled", goal = 150, text = "Defeat %d zombies", reward = { coins = 2000, mutagen = 40 } },
	{ id = "Waves", stat = "wavesCleared", goal = 5, text = "Clear %d base waves", reward = { coins = 3000 } },
	{ id = "Hatch", stat = "eggsHatched", goal = 10, text = "Hatch %d eggs", reward = { mutagen = 60 } },
	{ id = "Boss", stat = "bossesKilled", goal = 2, text = "Defeat %d bosses", reward = { heistTickets = 1 } },
	{ id = "Fruit", stat = "fruitsCollected", goal = 1, text = "Collect %d Beast Fruit", reward = { coins = 5000 } },
	{ id = "Heist", stat = "heistsWon", goal = 1, text = "Win %d Egg Heist", reward = { mutagen = 150 } },
	{ id = "Steal", stat = "capsulesStolen", goal = 1, text = "Steal %d capsule", reward = { coins = 4000 } },
}

-- Free Dragon's Nest heist tickets regenerate over time (capped).
Progression.FreeTicketEvery = 4 * 3600
Progression.FreeTicketCap = 2

-- Launch codes. Rotate through creators' videos for tracking.
Progression.Codes = {
	RELEASE = { coins = 2500, heistTickets = 1 },
	GROWYOURPETS = { fruit = "Blaze" },
	ZOMBIEPARTY = { mutagen = 200 },
	SIXSEVEN = { capsule = "Rare" },
}

-- Offline conveyor earnings (fraction of live rate, capped duration).
Progression.OfflineRate = 0.5
Progression.OfflineCapSeconds = 2 * 3600
Progression.OfflineCapSecondsVip = 8 * 3600

return Progression
