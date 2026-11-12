-- DataService
-- Every player's saved game data, loaded and saved with ProfileStore
-- (Modules/ProfileStore). ProfileStore "session locks" each save, so the same
-- account can't be loaded on two servers at once (no duplicated items from
-- joining on two devices). Joining somewhere else ends the old session.
--
-- When a player joins, their data loads first; then DataService.Loaded fires
-- and the rest of the game (lane, gear, crate...) is set up from it.
-- Other services read and change the table from DataService:Get(player)
-- directly; ProfileStore saves it every few minutes and when they leave.
--
-- Studio playtests use a separate save ("_Studio") so testing never touches
-- real players' data. Without "Enable Studio Access to API Services" (Game
-- Settings > Security), ProfileStore keeps data in memory only, and every
-- playtest starts fresh.
--
-- Keys are strings (e.g. slots["1"]) because Roblox can't save tables with
-- gaps in their number keys.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))
local Signal = require(Shared:WaitForChild("Signal"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local ProfileStore = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("ProfileStore"))

-- Change the version suffix only to start everyone over (it's a new save).
local STORE_NAME = if RunService:IsStudio() then "PlayerData_Studio_v1" else "PlayerData_v1"
local LOAD_WAIT_LIMIT = 30 -- seconds :Get() waits for a joining player's data

export type OwnedGear = {
	level: number,
	copies: number, -- copies collected toward the next level
}

export type PlayerData = {
	coins: number,
	totalCoins: number, -- lifetime coins collected
	unlockedSlots: { [string]: boolean }, -- slot index -> open
	digging: { [string]: number }, -- slot index -> dig progress so far (paid, not yet dug out)
	slots: { [string]: string }, -- slot index -> gear id mounted there
	owned: { [string]: OwnedGear }, -- every gear the player owns, by gear id
	totalRolls: number,
	loot: { [string]: { count: number, value: number } }, -- your bag: item id -> stack (value = total forge value)
	pickaxeTier: number, -- 1 Stone, 2 Iron, 3 Gold (LootConfig.Pickaxes)
	pendingRoll: { gearId: string, price: number, lucky: boolean? }?, -- rolled but not bought or skipped yet (lucky = free Lucky Roll)
	wave: number, -- the wave you're on (you return to it when you rejoin)

	-- Layers and quests (week 6)
	layer: number, -- the layer you play in (LayerConfig); beating its boss moves you down
	bossesBeaten: { [string]: boolean }, -- layer -> beaten that layer's boss
	quests: { [string]: { step: number, active: boolean, progress: number } }, -- layer -> quest line progress (QuestConfig)
	deepestEver: number, -- deepest layer ever reached (kept through Re-Drills; sets the level cap)

	-- Re-Drill and daily hooks (week 7)
	reDrills: number,
	upgrades: { [string]: number }, -- unused (the gold upgrade shop was removed; old saves may have levels here)

	-- Core Powers (week 8, PowerData)
	powers: {
		crystals: number, -- unopened Power Crystals
		equipped: string, -- power id, or "" for none
		owned: { [string]: { xp: number } }, -- power id -> mastery XP
		starterGiven: boolean, -- got the free crystal for reaching level 30
	},
	-- Store (week 9, StoreConfig)
	store: {
		owned: { [string]: boolean }, -- passes Roblox has confirmed (fallback if it can't be asked)
		settings: { [string]: any }, -- toggles and the Auto-Skip rarity (StoreConfig.DefaultSettings)
		tokens: number, -- paid Price Skips not used yet
		receipts: { string }, -- recent purchase ids already granted
	},
	settings: { sound: number, music: number, lowGraphics: boolean, effects: boolean }, -- week 9 (SettingsService)
	daily: {
		day: number, -- the day (DailyConfig.Today) the daily quests below are for
		quests: { { id: string, progress: number, done: boolean } },
		allDone: boolean, -- got the bonus for finishing all 3 today
		streakDay: number, -- login streak day you claimed last (0-7)
		lastClaimDay: number, -- the day you last claimed a streak reward
		luckyRolls: number, -- free Lucky Rolls waiting
		lastLuckyDay: number, -- the day you last got your daily Lucky Roll
	},

	-- Hero
	level: number,
	xp: number, -- XP toward the next level
	stats: { [string]: number }, -- stat id -> points spent

	-- Rebirth
	rebirths: number,
	coinMultiplier: number, -- every coin earned is multiplied by this
	runBestWave: number, -- best wave beaten since the last rebirth
	lostThisRun: boolean, -- lost a wave since the last rebirth (unlocks rebirth)
	recordAnnounced: boolean, -- "New record" already shown this run
	bestWaveEver: number,
	discovered: { [string]: boolean }, -- every gear ever owned (kept through rebirths)

	-- Offline earnings
	lastOnline: number, -- os.time() when last seen playing (0 = never)
	offlinePending: number, -- offline coins earned but not collected yet
	offlineSeconds: number, -- how long away those coins cover
}

local function newTemplate(): PlayerData
	local data: PlayerData = {
		coins = 0,
		totalCoins = 0,
		unlockedSlots = {},
		digging = {},
		slots = {},
		owned = {},
		totalRolls = 0,
		loot = {},
		pickaxeTier = 1,
		wave = 1,
		layer = 1,
		bossesBeaten = {},
		quests = {},
		deepestEver = 1,
		reDrills = 0,
		upgrades = {},
		powers = { crystals = 0, equipped = "", owned = {}, starterGiven = false },
		store = { owned = {}, settings = table.clone(StoreConfig.DefaultSettings), tokens = 0, receipts = {} },
		settings = { sound = 1, music = 1, lowGraphics = false, effects = true },
		daily = { day = -1, quests = {}, allDone = false, streakDay = 0, lastClaimDay = -1, luckyRolls = 0, lastLuckyDay = -1 },
		level = 1,
		xp = 0,
		stats = { power = 0, command = 0, excavation = 0, fortune = 0, vitality = 0 },
		rebirths = 0,
		coinMultiplier = 1,
		runBestWave = 0,
		lostThisRun = false,
		recordAnnounced = false,
		bestWaveEver = 0,
		discovered = {},
		lastOnline = 0,
		offlinePending = 0,
		offlineSeconds = 0,
	}
	for _, slotIndex in LaneConfig.StarterSlots do
		data.unlockedSlots[tostring(slotIndex)] = true
	end
	for slotIndex, gearId in LaneConfig.StarterGear do
		data.slots[tostring(slotIndex)] = gearId
		data.owned[gearId] = { level = 1, copies = 0 }
		data.discovered[gearId] = true
	end
	return data
end

local store = ProfileStore.New(STORE_NAME, newTemplate())

local DataService = {}

-- Fires (player, data) once a player's data has loaded
DataService.Loaded = Signal.new()
-- Fires (player, data) just before a player's data is saved for the last
-- time (they're leaving), so services can write final values into it
DataService.Leaving = Signal.new()

local profiles: { [Player]: any } = {}

local function loadPlayer(player: Player)
	local profile = store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		if player.Parent == Players then
			player:Kick("Your save couldn't be loaded. Please rejoin in a moment.")
		end
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: lets Roblox data-deletion requests find this save
	profile:Reconcile() -- adds fields that are new since this save was made
	profile.Data.deepestEver = math.max(profile.Data.deepestEver, profile.Data.layer) -- saves from before week 7

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your game was opened somewhere else. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end
	profiles[player] = profile
	DataService.Loaded:Fire(player, profile.Data)
end

function DataService:IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- The player's data. If they're still loading, waits for it. Every service
-- normally only calls this after Loaded, so the wait is just a safety net.
function DataService:Get(player: Player): PlayerData
	local profile = profiles[player]
	if not profile then
		local started = os.clock()
		while not profiles[player] and player.Parent == Players and os.clock() - started < LOAD_WAIT_LIMIT do
			task.wait(0.1)
		end
		profile = profiles[player]
		if not profile then
			-- Gone or never loaded: a throwaway table so callers don't error
			return newTemplate()
		end
	end
	return profile.Data
end

-- Dev only: erase a player's save and send them out so they rejoin fresh.
function DataService:Wipe(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Data = newTemplate()
	profiles[player] = nil
	profile:EndSession()
	player:Kick("Save wiped. Rejoin (or press Play again) to start fresh.")
end

function DataService:Start()
	Players.PlayerAdded:Connect(loadPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if not profile then
			return
		end
		DataService.Leaving:Fire(player, profile.Data)
		profiles[player] = nil
		profile:EndSession() -- saves and releases the session lock
	end)
end

return DataService
