--[[
	CombatService: all damage flows through here so fruit passives, brainrot
	mutation specials, statuses and kill credit behave the same whether the
	hit came from a pet, a mounted attack, an ability or a turret.

	Statuses live in entity.effects:
	  burn   { dps, untilT, source }
	  slow   { mult, untilT }
	  stun   { untilT, kind = "Frozen" | "Stunned" }
	  launch { t0, dur, height }     -- zombie flies up (great for clips)
	  vulnerable = untilT            -- takes +50% damage (Rizz Aura charm)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Protocol = require(Shared.Util.EntityProtocol)
local Fruits = require(Shared.Config.Fruits)

local EV = Protocol.Event
local State = Protocol.State

local CombatService = { Name = "CombatService" }

local S

function CombatService:Init(services)
	S = services
end

local function event(target, ev)
	S.EntityService:Event(target.pos, ev, target.visibleTo)
end

function CombatService:Text(entity, text: string, color: string?)
	event(entity, { EV.Text, entity.id, text, color or "#FFFFFF" })
end

----------------------------------------------------------------------------
-- Core damage
----------------------------------------------------------------------------

-- opts: { fx, status, canCrit, silent }
function CombatService:Damage(attacker, target, amount: number, opts: { [string]: any }?): number
	local o = opts or {}
	if not target or target.dead or target.removed then
		return 0
	end
	local now = os.clock()
	local tstats = target.stats
	if tstats and tstats.dodge > 0 and math.random() < tstats.dodge then
		self:Text(target, "DODGE", "#DDDDDD")
		return 0
	end

	local crit = false
	if attacker and not attacker.removed then
		local astats = attacker.stats
		if astats then
			if o.canCrit ~= false and math.random() < astats.critChance then
				crit = true
				amount *= 2
			end
			local sp = astats.special
			if target.boss and sp.bossDamage then
				amount *= sp.bossDamage
			end
			if sp.auraPerStack and (attacker.aura or 0) > 0 then
				amount *= 1 + attacker.aura * sp.auraPerStack
			end
		end
		local buff = attacker.buff
		if buff and now < buff.untilT then
			amount *= buff.power or 1
		end
	end

	if tstats then
		amount *= tstats.damageTaken
	end
	if target.effects.vulnerable and now < target.effects.vulnerable then
		amount *= 1.5
	end
	amount = math.max(1, math.floor(amount + 0.5))

	target.hp -= amount
	target.lastHitAt = now
	target.lastAttacker = attacker
	if not o.silent then
		event(target, { EV.Hit, if attacker then attacker.id else 0, target.id, amount, crit, o.fx or "" })
	end
	if o.status then
		self:ApplyStatus(target, o.status, attacker)
	end
	if target.hp <= 0 then
		self:Kill(target, attacker, o)
	end
	return amount
end

function CombatService:Kill(target, killer, opts)
	if target.dead then
		return
	end
	target.dead = true
	target.hp = 0
	target.state = State.Dead
	if target.kind == "Zombie" then
		S.ZombieService:OnKilled(target, killer, opts)
	elseif target.kind == "Pet" then
		S.PetService:OnFainted(target, killer)
	end
end

----------------------------------------------------------------------------
-- Pet basic attack: fruit passives + brainrot mutation specials
----------------------------------------------------------------------------

function CombatService:PetBasicHit(pet, target, baseDamage: number, fx: string?)
	local stats = pet.stats
	local sp = stats.special
	local fruit = pet.fruitId and Fruits.List[pet.fruitId]
	local onHit = fruit and fruit.onHit
	pet.hitCount = (pet.hitCount or 0) + 1

	local dmg = baseDamage
	local status = nil
	local chain = nil
	if sp.everyNthHit and pet.hitCount % sp.everyNthHit == 0 then
		dmg *= sp.nthMult
		self:Text(target, "🤲 SIX SEVEN!!", "#FFD23F")
	end
	if onHit and math.random() < (onHit.chance or 1) then
		if onHit.status == "SixSeven" then
			dmg *= onHit.mult
			self:Text(target, "6.7x OHIO CRIT", "#FF46D2")
		elseif onHit.status == "Chain" then
			chain = onHit
		else
			status = onHit
		end
	end

	self:Damage(pet, target, dmg, { fx = fx or (fruit and fruit.element) or "Hit", status = status })

	if sp.charmChance and not target.dead and math.random() < sp.charmChance then
		self:ApplyStatus(target, { status = "Mesmerize", duration = sp.charmDuration or 2 }, pet)
		self:Text(target, "💖 rizzed", "#FF7AC8")
	end
	if chain then
		self:ChainFrom(pet, target, chain.jumps, chain.jumpRange, baseDamage * chain.damageMult, nil, "Volt")
	end
	if onHit and onHit.splash then
		for _, z in S.ZombieService:Query(target.pos, onHit.splash, pet.ownerId) do
			if z ~= target then
				self:Damage(pet, z, dmg * onHit.splashMult, { fx = "Splash", canCrit = false })
			end
		end
	end
	if sp.repeatHit then
		task.delay(sp.repeatHit, function()
			if not target.dead and not pet.removed then
				self:Damage(pet, target, dmg, { fx = "Lag", canCrit = false })
				self:Text(target, "📶 lag", "#9AE6FF")
			end
		end)
	end
end

----------------------------------------------------------------------------
-- Area helpers (abilities, mounted attacks, turrets)
----------------------------------------------------------------------------

function CombatService:Burst(attacker, center: Vector3, radius: number, damage: number, status, fx: string, viewerId: number?): number
	local hits = 0
	for _, z in S.ZombieService:Query(center, radius, viewerId) do
		self:Damage(attacker, z, damage, { fx = fx, status = status })
		hits += 1
	end
	S.EntityService:Event(center, { EV.Ability, if attacker then attacker.id else 0, fx, center.X, center.Z, radius, 0, 0 }, if attacker then attacker.visibleTo else nil)
	return hits
end

function CombatService:Cone(attacker, origin: Vector3, dir: Vector3, range: number, angleDeg: number, damage: number, status, fx: string, viewerId: number?): number
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 1e-3 then
		return 0
	end
	flatDir = flatDir.Unit
	local cosHalf = math.cos(math.rad(angleDeg / 2))
	local hits = 0
	for _, z in S.ZombieService:Query(origin, range + 3, viewerId) do
		local to = Vector3.new(z.pos.X - origin.X, 0, z.pos.Z - origin.Z)
		local dist = to.Magnitude
		if dist < 2 or (dist <= range + z.radius and to.Unit:Dot(flatDir) >= cosHalf) then
			self:Damage(attacker, z, damage, { fx = fx, status = status })
			hits += 1
		end
	end
	S.EntityService:Event(origin, { EV.Ability, if attacker then attacker.id else 0, fx, origin.X, origin.Z, range, flatDir.X, flatDir.Z }, if attacker then attacker.visibleTo else nil)
	return hits
end

-- Hops from `first` to the nearest un-hit zombie, `jumps` times.
function CombatService:ChainFrom(attacker, first, jumps: number, range: number, damage: number, status, fx: string, includeFirst: boolean?): number
	local hit = { [first.id] = true }
	local ids = { first.id }
	if includeFirst then
		self:Damage(attacker, first, damage, { fx = fx, status = status, canCrit = false })
	end
	local current = first
	for _ = 1, jumps do
		local best, bestD = nil, range * range
		for _, z in S.ZombieService:Query(current.pos, range, attacker and attacker.ownerId) do
			if not hit[z.id] then
				local d = z.pos - current.pos
				local d2 = d.X * d.X + d.Z * d.Z
				if d2 < bestD then
					best, bestD = z, d2
				end
			end
		end
		if not best then
			break
		end
		hit[best.id] = true
		table.insert(ids, best.id)
		self:Damage(attacker, best, damage, { fx = fx, status = status, canCrit = false })
		current = best
	end
	S.EntityService:Event(first.pos, { EV.Chain, ids, fx }, if attacker then attacker.visibleTo else nil)
	return #ids
end

----------------------------------------------------------------------------
-- Statuses
----------------------------------------------------------------------------

function CombatService:ApplyStatus(target, s, attacker)
	if target.dead then
		return
	end
	local now = os.clock()
	local e = target.effects
	local duration = s.duration or 1
	local kind = s.status
	if kind == "Burn" then
		local power = if attacker and attacker.stats then attacker.stats.power else 5
		e.burn = { dps = power * s.dps, untilT = now + duration, source = attacker }
	elseif kind == "Chill" then
		e.slow = { mult = 1 - s.slow, untilT = now + duration }
	elseif kind == "Freeze" then
		duration *= if target.boss then 0.35 else 1
		e.stun = { untilT = now + duration, kind = "Frozen" }
	elseif kind == "Shock" then
		duration *= if target.boss then 0.35 else 1
		e.stun = { untilT = now + duration, kind = "Stunned" }
	elseif kind == "Mesmerize" then
		e.stun = { untilT = now + duration * (if target.boss then 0.3 else 1), kind = "Stunned" }
		e.vulnerable = now + duration
	elseif kind == "Launch" then
		if target.boss then
			return
		end
		duration = 1.1
		e.launch = { t0 = now, dur = duration, height = s.height or 12 }
		e.stun = { untilT = now + duration, kind = "Stunned" }
	else
		return
	end
	S.EntityService:Event(target.pos, { EV.Status, target.id, kind, duration }, target.visibleTo)
end

-- Advances statuses. Returns speedMult, stunKind (or nil), yOffset.
function CombatService:StepEffects(entity, dt: number, now: number): (number, string?, number)
	local e = entity.effects
	local speed = 1
	local stun = nil
	local yOffset = 0
	if e.burn then
		if now > e.burn.untilT then
			e.burn = nil
		else
			local source = e.burn.source
			if source and source.removed then
				source = nil
			end
			self:Damage(source, entity, e.burn.dps * dt, { silent = true, canCrit = false })
		end
	end
	if e.slow then
		if now > e.slow.untilT then
			e.slow = nil
		else
			speed *= e.slow.mult
		end
	end
	if e.stun then
		if now > e.stun.untilT then
			e.stun = nil
		else
			stun = e.stun.kind
		end
	end
	if e.launch then
		local t = (now - e.launch.t0) / e.launch.dur
		if t >= 1 then
			e.launch = nil
		else
			yOffset = e.launch.height * 4 * t * (1 - t)
		end
	end
	return speed, stun, yOffset
end

----------------------------------------------------------------------------
-- Players
----------------------------------------------------------------------------

function CombatService:DamagePlayer(player: Player, amount: number, source)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if character:FindFirstChildOfClass("ForceField") then
		return
	end
	humanoid:TakeDamage(amount)
	S.CarryService:OnCarrierHit(player, source)
end

return CombatService
