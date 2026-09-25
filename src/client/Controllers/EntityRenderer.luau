--[[
	EntityRenderer: draws every pet and zombie locally.

	Server sends 10 Hz snapshots; we smooth toward them every frame and pose
	blocky rigs procedurally (legs swing, tails wag, wings flap, zombies
	shamble). All parts are anchored, non-colliding and moved with ONE
	workspace:BulkMoveTo call per frame.

	Mobile LOD:
	  * models only exist within RENDER_DIST (streamed in/out, a few per frame)
	  * beyond ANIM_DIST limbs freeze and far entities update every 2nd frame
	  * particle/aura budgets come from FX.Quality()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Zombies = require(Shared.Config.Zombies)
local BlockyBuilder = require(Shared.Art.BlockyBuilder)
local Protocol = require(Shared.Util.EntityProtocol)
local Signal = require(Shared.Util.Signal)

local FX = require(script.Parent.FX)

local State = Protocol.State
local EV = Protocol.Event
local LOCAL = Players.LocalPlayer

local RENDER_DIST = 300
local ANIM_DIST = 110
local BUILDS_PER_FRAME = 4
local STALE_AFTER = 2.5

local EntityRenderer = {
	Spawned = Signal.new(),
	Removed = Signal.new(),
}

local entities: { [number]: any } = {}
local folder: Folder
local mounts: { [number]: any } = {} -- userId -> { entityId, height }
local frame = 0

local AURA_COLORS = {
	Fire = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 70, 20) },
	Ice = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 220, 255) },
	Volt = { Color3.fromRGB(255, 255, 180), Color3.fromRGB(255, 220, 40) },
	Dragon = { Color3.fromRGB(255, 180, 60), Color3.fromRGB(200, 20, 40) },
	Glitch = { Color3.fromRGB(255, 60, 220), Color3.fromRGB(60, 255, 240) },
	Gold = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 190, 20) },
}

----------------------------------------------------------------------------
-- Building models
----------------------------------------------------------------------------

local function bodyFor(appearance)
	if appearance.source == "Pet" then
		return Pets.Species[appearance.species].body, {
			scale = appearance.scale,
			variant = appearance.variant,
			fruit = appearance.fruit,
			awakened = appearance.awakened,
			mutations = appearance.mutations,
		}
	end
	return Zombies.Types[appearance.type].body, {}
end

local function addEmitter(parent: BasePart, colors, rate: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(colors[1], colors[2])
	e.LightEmission = 0.7
	e.Rate = rate * FX.Quality()
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(1.5, 4)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Size = NumberSequence.new(size, 0)
	e.Acceleration = Vector3.new(0, 4, 0)
	e.Parent = parent
	return e
end

local function build(ent)
	local body, opts = bodyFor(ent.appearance)
	local rig = BlockyBuilder.Build(body, opts)
	local model = Instance.new("Model")
	model.Name = ent.name or "Entity"
	local parts, specs = {}, {}
	local quality = FX.Quality()
	local torso: BasePart? = nil
	for i, spec in rig.parts do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = quality > 0.6 and spec.size.Magnitude > 2.5
		p.Size = spec.size
		p.Color = spec.color
		p.Material = spec.material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		parts[i] = p
		specs[i] = spec
		if spec.name == "Torso" then
			torso = p
		end
	end
	local effects = rig.effects
	if torso then
		if effects.aura and AURA_COLORS[effects.aura] then
			addEmitter(torso, AURA_COLORS[effects.aura], if effects.awakened then 22 else 12, 0.7 * (ent.appearance.scale or 1))
		end
		if effects.sparkles then
			addEmitter(torso, { Color3.new(1, 1, 1), Color3.fromRGB(255, 250, 200) }, 6, 0.4)
		end
		if effects.hearts then
			addEmitter(torso, { Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 60, 140) }, 4, 0.6)
		end
	end
	local extra = {}
	if effects.spotlight then
		local beam = Instance.new("Part")
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = Color3.fromRGB(255, 250, 200)
		beam.Transparency = 0.85
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(30, 4, 4)
		beam.Parent = model
		table.insert(extra, { part = beam, offset = CFrame.new(0, 15, 0) * CFrame.Angles(0, 0, math.pi / 2) })
	end
	if ent.boss then
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(240, 40)
		gui.StudsOffsetWorldSpace = Vector3.new(0, rig.height + 2, 0)
		gui.MaxDistance = 200
		gui.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 90, 90)
		label.Text = ("👹 %s  Lv%d"):format(ent.name or "Boss", ent.level or 1)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Parent = label
		label.Parent = gui
		gui.Adornee = torso or parts[1]
		gui.Parent = model
	end
	model.Parent = folder
	ent.model = model
	ent.parts = parts
	ent.specs = specs
	ent.rig = rig
	ent.extra = extra
	ent.effects = effects
	ent.baseColors = nil
