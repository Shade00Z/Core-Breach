-- FXController
-- Visual feedback that isn't UI:
--   * your barricade turns red as it takes damage and looks broken at 0
--   * mounted gear turns to face its target, with a muzzle flash and tracer
--   * killed enemies pop and throw a coin over the barricade onto your side
--   * coins sit spinning on the ground until you walk over them, then fly
--     to you (the server decides pickups; this only draws them)
-- Everything is pooled, so nothing is created or destroyed per shot.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local FXPacket = require(Shared:WaitForChild("FXPacket"))

local WOOD = Color3.fromRGB(150, 110, 70)
local DAMAGED = Color3.fromRGB(170, 40, 30)
local COIN_COLOR = Color3.fromRGB(255, 205, 50)
local HIDDEN = CFrame.new(0, -500, 0)

local TRACER_TIME = 0.07
local FLASH_TIME = 0.06
local POP_TIME = 0.15
local ARC_TIME = 0.6 -- coin flying over the barricade
local ARC_HEIGHT = 9
local COLLECT_TIME = 0.25 -- coin flying to you when picked up
local COIN_HEIGHT = 1.05 -- resting height (floor top + coin radius)
local MAX_TRACERS = 80
local MAX_MERGE_ARCS = 30
local ENEMY_AIM_HEIGHT = 1.5

type Effect = { part: BasePart, expires: number, kind: string, born: number }

-- A coin drop on the ground (or flying to its landing spot / to you)
type Coin = {
	part: BasePart,
	state: "arcing" | "resting" | "collecting",
	from: Vector3,
	to: Vector3,
	born: number,
	spin: number,
}

-- A coin that flies into an existing pile, then disappears
type MergeArc = { part: BasePart, from: Vector3, to: Vector3, born: number }

local FXController = {}

local EnemyRenderer
local SoundController
local folder: Folder
local myLane: Model?
local pools: { [string]: { BasePart } } = { tracer = {}, flash = {}, coin = {}, pop = {} }
local activeEffects: { Effect } = {}
local tracerCount = 0
local coins: { [number]: Coin } = {}
local mergeArcs: { MergeArc } = {}

------------------------------------------------------------------------
-- Pooling
------------------------------------------------------------------------

local function newPart(kind: string): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.CFrame = HIDDEN
	if kind == "flash" or kind == "pop" then
		part.Shape = Enum.PartType.Ball
	elseif kind == "coin" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.25, 1.1, 1.1)
		part.Color = COIN_COLOR
	end
	part.Parent = folder
	return part
end

local function take(kind: string): BasePart
	return table.remove(pools[kind]) or newPart(kind)
end

local function release(kind: string, part: BasePart)
	part.CFrame = HIDDEN
	table.insert(pools[kind], part)
end

local function rootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

------------------------------------------------------------------------
-- Barricade
------------------------------------------------------------------------

local function trackBarricade(barricade: BasePart)
	local lastHp = barricade:GetAttribute("HP") or 0
	local function refresh()
		local hp = barricade:GetAttribute("HP") or 0
		if hp < lastHp then
			SoundController:PlayAt(if hp <= 0 then "BarricadeBreak" else "BarricadeHit", barricade.Position)
		end
		lastHp = hp
		local maxHp = math.max(1, barricade:GetAttribute("MaxHP") or 1)
		local fraction = math.clamp(hp / maxHp, 0, 1)
		barricade.Color = DAMAGED:Lerp(WOOD, fraction)
		barricade.Transparency = if hp <= 0 then 0.7 else 0
	end
	barricade:GetAttributeChangedSignal("HP"):Connect(refresh)
	refresh()
end

local function onLane(model: Instance)
	if model:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
		return
	end
	myLane = model :: Model
	local barricade = model:WaitForChild("Barricade", 10)
	if barricade and barricade:IsA("BasePart") then
		trackBarricade(barricade)
	end
end

------------------------------------------------------------------------
-- Shots, kills and coins
------------------------------------------------------------------------

local function gearPart(slot: number): BasePart?
	if not myLane then
		return nil
	end
	local slots = myLane:FindFirstChild("Slots")
	local slotPart = slots and slots:FindFirstChild("Slot" .. slot)
	local gear = slotPart and slotPart:FindFirstChild("Gear")
	return if gear and gear:IsA("BasePart") then gear else nil
end

local function onShot(shot: FXPacket.Shot, now: number)
	local gear = gearPart(shot.slot)
	if not gear then
		return
	end
	local target = EnemyRenderer:GetPosition(shot.enemyId) or Vector3.new(shot.x, ENEMY_AIM_HEIGHT, shot.z)
	EnemyRenderer:Flash(shot.enemyId)
	-- Turn the gun toward its target
	local origin = gear.Position
	SoundController:PlayAt("Shot", origin)
	gear.CFrame = CFrame.lookAt(origin, Vector3.new(target.X, origin.Y, target.Z))
	local muzzle = origin + gear.CFrame.LookVector * (gear.Size.Z / 2)

	-- Muzzle flash
	local flash = take("flash")
	flash.Color = gear.Color
	flash.Size = Vector3.new(0.9, 0.9, 0.9)
	flash.CFrame = CFrame.new(muzzle)
	table.insert(activeEffects, { part = flash, expires = now + FLASH_TIME, kind = "flash", born = now })

	-- Tracer
	if tracerCount < MAX_TRACERS then
		local length = (target - muzzle).Magnitude
		if length > 0.5 then
			local tracer = take("tracer")
			tracerCount += 1
			tracer.Color = gear.Color
			tracer.Size = Vector3.new(0.18, 0.18, length)
			tracer.CFrame = CFrame.lookAt((muzzle + target) / 2, target)
			table.insert(activeEffects, { part = tracer, expires = now + TRACER_TIME, kind = "tracer", born = now })
		end
	end
