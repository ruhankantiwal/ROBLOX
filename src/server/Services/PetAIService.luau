--[[
	PetAIService: the Animal Army brain. Runs at 10 Hz on the server.

	Per squad, per tick:
	  1. Context     owner position/facing, command mode, anchor (owner or
	                 base core), thieves, whether the owner stands on a
	                 structure (then pets raycast for floor height).
	  2. Separation  squadmates push apart so they never stack.
	  3. Per pet     a small state machine:

	       Fainted -> (timer) -> Follow
	       Mounted -> glued under the owner (MountService handles input)
	       Thief nearby -> Chase thief -> Catch (drops stolen loot)
	       Target?  -> TryAbility -> Engage (surround / kite) -> Attack
	       else     -> Formation slot (V behind owner, ring around core)

	Target choice is role-driven, which is what makes the army read as a
	team instead of a blob:
	  Tank     picks the zombie closest to the OWNER and taunts
	  Striker  picks the weakest zombie (finishing blows)
	  Ranged   kites at 85% range, fires projectiles
	  Support  stays near the owner, heals the squad on a pulse
	A "pressure" count spreads pets across targets; a focus command
	(tap a zombie) overrides everything.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Protocol = require(Shared.Util.EntityProtocol)
local World = require(Shared.Config.World)
local Pets = require(Shared.Config.Pets)
local Fruits = require(Shared.Config.Fruits)
local Rng = require(Shared.Util.Rng)

local State = Protocol.State
local EV = Protocol.Event

local AGGRO = { Follow = 38, Attack = 90, Guard = 60, Hunt = 90 }
local LEASH = { Follow = 70, Attack = 120, Guard = 75, Hunt = 150 }
local TELEPORT_DIST = 220
local SCAN_INTERVAL = 0.3
local SEPARATION = 3

local MEME_TEXT = {
	GravityFlip = "🌀 GRAVITY? NEVER HEARD OF HER",
	BruhFreeze = "💀 bruh.",
	ConfettiNuke = "🎉 CONFETTI NUKE",
	GigaMode = "🗿 GIGA MODE",
}

local PetAIService = { Name = "PetAIService" }

local S
local floorParams: RaycastParams

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function yawFrom(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

function PetAIService:Init(services)
	S = services
end

function PetAIService:Start()
	floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Include
	local filter = {}
	for _, name in { "World", "Plots" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(filter, folder)
		end
	end
	floorParams.FilterDescendantsInstances = filter
end

----------------------------------------------------------------------------
-- Tick
----------------------------------------------------------------------------

function PetAIService:Step(dt: number)
	local now = os.clock()
	for player, squad in S.PetService:Squads() do
		local root = S.EntityService:RootOf(player)
		if root and #squad.order > 0 then
			self:StepSquad(player, squad, root, dt, now)
		end
	end
end

function PetAIService:StepSquad(player: Player, squad, root: BasePart, dt: number, now: number)
	local character = root.Parent :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local ownerPos = root.Position
	local hip = if humanoid then humanoid.HipHeight else 2
	local ownerFeetY = ownerPos.Y - root.Size.Y / 2 - hip
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)

	local ctx = {
		player = player,
		squad = squad,
		ownerPos = ownerPos,
		ownerFeetY = ownerFeetY,
		look = look,
		mode = squad.mode,
		anchor = ownerPos,
		onStructure = math.abs(ownerFeetY - World.GroundHeight(ownerPos.X, ownerPos.Z)) > 4,
		now = now,
		dt = dt,
		ownerYaw = yawFrom(look),
		count = #squad.order,
	}

	if ctx.mode == "Guard" then
		local plot = S.PlotService:GetPlot(player)
		if plot then
			ctx.anchor = plot.corePos
		else
			ctx.mode = "Follow"
		end
	end
	if squad.focusId then
		local focus = S.EntityService:Get(squad.focusId)
		if not focus or focus.dead then
			squad.focusId = nil
			if squad.mode == "Attack" then
				squad.mode = "Follow"
				ctx.mode = "Follow"
			end
		end
	end

	-- How many squadmates already hit each target (spreads damage).
	local pressure = {}
	for _, pet in squad.order do
		if pet.target then
			pressure[pet.target] = (pressure[pet.target] or 0) + 1
		end
	end
	ctx.pressure = pressure
	ctx.thieves = S.CarryService:ThievesFrom(player)

	-- Separation
	local order = squad.order
	for i, a in order do
		local push = Vector3.zero
		for j, b in order do
			if i ~= j and not b.fainted then
				local d = flat(a.pos - b.pos)
				local m = d.Magnitude
				if m < SEPARATION and m > 1e-3 then
					push += d.Unit * (SEPARATION - m)
				end
			end
		end
		a.sep = push
	end

	for i, pet in order do
		self:StepPet(ctx, pet, i)
	end
end

----------------------------------------------------------------------------
-- Per-pet state machine
----------------------------------------------------------------------------

function PetAIService:StepPet(ctx, pet, slot: number)
	local now = ctx.now
	local stats = pet.stats

	if pet.fainted then
		pet.state = State.Fainted
		if now >= pet.respawnAt then
			pet.fainted = false
			pet.hp = pet.maxHp
			pet.pos = self:FormationSlot(ctx, slot)
			S.CombatService:Text(pet, "Back in action!", "#7CFF6B")
		end
		return
	end

	if pet.mounted then
		pet.pos = Vector3.new(ctx.ownerPos.X, ctx.ownerFeetY, ctx.ownerPos.Z)
		pet.yaw = ctx.ownerYaw
		pet.state = State.Mounted
		return
	end

	self:Passives(ctx, pet)

	-- Hopelessly far (owner teleported or galloped off): snap to formation.
	local home = if ctx.mode == "Guard" then ctx.anchor else ctx.ownerPos
	if flatDist(pet.pos, home) > TELEPORT_DIST then
		pet.pos = self:FormationSlot(ctx, slot)
		pet.target = nil
		return
	end

	-- Thieves carrying our owner's loot take priority over zombies.
	for _, thief in ctx.thieves do
		local d = flatDist(pet.pos, thief.pos)
		if d < 55 then
			if d < 5 + pet.radius then
				S.CarryService:Catch(thief.player, ctx.player, pet)
			else
				self:MoveToward(ctx, pet, thief.pos, stats.speed * 1.3, 1)
			end
			return
		end
	end

	-- Validate / reacquire target
	local target = S.EntityService:Get(pet.target)
	if target and (target.dead or target.removed or flatDist(target.pos, ctx.anchor) > LEASH[ctx.mode] + 10) then
		target = nil
		pet.target = nil
	end
	if not target or now >= pet.nextScan then
		local best = self:ChooseTarget(ctx, pet)
		if best ~= target then
			if target then
				ctx.pressure[target.id] = math.max(0, (ctx.pressure[target.id] or 1) - 1)
			end
			if best then
				ctx.pressure[best.id] = (ctx.pressure[best.id] or 0) + 1
			end
		end
		target = best
		pet.target = if best then best.id else nil
		pet.nextScan = now + SCAN_INTERVAL + (pet.id % 4) * 0.025
	end

	if target then
		if self:TryAbility(ctx, pet, target) then
			return
		end
		self:Engage(ctx, pet, target, slot)
	else
		local speed = stats.speed
		local distOwner = flatDist(pet.pos, ctx.ownerPos)
		if distOwner > 14 then
			speed = math.max(speed, 30) * (if distOwner > 40 then 1.8 else 1.2)
		end
		self:MoveToward(ctx, pet, self:FormationSlot(ctx, slot), speed, 0.8)
	end
end

function PetAIService:Passives(ctx, pet)
	local now, dt = ctx.now, ctx.dt
	local stats = pet.stats
	local sp = stats.special
	local role = Pets.Roles[stats.role] or {}

	if sp.regen and now - (pet.lastHitAt or 0) > 3 and pet.hp < pet.maxHp then
		pet.hp = math.min(pet.maxHp, pet.hp + pet.maxHp * sp.regen * dt)
	end

	if stats.role == "Support" and now >= (pet.nextHeal or 0) then
		pet.nextHeal = now + role.healEvery
		local healed = false
		for _, mate in ctx.squad.order do
			if not mate.fainted and mate.hp < mate.maxHp and flatDist(mate.pos, pet.pos) < role.healRadius then
				local amount = mate.maxHp * role.healPct
				mate.hp = math.min(mate.maxHp, mate.hp + amount)
				S.EntityService:Event(mate.pos, { EV.Heal, mate.id, math.floor(amount) })
				healed = true
			end
		end
		if healed then
			S.EntityService:Event(pet.pos, { EV.Ability, pet.id, "Heal", pet.pos.X, pet.pos.Z, role.healRadius, 0, 0 })
		end
	end

	if (stats.role == "Tank" or sp.taunt) and now >= (pet.nextTaunt or 0) then
		local tank = Pets.Roles.Tank
		pet.nextTaunt = now + tank.tauntEvery
		local taunted = 0
		for _, z in S.ZombieService:Query(pet.pos, tank.tauntRadius, ctx.player.UserId) do
			if not z.boss then
				z.tauntedBy = pet
				z.tauntUntil = now + 3
				taunted += 1
			end
		end
		if taunted > 0 then
			S.EntityService:Event(pet.pos, { EV.Ability, pet.id, "Taunt", pet.pos.X, pet.pos.Z, tank.tauntRadius, 0, 0 })
		end
	end

	if pet.buff and now >= pet.buff.untilT then
		pet.buff = nil
		S.PetService:RefreshPet(ctx.player, pet.uid)
	end
end

----------------------------------------------------------------------------
-- Targeting
----------------------------------------------------------------------------

function PetAIService:ChooseTarget(ctx, pet)
	local stats = pet.stats
	local role = stats.role
	local center = if ctx.mode == "Guard" then ctx.anchor else ctx.ownerPos
	local candidates = S.ZombieService:Query(center, AGGRO[ctx.mode], ctx.player.UserId)
	local focusId = ctx.squad.focusId
	if focusId then
		local focus = S.EntityService:Get(focusId)
		if focus and not focus.dead and flatDist(focus.pos, center) < LEASH[ctx.mode] then
			return focus
		end
	end

	local best, bestScore = nil, math.huge
	for _, z in candidates do
		local d = flatDist(pet.pos, z.pos)
		local score
		if role == "Tank" then
			score = flatDist(z.pos, ctx.ownerPos) * 0.8 + d * 0.2
		elseif role == "Striker" then
			score = d - (1 - z.hp / z.maxHp) * 25
		elseif role == "Ranged" then
			score = d * 0.6
		else -- Support
			score = d + flatDist(z.pos, ctx.ownerPos) * 0.5
		end
		if z.boss then
			score -= if stats.special.bossDamage then 30 else 10
		end
		if role ~= "Tank" then
			score += (ctx.pressure[z.id] or 0) * 7
		end
		if score < bestScore then
			best, bestScore = z, score
		end
	end
	return best
end

----------------------------------------------------------------------------
-- Movement
----------------------------------------------------------------------------

function PetAIService:FloorY(ctx, x: number, z: number): number
	if not ctx.onStructure then
		return World.GroundHeight(x, z)
	end
	local origin = Vector3.new(x, ctx.ownerFeetY + 6, z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -40, 0), floorParams)
	return if hit then hit.Position.Y else ctx.ownerFeetY
end

-- V formation behind the owner; alpha walks at their right hand.
function PetAIService:FormationSlot(ctx, i: number): Vector3
	local p
	if ctx.mode == "Guard" then
		local a = (i / math.max(1, ctx.count)) * math.pi * 2
		p = ctx.anchor + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
	else
		local look = ctx.look
		local right = Vector3.new(-look.Z, 0, look.X)
		if i == 1 then
			p = ctx.ownerPos + right * 4 + look * 1.5
		else
			local row = math.floor((i - 2) / 3)
			local col = (i - 2) % 3 - 1
			p = ctx.ownerPos - look * (4.5 + row * 4) + right * (col * 4.5)
		end
	end
	return Vector3.new(p.X, self:FloorY(ctx, p.X, p.Z), p.Z)
end

function PetAIService:MoveToward(ctx, pet, goal: Vector3, speed: number, stopDist: number)
	local to = Vector3.new(goal.X - pet.pos.X, 0, goal.Z - pet.pos.Z)
	local dist = to.Magnitude
	local sep = pet.sep or Vector3.zero
	if dist <= stopDist and sep.Magnitude < 0.5 then
		if ctx.now > (pet.stateHold or 0) then
			pet.state = State.Idle
		end
		return
	end
	local dir = if dist > 1e-3 then to / dist else Vector3.zero
	local move = dir * math.min(dist, speed * ctx.dt) + sep * ctx.dt * 5
	local nx, nz = pet.pos.X + move.X, pet.pos.Z + move.Z
	if not ctx.onStructure then
		nx, nz = World.ClampToValley(nx, nz, 6)
	end
	if dist > 1e-3 then
		pet.yaw = yawFrom(dir)
	end
	pet.pos = Vector3.new(nx, self:FloorY(ctx, nx, nz), nz)
	if ctx.now > (pet.stateHold or 0) then
		pet.state = State.Move
	end
end

----------------------------------------------------------------------------
-- Combat
----------------------------------------------------------------------------

function PetAIService:Engage(ctx, pet, target, slot: number)
	local now = ctx.now
	local stats = pet.stats
	local reach = stats.range + target.radius + pet.radius * 0.5
	local to = flat(target.pos - pet.pos)
	local dist = to.Magnitude

	if stats.role == "Ranged" then
		if dist > reach then
			self:MoveToward(ctx, pet, target.pos - to.Unit * reach * 0.85, stats.speed, 0.5)
			return
		elseif dist < reach * 0.35 then
			self:MoveToward(ctx, pet, pet.pos - to.Unit * 6, stats.speed, 0.5)
		end
	elseif dist > reach then
		-- Surround: each pet approaches its own angle around the target.
		local angle = (slot / math.max(1, ctx.count)) * math.pi * 2 + (target.id % 7)
		local goal = target.pos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (reach * 0.8)
		self:MoveToward(ctx, pet, goal, stats.speed, 0.5)
		return
	end

	if dist > 1e-3 then
		pet.yaw = yawFrom(to.Unit)
	end
	if now >= pet.nextAttack then
		pet.nextAttack = now + 1 / stats.attackRate
		pet.state = State.Attack
		pet.stateHold = now + 0.3
		local fruit = pet.fruitId and Fruits.List[pet.fruitId]
		local fx = if fruit then fruit.element else "Hit"
		if stats.role == "Ranged" then
			S.EntityService:Event(pet.pos, { EV.Projectile, pet.id, target.id, fx })
		end
		S.CombatService:PetBasicHit(pet, target, stats.power, fx)
	elseif now > (pet.stateHold or 0) then
		pet.state = State.Idle
	end
end

function PetAIService:TryAbility(ctx, pet, target): boolean
	local abilities = pet.stats.abilities
	for i = #abilities, 1, -1 do
		local ability = abilities[i]
		if ctx.now >= (pet.cooldowns[ability.id] or 0) and self:Cast(ctx, pet, target, ability) then
			pet.cooldowns[ability.id] = ctx.now + ability.cooldown
			pet.state = State.Ability
			pet.stateHold = ctx.now + 0.6
			S.CombatService:Text(pet, ability.name .. "!", "#FFE45C")
			return true
		end
	end
	return false
end

-- Generic ability executor. New fruits only add data to Config/Fruits.
function PetAIService:Cast(ctx, pet, target, ability): boolean
	local viewer = ctx.player.UserId
	local power = pet.stats.power
	local kind = ability.kind
	local dist = flatDist(pet.pos, target.pos)
	local boss = target.boss == true
	local function enough(n: number): boolean
		return n >= (ability.minTargets or 1) or boss
	end

	if kind == "Burst" then
		if dist > ability.radius then
			return false
		end
		if not enough(#S.ZombieService:Query(pet.pos, ability.radius, viewer)) then
			return false
		end
		S.CombatService:Burst(pet, pet.pos, ability.radius, power * ability.damageMult, ability.status, ability.fx, viewer)
		if ability.grantsAura then
			pet.aura = math.min((pet.aura or 0) + ability.grantsAura, 50)
			S.CombatService:Text(pet, "✨ +1000 AURA", "#FFD700")
		end
		return true
	elseif kind == "Cone" then
		if dist > ability.range then
			return false
		end
		local dir = flat(target.pos - pet.pos)
		local cosHalf = math.cos(math.rad(ability.angle / 2))
		local n = 0
		for _, z in S.ZombieService:Query(pet.pos, ability.range, viewer) do
			local to = flat(z.pos - pet.pos)
			if to.Magnitude < 2 or (dir.Magnitude > 0 and to.Unit:Dot(dir.Unit) >= cosHalf) then
				n += 1
			end
		end
		if not enough(n) then
			return false
		end
		pet.yaw = yawFrom(dir.Unit)
		S.CombatService:Cone(pet, pet.pos, dir, ability.range, ability.angle, power * ability.damageMult, ability.status, ability.fx, viewer)
		return true
	elseif kind == "Chain" then
		if dist > pet.stats.range + 12 then
			return false
		end
		if not enough(#S.ZombieService:Query(target.pos, ability.jumpRange, viewer)) then
			return false
		end
		S.CombatService:ChainFrom(pet, target, ability.jumps, ability.jumpRange, power * ability.damageMult, ability.status, ability.fx, true)
		return true
	elseif kind == "Dash" then
		if dist > ability.dashRange then
			return false
		end
		-- Land on the densest cluster in reach.
		local best, bestN = target, 0
		local candidates = S.ZombieService:Query(pet.pos, ability.dashRange, viewer)
		for i = 1, math.min(#candidates, 12) do
			local z = candidates[i]
			local n = #S.ZombieService:Query(z.pos, ability.radius, viewer)
			if n > bestN then
				best, bestN = z, n
			end
		end
		if not enough(bestN) then
			return false
		end
		local from = pet.pos
		local back = flat(from - best.pos)
		local landing = best.pos + (if back.Magnitude > 1e-3 then back.Unit * 2 else Vector3.zero)
		pet.pos = Vector3.new(landing.X, self:FloorY(ctx, landing.X, landing.Z), landing.Z)
		S.EntityService:Event(from, { EV.Ability, pet.id, "Dash", from.X, from.Z, 0, landing.X - from.X, landing.Z - from.Z })
		S.CombatService:Burst(pet, best.pos, ability.radius, power * ability.damageMult, ability.status, ability.fx, viewer)
		return true
	elseif kind == "Meme" then
		if dist > ability.radius then
			return false
		end
		if not enough(#S.ZombieService:Query(pet.pos, ability.radius, viewer)) then
			return false
		end
		local effect = Rng.Pick(ability.memeEffects, function(e)
			return e.weight
		end)
		S.CombatService:Text(pet, MEME_TEXT[effect.id] or effect.id, "#FF46D2")
		if effect.buff then
			pet.buff = { power = effect.buff.power, untilT = ctx.now + effect.buff.duration }
			local look = table.clone(pet.appearance)
			look.scale = (look.scale or 1) * effect.buff.size
			S.EntityService:SetAppearance(pet, look)
			S.EntityService:Event(pet.pos, { EV.Ability, pet.id, "Meme_GigaMode", pet.pos.X, pet.pos.Z, 10, 0, 0 })
		else
			S.CombatService:Burst(pet, pet.pos, ability.radius, power * effect.damageMult, effect.status, "Meme_" .. effect.id, viewer)
		end
		return true
	end
	return false
end

return PetAIService
