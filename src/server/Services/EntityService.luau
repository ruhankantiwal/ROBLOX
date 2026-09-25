--[[
	EntityService: registry + replication for every simulated creature
	(pets, zombies, bosses, heist guardians).

	Entities are plain Lua tables on the server. Nothing physical exists in
	the server's Workspace for them; clients build and animate the blocks.
	That is what lets a phone render 60 zombies and 30 pets at once.

	Replication (10 Hz):
	  * EntitySpawned / EntityRemoved / EntityAppearance: reliable, rare
	  * EntitySnapshot: unreliable binary, per player, interest-managed
	    (your own pets always, everything else within INTEREST studs)
	  * CombatEvents: reliable batches of hit/ability/death FX, sent only
	    to players close enough to see them
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Protocol = require(Shared.Util.EntityProtocol)

local INTEREST = 340
local EVENT_RADIUS = 260

local EntityService = { Name = "EntityService" }

local entities: { [number]: any } = {}
local byKind: { [string]: { [number]: any } } = { Pet = {}, Zombie = {} }
local nextId = 1
local eventQueue = {}

local snapshotRemote: UnreliableRemoteEvent
local spawnRemote: RemoteEvent
local removeRemote: RemoteEvent
local appearanceRemote: RemoteEvent
local combatRemote: RemoteEvent

local function allocateId(): number
	for _ = 1, 65535 do
		local id = nextId
		nextId = if nextId >= 65535 then 1 else nextId + 1
		if not entities[id] then
			return id
		end
	end
	error("entity id space exhausted")
end

local function canSee(player: Player, e): boolean
	return e.visibleTo == nil or e.visibleTo == player.UserId
end

function EntityService:Start()
	snapshotRemote = Net.Unreliable("EntitySnapshot")
	spawnRemote = Net.Event("EntitySpawned")
	removeRemote = Net.Event("EntityRemoved")
	appearanceRemote = Net.Event("EntityAppearance")
	combatRemote = Net.Event("CombatEvents")

	Players.PlayerAdded:Connect(function(player)
		self:SendAll(player)
	end)
	for _, player in Players:GetPlayers() do
		self:SendAll(player)
	end
end

function EntityService:Describe(e)
	return {
		id = e.id,
		kind = e.kind,
		ownerId = e.ownerId,
		uid = e.uid,
		name = e.name,
		appearance = e.appearance,
		maxHp = e.maxHp,
		boss = e.boss,
		level = e.level,
		rarity = e.rarity,
		x = e.pos.X,
		y = e.pos.Y,
		z = e.pos.Z,
	}
end

function EntityService:SendAll(player: Player)
	local list = {}
	for _, e in entities do
		if canSee(player, e) then
			table.insert(list, self:Describe(e))
		end
	end
	if #list > 0 then
		spawnRemote:FireClient(player, list)
	end
end

-- Registers an entity table. Required fields: pos (Vector3), maxHp,
-- appearance. Optional: ownerId, visibleTo (userId), radius, name, boss.
function EntityService:Create(kind: string, e)
	e.id = allocateId()
	e.kind = kind
	e.state = e.state or Protocol.State.Idle
	e.yaw = e.yaw or 0
	e.effects = e.effects or {}
	e.hp = e.hp or e.maxHp
	e.radius = e.radius or 1.5
	entities[e.id] = e
	byKind[kind] = byKind[kind] or {}
	byKind[kind][e.id] = e

	local desc = { self:Describe(e) }
	if e.visibleTo then
		local player = Players:GetPlayerByUserId(e.visibleTo)
		if player then
			spawnRemote:FireClient(player, desc)
		end
	else
		spawnRemote:FireAllClients(desc)
	end
	return e
end

function EntityService:Remove(e, fx: string?)
	if not entities[e.id] or entities[e.id] ~= e then
		return
	end
	entities[e.id] = nil
	byKind[e.kind][e.id] = nil
	e.removed = true
	if e.visibleTo then
		local player = Players:GetPlayerByUserId(e.visibleTo)
		if player then
			removeRemote:FireClient(player, e.id, fx)
		end
	else
		removeRemote:FireAllClients(e.id, fx)
	end
end

function EntityService:SetAppearance(e, appearance, maxHp: number?)
	e.appearance = appearance
	if maxHp then
		e.maxHp = maxHp
	end
	if e.visibleTo then
		local player = Players:GetPlayerByUserId(e.visibleTo)
		if player then
			appearanceRemote:FireClient(player, e.id, appearance, e.maxHp)
		end
	else
		appearanceRemote:FireAllClients(e.id, appearance, e.maxHp)
	end
end

function EntityService:Get(id: number?)
	return if id then entities[id] else nil
end

function EntityService:OfKind(kind: string)
	return byKind[kind] or {}
end

-- Queue an FX/combat event for players near `pos`.
function EntityService:Event(pos: Vector3, ev: { any }, visibleTo: number?)
	table.insert(eventQueue, { pos = pos, ev = ev, visibleTo = visibleTo })
end

function EntityService:RootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root :: BasePart?
end

function EntityService:Replicate(_dt: number)
	local players = Players:GetPlayers()
	local interest2 = INTEREST * INTEREST
	local event2 = EVENT_RADIUS * EVENT_RADIUS

	for _, player in players do
		local root = self:RootOf(player)
		local center = if root then root.Position else nil
		local entries = {}
		for _, e in entities do
			if canSee(player, e) then
				local include = e.ownerId == player.UserId
				if not include and center then
					local d = e.pos - center
					include = d.X * d.X + d.Z * d.Z < interest2
				end
				if include then
					table.insert(entries, {
						id = e.id,
						x = e.pos.X,
						y = e.pos.Y,
						z = e.pos.Z,
						yaw = e.yaw,
						state = e.state,
						hp = if e.maxHp > 0 then math.clamp(e.hp / e.maxHp, 0, 1) else 0,
					})
				end
			end
		end
		local per = Protocol.MaxPerPacket
		for from = 1, #entries, per do
			snapshotRemote:FireClient(player, Protocol.Pack(entries, from, math.min(#entries, from + per - 1)))
		end

		if #eventQueue > 0 and center then
			local batch = {}
			for _, item in eventQueue do
				if item.visibleTo == nil or item.visibleTo == player.UserId then
					local d = item.pos - center
					if d.X * d.X + d.Z * d.Z < event2 then
						table.insert(batch, item.ev)
					end
				end
			end
			if #batch > 0 then
				combatRemote:FireClient(player, batch)
			end
		end
	end
	table.clear(eventQueue)
end

return EntityService
