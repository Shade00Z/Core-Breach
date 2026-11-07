-- EconomyService
-- Coins and rebirths.
--
-- Coins: a wave is worth WaveService.WaveCoins(wave, coinMultiplier). Each
-- kill drops its share of that by HP, so clearing a whole wave drops the full
-- amount and enemies that leak through the barricade drop nothing.
-- Drops land on the player's side of the barricade and only count once the
-- player walks within LaneConfig.CoinDrops.PickupRadius of them. The server
-- checks this itself (the client can't claim coins).
-- Week 9: the Auto-Collect gamepass will simply collect drops instantly.
--
-- Rebirth: unlocked once you LOSE a wave in a run. Rebirthing sends you back
-- to wave 1 and keeps your coins, gear, levels, stash and coins on the
-- ground. Your coin multiplier goes up by Config.RebirthGain(best wave this
-- run), so each climb pays more than the last and you get further.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local FXBatcher = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("FXBatcher"))

local STATS_INTERVAL = 0.1 -- send coin updates at most 10 times a second
local PICKUP_INTERVAL = 0.1 -- check for pickups 10 times a second
local REBIRTH_COOLDOWN = 2 -- seconds, guards against double clicks

type Drop = { id: number, value: number, position: Vector3 }
type DropState = { nextId: number, drops: { [number]: Drop }, count: number }

local EconomyService = {}

local services
local DataService
local WaveService
local statsRemote: RemoteEvent
local notifyRemote: RemoteEvent
local dirty: { [Player]: boolean } = {}
local dropStates: { [Player]: DropState } = {}
local lastRebirth: { [Player]: number } = {}
local rng = Random.new()

------------------------------------------------------------------------
-- Coins
------------------------------------------------------------------------

function EconomyService:GetCoins(player: Player): number
	return DataService:Get(player).coins
end

function EconomyService:AddCoins(player: Player, amount: number)
	if amount <= 0 or amount ~= amount then
		return
	end
	local data = DataService:Get(player)
	data.coins += amount
	data.totalCoins += amount
	dirty[player] = true
end

-- Returns true if the player had enough and the coins were taken.
function EconomyService:SpendCoins(player: Player, amount: number): boolean
	local data = DataService:Get(player)
	if amount < 0 or data.coins < amount then
		return false
	end
	data.coins -= amount
	dirty[player] = true
	return true
end

-- Send a partial stats update straight away (used by other services too).
function EconomyService:PushStats(player: Player, stats: { [string]: any })
	statsRemote:FireClient(player, stats)
end

------------------------------------------------------------------------
-- Rebirth
------------------------------------------------------------------------

function EconomyService:CanRebirth(player: Player): boolean
	local data = DataService:Get(player)
	return data.lostThisRun and Config.RebirthGain(data.runBestWave) > 0
end

local function pushRebirthStats(player: Player)
	local data = DataService:Get(player)
	EconomyService:PushStats(player, {
		rebirths = data.rebirths,
		coinMultiplier = data.coinMultiplier,
		runBestWave = data.runBestWave,
		bestWaveEver = data.bestWaveEver,
		rebirthGain = Config.RebirthGain(data.runBestWave),
		canRebirth = EconomyService:CanRebirth(player),
	})
end

-- Re-sends rebirth info (used by dev cheats).
function EconomyService:RefreshRebirth(player: Player)
	pushRebirthStats(player)
end

function EconomyService:Rebirth(player: Player): boolean
	local now = os.clock()
	if lastRebirth[player] and now - lastRebirth[player] < REBIRTH_COOLDOWN then
		return false
	end
	if not self:CanRebirth(player) then
		return false
	end
	lastRebirth[player] = now

	local data = DataService:Get(player)
	local gain = Config.RebirthGain(data.runBestWave)
	local reached = data.runBestWave

	-- Keep the stash's remaining waves when the wave number resets
	local lane = WaveService:GetLane(player)
	if data.stash and lane then
		local wavesLeft = math.max(1, data.stash.expiresAfterWave - lane.wave + 1)
		data.stash.expiresAfterWave = wavesLeft
	end

	data.rebirths += 1
	data.coinMultiplier += gain
	data.runBestWave = 0
	data.lostThisRun = false
	data.recordAnnounced = false
	WaveService:ResetLane(player, 1)

	pushRebirthStats(player)
	services.CrateService:Refresh(player)
	notifyRemote:FireClient(player, string.format(
		"Rebirth %d! You beat wave %d, so coins are now worth x%.2f (+%.2f). Beat your record!",
		data.rebirths,
		reached,
		data.coinMultiplier,
		gain
	))
	return true
end

------------------------------------------------------------------------
-- Drops
------------------------------------------------------------------------

