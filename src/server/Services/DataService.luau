-- DataService
-- Every player's game data, in one table per player.
--
-- Week 2: data lives in memory only (it resets when you leave).
-- Week 4: the same API saves and loads with ProfileStore, so nothing that
-- uses DataService has to change.
--
-- Keys are strings (e.g. slots["1"]) because Roblox DataStores can't save
-- tables with gaps in their number keys.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaneConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LaneConfig"))

export type StashEntry = {
	gearId: string,
	price: number,
	expiresAfterWave: number,
}

export type OwnedGear = {
	level: number,
	copies: number, -- copies collected toward the next level
}

export type PlayerData = {
	coins: number,
	totalCoins: number, -- lifetime coins collected
	unlockedSlots: { [string]: boolean }, -- slot index -> open
	digging: { [string]: number }, -- slot index -> pickaxe hits so far (paid, not yet dug out)
	slots: { [string]: string }, -- slot index -> gear id mounted there
	owned: { [string]: OwnedGear }, -- every gear the player owns, by gear id
	stash: StashEntry?,
	totalRolls: number,

	-- Rebirth
	rebirths: number,
	coinMultiplier: number, -- every coin earned is multiplied by this
	runBestWave: number, -- best wave beaten since the last rebirth
	lostThisRun: boolean, -- lost a wave since the last rebirth (unlocks rebirth)
	bestWaveEver: number,
	discovered: { [string]: boolean }, -- every gear ever owned (kept through rebirths)
}

local DataService = {}

local cache: { [Player]: PlayerData } = {}

local function newData(): PlayerData
	local data: PlayerData = {
		coins = 0,
		totalCoins = 0,
		unlockedSlots = {},
		digging = {},
		slots = {},
		owned = {},
		stash = nil,
		totalRolls = 0,
		rebirths = 0,
		coinMultiplier = 1,
		runBestWave = 0,
		lostThisRun = false,
		bestWaveEver = 0,
		discovered = {},
	}
	for _, slotIndex in LaneConfig.StarterSlots do
		data.unlockedSlots[tostring(slotIndex)] = true
	end
	DataService.GiveStarterGear(data)
	return data
end

-- Puts the starter gear on the wall (new players, and after a rebirth).
function DataService.GiveStarterGear(data: PlayerData)
	table.clear(data.slots)
	table.clear(data.owned)
	for slotIndex, gearId in LaneConfig.StarterGear do
		data.slots[tostring(slotIndex)] = gearId
		data.owned[gearId] = { level = 1, copies = 0 }
		data.discovered[gearId] = true
	end
end

-- The player's data. Created on first use.
function DataService:Get(player: Player): PlayerData
	local data = cache[player]
	if not data then
		data = newData()
		cache[player] = data
	end
	return data
end

function DataService:Start()
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return DataService
