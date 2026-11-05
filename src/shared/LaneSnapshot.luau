-- LaneSnapshot
-- The packed format the server uses to send a lane's state to its owner.
-- Server and client both use this module, so the format can't drift apart.
--
-- Header (17 bytes):
--   0  u16  wave
--   2  u16  barricade HP
--   4  u16  barricade max HP
--   6  u8   state (0 Intermission, 1 Running, 2 Failed)
--   7  u16  enemy count
--   9  f32  move direction X  (the way enemies walk, in world space)
--   13 f32  move direction Z
-- Each enemy (14 bytes):
--   0  u16  id
--   2  f32  world X
--   6  f32  world Z
--   10 u8   health fraction (0-255)
--   11 u8   kind (see LaneConfig.Enemies)
--   12 u16  speed x 100 (studs per second)

local LaneSnapshot = {}

LaneSnapshot.HEADER_BYTES = 17
LaneSnapshot.ENTRY_BYTES = 14
LaneSnapshot.States = { Intermission = 0, Running = 1, Failed = 2 }

export type Header = {
	wave: number,
	barricadeHp: number,
	barricadeMax: number,
	state: number,
	count: number,
	dirX: number,
	dirZ: number,
}

function LaneSnapshot.Create(count: number): buffer
	return buffer.create(LaneSnapshot.HEADER_BYTES + count * LaneSnapshot.ENTRY_BYTES)
end

function LaneSnapshot.WriteHeader(buf: buffer, h: Header)
	buffer.writeu16(buf, 0, math.clamp(h.wave, 0, 65535))
	buffer.writeu16(buf, 2, math.clamp(math.ceil(h.barricadeHp), 0, 65535))
	buffer.writeu16(buf, 4, math.clamp(h.barricadeMax, 0, 65535))
	buffer.writeu8(buf, 6, h.state)
	buffer.writeu16(buf, 7, h.count)
	buffer.writef32(buf, 9, h.dirX)
	buffer.writef32(buf, 13, h.dirZ)
end

function LaneSnapshot.ReadHeader(buf: buffer): Header
	return {
		wave = buffer.readu16(buf, 0),
		barricadeHp = buffer.readu16(buf, 2),
		barricadeMax = buffer.readu16(buf, 4),
		state = buffer.readu8(buf, 6),
		count = buffer.readu16(buf, 7),
		dirX = buffer.readf32(buf, 9),
		dirZ = buffer.readf32(buf, 13),
	}
end

-- index starts at 0
function LaneSnapshot.WriteEntry(buf: buffer, index: number, id: number, x: number, z: number, healthFraction: number, kind: number, speed: number)
	local o = LaneSnapshot.HEADER_BYTES + index * LaneSnapshot.ENTRY_BYTES
	buffer.writeu16(buf, o, id)
	buffer.writef32(buf, o + 2, x)
	buffer.writef32(buf, o + 6, z)
	buffer.writeu8(buf, o + 10, math.clamp(math.floor(healthFraction * 255 + 0.5), 0, 255))
	buffer.writeu8(buf, o + 11, kind)
	buffer.writeu16(buf, o + 12, math.clamp(math.floor(speed * 100 + 0.5), 0, 65535))
end

-- index starts at 0. Returns id, x, z, healthFraction (0-1), kind, speed
function LaneSnapshot.ReadEntry(buf: buffer, index: number): (number, number, number, number, number, number)
	local o = LaneSnapshot.HEADER_BYTES + index * LaneSnapshot.ENTRY_BYTES
	return buffer.readu16(buf, o),
		buffer.readf32(buf, o + 2),
		buffer.readf32(buf, o + 6),
		buffer.readu8(buf, o + 10) / 255,
		buffer.readu8(buf, o + 11),
		buffer.readu16(buf, o + 12) / 100
end

return LaneSnapshot
