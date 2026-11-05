-- WaveService
-- Runs every player's lane: spawns waves, moves enemies, damages the barricade.
--
-- Enemies are plain data (tables of numbers), never Humanoids or Parts on the
-- server. A few times a second the server packs each lane into a buffer
-- (format in shared/LaneSnapshot) and sends it ONLY to that lane's owner.
-- The client draws the enemies (client/Controllers/EnemyRenderer).
--
-- Leaks: an enemy reaching the barricade deals damage based on the share of
-- the wave's HP it still carries (see LaneConfig.LeakDamage). Kill more of a
-- wave and less of it gets through. With no gear, wave 1 breaks the barricade.
--
-- Week 2: GearService calls WaveService:DamageEnemy() and gets kill callbacks
-- through WaveService.EnemyKilled.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))
local LaneSnapshot = require(Shared:WaitForChild("LaneSnapshot"))
local DebugConfig = require(Shared:WaitForChild("DebugConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local LaneBuilder = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("LaneBuilder"))

export type Enemy = {
	id: number,
	kind: number,
	hp: number,
	maxHp: number,
	dist: number, -- studs up the lane from the player end
	lateral: number, -- studs left/right of the lane center
	speed: number,
}

type LaneState = "Intermission" | "Running" | "Failed"

export type Lane = {
	index: number,
	owner: Player,
	model: Model,
	origin: CFrame,
	moveDir: Vector3, -- world direction enemies walk (toward the player end)
	debug: DebugConfig.Settings,
	wave: number,
	waveTotalHp: number,
	state: LaneState,
	stateTimer: number,
	barricadeHp: number,
	enemies: { [number]: Enemy },
	spawnQueue: { Enemy },
	spawnTimer: number,
	spawnInterval: number,
	sendTimer: number,
	nextId: number,
}

local WaveService = {}
WaveService.Lanes = {} :: { [Player]: Lane }

-- Events other services listen to:
--   EnemyKilled(lane, enemy)  an enemy was killed (coins, loot)
--   LaneCreated(lane)         a player's lane was built
--   LaneRemoved(lane)         a player's lane was removed
--   WaveStarted(lane)         a wave began (luck, stash expiry)
-- (Signals, not BindableEvents: BindableEvents would pass a copy of the lane.)
local killedEvent = Signal.new()
local laneCreatedEvent = Signal.new()
local laneRemovedEvent = Signal.new()
local waveStartedEvent = Signal.new()
WaveService.EnemyKilled = killedEvent
WaveService.LaneCreated = laneCreatedEvent
WaveService.LaneRemoved = laneRemovedEvent
WaveService.WaveStarted = waveStartedEvent

local lanesFolder: Folder
local usedIndexes: { [number]: boolean } = {}
local snapshotRemote: RemoteEvent
local notifyRemote: RemoteEvent

------------------------------------------------------------------------
-- Waves
------------------------------------------------------------------------

local function newEnemy(lane: Lane, kind: number, hp: number): Enemy
	lane.nextId = (lane.nextId % 65535) + 1
	local stats = LaneConfig.Enemies[kind]
	local margin = LaneConfig.Width / 2 - 3
	return {
		id = lane.nextId,
		kind = kind,
		hp = hp,
		maxHp = hp,
		dist = LaneConfig.Length,
		lateral = (math.random() * 2 - 1) * margin,
		speed = stats.speed * (0.9 + math.random() * 0.2),
	}
end

local function setBarricade(lane: Lane, hp: number)
	lane.barricadeHp = hp
	lane.model.Barricade:SetAttribute("HP", math.max(0, math.ceil(hp)))
end

local function startWave(lane: Lane)
	table.clear(lane.enemies)
	table.clear(lane.spawnQueue)
	setBarricade(lane, LaneConfig.BarricadeMaxHP)
	lane.model:SetAttribute("Wave", lane.wave)

	local wave = lane.wave
	local totalHp = Config.WaveHP(wave)
	local isBoss = WaveService.IsBoss(wave)
	lane.waveTotalHp = totalHp

	if isBoss then
		-- One big boss carrying most of the wave's HP, plus a few minions.
		local minions = LaneConfig.BossMinions
		table.insert(lane.spawnQueue, newEnemy(lane, 3, totalHp * 0.6))
		for _ = 1, minions do
			table.insert(lane.spawnQueue, newEnemy(lane, 1, totalHp * 0.4 / minions))
		end
	else
		local count = WaveService.EnemyCount(wave)
		if lane.debug.EnemyCountOverride > 0 then
			count = lane.debug.EnemyCountOverride
		end
		local swarm = WaveService.IsSwarm(wave)
		for i = 1, count do
			-- Swarm waves are mostly grubs; normal waves are 1 in 3 skeletons
			local kind = if i % (if swarm then 5 else 3) == 0 then 2 else 1
			table.insert(lane.spawnQueue, newEnemy(lane, kind, totalHp / count))
		end
	end

	lane.spawnInterval = LaneConfig.SpawnSpread / #lane.spawnQueue
	lane.spawnTimer = 0
	lane.state = "Running"
	waveStartedEvent:Fire(lane)
end

local function failWave(lane: Lane)
	table.clear(lane.enemies)
	table.clear(lane.spawnQueue)
	setBarricade(lane, 0)
	lane.state = "Failed"
	lane.stateTimer = LaneConfig.FailRestartSeconds
end

local function finishWave(lane: Lane)
	lane.wave += 1
	lane.model:SetAttribute("Wave", lane.wave)
	lane.state = "Intermission"
	lane.stateTimer = LaneConfig.IntermissionSeconds
end

-- Barricade damage from one enemy reaching it, based on the HP it has left.
local function leakDamage(lane: Lane, enemy: Enemy): number
	return LaneConfig.BarricadeMaxHP * LaneConfig.LeakDamage * (enemy.hp / lane.waveTotalHp)
end

------------------------------------------------------------------------
-- Simulation
------------------------------------------------------------------------

local function stepLane(lane: Lane, dt: number)
	if lane.state ~= "Running" then
		lane.stateTimer -= dt
		if lane.stateTimer <= 0 then
			startWave(lane)
		end
		return
	end

	-- Spawn from the queue over SpawnSpread seconds
	lane.spawnTimer -= dt
	while lane.spawnTimer <= 0 and #lane.spawnQueue > 0 do
		local enemy = table.remove(lane.spawnQueue, 1) :: Enemy
		lane.enemies[enemy.id] = enemy
		lane.spawnTimer += lane.spawnInterval
	end

	-- Move enemies; anything reaching the barricade damages it and is removed.
	-- Enemies marked breaksBarricade (bosses) break it outright.
	local stopAt = LaneConfig.BarricadeDistance + 1.5
	local hp = lane.barricadeHp
	local brokenBy: string? = nil
	for id, enemy in lane.enemies do
		enemy.dist -= enemy.speed * dt
		if enemy.dist <= stopAt then
			if LaneConfig.Enemies[enemy.kind].breaksBarricade then
				hp = 0
				brokenBy = "The boss broke through! Retrying wave " .. lane.wave .. "..."
			else
				hp -= leakDamage(lane, enemy)
			end
			lane.enemies[id] = nil
		end
	end

	if lane.debug.InvincibleBarricade then
		hp = math.max(hp, 1)
	end

	if hp ~= lane.barricadeHp then
		setBarricade(lane, hp)
	end

	if lane.barricadeHp <= 0 then
		notifyRemote:FireClient(lane.owner, brokenBy or ("Barricade broken! Retrying wave " .. lane.wave .. "..."))
		failWave(lane)
		return
	end

	if #lane.spawnQueue == 0 and next(lane.enemies) == nil then
		finishWave(lane)
	end
end

local function sendSnapshot(lane: Lane)
	local count = 0
	for _ in lane.enemies do
		count += 1
	end

	local buf = LaneSnapshot.Create(count)
	LaneSnapshot.WriteHeader(buf, {
		wave = lane.wave,
		barricadeHp = lane.barricadeHp,
		barricadeMax = LaneConfig.BarricadeMaxHP,
		state = LaneSnapshot.States[lane.state],
		count = count,
		dirX = lane.moveDir.X,
		dirZ = lane.moveDir.Z,
	})

	local index = 0
	for _, enemy in lane.enemies do
		local position = lane.origin * Vector3.new(enemy.lateral, 0, -enemy.dist)
		LaneSnapshot.WriteEntry(buf, index, enemy.id, position.X, position.Z, enemy.hp / enemy.maxHp, enemy.kind, enemy.speed)
		index += 1
	end

	snapshotRemote:FireClient(lane.owner, buf)
end

------------------------------------------------------------------------
-- Lane ownership
------------------------------------------------------------------------

local function placeCharacter(lane: Lane, character: Model)
	character:PivotTo(lane.origin * CFrame.new(0, 4, 0))
end

local function createLane(player: Player)
	if WaveService.Lanes[player] then
		return
	end

	local index
	for i = 1, LaneConfig.MaxLanes do
		if not usedIndexes[i] then
			index = i
			break
		end
	end
	if not index then
		warn("[WaveService] No free lane for", player.Name)
		return
	end
	usedIndexes[index] = true

	local debugSettings = DebugConfig.For(player)
	local firstWave = math.max(1, debugSettings.StartWave)
	local model, origin = LaneBuilder.Build(index, lanesFolder, {
		OwnerUserId = player.UserId,
		Debug = DebugConfig.Changes(debugSettings),
		Wave = firstWave,
	})

	local lane: Lane = {
		index = index,
		owner = player,
		model = model,
		origin = origin,
		moveDir = -origin.LookVector,
		debug = debugSettings,
		wave = firstWave,
		waveTotalHp = 1,
		state = "Intermission",
		stateTimer = LaneConfig.IntermissionSeconds,
		barricadeHp = LaneConfig.BarricadeMaxHP,
		enemies = {},
		spawnQueue = {},
		spawnTimer = 0,
		spawnInterval = 0,
		sendTimer = 0,
		nextId = 0,
	}
	WaveService.Lanes[player] = lane
	laneCreatedEvent:Fire(lane)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart")
		placeCharacter(lane, character)
	end)
	if player.Character then
		placeCharacter(lane, player.Character)
	end
end

local function removeLane(player: Player)
	local lane = WaveService.Lanes[player]
	if not lane then
		return
	end
	WaveService.Lanes[player] = nil
	usedIndexes[lane.index] = nil
	laneRemovedEvent:Fire(lane)
	lane.model:Destroy()
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

-- Enemies in a normal (non-boss) wave.
function WaveService.EnemyCount(wave: number): number
	local count = math.min(math.floor(LaneConfig.BaseEnemyCount + LaneConfig.EnemiesPerWave * wave), LaneConfig.MaxEnemyCount)
	if WaveService.IsSwarm(wave) then
		count = math.min(math.floor(count * LaneConfig.SwarmMultiplier), LaneConfig.SwarmMax)
	end
	return count
end

function WaveService.IsBoss(wave: number): boolean
	return wave % Config.Wave.BossEvery == 0
end

function WaveService.IsSwarm(wave: number): boolean
	return wave % LaneConfig.SwarmEvery == 0 and not WaveService.IsBoss(wave)
end

-- Coins a wave is worth in total (kills pay out their HP share of this).
function WaveService.WaveCoins(wave: number, rebirths: number): number
	local coins = Config.CoinsForWave(wave, rebirths)
	if WaveService.IsBoss(wave) then
		coins *= LaneConfig.BossCoinMultiplier
	end
	return coins
end

function WaveService:GetLane(player: Player): Lane?
	return self.Lanes[player]
end

-- Damage an enemy in a lane. Returns true if it died.
-- Used by GearService (week 2) and AbilityService (week 3).
function WaveService:DamageEnemy(lane: Lane, enemyId: number, amount: number): boolean
	local enemy = lane.enemies[enemyId]
	if not enemy or amount <= 0 then
		return false
	end
	enemy.hp -= amount
	if enemy.hp <= 0 then
		lane.enemies[enemyId] = nil
		killedEvent:Fire(lane, enemy)
		return true
	end
	return false
end

function WaveService:Init()
	lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = workspace
	snapshotRemote = Remotes.Event("EnemySnapshot")
	notifyRemote = Remotes.Event("Notify")
end

function WaveService:Start()
	Players.PlayerAdded:Connect(createLane)
	Players.PlayerRemoving:Connect(removeLane)
	for _, player in Players:GetPlayers() do
		task.spawn(createLane, player)
	end

	local sendInterval = 1 / LaneConfig.SnapshotRate
	RunService.Heartbeat:Connect(function(dt)
		for _, lane in WaveService.Lanes do
			stepLane(lane, dt)
			lane.sendTimer -= dt
			if lane.sendTimer <= 0 then
				lane.sendTimer = math.max(lane.sendTimer + sendInterval, 0)
				sendSnapshot(lane)
			end
		end
	end)
end

return WaveService
