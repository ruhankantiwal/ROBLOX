local fails = 0
local function check(cond, msg)
	if not cond then
		fails += 1
		print("FAIL: " .. msg)
	end
end
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

local root = node("")
local Rarity = require(root.Config.Rarity)
local Pets = require(root.Config.Pets)
local Fruits = require(root.Config.Fruits)
local Mutations = require(root.Config.Mutations)
local Eggs = require(root.Config.Eggs)
local Zombies = require(root.Config.Zombies)
local Progression = require(root.Config.Progression)
local Base = require(root.Config.Base)
local Monetization = require(root.Config.Monetization)
local World = require(root.Config.World)
local Rng = require(root.Util.Rng)
local Format = require(root.Util.Format)
local PetStats = require(root.Util.PetStats)
local Protocol = require(root.Util.EntityProtocol)
local BlockyBuilder = require(root.Art.BlockyBuilder)

-- Pets
local speciesCount = 0
for id, s in Pets.Species do
	speciesCount += 1
	check(Rarity.Info[s.rarity] ~= nil, id .. " bad rarity")
	check(Pets.Roles[s.role] ~= nil, id .. " bad role")
	for _, k in { "power", "hp", "speed", "attackRate", "range" } do
		check(finite(s.base[k]) and s.base[k] > 0, id .. " base." .. k)
	end
end
print("species:", speciesCount)

-- Eggs
for id, egg in Eggs.List do
	local sum = 0
	for _, e in egg.odds do
		sum += e.chance
		check(Pets.Species[e.pet] ~= nil, id .. " unknown pet " .. e.pet)
	end
	check(math.abs(sum - 100) < 1e-6, ("%s odds sum %.4f"):format(id, sum))
	for _, luck in { 1, 1.5, 2, 3 } do
		local adj = Rng.LuckAdjustedOdds(egg.odds, luck, Eggs.LuckMaxChance)
		local s2 = 0
		for _, e in adj do s2 += e.chance end
		check(math.abs(s2 - 100) < 1e-6, id .. " luck odds sum")
	end
	if egg.source == "Shop" then
		check(World.EggStands[id] ~= nil, id .. " has no stand")
	end
end
local adj = Rng.LuckAdjustedOdds(Eggs.List.DragonEgg.odds, 3, Eggs.LuckMaxChance)
for _, e in adj do print(("  DragonEgg luck x3: %-14s %7.3f%%"):format(e.pet, e.chance)) end

-- Fruits & abilities
local KINDS = { Burst = { "radius", "damageMult" }, Cone = { "range", "angle", "damageMult" }, Chain = { "jumps", "jumpRange", "damageMult" }, Dash = { "dashRange", "radius", "damageMult" }, Meme = { "radius", "memeEffects" } }
for _, id in Fruits.Order do
	local f = Fruits.List[id]
	check(f ~= nil, "fruit order " .. id)
	check(Fruits.Categories[f.category] ~= nil, id .. " category")
	for _, a in f.abilities do
		local req = KINDS[a.kind]
		check(req ~= nil, id .. " unknown ability kind " .. tostring(a.kind))
		for _, field in req or {} do
			check(a[field] ~= nil, ("%s.%s missing %s"):format(id, a.id, field))
		end
		check(finite(a.cooldown), id .. " cooldown")
	end
	check(f.look and f.look.palette, id .. " look")
end

-- Mutations
local mcount = 0
for id, m in Mutations.List do
	mcount += 1
	check(table.find(Mutations.Order, id) ~= nil, id .. " not in Order")
	check(Mutations.ApplyCost[m.rarity] ~= nil and Mutations.BeltPrice[m.rarity] ~= nil, id .. " price")