end

local function destroyModel(ent)
	if ent.model then
		ent.model:Destroy()
	end
	ent.model = nil
	ent.parts = nil
	ent.specs = nil
	ent.extra = nil
end

----------------------------------------------------------------------------
-- Posing
----------------------------------------------------------------------------

local ANGLES = CFrame.Angles

local function groupAnim(ent, t: number, moving: number, animate: boolean)
	local offsets = {}
	if not animate then
		return offsets
	end
	local state = ent.state
	local speedK = if ent.kind == "Zombie" then 6 else 11
	local swing = math.sin(t * speedK) * 0.7 * moving
	local attack = if state == State.Attack or state == State.Ability then math.sin(math.clamp((os.clock() - (ent.stateChanged or 0)) / 0.3, 0, 1) * math.pi) else 0
	local fx = ent.effects or {}

	if fx.biped then
		offsets.LegFL = ANGLES(swing, 0, 0)
		offsets.LegFR = ANGLES(-swing, 0, 0)
		local armBob = math.sin(t * 3) * 0.12 - attack * 0.9
		offsets.ArmL = ANGLES(armBob + swing * 0.3, 0, 0)
		offsets.ArmR = ANGLES(armBob - swing * 0.3, 0, 0)
		offsets.Head = ANGLES(math.sin(t * 2.1) * 0.1, math.sin(t * 1.3) * 0.2, math.sin(t * 1.7) * 0.15)
	else
		offsets.LegFL = ANGLES(swing, 0, 0)
		offsets.LegBR = ANGLES(swing, 0, 0)
		offsets.LegFR = ANGLES(-swing, 0, 0)
		offsets.LegBL = ANGLES(-swing, 0, 0)
		offsets.Head = ANGLES(-attack * 0.5 + math.sin(t * 2) * 0.05, 0, 0)
		offsets.Tail = ANGLES(0.2, math.sin(t * (6 + moving * 6)) * 0.5, 0)
	end
	if fx.wings then
		local flap = math.sin(t * (if moving > 0.3 or ent.state == State.Ability then 16 else 4)) * (0.35 + moving * 0.4)
		offsets.WingL = ANGLES(0, 0, -0.35 - flap)
		offsets.WingR = ANGLES(0, 0, 0.35 + flap)
	end
	if fx.halo then
		offsets.Halo = ANGLES(0, t * 3, 0)
	end
	if fx.hands67 then
		local six = math.sin(t * 7)
		offsets.HandL = CFrame.new(0, six * 0.5, 0)
		offsets.HandR = CFrame.new(0, -six * 0.5, 0)
	end
	return offsets
end

local function rootPose(ent, t: number, moving: number): CFrame
	local cf = CFrame.new(ent.pos) * ANGLES(0, ent.yaw, 0)
	local state = ent.state
	if state == State.Fainted then
		return cf * CFrame.new(0, 0.2, 0) * ANGLES(0, 0, math.pi / 2) * CFrame.new(0, -0.6, 0)
	end
	local fx = ent.effects or {}
	local bob = math.abs(math.sin(t * 11)) * 0.25 * moving
	if fx.hop then
		bob = math.abs(math.sin(t * 9)) * 0.6 * moving
	end
	local lunge = 0
	if state == State.Attack then
		lunge = math.sin(math.clamp((os.clock() - (ent.stateChanged or 0)) / 0.3, 0, 1) * math.pi) * 0.9
	end
	cf *= CFrame.new(0, bob, -lunge)
	if fx.jitter then
		cf *= CFrame.new((math.random() - 0.5) * 0.15, 0, (math.random() - 0.5) * 0.15)
	end
	if ent.kind == "Zombie" and moving > 0.1 then
		cf *= ANGLES(0.08, 0, math.sin(t * 3) * 0.06)
	end
	return cf
end

