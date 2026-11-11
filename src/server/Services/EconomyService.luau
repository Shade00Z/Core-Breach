-- EconomyService
-- Coins and rebirths.
--
-- Coins: a wave is worth WaveService.WaveCoins(wave, coinMultiplier), times
-- your layer's coin bonus (LayerConfig). Each
-- kill drops its share of that by HP, so clearing a whole wave drops the full
-- amount and enemies that leak through the barricade drop nothing.
-- Drops land on the player's side of the barricade and only count once the
-- player walks within LaneConfig.CoinDrops.PickupRadius of them. The server
-- checks this itself (the client can't claim coins).
-- Week 9: the Auto-Collect gamepass will simply collect drops instantly.
--
-- Offline earnings: while you're away your wall keeps earning at
-- Config.Offline.Rate (25%) of what your current wave pays, for up to
-- Config.Offline.MaxHours (8). It waits in the save until you press Collect
-- on the welcome-back popup.
--
-- Rebirth: unlocked once you LOSE a wave in a run. Rebirthing sends you back
-- to wave 1 and keeps your coins, gear, hero level, opened slots and coins on the
-- ground. Your coin multiplier goes up by Config.RebirthGain(best wave this
-- run), so each climb pays more than the last and you get further.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local FXBatcher = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("FXBatcher"))

local STATS_INTERVAL = 0.1 -- send coin updates at most 10 times a second
local PICKUP_INTERVAL = 0.1 -- check for pickups 10 times a second
local REBIRTH_COOLDOWN = 2 -- seconds, guards against double clicks
local OFFLINE_MIN_SECONDS = 60 -- shorter absences don't earn anything
local LAST_ONLINE_INTERVAL = 30 -- how often "last seen" is written (covers crashes)

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

-- Everything that multiplies coins: rebirths, your layer and permanent
-- boosts (Gear Index pages)
function EconomyService:CoinMultiplier(player: Player, layer: number?): number
	local data = DataService:Get(player)
	return data.coinMultiplier * LayerConfig.Get(layer or data.layer).coinMultiplier * services.CharacterService:GetEffects(player).coins
end

-- Coins worth this many of your current waves (quest, boss and daily rewards)
function EconomyService:WaveReward(player: Player, waves: number): number
	local data = DataService:Get(player)
	return Config.CoinsForWave(math.max(1, data.wave - 1), self:CoinMultiplier(player)) * waves
end