end
check(mcount == #Mutations.Order, "mutation order count")

-- PetStats over every combination
local maxScore, minScore = 0, math.huge
local combos = 0
for id in Pets.Species do
	for variant in Pets.Variants do
		for _, fruitId in { false, "Blaze", "Frost", "Volt", "Dragon", "Ohio" } do
			for _, mastery in { 0, 200, 600 } do
				for mutId in Mutations.List do
					local pet = { species = id, level = 10, variant = variant, mutations = { mutId, "SigmaStare" }, fruit = if fruitId then { id = fruitId, mastery = mastery } else nil }
					local ok, stats = pcall(PetStats.Compute, pet)
					combos += 1
					if not ok then
						check(false, "PetStats " .. id .. " " .. tostring(stats))
					else
						for _, k in { "power", "hp", "speed", "attackRate", "range", "critChance", "sizeMult", "powerScore" } do
							check(finite(stats[k]) and stats[k] >= 0, ("%s %s %s"):format(id, variant, k))
						end
						maxScore = math.max(maxScore, stats.powerScore)
						minScore = math.min(minScore, stats.powerScore)
					end
				end
			end
		end
	end
end
print(("petstats combos: %d  powerScore %d .. %d"):format(combos, minScore, maxScore))
for _, id in { "Pup", "Fox", "Bear", "Tiger", "Griffin", "SigmaCapybara" } do
	local s = PetStats.Compute({ species = id, level = 1, variant = "Normal", mutations = {} })
	print(("  %-14s Lv1 power %6.1f hp %7.1f score %6d"):format(id, s.power, s.hp, s.powerScore))
end

-- BlockyBuilder
local minParts, maxParts, builds = math.huge, 0, 0
for id, s in Pets.Species do
	for _, fruitId in { false, "Blaze", "Frost", "Volt", "Dragon", "Ohio" } do
		for mutId in Mutations.List do
			for variant in Pets.Variants do
				local ok, rig = pcall(BlockyBuilder.Build, s.body, { scale = 1.2, variant = variant, fruit = fruitId or nil, mutations = { mutId }, awakened = true })
				builds += 1
				if not ok then
					check(false, ("Build %s %s %s: %s"):format(id, tostring(fruitId), mutId, tostring(rig)))
				else
					minParts = math.min(minParts, #rig.parts)
					maxParts = math.max(maxParts, #rig.parts)
					check(rig.height > 0 and finite(rig.height), id .. " rig height")
					for _, p in rig.parts do
						check(rig.groups[p.group] ~= nil, id .. " part group missing " .. p.group)
					end
				end
			end
		end
	end
end
for id, z in Zombies.Types do
	local ok, rig = pcall(BlockyBuilder.Build, z.body, {})
	builds += 1
	check(ok, "Build zombie " .. id .. ": " .. tostring(rig))
	if ok then maxParts = math.max(maxParts, #rig.parts) end
end
print(("builds: %d  parts per creature %d .. %d"):format(builds, minParts, maxParts))

-- Zombies
for wave = 1, 40 do
	for _, t in Zombies.WaveComposition(wave) do
		check(Zombies.Types[t] ~= nil, "wave type " .. t)
	end
end
for id in Zombies.Types do
	local s = Zombies.Scale(id, 60)
	check(finite(s.hp) and finite(s.damage), id .. " scale")
end
print("wave 1:", #Zombies.WaveComposition(1), "wave 10:", #Zombies.WaveComposition(10), "wave 25:", #Zombies.WaveComposition(25))

-- World
local zonesSeen = {}
for z = World.StartZ, World.Length, 16 do
	local zone = World.ZoneAt(z)
	zonesSeen[zone.id] = true
	local cx = World.CenterX(z)
	local hw = World.HalfWidth(z)
	check(finite(cx) and finite(hw) and hw > 100, "width at " .. z)
	for x = cx - hw - 40, cx + hw + 40, 16 do
		local h = World.GroundHeight(x, z)
		check(finite(h) and h >= 0 and h < 200, ("ground %d,%d = %s"):format(x, z, tostring(h)))
	end
end
local zc = 0
for _ in zonesSeen do zc += 1 end
check(zc == #World.Zones, "all zones reachable")
for i = 1, World.PlotCount do
	local cf = World.PlotCFrame(i)
	local p = cf.Position
	check(World.IsInsideValley(p.X - 55, p.Z, 0) and World.IsInsideValley(p.X + 55, p.Z, 0), "plot inside valley " .. i)
	check(World.GroundHeight(p.X, p.Z) == 0, "plot flat " .. i)
	local core = cf:PointToWorldSpace(Base.CoreOffset)
	local rift = cf:PointToWorldSpace(Base.RiftOffset)
	check(math.abs(core.X) < math.abs(rift.X), "plot " .. i .. " core faces road")
end
for id, h in World.Heists do
	local c = World.Resolve(h.center)
	check(World.IsInsideValley(c.X, c.Z, 50), id .. " heist inside valley")
	check(World.GroundHeight(c.X, c.Z) == World.GroundHeight(c.X + 40, c.Z + 22), id .. " heist yard flat")
	check(Eggs.List[h.egg] and Zombies.Types[h.boss], id .. " refs")
end
local camps = World.Camps()
for _, camp in camps do
	check(World.IsInsideValley(camp.position.X, camp.position.Z, 30), "camp inside " .. camp.id)
end
print("camps:", #camps)

-- Protocol roundtrip
local entries = {}
for i = 1, 60 do
	table.insert(entries, { id = i * 1000 % 65535, x = i * 1.5, y = -600 + i, z = 3000 - i, yaw = i * 0.3, state = i % 10, hp = (i % 7) / 6 })
end
local buf = Protocol.Pack(entries, 1, 48)
check(buffer.len(buf) <= 900, "snapshot packet size " .. buffer.len(buf))
local n = 0
Protocol.Unpack(buf, function(id, x, y, z, yaw, state, hp)
	n += 1
	local e = entries[n]
	check(id == e.id and math.abs(x - e.x) < 1e-3 and math.abs(y - e.y) < 1e-3 and state == e.state, "roundtrip " .. n)
	check(math.abs(hp - e.hp) < 0.01, "hp roundtrip")
	local dy = (yaw - e.yaw % (2 * math.pi) + math.pi) % (2 * math.pi) - math.pi
	check(math.abs(dy) < 0.03, "yaw roundtrip")
end)
check(n == 48, "unpacked count")
print("packet bytes for 48 entities:", buffer.len(buf))

-- Format
check(Format.Short(1234) == "1.23K", "short 1234 -> " .. Format.Short(1234))
check(Format.Short(5600000) == "5.6M", "short 5.6M -> " .. Format.Short(5600000))
check(Format.Short(999) == "999", "short 999")
check(Format.Commas(1234567) == "1,234,567", "commas")

-- Monetization refs
for key, p in Monetization.Products do
	if p.oddsFrom and p.oddsFrom ~= "FruitRobux" then
		check(Eggs.List[p.oddsFrom] ~= nil, key .. " oddsFrom")
	end
	check(table.find(Monetization.ProductOrder, key) ~= nil, key .. " in order")
end
for key in Monetization.GamePasses do
	check(table.find(Monetization.PassOrder, key) ~= nil, key .. " in pass order")
end

-- Progression
check(Progression.PlayerXpToNext(1) > 0 and Progression.PetXpToNext(50) > 0, "xp curves")
for code, reward in Progression.Codes do
	if reward.fruit then check(Fruits.List[reward.fruit] ~= nil, code .. " fruit") end
end
for _, q in Progression.QuestPool do
	check(q.text:format(q.goal) ~= nil, "quest text")
end

print(if fails == 0 then "ALL TESTS PASSED" else ("%d FAILURES"):format(fails))

-- Balance simulation: fresh 2-pet squad vs waves; endgame army vs Nest Mother
local function squadDps(list)
	local dps, hp = 0, 0
	for _, pet in list do
		local s = PetStats.Compute(pet)
		dps += s.power * s.attackRate * (1 + s.critChance)
		hp += s.hp
	end
	return dps, hp
end
local fresh = { { species = "Pup", level = 1, variant = "Normal", mutations = {} }, { species = "Kitty", level = 1, variant = "Normal", mutations = {} } }
local d1, h1 = squadDps(fresh)
for _, wave in { 1, 3, 5 } do
	local totalHp = 0
	for _, t in Zombies.WaveComposition(wave) do totalHp += Zombies.Scale(t, Zombies.WaveLevel(wave)).hp end
	print(("  fresh squad dps %.0f hp %.0f vs wave %d: %d zombies, %.0f total hp -> %.0fs to clear"):format(d1, h1, wave, #Zombies.WaveComposition(wave), totalHp, totalHp / d1))
end
local late = {}
for _ = 1, 5 do table.insert(late, { species = "Griffin", level = 50, variant = "Normal", mutations = { "SigmaStare" }, fruit = { id = "Dragon", mastery = 600 } }) end
local d2 = squadDps(late)
local nest = Zombies.Scale("NestMother", 57)
print(("  endgame squad dps %.0f vs Nest Mother %.0f hp -> %.0fs (x1.5 sigma boss dmg not included)"):format(d2, nest.hp, nest.hp / d2))
local mid = {}
for _ = 1, 4 do table.insert(mid, { species = "Wolf", level = 20, variant = "Normal", mutations = {}, fruit = { id = "Blaze", mastery = 100 } }) end
local d3 = squadDps(mid)
local w = Zombies.Scale("Walker", 20)
print(("  mid squad dps %.0f vs Lv20 walker %.0f hp -> %.2fs each"):format(d3, w.hp, w.hp / d3))
check(Format.Short(5600000) == "5.6M" and Format.Short(1000) == "1K" and Format.Short(1500) == "1.5K", "format trims")