----------------------------------------------------------------------------
-- Frame loop
----------------------------------------------------------------------------

local tintTimer = 0

local function mountedPose(ent): boolean
	local info = ent.mountedBy and mounts[ent.mountedBy]
	if not info or info.entityId ~= ent.id then
		return false
	end
	local player = Players:GetPlayerByUserId(ent.mountedBy)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return false
	end
	local feet = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	ent.pos = Vector3.new(root.Position.X, feet, root.Position.Z)
	local look = root.CFrame.LookVector
	ent.yaw = math.atan2(-look.X, -look.Z)
	ent.moving = math.clamp(Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude / 20, 0, 1)
	return true
end

local function step(dt: number)
	frame += 1
	local camera = workspace.CurrentCamera
	local camPos = camera.CFrame.Position
	local now = os.clock()
	local alpha = 1 - math.exp(-dt * 12)
	local builds = 0
	local partList, cfList = {}, {}
	tintTimer += dt
	local doTint = tintTimer > 0.1
	if doTint then
		tintTimer = 0
	end

	for _, ent in entities do
		-- smoothing (mounted pets snap to their rider)
		if not mountedPose(ent) then
			local prev = ent.pos
			ent.pos = ent.pos:Lerp(ent.targetPos, alpha)
			local dy = (ent.targetYaw - ent.yaw + math.pi) % (math.pi * 2) - math.pi
			ent.yaw += dy * alpha
			local speed = Vector3.new(ent.pos.X - prev.X, 0, ent.pos.Z - prev.Z).Magnitude / math.max(dt, 1e-3)
			ent.moving = math.clamp(speed / 12, 0, 1)
		end

		local dist = (ent.pos - camPos).Magnitude
		local stale = now - ent.lastUpdate > STALE_AFTER and ent.ownerId ~= LOCAL.UserId and not ent.mountedBy
		if dist > RENDER_DIST or stale then
			if ent.model then
				destroyModel(ent)
			end
		else
			if not ent.model and builds < BUILDS_PER_FRAME then
				builds += 1
				build(ent)
			end
			if ent.model and ent.parts and (dist < ANIM_DIST or (frame + ent.id) % 2 == 0) then
				local animate = dist < ANIM_DIST
				local t = now + ent.id * 0.37
				local root = rootPose(ent, t, ent.moving)
				local offsets = groupAnim(ent, t, ent.moving, animate)
				local groups = ent.rig.groups
				local groupCF = {}
				for name, pivot in groups do
					local off = offsets[name]
					groupCF[name] = if off then root * pivot * off else root * pivot
				end
				for i, part in ent.parts do
					local spec = ent.specs[i]
					table.insert(partList, part)
					table.insert(cfList, groupCF[spec.group] * spec.localCF)
				end
				for _, x in ent.extra do
					table.insert(partList, x.part)
					table.insert(cfList, root * x.offset)
				end

				-- colour effects
				if doTint then
					local fx = ent.effects
					if fx.rainbow then
						local hue = (now * 0.25 + ent.id * 0.1) % 1
						for i, part in ent.parts do
							if ent.specs[i].role == "main" or ent.specs[i].role == "head" then
								part.Color = Color3.fromHSV(hue, 0.65, 1)
							end
						end
					end
					if fx.glitch and math.random() < 0.15 then
						local p = ent.parts[math.random(1, #ent.parts)]
						p.Color = Color3.fromHSV(math.random(), 1, 1)
					end
					if ent.flashUntil and now > ent.flashUntil then
						ent.flashUntil = nil
						for i, part in ent.parts do
							part.Color = ent.specs[i].color
						end
					end
					local frozen = ent.state == State.Frozen
					if frozen ~= (ent.frozenTint == true) then
						ent.frozenTint = frozen
						for i, part in ent.parts do
							part.Color = if frozen then ent.specs[i].color:Lerp(Color3.fromRGB(170, 230, 255), 0.7) else ent.specs[i].color
						end
					end
				end
			end
		end
	end
	if #partList > 0 then
		workspace:BulkMoveTo(partList, cfList, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------------
-- Network handlers
----------------------------------------------------------------------------

local function addEntity(desc)
	local existing = entities[desc.id]
	if existing then
		destroyModel(existing)
	end
	local pos = Vector3.new(desc.x, desc.y, desc.z)
	local ent = {
		id = desc.id,
		kind = desc.kind,
		ownerId = desc.ownerId,
		uid = desc.uid,
		name = desc.name,
		appearance = desc.appearance,
		maxHp = desc.maxHp,
		boss = desc.boss,
		level = desc.level,
		rarity = desc.rarity,
		pos = pos,
		targetPos = pos,
		yaw = 0,
		targetYaw = 0,
		state = State.Idle,
		hp = 1,
		moving = 0,
		lastUpdate = os.clock(),
	}
	for userId, info in mounts do
		if info.entityId == desc.id then
			ent.mountedBy = userId
		end
	end
	entities[desc.id] = ent
	EntityRenderer.Spawned:Fire(ent)
end

local function removeEntity(id: number, fx: string?)
	local ent = entities[id]
	if not ent then
		return
	end
	entities[id] = nil
	if ent.model and fx and fx:sub(1, 6) == "Death:" and ent.parts then
		local parts = ent.parts
		for _, x in ent.extra or {} do
			x.part:Destroy()
		end
		for _, child in ent.model:GetDescendants() do
			if child:IsA("BillboardGui") or child:IsA("ParticleEmitter") then
				child:Destroy()
			end
		end
		FX.DeathExplosion(parts, ent.pos + Vector3.new(0, 2, 0), fx:sub(7))
		ent.model.Parent = nil
		task.delay(3, function()
			if ent.model then
				ent.model:Destroy()
			end
		end)
	else
		destroyModel(ent)
	end
	EntityRenderer.Removed:Fire(ent)
end

local function flash(ent)
	if not ent.parts then
		return
	end
	ent.flashUntil = os.clock() + 0.08
	for i = 1, math.min(3, #ent.parts) do
		ent.parts[i].Color = Color3.new(1, 1, 1)
	end
end

local function colorFromHex(hex: string?): Color3
	local ok, c = pcall(Color3.fromHex, hex or "#FFFFFF")
	return if ok then c else Color3.new(1, 1, 1)
end

local function headPos(ent): Vector3
	local h = if ent.rig then ent.rig.height else 3
	return ent.pos + Vector3.new(0, h + 0.5, 0)
end

local function onCombat(batch)
	for _, ev in batch do
		local code = ev[1]
		if code == EV.Hit then
			local target = entities[ev[3]]
			if target then
				flash(target)
				local attacker = entities[ev[2]]
				local color = FX.ElementColors[ev[6]] or Color3.new(1, 1, 1)
				local mine = (attacker and attacker.ownerId == LOCAL.UserId) or target.ownerId == LOCAL.UserId
				if mine or target.boss or FX.Quality() > 0.7 then
					FX.Damage(headPos(target), ev[4], ev[5], if target.kind == "Pet" then Color3.fromRGB(255, 110, 110) else color)
				end
				if ev[6] ~= "" and ev[6] ~= "Hit" and ev[6] ~= "Claw" then
					FX.Burst(target.pos + Vector3.new(0, 1.5, 0), color, 3, 3)
				end
			end
		elseif code == EV.Ability then
			local caster = entities[ev[2]]
			local pos = Vector3.new(ev[4], if caster then caster.pos.Y else 0, ev[5])
			if not caster then
				local root = FX.LocalPlayerPosition()
				pos = Vector3.new(ev[4], if root then root.Y - 3 else 0, ev[5])
			end
			FX.Ability(ev[3], pos, ev[6], Vector3.new(ev[7], 0, ev[8]), caster ~= nil and caster.ownerId == LOCAL.UserId)
		elseif code == EV.Text then
			local ent = entities[ev[2]]
			if ent then
				FX.Text(headPos(ent) + Vector3.new(0, 1, 0), ev[3], colorFromHex(ev[4]), true)
			end
		elseif code == EV.Projectile then
			local from, to = entities[ev[2]], entities[ev[3]]
			if from and to then
				FX.Projectile(from.pos + Vector3.new(0, 1.5, 0), to.pos + Vector3.new(0, 1.5, 0), FX.ElementColors[ev[4]] or Color3.new(1, 1, 1))
			end
		elseif code == EV.Heal then
			local ent = entities[ev[2]]
			if ent then
				FX.Text(headPos(ent), "+" .. tostring(ev[3]), FX.ElementColors.Heal)
			end
		elseif code == EV.Chain then
			local points = {}
			for _, id in ev[2] do
				local ent = entities[id]
				if ent then
					table.insert(points, ent.pos + Vector3.new(0, 2, 0))
				end
			end
			if #points >= 2 then
				FX.Lightning(points, FX.ElementColors.Volt)
			end
		elseif code == EV.Beam then
			local from = Vector3.new(ev[3], ev[4], ev[5])
			local to = Vector3.new(ev[6], ev[7], ev[8])
			if ev[2] == "CoreHit" then
				FX.Burst(from, Color3.fromRGB(255, 60, 90), 5, 4)
			elseif ev[2] == "DefenseBroken" then
				FX.Burst(from, Color3.fromRGB(200, 170, 120), 12, 6)
			else
				FX.Beam(from, to, if ev[2] == "BlazeCannon" then FX.ElementColors.Fire else FX.ElementColors.Turret, 0.6)
				FX.Burst(to, FX.ElementColors.Turret, 3, 3)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Public
----------------------------------------------------------------------------

function EntityRenderer.Start()
	folder = Instance.new("Folder")
	folder.Name = "ClientEntities"
	folder.Parent = workspace

	Net.Event("EntitySpawned").OnClientEvent:Connect(function(list)
		for _, desc in list do
			addEntity(desc)
		end
	end)
	Net.Event("EntityRemoved").OnClientEvent:Connect(removeEntity)
	Net.Event("EntityAppearance").OnClientEvent:Connect(function(id, appearance, maxHp)
		local ent = entities[id]
		if ent then
			ent.appearance = appearance
			ent.maxHp = maxHp or ent.maxHp
			destroyModel(ent)
		end
	end)
	Net.Unreliable("EntitySnapshot").OnClientEvent:Connect(function(buf)
		local now = os.clock()
		Protocol.Unpack(buf, function(id, x, y, z, yaw, state, hp)
			local ent = entities[id]
			if ent then
				ent.targetPos = Vector3.new(x, y, z)
				ent.targetYaw = yaw
				if ent.state ~= state then
					ent.state = state
					ent.stateChanged = now
				end
				ent.hp = hp
				if ent.lastUpdate and now - ent.lastUpdate > STALE_AFTER then
					ent.pos = ent.targetPos -- re-entered interest range: snap
				end
				ent.lastUpdate = now
			end
		end)
	end)
	Net.Event("CombatEvents").OnClientEvent:Connect(onCombat)
	Net.Event("MountState").OnClientEvent:Connect(function(userId, info)
		for _, ent in entities do
			if ent.mountedBy == userId then
				ent.mountedBy = nil
			end
		end
		mounts[userId] = info
		if info then
			local ent = entities[info.entityId]
			if ent then
				ent.mountedBy = userId
			end
		end
	end)

	RunService.PreRender:Connect(step)
end

function EntityRenderer.Get(id: number)
	return entities[id]
end

function EntityRenderer.All()
	return entities
end

-- The local player's pet entity for an inventory uid.
function EntityRenderer.PetByUid(uid: string)
	for _, ent in entities do
		if ent.kind == "Pet" and ent.uid == uid and ent.ownerId == LOCAL.UserId then
			return ent
		end
	end
	return nil
end

-- Nearest living boss the local player can see (for the boss bar).
function EntityRenderer.NearestBoss(maxDist: number)
	local root = FX.LocalPlayerPosition()
	if not root then
		return nil
	end
	local best, bestD = nil, maxDist
	for _, ent in entities do
		if ent.boss and ent.state ~= State.Dead then
			local d = (ent.pos - root).Magnitude
			if d < bestD then
				best, bestD = ent, d
			end
		end
	end
	return best
end

-- Raycast-free picking for "tap a zombie to focus": nearest zombie to a
-- screen point.
function EntityRenderer.PickZombie(screenPos: Vector2, radiusPx: number)
	local camera = workspace.CurrentCamera
	local best, bestD = nil, radiusPx
	for _, ent in entities do
		if ent.kind == "Zombie" and ent.model then
			local p, onScreen = camera:WorldToViewportPoint(ent.pos + Vector3.new(0, 2.5, 0))
			if onScreen then
				local d = (Vector2.new(p.X, p.Y) - screenPos).Magnitude
				if d < bestD then
					best, bestD = ent, d
				end
			end
		end
	end
	return best
end


return EntityRenderer
