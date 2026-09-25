--[[
	Single source of truth for a pet's final stats. Shared so the server
	(combat) and the client (inventory cards, "equip best") always agree.

	pet data shape (stored in the player profile):
	{
		uid: string,
		species: string,
		level: number, xp: number,
		variant: "Normal" | "Shiny" | "Golden" | "Rainbow",
		fruit: { id: string, mastery: number }?,
		mutations: { string },
		locked: boolean?,
	}
]]

local Config = script.Parent.Parent.Config
local Pets = require(Config.Pets)
local Rarity = require(Config.Rarity)
local Fruits = require(Config.Fruits)
local Mutations = require(Config.Mutations)
local Progression = require(Config.Progression)

local PetStats = {}

export type Stats = {
	power: number,
	hp: number,
	speed: number,
	attackRate: number,
	range: number,
	critChance: number,
	dodge: number,
	damageTaken: number,
	sizeMult: number,
	role: string,
	rarity: string,
	special: { [string]: any },
	abilities: { any },
	powerScore: number,
}

local function applyMods(stats, mods)
	if not mods then
		return
	end
	for key, mult in mods do
		if type(stats[key]) == "number" then
			stats[key] *= mult
		end
	end
end

function PetStats.Compute(pet): Stats
	local species = Pets.Species[pet.species]
	assert(species, "Unknown species " .. tostring(pet.species))
	local rarity = Rarity.Info[species.rarity]
	local variant = Pets.Variants[pet.variant or "Normal"] or Pets.Variants.Normal
	local roleInfo = Pets.Roles[species.role] or {}
	local levelMult = 1 + ((pet.level or 1) - 1) * Progression.PetStatPerLevel
	local grow = rarity.statMult * variant.mult * levelMult
	local tuning = Pets.GlobalTuning

	local stats = {
		power = species.base.power * grow * tuning.power,
		hp = species.base.hp * grow * tuning.hp,
		speed = species.base.speed,
		attackRate = species.base.attackRate,
		range = species.base.range,
		critChance = 0.05 + (roleInfo.critBonus or 0),
		dodge = 0,
		damageTaken = roleInfo.damageTaken or 1,
		sizeMult = rarity.sizeMult,
		role = species.role,
		rarity = species.rarity,
		special = {},
		abilities = {},
		powerScore = 0,
	}

	-- Beast Fruit
	local fruit = pet.fruit and Fruits.List[pet.fruit.id]
	if fruit then
		applyMods(stats, fruit.stats)
		local mastery = pet.fruit.mastery or 0
		if fruit.awaken and mastery >= fruit.awaken.mastery then
			applyMods(stats, fruit.awaken.stats)
			stats.special.awakened = true
		end
		stats.sizeMult *= fruit.look.sizeMult or 1
		for _, ability in fruit.abilities do
			if mastery >= ability.mastery then
				table.insert(stats.abilities, ability)
			end
		end
	end

	-- Brainrot mutations
	for _, mutationId in pet.mutations or {} do
		local m = Mutations.List[mutationId]
		if m then
			applyMods(stats, m.stats)
			stats.sizeMult *= m.sizeMult or 1
			for key, value in m.special do
				if key == "critChance" then
					stats.critChance += value
				elseif key == "dodge" then
					stats.dodge += value
				elseif key == "damageTaken" then
					stats.damageTaken *= value
				else
					stats.special[key] = value
				end
			end
		end
	end

	stats.critChance = math.min(stats.critChance, 0.75)
	stats.dodge = math.min(stats.dodge, 0.4)
	stats.powerScore = PetStats.PowerScore(stats)
	return stats
end

-- One number for sorting and "Equip Best": damage per second weighted up,
-- survivability weighted down.
function PetStats.PowerScore(stats): number
	local dps = stats.power * stats.attackRate * (1 + stats.critChance)
	return math.floor(dps * 10 + stats.hp * 0.5)
end

function PetStats.MutationSlots(pet): number
	if (pet.level or 1) >= Pets.SecondMutationSlotLevel then
		return Pets.MaxMutationSlots
	end
	return 1
end

return PetStats
