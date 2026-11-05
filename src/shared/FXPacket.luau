-- FXPacket
-- Packed format for the LaneFX remote, batched about 20 times a second:
--   shots    for tracers
--   kills    for pops and coin drops landing on your side of the barricade
--   pickups  coin drops you collected (they fly to you)
-- Server and client both use this module so the format can't drift apart.
--
-- Header (6 bytes): 0 u16 shots, 2 u16 kills, 4 u16 pickups
-- Shot (11 bytes):  0 u8 slot, 1 u16 enemy id, 3 f32 x, 7 f32 z
-- Kill (29 bytes):  0 u16 enemy id, 2 f32 x, 6 f32 z, 10 u8 kind,
--                   11 u16 drop id (0 = no coins), 13 f32 land x, 17 f32 land z,
--                   21 f64 drop value
-- Pickup (2 bytes): 0 u16 drop id

local FXPacket = {}

FXPacket.HEADER = 6
FXPacket.SHOT = 11
FXPacket.KILL = 29
FXPacket.PICKUP = 2

export type Shot = { slot: number, enemyId: number, x: number, z: number }
export type Kill = {
	enemyId: number,
	x: number,
	z: number,
	kind: number,
	dropId: number,
	landX: number,
	landZ: number,
	value: number,
}

function FXPacket.Encode(shots: { Shot }, kills: { Kill }, pickups: { number }): buffer
	local buf = buffer.create(FXPacket.HEADER + #shots * FXPacket.SHOT + #kills * FXPacket.KILL + #pickups * FXPacket.PICKUP)
	buffer.writeu16(buf, 0, #shots)
	buffer.writeu16(buf, 2, #kills)
	buffer.writeu16(buf, 4, #pickups)
	local o = FXPacket.HEADER
	for _, s in shots do
		buffer.writeu8(buf, o, s.slot)
		buffer.writeu16(buf, o + 1, s.enemyId)
		buffer.writef32(buf, o + 3, s.x)
		buffer.writef32(buf, o + 7, s.z)
		o += FXPacket.SHOT
	end
	for _, k in kills do
		buffer.writeu16(buf, o, k.enemyId)
		buffer.writef32(buf, o + 2, k.x)
		buffer.writef32(buf, o + 6, k.z)
		buffer.writeu8(buf, o + 10, k.kind)
		buffer.writeu16(buf, o + 11, k.dropId)
		buffer.writef32(buf, o + 13, k.landX)
		buffer.writef32(buf, o + 17, k.landZ)
		buffer.writef64(buf, o + 21, k.value)
		o += FXPacket.KILL
	end
	for _, id in pickups do
		buffer.writeu16(buf, o, id)
		o += FXPacket.PICKUP
	end
	return buf
end

function FXPacket.Decode(buf: buffer): ({ Shot }, { Kill }, { number })
	local shotCount = buffer.readu16(buf, 0)
	local killCount = buffer.readu16(buf, 2)
	local pickupCount = buffer.readu16(buf, 4)
	local shots, kills, pickups = table.create(shotCount), table.create(killCount), table.create(pickupCount)
	local o = FXPacket.HEADER
	for i = 1, shotCount do
		shots[i] = {
			slot = buffer.readu8(buf, o),
			enemyId = buffer.readu16(buf, o + 1),
			x = buffer.readf32(buf, o + 3),
			z = buffer.readf32(buf, o + 7),
		}
		o += FXPacket.SHOT
	end
	for i = 1, killCount do
		kills[i] = {
			enemyId = buffer.readu16(buf, o),
			x = buffer.readf32(buf, o + 2),
			z = buffer.readf32(buf, o + 6),
			kind = buffer.readu8(buf, o + 10),
			dropId = buffer.readu16(buf, o + 11),
			landX = buffer.readf32(buf, o + 13),
			landZ = buffer.readf32(buf, o + 17),
			value = buffer.readf64(buf, o + 21),
		}
		o += FXPacket.KILL
	end
	for i = 1, pickupCount do
		pickups[i] = buffer.readu16(buf, o)
		o += FXPacket.PICKUP
	end
	return shots, kills, pickups
end

return FXPacket