local function stateFor(player: Player): DropState
	local state = dropStates[player]
	if not state then
		state = { nextId = 0, drops = {}, count = 0 }
		dropStates[player] = state
	end
	return state
end

-- A random landing spot on the player's side of the barricade, off the crate.
local function landingSpot(lane): Vector3
	local cfg = LaneConfig.CoinDrops
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local lateral = side * rng:NextNumber(cfg.KeepClearOfCenter, LaneConfig.Width / 2 - 2)
	local dist = rng:NextNumber(cfg.LandMinDistance, cfg.LandMaxDistance)
	return lane.origin * Vector3.new(lateral, 0, -dist)
end

local function onEnemyKilled(lane, enemy)
	local player = lane.owner
	local data = DataService:Get(player)
	local value = WaveService.WaveCoins(lane.wave, data.coinMultiplier) * (enemy.maxHp / lane.waveTotalHp)
	local deathPosition = lane.origin * Vector3.new(enemy.lateral, 0, -enemy.dist)
	local state = stateFor(player)

	local drop: Drop
	if state.count < LaneConfig.CoinDrops.MaxOnGround then
		state.nextId = (state.nextId % 65535) + 1
		drop = { id = state.nextId, value = value, position = landingSpot(lane) }
		state.drops[drop.id] = drop
		state.count += 1
	else
		-- Too many on the ground: add to an existing pile instead
		local _, existing = next(state.drops)
		drop = existing :: Drop
		drop.value += value
	end

	FXBatcher.Kill(player, {
		enemyId = enemy.id,
		x = deathPosition.X,
		z = deathPosition.Z,
		kind = enemy.kind,
		dropId = drop.id,
		landX = drop.position.X,
		landZ = drop.position.Z,
		value = value,
	})
end

local function checkPickups()
	local radius = LaneConfig.CoinDrops.PickupRadius
	local radiusSq = radius * radius
	for player, state in dropStates do
		if state.count == 0 then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local p = root.Position
		for id, drop in state.drops do
			local dx, dz = drop.position.X - p.X, drop.position.Z - p.Z
			if dx * dx + dz * dz <= radiusSq and math.abs(drop.position.Y - p.Y) < 12 then
				state.drops[id] = nil
				state.count -= 1
				EconomyService:AddCoins(player, drop.value)
				FXBatcher.Pickup(player, id)
			end
		end
	end
end

------------------------------------------------------------------------

function EconomyService:Init(allServices)
	services = allServices
	DataService = allServices.DataService
	WaveService = allServices.WaveService
	statsRemote = Remotes.Event("StatsChanged")
	notifyRemote = Remotes.Event("Notify")
end

function EconomyService:Start()
	FXBatcher.Start()

	WaveService.EnemyKilled:Connect(onEnemyKilled)
	WaveService.WaveCleared:Connect(function(lane, cleared)
		local player = lane.owner
		local data = DataService:Get(player)
		if cleared > data.runBestWave then
			-- Announce a new record once per run (when you first pass your old
			-- best); after that the HUD's "Record" number just keeps counting up
			local newRecord = cleared > data.bestWaveEver and data.rebirths > 0 and not data.recordAnnounced
			data.runBestWave = cleared
			data.bestWaveEver = math.max(data.bestWaveEver, cleared)
			pushRebirthStats(player)
			if newRecord then
				data.recordAnnounced = true
				notifyRemote:FireClient(player, "New record! You've passed your best wave.")
			end
		end
	end)
	WaveService.WaveFailed:Connect(function(lane)
		local player = lane.owner
		local data = DataService:Get(player)
		if not data.lostThisRun then
			data.lostThisRun = true
			pushRebirthStats(player)
		end
	end)
	WaveService.LaneCreated:Connect(function(lane)
		pushRebirthStats(lane.owner)
	end)
	WaveService.LaneRemoved:Connect(function(lane)
		dropStates[lane.owner] = nil
	end)

	Remotes.Event("RequestRebirth").OnServerEvent:Connect(function(player)
		EconomyService:Rebirth(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		dirty[player] = true
	end)
	for _, player in Players:GetPlayers() do
		dirty[player] = true
		pushRebirthStats(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		dropStates[player] = nil
		lastRebirth[player] = nil
	end)

	local statsTimer, pickupTimer = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		pickupTimer += dt
		if pickupTimer >= PICKUP_INTERVAL then
			pickupTimer = 0
			checkPickups()
		end

		statsTimer += dt
		if statsTimer < STATS_INTERVAL then
			return
		end
		statsTimer = 0
		for player in dirty do
			if player.Parent == Players then
				statsRemote:FireClient(player, { coins = DataService:Get(player).coins })
			end
			dirty[player] = nil
		end
	end)
end

return EconomyService
