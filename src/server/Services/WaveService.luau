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
-- Week 3: the hero can jump into the lane. Enemies that touch the hero hurt
-- it (LaneConfig.Enemies heroDamage); the hero's swings and Fire Blast also
-- go through DamageEnemy.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
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
	hitTimer: number, -- seconds until it can hit the hero again
	slowTimer: number, -- seconds left of a Slow effect (forge trait)
	slowFactor: number, -- speed multiplier while slowed
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
	waveEnemyTotal: number,
	timeScale: number, -- dev cheat: game speed for this lane (1 = normal)
	cheatInvincible: boolean, -- dev cheat: barricade can't break, hero can't be hurt
	enemyCountOverride: number, -- dev stress test: enemies per wave (0 = normal)
}

local WaveService = {}
WaveService.Lanes = {} :: { [Player]: Lane }

local services -- every service, set in Init

-- Events other services listen to:
--   EnemyKilled(lane, enemy, source)  an enemy was killed (coins, XP, loot);
--                             source = "hero" (your own swing or ability) or "gear"
--   LaneCreated(lane)         a player's lane was built
--   LaneRemoved(lane)         a player's lane was removed
--   WaveStarted(lane)         a wave began (luck announcements)
--   WaveCleared(lane, wave)   a wave was beaten (best wave for rebirth)
--   WaveFailed(lane, wave)    the barricade broke; the lane drops back a wave
-- (Signals, not BindableEvents: BindableEvents would pass a copy of the lane.)
local killedEvent = Signal.new()
local laneCreatedEvent = Signal.new()
local laneRemovedEvent = Signal.new()
local waveStartedEvent = Signal.new()
local waveClearedEvent = Signal.new()
local waveFailedEvent = Signal.new()
WaveService.WaveCleared = waveClearedEvent -- (lane, clearedWave)
WaveService.WaveFailed = waveFailedEvent -- (lane, failedWave)
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
		hitTimer = 0,
		slowTimer = 0,
		slowFactor = 1,
	}
end

-- How fast an enemy is moving right now (slowed or not)
local function currentSpeed(enemy: Enemy): number
	return if enemy.slowTimer > 0 then enemy.speed * enemy.slowFactor else enemy.speed
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
	-- Saved, so you come back to this wave when you rejoin
	services.DataService:Get(lane.owner).wave = lane.wave

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
		if lane.enemyCountOverride > 0 then
			count = lane.enemyCountOverride
		elseif lane.debug.EnemyCountOverride > 0 then
			count = lane.debug.EnemyCountOverride
		end
		local swarm = WaveService.IsSwarm(wave)
		for i = 1, count do
			-- Swarm waves are mostly grubs; normal waves are 1 in 3 skeletons
			local kind = if i % (if swarm then 5 else 3) == 0 then 2 else 1
			table.insert(lane.spawnQueue, newEnemy(lane, kind, totalHp / count))
		end
	end

	lane.waveEnemyTotal = #lane.spawnQueue
	lane.spawnInterval = LaneConfig.SpawnSpread / #lane.spawnQueue
	lane.spawnTimer = 0
	lane.state = "Running"
	waveStartedEvent:Fire(lane)
end

-- Losing a wave sends the lane back one wave, so the player keeps earning
-- on a wave they can beat instead of being stuck on one they can't.
local function failWave(lane: Lane)
	local failed = lane.wave
	table.clear(lane.enemies)
	table.clear(lane.spawnQueue)
	setBarricade(lane, 0)
	lane.wave = math.max(1, failed - 1)
	lane.model:SetAttribute("Wave", lane.wave)
	lane.state = "Failed"
	lane.stateTimer = LaneConfig.FailRestartSeconds
	waveFailedEvent:Fire(lane, failed)
end

local function finishWave(lane: Lane)
	local cleared = lane.wave
	lane.wave += 1
	lane.model:SetAttribute("Wave", lane.wave)
	lane.state = "Intermission"
	lane.stateTimer = LaneConfig.IntermissionSeconds
	waveClearedEvent:Fire(lane, cleared)
end

-- Barricade damage from one enemy reaching it, based on the HP it has left.
-- The Vitality stat makes the barricade stronger.
local function leakDamage(lane: Lane, enemy: Enemy): number
	local strength = services.CharacterService:GetEffects(lane.owner).barricade
	return LaneConfig.BarricadeMaxHP * LaneConfig.LeakDamage * (enemy.hp / lane.waveTotalHp) / strength
