--[[
	Weighted random helpers shared by eggs, fruits, capsules and memes.
]]

local Rng = {}

export type WeightedEntry = { weight: number, [string]: any }

-- Picks one entry from a list of {weight = n, ...}.
function Rng.Pick<T>(entries: { T }, weightOf: (T) -> number, rng: Random?): T
	local total = 0
	for _, e in entries do
		total += weightOf(e)
	end
	local roll = (if rng then rng:NextNumber() else math.random()) * total
	for _, e in entries do
		roll -= weightOf(e)
		if roll <= 0 then
			return e
		end
	end
	return entries[#entries]
end

-- Returns egg odds with luck applied: every "rare pull" (base chance under
-- `maxChance` percent) gets its weight multiplied by `luck`, then the table
-- is renormalised to sum to 100. This exact table is what the UI shows.
function Rng.LuckAdjustedOdds(odds: { { pet: string, chance: number } }, luck: number, maxChance: number)
	local adjusted = {}
	local total = 0
	for _, entry in odds do
		local w = entry.chance
		if luck ~= 1 and entry.chance < maxChance then
			w *= luck
		end
		total += w
		table.insert(adjusted, { pet = entry.pet, chance = w })
	end
	for _, entry in adjusted do
		entry.chance = entry.chance / total * 100
	end
	return adjusted
end

function Rng.Chance(p: number): boolean
	return math.random() < p
end

return Rng
