-- EnemyRenderer
-- Draws the enemies in YOUR lane from the server's packed snapshots.
--
-- Snapshots arrive 5 times a second. Between them, each enemy is moved
-- forward along the lane at its known speed (prediction), so movement looks
-- continuous instead of stepping. Small corrections are blended out.
-- Parts are client-only, pooled, and moved in one BulkMoveTo call per frame.
-- Damaged enemies show a health bar above them (full-health ones don't, so
-- big waves stay readable and cheap to draw).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LaneSnapshot = require(Shared:WaitForChild("LaneSnapshot"))

local FLOOR_Y = 0.4 -- top of the lane floor
local MAX_PREDICT = 0.4 -- never predict further ahead than this (seconds)
local SMOOTHING = 20 -- how fast corrections blend in (higher = snappier)
local HIDDEN = CFrame.new(0, -500, 0)
local HURT_COLOR = Color3.fromRGB(60, 10, 10)
local FLASH_COLOR = Color3.new(1, 1, 1)
local FLASH_TIME = 0.06

-- Health bars
local BAR_HEIGHT = 0.45 -- studs
local BAR_GAP = 0.9 -- studs above the enemy
local BAR_MAX_DISTANCE = 120
local BAR_SMOOTHING = 12 -- how fast the bar slides down after a hit
local BAR_FULL = Color3.fromRGB(90, 220, 90)
local BAR_HALF = Color3.fromRGB(240, 200, 50)
local BAR_LOW = Color3.fromRGB(230, 60, 40)

-- How each enemy kind looks (gray-box blocks for now)
local LOOKS = {
	[1] = { size = Vector3.new(3, 1.6, 3.5), color = Color3.fromRGB(140, 95, 55) }, -- Burrow Grub
	[2] = { size = Vector3.new(2, 5, 2), color = Color3.fromRGB(225, 220, 200) }, -- Skeleton Miner
	[3] = { size = Vector3.new(8, 10, 8), color = Color3.fromRGB(200, 50, 40) }, -- Layer Boss
}

type Visual = {
	part: BasePart,
	kind: number,
	baseX: number, -- last position the server sent
	baseZ: number,
	baseTime: number, -- when it arrived
	speed: number,
	health: number,
	flashUntil: number?, -- white hit flash
	barShown: number, -- health the bar currently shows (slides toward health)
}

type Bar = { gui: BillboardGui, fill: Frame }

local EnemyRenderer = {}

local folder: Folder
local pool: { BasePart } = {}
local active: { [number]: Visual } = {}
local bars: { [BasePart]: Bar } = {}
local removedAt: { [number]: number } = {} -- ids killed early by FX, ignored briefly
local REMOVED_IGNORE = 1 -- seconds to ignore a killed id in late snapshots
local dirX, dirZ = 0, -1

local function lookFor(kind: number)
	return LOOKS[kind] or LOOKS[1]
end

local function getPart(kind: number): BasePart
	local part = table.remove(pool)
	if not part then
		local newPart = Instance.new("Part")
		newPart.Anchored = true
		newPart.CanCollide = false
		newPart.CanQuery = false
		newPart.CanTouch = false
		newPart.CastShadow = false
		newPart.Material = Enum.Material.SmoothPlastic
		newPart.Parent = folder
		part = newPart

		-- Health bar (hidden until the enemy is hurt)
		local gui = Instance.new("BillboardGui")
		gui.Name = "HealthBar"
		gui.LightInfluence = 0
		gui.MaxDistance = BAR_MAX_DISTANCE
		gui.Enabled = false
		local back = Instance.new("Frame")
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = Color3.fromRGB(25, 20, 20)
		back.BorderSizePixel = 0
		back.Parent = gui
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = BAR_FULL
		fill.BorderSizePixel = 0
		fill.Parent = back
		gui.Parent = newPart
		bars[newPart] = { gui = gui, fill = fill }
	end
	local look = lookFor(kind)
	part.Size = look.size
	part.Color = look.color
	-- Size the bar to this kind of enemy (scale = studs, so it shrinks with distance)
	local bar = bars[part]
	bar.gui.Size = UDim2.fromScale(math.max(2, look.size.X * 1.1), BAR_HEIGHT)
	bar.gui.StudsOffset = Vector3.new(0, look.size.Y / 2 + BAR_GAP, 0)
	bar.gui.Enabled = false
	return part
end

local function releasePart(part: BasePart)
	part.CFrame = HIDDEN
	bars[part].gui.Enabled = false
	table.insert(pool, part)
end

local function barColor(health: number): Color3
	if health > 0.5 then
		return BAR_HALF:Lerp(BAR_FULL, (health - 0.5) * 2)
	end
	return BAR_LOW:Lerp(BAR_HALF, health * 2)
end

local function setBar(visual: Visual, shown: number)
	visual.barShown = shown
	local fill = bars[visual.part].fill
	fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	fill.BackgroundColor3 = barColor(shown)
end

