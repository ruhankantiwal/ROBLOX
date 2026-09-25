--[[
	Wire format for entity snapshots (pets, zombies, guardians).

	The server simulates every entity at 10 Hz and sends each player a
	compact binary snapshot of the entities near them over an
	UnreliableRemoteEvent. Clients own all the parts and animation, so no
	physics or Humanoids replicate. 17 bytes per entity:

		u16 id | f32 x | f32 y | f32 z | u8 yaw | u8 state | u8 hp

	UnreliableRemoteEvent payloads are capped (~900 bytes), so snapshots are
	chunked at MaxPerPacket entities.
]]

local EntityProtocol = {}

EntityProtocol.State = {
	Idle = 0,
	Move = 1,
	Attack = 2,
	Ability = 3,
	Fainted = 4,
	Mounted = 5,
	Stunned = 6,
	Dead = 7,
	Frozen = 8,
	Carry = 9,
}

EntityProtocol.EntrySize = 17
EntityProtocol.MaxPerPacket = 48
EntityProtocol.TickRate = 10

local TAU = math.pi * 2

export type Entry = {
	id: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	state: number,
	hp: number, -- 0..1
}

function EntityProtocol.Pack(entries: { Entry }, from: number, to: number): buffer
	local count = to - from + 1
	local buf = buffer.create(1 + count * EntityProtocol.EntrySize)
	buffer.writeu8(buf, 0, count)
	local offset = 1
	for i = from, to do
		local e = entries[i]
		buffer.writeu16(buf, offset, e.id)
		buffer.writef32(buf, offset + 2, e.x)
		buffer.writef32(buf, offset + 6, e.y)
		buffer.writef32(buf, offset + 10, e.z)
		buffer.writeu8(buf, offset + 14, math.floor(((e.yaw % TAU) / TAU) * 256) % 256)
		buffer.writeu8(buf, offset + 15, e.state)
		buffer.writeu8(buf, offset + 16, math.clamp(math.floor(e.hp * 255 + 0.5), 0, 255))
		offset += EntityProtocol.EntrySize
	end
	return buf
end

function EntityProtocol.Unpack(buf: buffer, onEntry: (id: number, x: number, y: number, z: number, yaw: number, state: number, hp: number) -> ())
	local count = buffer.readu8(buf, 0)
	local offset = 1
	for _ = 1, count do
		onEntry(
			buffer.readu16(buf, offset),
			buffer.readf32(buf, offset + 2),
			buffer.readf32(buf, offset + 6),
			buffer.readf32(buf, offset + 10),
			buffer.readu8(buf, offset + 14) / 256 * TAU,
			buffer.readu8(buf, offset + 15),
			buffer.readu8(buf, offset + 16) / 255
		)
		offset += EntityProtocol.EntrySize
	end
end

-- Combat event codes, sent batched per tick on the reliable CombatEvents
-- remote as small arrays: { code, ... }.
EntityProtocol.Event = {
	Hit = 1, -- { 1, attackerId, targetId, damage, isCrit, fx }
	Ability = 2, -- { 2, casterId, fx, x, z, radius, dirX, dirZ }
	Death = 3, -- { 3, id, killerId, fx }
	Text = 4, -- { 4, id, text, colorHex }
	Projectile = 5, -- { 5, fromId, toId, fx }
	Heal = 6, -- { 6, id, amount }
	Status = 7, -- { 7, id, status, duration }
	Chain = 8, -- { 8, { id1, id2, ... }, fx }
	Beam = 9, -- { 9, fx, x1, y1, z1, x2, y2, z2 }  (turrets, world FX)
}

return EntityProtocol
