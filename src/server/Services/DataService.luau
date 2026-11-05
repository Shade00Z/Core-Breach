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
	slots: { [string]: string }, -- slot index -> gear id mounted there
	owned: { [string]: OwnedGear }, -- every gear the player owns, by gear id
	stash: StashEntry?,
	totalRolls: number,
}

local DataService = {}

local cache: { [Player]: PlayerData } = {}

local function newData(): PlayerData
	local data: PlayerData = {
		coins = 0,
		totalCoins = 0,
		unlockedSlots = {},
		slots = {},
		owned = {},
		stash = nil,
		totalRolls = 0,
	}
	for _, slotIndex in LaneConfig.StarterSlots do
		data.unlockedSlots[tostring(slotIndex)] = true
	end
	for slotIndex, gearId in LaneConfig.StarterGear do
		data.slots[tostring(slotIndex)] = gearId
		data.owned[gearId] = { level = 1, copies = 0 }
	end
	return data
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