local function pushRebirthStats(player: Player)
	local data = DataService:Get(player)
	EconomyService:PushStats(player, {
		reDrills = data.reDrills,
		reDrillNeeds = Config.ReDrill.RebirthsNeeded,
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
-- Re-Drill: at the Big Drill in Drill Town, once you have enough rebirths.
-- Resets your rebirths (coin bonus back to x1), your wave and your layer
-- (back to Layer 1; beat Rootmaw again to go down). Keeps coins, gear,
-- opened slots and your hero. In return: x1.5 gear damage and +10% luck
-- for good, per Re-Drill (Boosts).
------------------------------------------------------------------------

function EconomyService:CanReDrill(player: Player): boolean
	return DataService:Get(player).rebirths >= Config.ReDrill.RebirthsNeeded
end

function EconomyService:ReDrill(player: Player): boolean
	local now = os.clock()
	if lastRebirth[player] and now - lastRebirth[player] < REBIRTH_COOLDOWN then
		return false
	end
	if not self:CanReDrill(player) or not services.TownService:NearBigDrill(player) then
		return false
	end
	lastRebirth[player] = now

	local data = DataService:Get(player)
	data.reDrills += 1
	data.rebirths = 0
	data.coinMultiplier = 1
	data.runBestWave = 0
	data.lostThisRun = false
	data.recordAnnounced = false
	data.bossesBeaten = {}
	WaveService:ResetLane(player, 1)
	services.HubService:MoveToLayer(player, 1)
	services.CharacterService:RefreshBoosts(player)
	pushRebirthStats(player)

	notifyRemote:FireClient(player, string.format(
		"Re-Drill %d! Gear damage x%.2f and luck +%d%% for good. Back to Layer 1, wave 1: beat Rootmaw to go down again.",
		data.reDrills,
		Config.ReDrill.DPSMult ^ data.reDrills,
		math.floor(Config.ReDrill.LuckBonus * data.reDrills * 100 + 0.5)
	))
	Remotes.Event("Announce"):FireAllClients(string.format("%s just Re-Drilled! (Re-Drill %d)", player.DisplayName, data.reDrills), "ReDrill")
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
	-- Deeper layers pay more (LayerConfig coinMultiplier), and so do Gear Index pages
	local multiplier = EconomyService:CoinMultiplier(lane.owner, lane.layer)
	local value = WaveService.WaveCoins(lane.wave, multiplier) * (enemy.maxHp / lane.waveTotalHp)
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
	for player, state in dropStates do
		if state.count == 0 then
			continue
		end
		local radius = LaneConfig.CoinDrops.PickupRadius
		local radiusSq = radius * radius
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
-- Offline earnings
------------------------------------------------------------------------

-- Coins per second an active player earns at their current wave
local function activeCoinRate(player: Player, data): number
	local lastCleared = math.max(1, (data.wave or 1) - 1)
	return Config.CoinsForWave(lastCleared, EconomyService:CoinMultiplier(player)) / Config.Offline.AverageWaveSeconds
end

local function pushOffline(player: Player)
	local data = DataService:Get(player)
	EconomyService:PushStats(player, {
		offline = if data.offlinePending >= 1
			then { coins = math.floor(data.offlinePending), seconds = data.offlineSeconds }
			else false,
	})
end

-- Adds coins for the time since the player was last seen (call on join)
function EconomyService:CheckOffline(player: Player)
	local data = DataService:Get(player)
	local now = os.time()
	if data.lastOnline > 0 then
		local away = now - data.lastOnline
		if away >= OFFLINE_MIN_SECONDS then
			local cap = Config.Offline.MaxHours * 3600
			local coins = math.min(away, cap) * activeCoinRate(player, data) * Config.Offline.Rate
			if coins >= 1 then
				data.offlinePending += coins
				data.offlineSeconds = math.min(cap, data.offlineSeconds + math.min(away, cap))
			end
		end
	end
	data.lastOnline = now
	pushOffline(player)
end

local function collectOffline(player: Player)
	local data = DataService:Get(player)
	local coins = math.floor(data.offlinePending)
	data.offlinePending = 0
	data.offlineSeconds = 0
	if coins > 0 then
		EconomyService:AddCoins(player, coins)
	end
	pushOffline(player)
end

-- Dev cheat: pretend the player was away for this many seconds
function EconomyService:SimulateAway(player: Player, seconds: number)
	local data = DataService:Get(player)
	data.lastOnline = os.time() - seconds
	self:CheckOffline(player)
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
	Remotes.Event("RequestReDrill").OnServerEvent:Connect(function(player)
		EconomyService:ReDrill(player)
	end)

	Remotes.Event("CollectOffline").OnServerEvent:Connect(collectOffline)

	-- Once a player's save loads: send their coins and rebirth info, and pay
	-- out anything they earned while away
	local function onLoaded(player: Player)
		dirty[player] = true
		pushRebirthStats(player)
		EconomyService:CheckOffline(player)
	end
	DataService.Loaded:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			task.spawn(onLoaded, player)
		end
	end
	DataService.Leaving:Connect(function(_, data)
		data.lastOnline = os.time()
	end)
	task.spawn(function()
		while true do
			task.wait(LAST_ONLINE_INTERVAL)
			for _, player in Players:GetPlayers() do
				if DataService:IsLoaded(player) then
					DataService:Get(player).lastOnline = os.time()
				end
			end
		end
	end)
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
			if player.Parent == Players and DataService:IsLoaded(player) then
				statsRemote:FireClient(player, { coins = DataService:Get(player).coins })
			end
			dirty[player] = nil
		end
	end)
end

return EconomyService