end

------------------------------------------------------------------------
-- Simulation
------------------------------------------------------------------------

-- Enemies touching the hero hurt it. Enemies only exist past the barricade,
-- so this only happens when the hero has jumped into the lane.
local function hurtHero(lane: Lane, dt: number)
	local character = lane.owner.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local canHurt = humanoid ~= nil and root ~= nil and humanoid.Health > 0 and not lane.cheatInvincible
	local heroLateral, heroDist = 0, 0
	if canHurt then
		local localPos = lane.origin:PointToObjectSpace((root :: BasePart).Position)
		heroLateral, heroDist = localPos.X, -localPos.Z
		-- In the air above them (e.g. on a wall ledge) is safe
		canHurt = localPos.Y < 8
	end
	for _, enemy in lane.enemies do
		if enemy.hitTimer > 0 then
			enemy.hitTimer -= dt
		elseif canHurt then
			local stats = LaneConfig.Enemies[enemy.kind]
			local reach = stats.radius + 1.5
			local dx, dz = enemy.lateral - heroLateral, enemy.dist - heroDist
			if dx * dx + dz * dz <= reach * reach then
				enemy.hitTimer = HeroConfig.Health.EnemyHitCooldown
				local hum = humanoid :: Humanoid
				hum:TakeDamage(stats.heroDamage)
				if hum.Health <= 0 then
					notifyRemote:FireClient(lane.owner, "Knocked out! Back behind the barricade in " .. HeroConfig.Health.RespawnSeconds .. "s.")
					canHurt = false
				end
			end
		end
	end
end

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
		if enemy.slowTimer > 0 then
			enemy.slowTimer -= dt
		end
		enemy.dist -= currentSpeed(enemy) * dt
		if enemy.dist <= stopAt then
			if LaneConfig.Enemies[enemy.kind].breaksBarricade then
				hp = 0
				brokenBy = "The boss broke through!"
			else
				hp -= leakDamage(lane, enemy)
			end
			lane.enemies[id] = nil
		end
	end

	hurtHero(lane, dt)

	if lane.debug.InvincibleBarricade or lane.cheatInvincible then
		hp = math.max(hp, 1)
	end

	if hp ~= lane.barricadeHp then
		setBarricade(lane, hp)
	end

	if lane.barricadeHp <= 0 then
		local back = math.max(1, lane.wave - 1)
		notifyRemote:FireClient(lane.owner, (brokenBy or "Barricade broken!") .. " Back to wave " .. back .. ".")
		failWave(lane)
		return
	end

	if #lane.spawnQueue == 0 and next(lane.enemies) == nil then
		finishWave(lane)
	end
end