local function targetCFrame(visual: Visual, now: number): CFrame
	local ahead = math.min(now - visual.baseTime, MAX_PREDICT) * visual.speed
	local x = visual.baseX + dirX * ahead
	local z = visual.baseZ + dirZ * ahead
	local y = FLOOR_Y + lookFor(visual.kind).size.Y / 2
	local position = Vector3.new(x, y, z)
	return CFrame.lookAt(position, position + Vector3.new(dirX, 0, dirZ))
end

local function onSnapshot(buf: buffer)
	local header = LaneSnapshot.ReadHeader(buf)
	if header.dirX ~= 0 or header.dirZ ~= 0 then
		dirX, dirZ = header.dirX, header.dirZ
	end

	local now = os.clock()
	local seen: { [number]: boolean } = {}

	for i = 0, header.count - 1 do
		local id, x, z, health, kind, speed = LaneSnapshot.ReadEntry(buf, i)
		seen[id] = true

		local killedAt = removedAt[id]
		if killedAt then
			if now - killedAt < REMOVED_IGNORE then
				continue -- this snapshot left the server before the kill
			end
			removedAt[id] = nil
		end

		local visual = active[id]
		if not visual then
			local part = getPart(kind)
			local newVisual: Visual = {
				part = part,
				kind = kind,
				baseX = x,
				baseZ = z,
				baseTime = now,
				speed = speed,
				health = 1,
				barShown = 1,
			}
			active[id] = newVisual
			part.CFrame = targetCFrame(newVisual, now)
			visual = newVisual
		else
			visual.baseX, visual.baseZ, visual.baseTime, visual.speed = x, z, now, speed
		end

		-- Darken as health drops (only touches the part when health changes)
		if math.abs(visual.health - health) > 0.01 then
			visual.health = health
			if not visual.flashUntil then
				visual.part.Color = lookFor(visual.kind).color:Lerp(HURT_COLOR, (1 - health) * 0.7)
			end
			-- First hit: show the health bar
			local bar = bars[visual.part]
			if health < 0.995 and not bar.gui.Enabled then
				bar.gui.Enabled = true
				setBar(visual, visual.barShown)
			end
		end
	end

	-- Anything missing from the snapshot died or reached the barricade
	for id, visual in active do
		if not seen[id] then
			releasePart(visual.part)
			active[id] = nil
		end
	end

	-- Forget old kill records
	for id, killedAt in removedAt do
		if now - killedAt > REMOVED_IGNORE * 2 then
			removedAt[id] = nil
		end
	end
end

local parts: { BasePart } = {}
local cframes: { CFrame } = {}

local function onRender(dt: number)
	local now = os.clock()
	local alpha = 1 - math.exp(-dt * SMOOTHING)
	table.clear(parts)
	table.clear(cframes)
	for _, visual in active do
		table.insert(parts, visual.part)
		table.insert(cframes, visual.part.CFrame:Lerp(targetCFrame(visual, now), alpha))
		if visual.flashUntil and now >= visual.flashUntil then
			visual.flashUntil = nil
			visual.part.Color = lookFor(visual.kind).color:Lerp(HURT_COLOR, (1 - visual.health) * 0.7)
		end
		-- Slide the health bar down to the real health
		if visual.barShown - visual.health > 0.002 then
			setBar(visual, visual.health + (visual.barShown - visual.health) * math.exp(-dt * BAR_SMOOTHING))
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EnemyRenderer:Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientEnemies"
	folder.Parent = workspace
end

function EnemyRenderer:Start()
	Remotes.Event("EnemySnapshot").OnClientEvent:Connect(onSnapshot)
	RunService.RenderStepped:Connect(onRender)
end

-- Remove an enemy right away (called when a kill arrives, so it doesn't
-- keep walking until the next snapshot).
function EnemyRenderer:Remove(id: number)
	local visual = active[id]
	if visual then
		releasePart(visual.part)
		active[id] = nil
	end
	removedAt[id] = os.clock()
end

-- Flash an enemy white for a moment (called when it's hit).
function EnemyRenderer:Flash(id: number)
	local visual = active[id]
	if visual then
		if not visual.flashUntil then
			visual.part.Color = FLASH_COLOR
		end
		visual.flashUntil = os.clock() + FLASH_TIME
	end
end

-- Current drawn position of an enemy, if it's on screen.
function EnemyRenderer:GetPosition(id: number): Vector3?
	local visual = active[id]
	return if visual then visual.part.Position else nil
end

-- Enemies drawn within a radius of a point (flat distance). Used by the
-- hero's swing and Fire Blast to show hits right away.
function EnemyRenderer:FindInRange(center: Vector3, radius: number): { { id: number, kind: number, position: Vector3 } }
	local found = {}
	local r2 = radius * radius
	for id, visual in active do
		local p = visual.part.Position
		local dx, dz = p.X - center.X, p.Z - center.Z
		if dx * dx + dz * dz <= r2 then
			table.insert(found, { id = id, kind = visual.kind, position = p })
		end
	end
	return found
end

-- Number of enemies currently drawn (handy for debugging)
function EnemyRenderer:Count(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

return EnemyRenderer
