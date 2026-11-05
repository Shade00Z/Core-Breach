-- GearService
-- Owned gear, which gear sits in which wall slot, gear levels, and shooting.
--
-- Getting gear (GearService:Give):
--   * Gear you already own gains a copy toward its next level instead
--     (Lv N -> N+1 takes N copies; each level adds damage, see GearData).
--   * New gear goes in an empty open slot, or replaces your weakest mounted
--     gear if it's stronger (the old gear stays owned), or waits unmounted.
--
-- Shooting: every frame each gear counts down its cooldown. When ready it
-- targets the enemy closest to the barricade, anywhere in the lane, so it
-- starts firing as soon as an enemy leaves the breach. Damage happens on
-- the server; tracers go to the client through FXBatcher.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearData = require(Shared:WaitForChild("GearData"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local LaneBuilder = require(Modules:WaitForChild("LaneBuilder"))
local GearVisuals = require(Modules:WaitForChild("GearVisuals"))
local FXBatcher = require(Modules:WaitForChild("FXBatcher"))

local SLOT_PREFERENCE = { 1, 4, 2, 5, 3, 6 } -- fill front slots first
local SLOT_COLOR_LOCKED = Color3.fromRGB(85, 80, 75)
local SLOT_COLOR_OPEN = Color3.fromRGB(205, 205, 200)
local MAX_SHOTS_PER_FRAME = 4 -- per gear, for very fast guns on slow frames

type Mounted = {
	slot: number,
	gear: GearData.Gear,
	level: number,
	lateral: number,
	dist: number,
	cooldown: number,
}

type State = {
	lane: any,
	mounted: { [number]: Mounted },
}

export type Ownership = {
	level: number,
	copies: number,
	needed: number, -- copies needed for the next level
	maxed: boolean,
}

local GearService = {}

local DataService
local WaveService
local EconomyService
local states: { [Player]: State } = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function slotPart(lane, slotIndex: number): BasePart
	return lane.model.Slots["Slot" .. slotIndex]
end

local function refreshSlot(lane, slotIndex: number, unlocked: boolean)
	local part = slotPart(lane, slotIndex)
	part:SetAttribute("Unlocked", unlocked)
	part.Color = if unlocked then SLOT_COLOR_OPEN else SLOT_COLOR_LOCKED
end

local function levelOf(data, gearId: string): number
	local owned = data.owned[gearId]
	return if owned then owned.level else 1
end

local function totalDps(state: State): number
	local total = 0
	for _, m in state.mounted do
		total += GearData.DPS(m.gear, m.level)
	end
	return total
end

local function pushDps(player: Player, state: State?)
	if state then
		EconomyService:PushStats(player, { dps = totalDps(state) })
	end
end

local function mountedSlotOf(data, gearId: string): number?
	for key, id in data.slots do
		if id == gearId then
			return tonumber(key)
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Mounting
------------------------------------------------------------------------

local function unmount(state: State, slotIndex: number)
	local part = slotPart(state.lane, slotIndex)
	local old = part:FindFirstChild("Gear")
	if old then
		old:Destroy()
	end
	part:SetAttribute("GearId", "")
	state.mounted[slotIndex] = nil
end

local function mount(state: State, slotIndex: number, gearId: string, level: number): boolean
	local gear = GearData.Get(gearId)
	if not gear then
		warn("[GearService] Unknown gear", gearId)
		return false
	end
	unmount(state, slotIndex)

	local lane = state.lane
	local part = slotPart(lane, slotIndex)
	GearVisuals.Build(gear, level, part, lane.origin.LookVector)
	part:SetAttribute("GearId", gearId)

	local lateral, _, dist = LaneBuilder.SlotLocal(slotIndex)
	state.mounted[slotIndex] = {
		slot = slotIndex,
		gear = gear,
		level = level,
		lateral = lateral,
		dist = dist,
		cooldown = 0,
	}
	return true
end

-- Puts owned gear on the wall if there's room or it beats the weakest
-- mounted gear. Returns a message for the player (or nil if nothing changed).
local function autoMount(player: Player, gearId: string): string?
	local data = DataService:Get(player)
	local state = states[player]
	local gear = GearData.Get(gearId)
	if not gear or mountedSlotOf(data, gearId) then
		return nil
	end
	local myDps = GearData.DPS(gear, levelOf(data, gearId))

	local function place(slotIndex: number)
		data.slots[tostring(slotIndex)] = gearId
		if state then
			mount(state, slotIndex, gearId, levelOf(data, gearId))
		end
	end

	for _, slotIndex in SLOT_PREFERENCE do
		local key = tostring(slotIndex)
		if data.unlockedSlots[key] and not data.slots[key] then
			place(slotIndex)
			return gear.name .. " mounted!"
		end
	end

	local weakestSlot, weakestDps = nil, math.huge
	for _, slotIndex in SLOT_PREFERENCE do
		local key = tostring(slotIndex)
		local mountedId = data.slots[key]
		local mountedGear = mountedId and GearData.Get(mountedId)
		if data.unlockedSlots[key] and mountedGear then
			local dps = GearData.DPS(mountedGear, levelOf(data, mountedId))
			if dps < weakestDps then
				weakestSlot, weakestDps = slotIndex, dps
			end
		end
	end

	if weakestSlot and myDps > weakestDps then
		local oldGear = GearData.Get(data.slots[tostring(weakestSlot)])
		place(weakestSlot)
		return gear.name .. " replaced " .. (if oldGear then oldGear.name else "your weakest gear") .. " on the wall!"
	end

	return nil
end

local function setupLane(lane)
	local player = lane.owner
	local data = DataService:Get(player)
	local state: State = { lane = lane, mounted = {} }
	states[player] = state

	for slotIndex = 1, 6 do
		refreshSlot(lane, slotIndex, data.unlockedSlots[tostring(slotIndex)] == true)
	end
	for key, gearId in data.slots do
		local slotIndex = tonumber(key)
		if slotIndex and data.unlockedSlots[key] then
			mount(state, slotIndex, gearId, levelOf(data, gearId))
		end
	end
	pushDps(player, state)
end

------------------------------------------------------------------------
-- Shooting
------------------------------------------------------------------------

-- The enemy closest to the barricade, anywhere in the lane.
local function findTarget(lane)
	local best, bestDist = nil, math.huge
	for _, enemy in lane.enemies do
		if enemy.dist < bestDist then
			best, bestDist = enemy, enemy.dist
		end
	end
	return best
end

local function fire(state: State, m: Mounted, target)
	local lane = state.lane
	local damage = GearData.Damage(m.gear, m.level)

	-- Work out splash victims before dealing damage (kills remove enemies)
	local victims = { target.id }
	if m.gear.splash > 0 then
		local radiusSq = m.gear.splash * m.gear.splash
		for id, enemy in lane.enemies do
			if id ~= target.id then
				local dx = enemy.lateral - target.lateral
				local dd = enemy.dist - target.dist
				if dx * dx + dd * dd <= radiusSq then
					table.insert(victims, id)
				end
			end
		end
	end

	local position = lane.origin * Vector3.new(target.lateral, 0, -target.dist)
	FXBatcher.Shot(lane.owner, m.slot, target.id, position.X, position.Z)

	for _, id in victims do
		WaveService:DamageEnemy(lane, id, damage)
	end
end

local function stepState(state: State, dt: number)
	local lane = state.lane
	if lane.state ~= "Running" then
		return
	end
	for _, m in state.mounted do
		m.cooldown -= dt
		local shots = 0
		while m.cooldown <= 0 and shots < MAX_SHOTS_PER_FRAME do
			local target = findTarget(lane)
			if not target then
				m.cooldown = 0
				break
			end
			fire(state, m, target)
			m.cooldown += 1 / m.gear.fireRate
			shots += 1
		end
	end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

-- What the player owns of this gear, or nil if they don't own it.
function GearService:GetOwnership(player: Player, gearId: string): Ownership?
	local owned = DataService:Get(player).owned[gearId]
	if not owned then
		return nil
	end
	local maxed = owned.level >= GearData.Levels.MaxLevel
	return {
		level = owned.level,
		copies = owned.copies,
		needed = if maxed then 0 else GearData.CopiesToLevelUp(owned.level),
		maxed = maxed,
	}
end

-- Can the player receive this gear? (false when it's already max level)
function GearService:CanReceive(player: Player, gearId: string): (boolean, string?)
	local ownership = self:GetOwnership(player, gearId)
	if ownership and ownership.maxed then
		local gear = GearData.Get(gearId)
		return false, (if gear then gear.name else "That gear") .. " is already max level."
	end
	return true, nil
end

-- Gives a player a piece of gear. Returns a short message for the player.
function GearService:Give(player: Player, gearId: string): string
	local gear = GearData.Get(gearId)
	if not gear then
		return "That gear doesn't exist."
	end
	local data = DataService:Get(player)
	local state = states[player]
	local owned = data.owned[gearId]

	if not owned then
		data.owned[gearId] = { level = 1, copies = 0 }
		local message = autoMount(player, gearId)
		pushDps(player, state)
		return message or (gear.name .. " added to your collection. Your mounted gear is stronger.")
	end

	-- Already owned: add a copy toward the next level
	if owned.level >= GearData.Levels.MaxLevel then
		return gear.name .. " is already max level."
	end
	owned.copies += 1
	local message
	local needed = GearData.CopiesToLevelUp(owned.level)
	if owned.copies >= needed then
		owned.level += 1
		owned.copies = 0
		message = gear.name .. " leveled up to " .. (if owned.level >= GearData.Levels.MaxLevel then "MAX" else ("Lv " .. owned.level)) .. "!"
	else
		message = gear.name .. " +1 copy (" .. owned.copies .. "/" .. needed .. " to Lv " .. (owned.level + 1) .. ")"
	end

	-- Update it on the wall, or mount it if it's now strong enough
	local slotIndex = mountedSlotOf(data, gearId)
	if slotIndex and state and state.mounted[slotIndex] then
		state.mounted[slotIndex].level = owned.level
		local model = slotPart(state.lane, slotIndex):FindFirstChild("Gear")
		if model then
			GearVisuals.SetLevel(model, owned.level)
		end
	elseif not slotIndex then
		local mountMessage = autoMount(player, gearId)
		if mountMessage then
			message ..= " " .. mountMessage
		end
	end
	pushDps(player, state)
	return message
end

-- Opens a wall slot (used by digging in week 3).
function GearService:UnlockSlot(player: Player, slotIndex: number)
	local data = DataService:Get(player)
	data.unlockedSlots[tostring(slotIndex)] = true
	local state = states[player]
	if state then
		refreshSlot(state.lane, slotIndex, true)
	end
end

function GearService:GetTotalDps(player: Player): number
	local state = states[player]
	return if state then totalDps(state) else 0
end

function GearService:Init(services)
	DataService = services.DataService
	WaveService = services.WaveService
	EconomyService = services.EconomyService
end

function GearService:Start()
	WaveService.LaneCreated:Connect(setupLane)
	WaveService.LaneRemoved:Connect(function(lane)
		states[lane.owner] = nil
	end)
	for _, lane in WaveService.Lanes do
		if not states[lane.owner] then
			setupLane(lane)
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, state in states do
			stepState(state, dt)
		end
	end)
end

return GearService