local function sendSnapshot(lane: Lane)
	local count = 0
	local bossHealth: number? = nil
	for _, enemy in lane.enemies do
		count += 1
		if LaneConfig.Enemies[enemy.kind].breaksBarricade then
			bossHealth = enemy.hp / enemy.maxHp
		end
	end
	if not bossHealth and lane.state == "Running" and WaveService.IsBoss(lane.wave) then
		-- Boss wave: before the boss spawns show it full; after it dies, empty
		bossHealth = 0
		for _, enemy in lane.spawnQueue do
			if LaneConfig.Enemies[enemy.kind].breaksBarricade then
				bossHealth = 1
			end
		end
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
		total = lane.waveEnemyTotal,
		remaining = if lane.state == "Running" then count + #lane.spawnQueue else 0,
		bossHealth = bossHealth,
	})

	local index = 0
	for _, enemy in lane.enemies do
		local position = lane.origin * Vector3.new(enemy.lateral, 0, -enemy.dist)
		LaneSnapshot.WriteEntry(buf, index, enemy.id, position.X, position.Z, enemy.hp / enemy.maxHp, enemy.kind, currentSpeed(enemy) * lane.timeScale)
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

	-- Start on your saved wave (or DebugConfig's StartWave when testing)
	local debugSettings = DebugConfig.For(player)
	local savedWave = services.DataService:Get(player).wave or 1
	local firstWave = if debugSettings.StartWave > 1 then debugSettings.StartWave else math.max(1, savedWave)
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
		waveEnemyTotal = 0,
		timeScale = 1,
		cheatInvincible = false,
		enemyCountOverride = 0,
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
function WaveService.WaveCoins(wave: number, multiplier: number?): number
	local coins = Config.CoinsForWave(wave, multiplier)
	if WaveService.IsBoss(wave) then
		coins *= LaneConfig.BossCoinMultiplier
	end
	return coins
end

function WaveService:GetLane(player: Player): Lane?
	return self.Lanes[player]
end

-- Slow an enemy down for a while (the forge's Slow trait).
function WaveService:SlowEnemy(lane: Lane, enemyId: number, factor: number, seconds: number)
	local enemy = lane.enemies[enemyId]
	if enemy then
		enemy.slowFactor = math.min(if enemy.slowTimer > 0 then enemy.slowFactor else 1, factor)
		enemy.slowTimer = math.max(enemy.slowTimer, seconds)
	end
end

-- World position of an enemy (on the floor).
function WaveService.EnemyPosition(lane: Lane, enemy: Enemy): Vector3
	return lane.origin * Vector3.new(enemy.lateral, 0, -enemy.dist)
end

-- Clears the lane and starts it over at a wave (used by rebirth).
function WaveService:ResetLane(player: Player, wave: number)
	local lane = self.Lanes[player]
	if not lane then
		return
	end
	table.clear(lane.enemies)
	table.clear(lane.spawnQueue)
	lane.wave = math.max(1, wave)
	lane.model:SetAttribute("Wave", lane.wave)
	setBarricade(lane, LaneConfig.BarricadeMaxHP)
	lane.state = "Intermission"
	lane.stateTimer = LaneConfig.IntermissionSeconds
end

-- Dev cheat: kills every enemy in the wave, including ones not spawned yet,
-- so the wave counts as cleared and drops all its coins.
function WaveService:KillAll(player: Player)
	local lane = self.Lanes[player]
	if not lane or lane.state ~= "Running" then
		return
	end
	for _, enemy in lane.spawnQueue do
		lane.enemies[enemy.id] = enemy
	end
	table.clear(lane.spawnQueue)
	for id in table.clone(lane.enemies) do
		self:DamageEnemy(lane, id, math.huge, "gear")
	end
end

-- Damage an enemy in a lane. Returns true if it died.
-- source: "hero" for your own swings and abilities, "gear" (default) for the wall.
function WaveService:DamageEnemy(lane: Lane, enemyId: number, amount: number, source: string?): boolean
	local enemy = lane.enemies[enemyId]
	if not enemy or amount <= 0 then
		return false
	end
	enemy.hp -= amount
	if enemy.hp <= 0 then
		lane.enemies[enemyId] = nil
		killedEvent:Fire(lane, enemy, source or "gear")
		return true
	end
	return false
end

-- The place's default SpawnLocation sits in view at the start of lane 1.
-- Players are moved to their lane on spawn anyway, so hide it.
local function hideSpawnLocations()
	for _, spawn in workspace:GetDescendants() do
		if spawn:IsA("SpawnLocation") then
			spawn.Transparency = 1
			spawn.CanCollide = false
			spawn.CastShadow = false
			for _, child in spawn:GetChildren() do
				if child:IsA("Decal") then
					child.Transparency = 1
				end
			end
		end
	end
end

function WaveService:Init(allServices)
	services = allServices
	hideSpawnLocations()
	lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = workspace
	snapshotRemote = Remotes.Event("EnemySnapshot")
	notifyRemote = Remotes.Event("Notify")
end

function WaveService:Start()
	-- Build a player's lane once their save has loaded
	local DataService = services.DataService
	DataService.Loaded:Connect(createLane)
	Players.PlayerRemoving:Connect(removeLane)
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			task.spawn(createLane, player)
		end
	end

	local sendInterval = 1 / LaneConfig.SnapshotRate
	RunService.Heartbeat:Connect(function(dt)
		for _, lane in WaveService.Lanes do
			stepLane(lane, dt * lane.timeScale)
			lane.sendTimer -= dt
			if lane.sendTimer <= 0 then
				lane.sendTimer = math.max(lane.sendTimer + sendInterval, 0)
				sendSnapshot(lane)
			end
		end
	end)
end

return WaveService