end

local function onKill(kill: FXPacket.Kill, now: number)
	local position = EnemyRenderer:GetPosition(kill.enemyId) or Vector3.new(kill.x, ENEMY_AIM_HEIGHT, kill.z)
	EnemyRenderer:Remove(kill.enemyId)

	-- Pop
	local pop = take("pop")
	pop.Color = Color3.fromRGB(255, 240, 200)
	pop.Size = Vector3.new(1, 1, 1)
	pop.Transparency = 0
	pop.CFrame = CFrame.new(position)
	table.insert(activeEffects, { part = pop, expires = now + POP_TIME, kind = "pop", born = now })

	if kill.dropId == 0 then
		return
	end
	local landing = Vector3.new(kill.landX, COIN_HEIGHT, kill.landZ)

	if coins[kill.dropId] then
		-- Joins a pile that's already on the ground
		if #mergeArcs < MAX_MERGE_ARCS then
			local part = take("coin")
			part.CFrame = CFrame.new(position)
			table.insert(mergeArcs, { part = part, from = position, to = landing, born = now })
		end
		return
	end

	local part = take("coin")
	part.CFrame = CFrame.new(position)
	coins[kill.dropId] = {
		part = part,
		state = "arcing",
		from = position,
		to = landing,
		born = now,
		spin = math.random() * math.pi * 2,
	}
end

local function onPickup(dropId: number, now: number)
	local coin = coins[dropId]
	if not coin then
		return
	end
	coin.state = "collecting"
	coin.from = coin.part.Position
	coin.born = now
	SoundController:Play("CoinPickup")
end

local function onFX(buf: buffer)
	local now = os.clock()
	local shots, kills, pickups = FXPacket.Decode(buf)
	for _, shot in shots do
		onShot(shot, now)
	end
	for _, kill in kills do
		onKill(kill, now)
	end
	for _, dropId in pickups do
		onPickup(dropId, now)
	end
end

------------------------------------------------------------------------
-- Per-frame update
------------------------------------------------------------------------

local function arcPosition(from: Vector3, to: Vector3, t: number): Vector3
	return from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * ARC_HEIGHT, 0)
end

local function onRender(dt: number)
	local now = os.clock()
	local root = rootPosition()

	-- Short-lived effects
	local i = 1
	while i <= #activeEffects do
		local effect = activeEffects[i]
		if now >= effect.expires then
			if effect.kind == "tracer" then
				tracerCount -= 1
			end
			release(effect.kind, effect.part)
			activeEffects[i] = activeEffects[#activeEffects]
			activeEffects[#activeEffects] = nil
		else
			if effect.kind == "pop" then
				local t = (now - effect.born) / POP_TIME
				local size = 1 + 2.5 * t
				effect.part.Size = Vector3.new(size, size, size)
				effect.part.Transparency = t
			end
			i += 1
		end
	end

	-- Coins joining existing piles
	i = 1
	while i <= #mergeArcs do
		local arc = mergeArcs[i]
		local t = (now - arc.born) / ARC_TIME
		if t >= 1 then
			release("coin", arc.part)
			mergeArcs[i] = mergeArcs[#mergeArcs]
			mergeArcs[#mergeArcs] = nil
		else
			arc.part.CFrame = CFrame.new(arcPosition(arc.from, arc.to, t)) * CFrame.Angles(0, now * 10, 0)
			i += 1
		end
	end

	-- Coin drops
	for id, coin in coins do
		coin.spin += dt * 3
		if coin.state == "arcing" then
			local t = (now - coin.born) / ARC_TIME
			if t >= 1 then
				coin.state = "resting"
				coin.part.CFrame = CFrame.new(coin.to) * CFrame.Angles(0, coin.spin, 0)
			else
				coin.part.CFrame = CFrame.new(arcPosition(coin.from, coin.to, t)) * CFrame.Angles(0, now * 10, 0)
			end
		elseif coin.state == "resting" then
			local bob = math.sin(now * 3 + coin.spin) * 0.15
			coin.part.CFrame = CFrame.new(coin.to + Vector3.new(0, bob, 0)) * CFrame.Angles(0, coin.spin, 0)
		else -- collecting: fly to you
			local t = (now - coin.born) / COLLECT_TIME
			if t >= 1 or not root then
				release("coin", coin.part)
				coins[id] = nil
			else
				coin.part.CFrame = CFrame.new(coin.from:Lerp(root, t * t)) * CFrame.Angles(0, now * 14, 0)
			end
		end
	end
end

------------------------------------------------------------------------

function FXController:Init(controllers)
	EnemyRenderer = controllers.EnemyRenderer
	SoundController = controllers.SoundController
	folder = Instance.new("Folder")
	folder.Name = "ClientFX"
	folder.Parent = workspace
end

function FXController:Start()
	Remotes.Event("LaneFX").OnClientEvent:Connect(onFX)
	RunService.RenderStepped:Connect(onRender)

	local lanes = workspace:WaitForChild("Lanes")
	lanes.ChildAdded:Connect(onLane)
	for _, model in lanes:GetChildren() do
		task.spawn(onLane, model)
	end
end

-- Coins currently on the ground (handy for debugging)
function FXController:CoinCount(): number
	local n = 0
	for _ in coins do
		n += 1
	end
	return n
end

return FXController
