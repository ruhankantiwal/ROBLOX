--[[
	ZombieService: zombie simulation, spatial queries and encounters.

	Encounters own groups of zombies:
	  Wave     Build & Kill base defense. Zombies pour out of the plot's
	           Graveyard Rift and march on the Barn Heart; walls block,
	           turrets shoot, the Animal Army intercepts.
	  Camp     Zombie camps along the Long Valley (grind spots). Only
	           simulated while a player is near; a zone boss rises every
	           10 minutes and is announced to the whole server.
	  Dungeon  The Hollow Stump: an instanced arena under the Woods.
	  Heist    Guardians spawned by EggHeistService.

	Spatial hash (24-stud cells) is rebuilt every tick; Query() is what the
	Pet AI, abilities and turrets use to find zombies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Zombies = require(Shared.Config.Zombies)
local World = require(Shared.Config.World)
local Protocol = require(Shared.Util.EntityProtocol)

local State = Protocol.State
local EV = Protocol.Event

local CELL = 24
local CAMP_RANGE = 320
local CAMP_SLEEP = 30
local CAMP_RESPAWN = 15
local ZONE_BOSS_EVERY = 600
local REMOVE_DELAY = 0.3

local ZONE_BOSSES = {
	Meadow = { type = "FarmerZed", level = 8 },
	Woods = { type = "FarmerZed", level = 22 },
	Canyon = { type = "BrainrotTitan", level = 36 },
	Volcano = { type = "BrainrotTitan", level = 56 },
}

local ZombieService = { Name = "ZombieService" }

local S
local grid: { [number]: { any } } = {}
local waves: { [Player]: any } = {}
local camps: { any } = {}
local dungeons: { [Player]: any } = {}
local extraEncounters: { any } = {}
local dying: { any } = {}
local lastCampCheck = 0

local function cellKey(cx: number, cz: number): number
	return (cx + 4096) * 8192 + (cz + 4096)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function yawFrom(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

function ZombieService:Init(services)
	S = services
end

function ZombieService:Start()
	for _, camp in World.Camps() do
		local boss = ZONE_BOSSES[camp.zone]
		table.insert(camps, {
			kind = "Camp",
			camp = camp,
			alive = {},
			respawnAt = {},
			active = false,
			lastNear = 0,
			-- the last camp in each zone hosts that zone's boss
			boss = boss,
			bossAt = os.clock() + ZONE_BOSS_EVERY,
		})
	end
	-- only keep boss duty on the last camp of each zone
	local lastOfZone = {}
	for i, c in camps do
		lastOfZone[c.camp.zone] = i
	end
	for i, c in camps do
		if lastOfZone[c.camp.zone] ~= i then
			c.boss = nil
		end
	end

	Net.Event("StartWave").OnServerEvent:Connect(function(player)
		self:StartWave(player)
	end)
	S.DataService.PlayerLeaving:Connect(function(player)
		self:EndWave(player, "left")
		self:EndDungeon(player, false)
	end)
end

----------------------------------------------------------------------------
-- Spatial queries
----------------------------------------------------------------------------

function ZombieService:RebuildGrid()
	table.clear(grid)
	for _, z in S.EntityService:OfKind("Zombie") do
		if not z.dead then
			local key = cellKey(math.floor(z.pos.X / CELL), math.floor(z.pos.Z / CELL))
			local list = grid[key]
			if not list then
				list = {}
				grid[key] = list
			end
			table.insert(list, z)
		end
	end
end

-- Living zombies within `radius` of `pos` that `viewerId` may interact with.
function ZombieService:Query(pos: Vector3, radius: number, viewerId: number?)
	local out = {}
	local x0, x1 = math.floor((pos.X - radius - 4) / CELL), math.floor((pos.X + radius + 4) / CELL)
	local z0, z1 = math.floor((pos.Z - radius - 4) / CELL), math.floor((pos.Z + radius + 4) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local list = grid[cellKey(cx, cz)]
			if list then
				for _, z in list do
					if not z.dead and (z.visibleTo == nil or viewerId == nil or z.visibleTo == viewerId) then
						local r = radius + z.radius
						local dx, dz = z.pos.X - pos.X, z.pos.Z - pos.Z
						if dx * dx + dz * dz <= r * r and math.abs(z.pos.Y - pos.Y) < 40 then
							table.insert(out, z)
						end
					end
				end
			end
		end
	end
	return out
end

----------------------------------------------------------------------------
-- Spawning
----------------------------------------------------------------------------

-- opts: { encounter, visibleTo, leash, floorY, goal = "core"|"hunt"|nil, aggro }
function ZombieService:Spawn(typeId: string, level: number, pos: Vector3, opts: { [string]: any }?)
	local o = opts or {}
	local def = Zombies.Types[typeId]
	local scaled = Zombies.Scale(typeId, level)
	local scale = def.body.scale or 1
	local y = o.floorY or World.GroundHeight(pos.X, pos.Z)
	local z = S.EntityService:Create("Zombie", {
		typeId = typeId,
		def = def,
		level = level,
		name = def.displayName,
		boss = def.boss,
		guard = def.guard,
		maxHp = scaled.hp,
		hp = scaled.hp,
		damage = scaled.damage,
		speed = def.speed,
		attackRate = def.attackRate,
		range = def.range,
		aggro = o.aggro or def.aggro,
		rewards = { coins = scaled.coins, xp = scaled.xp, mutagen = scaled.mutagen },
		pos = Vector3.new(pos.X, y, pos.Z),
		home = Vector3.new(pos.X, y, pos.Z),
		radius = 1.3 * scale,
		appearance = { source = "Zombie", type = typeId },
		visibleTo = o.visibleTo,
		encounter = o.encounter,
		floorY = o.floorY,
		leash = o.leash,
		goal = o.goal,
		nextAttack = 0,
		nextScan = 0,
	})
	if o.encounter then
		o.encounter.alive[z.id] = z
	end
	return z
end

----------------------------------------------------------------------------
-- Tick
----------------------------------------------------------------------------

function ZombieService:Step(dt: number)
	local now = os.clock()
	self:RebuildGrid()

	for _, z in S.EntityService:OfKind("Zombie") do
		if not z.dead then
			self:StepZombie(z, dt, now)
		end
	end

	-- Deferred removal so the killing-blow numbers land first.
	for i = #dying, 1, -1 do
		local item = dying[i]
		if now >= item.at then
			S.EntityService:Remove(item.z, item.fx)
			table.remove(dying, i)
		end
	end

	for player, wave in waves do
		self:StepWave(player, wave, now)
	end
	for player, dungeon in dungeons do
		self:StepDungeon(player, dungeon, now)
	end
	if now - lastCampCheck > 1 then
		lastCampCheck = now
		for _, camp in camps do
			self:StepCamp(camp, now)
		end
	end
end

function ZombieService:GroundAt(z, x: number, zz: number): number
	return z.floorY or World.GroundHeight(x, zz)
end

function ZombieService:StepZombie(z, dt: number, now: number)
	local speedMult, stun, yOffset = S.CombatService:StepEffects(z, dt, now)
	if z.dead then
		return
	end
	local ground = self:GroundAt(z, z.pos.X, z.pos.Z)
	if stun then
		z.state = if stun == "Frozen" then State.Frozen else State.Stunned
		z.pos = Vector3.new(z.pos.X, ground + yOffset, z.pos.Z)
		return
	end

	if now >= z.nextScan then
		z.targetInfo = self:PickTarget(z, now)
		z.nextScan = now + 0.4 + (z.id % 5) * 0.02
	end
	local t = z.targetInfo
	local goalPos, reach
	if t then
		if t.kind == "pet" then
			if t.e.removed or t.e.fainted then
				z.targetInfo = nil
				z.nextScan = 0
				return
			end
			goalPos, reach = t.e.pos, z.range + t.e.radius
		elseif t.kind == "player" then
			local root = S.EntityService:RootOf(t.player)
			if not root then
				z.targetInfo = nil
				return
			end
			goalPos, reach = root.Position, z.range + 1
		elseif t.kind == "defense" then
			if t.d.broken then
				z.targetInfo = nil
				z.nextScan = 0
				return
			end
			goalPos, reach = t.d.pos, z.range + t.d.radius
		elseif t.kind == "core" then
			goalPos, reach = t.plot.corePos, z.range + 4
		elseif t.kind == "move" then
			goalPos, reach = t.pos, 2
		end
	end
	if not goalPos then
		z.state = State.Idle
		return
	end

	local to = Vector3.new(goalPos.X - z.pos.X, 0, goalPos.Z - z.pos.Z)
	local dist = to.Magnitude
	if dist > 1e-3 then
		z.yaw = yawFrom(to / dist)
	end

	if dist > reach then
		local speed = z.speed * speedMult * (if t and t.chase then 1.15 else 1)
		local step = math.min(dist - reach * 0.9, speed * dt)
		local nx, nz = z.pos.X + to.X / dist * step, z.pos.Z + to.Z / dist * step
		-- light separation inside the cell
		local list = grid[cellKey(math.floor(z.pos.X / CELL), math.floor(z.pos.Z / CELL))]
		if list then
			for _, other in list do
				if other ~= z then
					local dx, dz = nx - other.pos.X, nz - other.pos.Z
					local d2 = dx * dx + dz * dz
					local min = z.radius + other.radius
					if d2 < min * min and d2 > 1e-4 then
						local d = math.sqrt(d2)
						nx += dx / d * (min - d) * 0.5
						nz += dz / d * (min - d) * 0.5
					end
				end
			end
		end
		if not z.floorY then
			nx, nz = World.ClampToValley(nx, nz, 8)
		end
		z.pos = Vector3.new(nx, self:GroundAt(z, nx, nz) + yOffset, nz)
		z.state = State.Move
		return
	end

	z.pos = Vector3.new(z.pos.X, ground + yOffset, z.pos.Z)
	if t.kind == "move" then
		z.state = State.Idle
		z.targetInfo = nil
		if z.returningHome then
			z.returningHome = false
			z.hp = z.maxHp
		end
		return
	end
	if now < z.nextAttack then
		if now > (z.stateHold or 0) then
			z.state = State.Idle
		end
		return
	end
	z.nextAttack = now + 1 / z.attackRate
	z.state = State.Attack
	z.stateHold = now + 0.35
	if z.def.ranged then
		S.EntityService:Event(z.pos, { EV.Projectile, z.id, if t.kind == "pet" then t.e.id else 0, "Spit" }, z.visibleTo)
	end

	if t.kind == "pet" then
		S.CombatService:Damage(z, t.e, z.damage, { fx = if z.boss then "Smash" else "Claw" })
	elseif t.kind == "player" then
		local playerDamage = math.min(if z.boss then 40 else 25, 6 + z.level * 0.4)
		S.CombatService:DamagePlayer(t.player, playerDamage, z)
	elseif t.kind == "defense" then
		S.PlotService:DamageDefense(t.plot, t.d, z.damage, z)
	elseif t.kind == "core" then
		S.PlotService:DamageCore(t.plot, z.damage)
	end
end

function ZombieService:PickTarget(z, now: number)
	local enc = z.encounter

	-- Leash: camp zombies and guards walk home and heal.
	local leash = z.leash
	if leash and flatDist(z.pos, z.home) > leash then
		z.returningHome = true
	end
	if z.returningHome then
		return { kind = "move", pos = z.home }
	end

	-- Taunted by a Tank pet
	local taunter = z.tauntedBy
	if taunter and now < (z.tauntUntil or 0) and not taunter.removed and not taunter.fainted then
		return { kind = "pet", e = taunter }
	end

	-- Heist guards chase whoever carries their egg.
	if enc and enc.kind == "Heist" and enc.carrier then
		local root = S.EntityService:RootOf(enc.carrier)
		if root and flatDist(root.Position, z.pos) < (z.leash or 300) then
			return { kind = "player", player = enc.carrier, chase = true }
		end
	end

	local aggro = z.aggro
	local best, bestD = nil, aggro
	for _, pet in S.EntityService:OfKind("Pet") do
		if not pet.fainted and not pet.mounted and (z.visibleTo == nil or pet.ownerId == z.visibleTo) then
			local d = flatDist(pet.pos, z.pos)
			if d < bestD and math.abs(pet.pos.Y - z.pos.Y) < 30 then
				best, bestD = { kind = "pet", e = pet }, d
			end
		end
	end
	local playerAggro = aggro * 0.7
	for _, player in Players:GetPlayers() do
		if z.visibleTo == nil or player.UserId == z.visibleTo then
			local root = S.EntityService:RootOf(player)
			if root then
				local d = flatDist(root.Position, z.pos)
				if d < math.min(bestD, playerAggro) and math.abs(root.Position.Y - z.pos.Y) < 20 then
					best, bestD = { kind = "player", player = player }, d
				end
			end
		end
	end
	if best then
		return best
	end

	if z.goal == "core" and enc and enc.plot then
		local blocking = S.PlotService:BlockingDefense(enc.plot, z.pos, enc.plot.corePos, z.radius)
		if blocking then
			return { kind = "defense", d = blocking, plot = enc.plot }
		end
		return { kind = "core", plot = enc.plot }
	elseif z.goal == "hunt" and enc then
		-- Dungeon zombies hunt the runner's army anywhere in the arena.
		local owner = enc.player
		local squad = S.PetService:GetSquad(owner)
		if squad then
			for _, pet in squad.order do
				if not pet.fainted then
					return { kind = "pet", e = pet }
				end
			end
		end
		return { kind = "player", player = owner }
	elseif z.patrol then
		local p = z.patrol
		if flatDist(z.pos, p.points[p.i]) < 3 then
			p.i = p.i % #p.points + 1
		end
		return { kind = "move", pos = p.points[p.i] }
	elseif flatDist(z.pos, z.home) > 6 then
		return { kind = "move", pos = z.home }
	end
	return nil
end

----------------------------------------------------------------------------
-- Death & rewards
----------------------------------------------------------------------------

function ZombieService:OnKilled(z, killer, opts)
	z.state = State.Dead
	local enc = z.encounter
	if enc then
		enc.alive[z.id] = nil
		enc.killed = (enc.killed or 0) + 1
		if enc.kind == "Camp" then
			-- camps refill only after you stop killing for a moment
			enc.nextSpawn = math.max(enc.nextSpawn or 0, os.clock() + CAMP_RESPAWN)
		end
		if enc.onKilled then
			task.spawn(enc.onKilled, z, killer)
		end
	end

	local owner: Player? = nil
	if killer and killer.kind == "Pet" and killer.owner then
		owner = killer.owner
	elseif enc and enc.player then
		owner = enc.player
	elseif z.lastAttacker and z.lastAttacker.owner then
		owner = z.lastAttacker.owner
	end

	if owner and S.DataService:IsLoaded(owner) then
		local r = z.rewards
		local coins = S.DataService:Add(owner, "coins", r.coins)
		S.DataService:Add(owner, "mutagen", r.mutagen, true)
		S.DataService:AddXP(owner, r.xp)
		S.DataService:IncrementStat(owner, "zombiesKilled")
		if z.boss then
			S.DataService:IncrementStat(owner, "bossesKilled")
		end
		S.PetService:AwardKill(owner, if killer and killer.kind == "Pet" then killer else nil, r.xp, z.boss == true)
		S.EntityService:Event(z.pos, { EV.Text, z.id, "+💰" .. math.floor(coins), "#FFD84A" }, owner.UserId)
		if z.def.fruitDrop and math.random() < z.def.fruitDrop then
			S.FruitService:GrantRandom(owner, "boss")
		end
		if z.boss and not enc then
			S.AnnounceService:Announce(("%s's army defeated %s!"):format(owner.DisplayName, z.name), "reward")
		end
	end

	local fx = if opts and opts.fx then opts.fx else "Hit"
	table.insert(dying, { z = z, at = os.clock() + REMOVE_DELAY, fx = "Death:" .. fx })
end

-- Robux "Zombie Nuke": clears the buyer's wave and everything near them.
function ZombieService:Nuke(player: Player)
	local root = S.EntityService:RootOf(player)
	local wave = waves[player]
	local victims = {}
	if wave then
		for _, z in wave.alive do
			victims[z] = true
		end
		wave.queue = {}
	end
	if root then
		self:RebuildGrid()
		for _, z in self:Query(root.Position, 220, player.UserId) do
			if not z.guard then
				victims[z] = true
			end
		end
		S.EntityService:Event(root.Position, { EV.Ability, 0, "Nuke", root.Position.X, root.Position.Z, 220, 0, 0 })
	end
	for z in victims do
		S.CombatService:Kill(z, nil, { fx = "Nuke" })
	end
end

----------------------------------------------------------------------------
-- Base-defense waves (Build & Kill)
----------------------------------------------------------------------------

function ZombieService:GetWave(player: Player)
	return waves[player]
end

function ZombieService:StartWave(player: Player)
	local plot = S.PlotService:GetPlot(player)
	local d = S.DataService:Get(player)
	if not plot or not d then
		return
	end
	local wave = waves[player]
	if wave and wave.state == "Fighting" then
		return
	end
	local n = d.base.wave + 1
	wave = {
		kind = "Wave",
		player = player,
		plot = plot,
		wave = n,
		queue = Zombies.WaveComposition(n),
		alive = {},
		spawnTimer = 0,
		state = "Fighting",
		killed = 0,
	}
	wave.total = #wave.queue
	waves[player] = wave
	S.PlotService:SetCoreHp(plot, plot.coreMax)
	self:SendWaveState(player)
	S.AnnounceService:Notify(player, ("🧟 WAVE %d INCOMING!"):format(n), "warn")
end

function ZombieService:StepWave(player: Player, wave, now: number)
	local plot = wave.plot
	if wave.state == "Fighting" then
		local aliveCount = 0
		for _ in wave.alive do
			aliveCount += 1
		end
		if #wave.queue > 0 and now >= wave.spawnTimer and aliveCount < Zombies.MaxAlivePerPlot then
			wave.spawnTimer = now + Zombies.WaveSpawnInterval
			local typeId = table.remove(wave.queue, 1)
			local rift = plot.riftPos
			local jitter = Vector3.new(math.random(-8, 8), 0, math.random(-3, 3))
			self:Spawn(typeId, Zombies.WaveLevel(wave.wave), rift + plot.cf:VectorToWorldSpace(jitter), {
				encounter = wave,
				goal = "core",
				aggro = 22,
			})
			if Zombies.Types[typeId].boss then
				S.AnnounceService:Notify(player, ("👹 %s has entered your farm!"):format(Zombies.Types[typeId].displayName), "warn")
			end
		end
		if plot.coreHp <= 0 then
			self:EndWave(player, "failed")
			return
		end
		if #wave.queue == 0 and aliveCount == 0 then
			self:CompleteWave(player, wave, now)
		end
		if now - (wave.lastSync or 0) > 1 then
			wave.lastSync = now
			self:SendWaveState(player)
		end
	elseif wave.state == "Break" then
		local d = S.DataService:Get(player)
		if now >= wave.breakUntil and d and d.settings.autoWave and S.PlotService:IsOnPlot(player, 30) then
			self:StartWave(player)
		end
	end
end

function ZombieService:CompleteWave(player: Player, wave, now: number)
	local d = S.DataService:Get(player)
	local n = wave.wave
	d.base.wave = n
	d.base.bestWave = math.max(d.base.bestWave, n)
	S.DataService:Replicate(player, "base")
	S.DataService:IncrementStat(player, "wavesCleared")
	local coins = S.DataService:Add(player, "coins", math.floor(60 * n ^ 1.35))
	S.DataService:Add(player, "mutagen", 3 * n, true)
	S.DataService:AddXP(player, 20 * n)
	S.AnnounceService:Notify(player, ("✅ WAVE %d CLEARED! +💰%d"):format(n, math.floor(coins)), "reward")
	if n % 10 == 0 then
		S.AnnounceService:Announce(("%s survived WAVE %d on their farm!"):format(player.DisplayName, n), "reward")
	end
	wave.state = "Break"
	wave.breakUntil = now + Zombies.WaveBreak
	S.PlotService:SetCoreHp(wave.plot, wave.plot.coreMax)
	S.PlotService:RepairDefenses(wave.plot)
	self:SendWaveState(player)
end

function ZombieService:EndWave(player: Player, reason: string)
	local wave = waves[player]
	if not wave then
		return
	end
	for _, z in wave.alive do
		z.dead = true
		S.EntityService:Remove(z, "Death:Poof")
	end
	wave.alive = {}
	if reason == "failed" then
		S.AnnounceService:Notify(player, "💔 The horde broke your Barn Heart! Upgrade walls, turrets and pets, then try again.", "error")
		S.PlotService:SetCoreHp(wave.plot, wave.plot.coreMax)
		S.PlotService:RepairDefenses(wave.plot)
		wave.state = "Idle"
		self:SendWaveState(player)
	else
		waves[player] = nil
	end
end

function ZombieService:SendWaveState(player: Player)
	local wave = waves[player]
	if not wave then
		Net.Event("WaveState"):FireClient(player, nil)
		return
	end
	local alive = 0
	for _ in wave.alive do
		alive += 1
	end
	Net.Event("WaveState"):FireClient(player, {
		wave = wave.wave,
		state = wave.state,
		remaining = alive + #wave.queue,
		total = wave.total,
		coreHp = wave.plot.coreHp,
		coreMax = wave.plot.coreMax,
		breakLeft = if wave.breakUntil then math.max(0, wave.breakUntil - os.clock()) else 0,
	})
end

----------------------------------------------------------------------------
-- Valley camps + zone bosses
----------------------------------------------------------------------------

function ZombieService:StepCamp(c, now: number)
	local campPos = c.camp.position
	local near = false
	for _, player in Players:GetPlayers() do
		local root = S.EntityService:RootOf(player)
		if root and flatDist(root.Position, campPos) < CAMP_RANGE then
			near = true
			break
		end
	end
	if near then
		c.lastNear = now
		c.active = true
	elseif c.active and now - c.lastNear > CAMP_SLEEP then
		c.active = false
		for _, z in c.alive do
			z.dead = true
			S.EntityService:Remove(z)
		end
		c.alive = {}
		return
	end
	if not c.active then
		return
	end

	local count = 0
	for _ in c.alive do
		count += 1
	end
	if count < c.camp.size and now >= (c.nextSpawn or 0) then
		c.nextSpawn = now + 0.5
		local types = c.camp.types
		local typeId = types[math.random(1, #types)]
		local offset = Vector3.new(math.random(-14, 14), 0, math.random(-14, 14))
		local level = math.max(1, c.camp.level + math.random(-1, 1))
		self:Spawn(typeId, level, campPos + offset, { encounter = c, leash = 70 })
	end

	if c.boss and now >= c.bossAt then
		c.bossAt = now + ZONE_BOSS_EVERY
		local boss = self:Spawn(c.boss.type, c.boss.level, campPos, { encounter = c, leash = 90 })
		local zone = World.ZoneById(c.camp.zone)
		S.AnnounceService:Announce(("👹 %s has risen in %s!"):format(boss.name, if zone then zone.name else "the valley"), "warn")
	end
end

----------------------------------------------------------------------------
-- The Hollow Stump dungeon
----------------------------------------------------------------------------

function ZombieService:StartDungeon(player: Player): boolean
	local d = S.DataService:Get(player)
	if not d or dungeons[player] then
		return false
	end
	if os.time() < (d.dungeonCooldown or 0) then
		S.AnnounceService:Notify(player, ("The Hollow is sealed for %ds."):format(d.dungeonCooldown - os.time()), "warn")
		return false
	end
	local dun = World.Dungeon
	local center = Vector3.new(World.CenterX(dun.arena.Z) + dun.arena.X, dun.arena.Y, dun.arena.Z)
	local run = {
		kind = "Dungeon",
		player = player,
		wave = 0,
		maxWaves = dun.waves,
		level = d.level + dun.levelOffset,
		alive = {},
		center = center,
		floorY = center.Y,
		state = "Starting",
		nextWaveAt = os.clock() + 3,
	}
	dungeons[player] = run
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(center + Vector3.new(0, 5, 20)))
	end
	S.AnnounceService:Notify(player, "🪵 You entered THE HOLLOW STUMP. Survive 4 waves!", "warn")
	return true
end

function ZombieService:StepDungeon(player: Player, run, now: number)
	local alive = 0
	for _ in run.alive do
		alive += 1
	end
	local root = S.EntityService:RootOf(player)
	if not root or root.Position.Y > run.floorY + 60 then
		self:EndDungeon(player, false)
		return
	end
	if alive == 0 and now >= run.nextWaveAt then
		if run.wave >= run.maxWaves then
			self:EndDungeon(player, true)
			return
		end
		run.wave += 1
		local types = { "Walker", "Runner", "Spitter", "Brute" }
		local count = 6 + run.wave * 3
		for i = 1, count do
			local a = (i / count) * math.pi * 2
			local pos = run.center + Vector3.new(math.cos(a) * 45, 0, math.sin(a) * 45)
			self:Spawn(types[math.random(1, math.min(#types, run.wave + 1))], run.level, pos, {
				encounter = run,
				visibleTo = player.UserId,
				floorY = run.floorY,
				goal = "hunt",
				aggro = 200,
			})
		end
		if run.wave == run.maxWaves then
			self:Spawn("FarmerZed", run.level + 2, run.center + Vector3.new(0, 0, -40), {
				encounter = run,
				visibleTo = player.UserId,
				floorY = run.floorY,
				goal = "hunt",
				aggro = 200,
			})
		end
		S.AnnounceService:Notify(player, ("Hollow wave %d/%d"):format(run.wave, run.maxWaves), "warn")
		run.nextWaveAt = now + 2
	end
end

function ZombieService:EndDungeon(player: Player, won: boolean)
	local run = dungeons[player]
	if not run then
		return
	end
	dungeons[player] = nil
	for _, z in run.alive do
		z.dead = true
		S.EntityService:Remove(z, "Death:Poof")
	end
	local d = S.DataService:Get(player)
	if d then
		d.dungeonCooldown = os.time() + World.Dungeon.cooldown
	end
	if won and d then
		local coins = S.DataService:Add(player, "coins", 800 * run.level)
		S.DataService:Add(player, "mutagen", 25 * run.level, true)
		S.AnnounceService:Notify(player, ("🏆 HOLLOW CLEARED! +💰%d"):format(math.floor(coins)), "reward")
		if math.random() < 0.25 then
			S.FruitService:GrantRandom(player, "dungeon")
		end
		if math.random() < 0.5 then
			S.MutationService:AddCapsule(player, S.MutationService:RollMutation(1), "dungeon")
		end
	end
	task.delay(if won then 3 else 0, function()
		local character = player.Character
		if character and player.Parent then
			local entrance = World.Resolve(World.Dungeon.entrance)
			character:PivotTo(CFrame.new(entrance + Vector3.new(0, 5, -16)))
		end
	end)
end

-- Heist/other services register encounters they create here for cleanup.
function ZombieService:DespawnEncounter(enc)
	for _, z in enc.alive do
		z.dead = true
		S.EntityService:Remove(z, "Death:Poof")
	end
	enc.alive = {}
	local i = table.find(extraEncounters, enc)
	if i then
		table.remove(extraEncounters, i)
	end
end

return ZombieService
