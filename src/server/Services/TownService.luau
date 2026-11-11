-- TownService
-- Drill Town, the shared town on the surface (Modules/TownBuilder):
--   * Leaderboards for Top Level, Deepest Drillers and Top DPS, across all
--     servers (OrderedDataStores). Each player's scores are saved every
--     minute; the boards refresh every two minutes.
--   * Display stands: the top 3 players in this server (by level), each
--     with their strongest gear on show.
--   * The pull board: the latest Legendary and Mythic pulls in this server
--     (CrateService:RecordPull).
--   * The Big Drill: where you Re-Drill (EconomyService:ReDrill checks you
--     are standing here).
-- The elevator and the daily board just open panels on the client.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearData = require(Shared:WaitForChild("GearData"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local TownBuilder = require(Modules:WaitForChild("TownBuilder"))
local GearVisuals = require(Modules:WaitForChild("GearVisuals"))

local SAVE_INTERVAL = 60 -- seconds between saving each player's scores
local BOARD_INTERVAL = 120 -- seconds between reading the leaderboards
local STAND_INTERVAL = 15
local BIG_DRILL_DISTANCE = 18
local MAX_PULLS = 6
local SUFFIX = if RunService:IsStudio() then "_Studio" else ""

local TownService = {}

local services
local town: TownBuilder.Town
local stores: { [string]: OrderedDataStore } = {}
local names: { [number]: string } = {}
local pulls: { string } = {}

function TownService:GetTown(): TownBuilder.Town
	return town
end

function TownService:NearBigDrill(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and ((root :: BasePart).Position - town.bigDrill.Position).Magnitude <= BIG_DRILL_DISTANCE
end

------------------------------------------------------------------------
-- Leaderboards
------------------------------------------------------------------------

-- Depth score: Re-Drills count most, then the layer you're in
local function depthScore(data): number
	return data.reDrills * 10 + data.layer
end

local function depthText(score: number): string
	local reDrills, layer = score // 10, score % 10
	local layerName = LayerConfig.Get(layer).name
	return if reDrills > 0 then string.format("Re-Drill %d · %s", reDrills, layerName) else layerName
end

local BOARDS = {
	Level = function(player: Player, data)
		return data.level
	end,
	Depth = function(_player: Player, data)
		return depthScore(data)
	end,
	DPS = function(player: Player, _data)
		return math.floor(services.GearService:GetTotalDps(player))
	end,
}

local function storeFor(board: string): OrderedDataStore?
	if not stores[board] then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("Leaderboard_" .. board .. "_v1" .. SUFFIX)
		end)
		if not ok then
			return nil
		end
		stores[board] = store
	end
	return stores[board]
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and name then name else "Player"
	return names[userId]
end

local function saveScores()
	for _, player in Players:GetPlayers() do
		if services.DataService:IsLoaded(player) then
			local data = services.DataService:Get(player)
			for board, score in BOARDS do
				local store = storeFor(board)
				local value = score(player, data)
				if store and value > 0 then
					pcall(function()
						store:SetAsync(tostring(player.UserId), math.floor(value))
					end)
				end
			end
		end
	end
end

local function refreshBoards()
	for board in BOARDS do
		local store = storeFor(board)
		local display = town.leaderboards[board]
		if store and display then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, #display.rows)
			end)
			local entries = if ok and pages then pages:GetCurrentPage() else {}
			for i, row in display.rows do
				local entry = entries[i]
				if entry then
					local value = entry.value
					local shown = if board == "Depth" then depthText(value) elseif board == "Level" then "Lv " .. value else Format.Number(value) .. " DPS"
					row.Text = string.format("%d. %s  ·  %s", i, nameOf(tonumber(entry.key) or 0), shown)
				else
					row.Text = if i == 1 and not ok then "(leaderboards need API access)" else ""
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Display stands: the top 3 players here, with their strongest gear
------------------------------------------------------------------------

local function strongestGear(data): (GearData.Gear?, number, any)
	local best, bestDps, bestLevel, bestForge = nil, -1, 1, nil
	for gearId, owned in data.owned do
		local gear = GearData.Get(gearId)
		if gear then
			local dps = GearData.DPS(gear, owned.level) * (if owned.forge then owned.forge.mult or 1 else 1)
			if dps > bestDps then
				best, bestDps, bestLevel, bestForge = gear, dps, owned.level, owned.forge
			end
		end
	end
	return best, bestLevel, bestForge
end

local function refreshStands()
	local ranked = {}
	for _, player in Players:GetPlayers() do
		if services.DataService:IsLoaded(player) then
			table.insert(ranked, { player = player, data = services.DataService:Get(player) })
		end
	end
	table.sort(ranked, function(a, b)
		return a.data.level > b.data.level
	end)
	for i, stand in town.stands do
		local entry = ranked[i]
		local old = stand.pedestal:FindFirstChild("Gear")
		local shownId = old and old:GetAttribute("GearId")
		if entry then
			local gear, level, forge = strongestGear(entry.data)
			stand.label.Text = string.format("%s\nLv %d%s", entry.player.DisplayName, entry.data.level, if gear then "  ·  " .. gear.name else "")
			if gear and (shownId ~= gear.id or not old) then
				if old then
					old:Destroy()
				end
				local model = GearVisuals.Build(gear, level, stand.pedestal, Vector3.new(1, 0, 0), forge)
				model.CFrame = model.CFrame * CFrame.new(0, 1, 0) -- float a little
			end
		else
			stand.label.Text = "-"
			if old then
				old:Destroy()
			end
		end
	end
end

------------------------------------------------------------------------
-- Pull board
------------------------------------------------------------------------

-- A Legendary or Mythic pull (CrateService)
function TownService:RecordPull(player: Player, gear: GearData.Gear)
	table.insert(pulls, 1, string.format("%s  ·  %s %s", player.DisplayName, gear.rarity, gear.name))
	while #pulls > MAX_PULLS do
		table.remove(pulls)
	end
	for i, row in town.pullBoard.rows do
		row.Text = pulls[i] or ""
		local rarity = if pulls[i] and pulls[i]:find("Mythic") then "Mythic" else "Legendary"
		row.TextColor3 = GearData.Rarities[rarity].color
	end
end

------------------------------------------------------------------------

function TownService:Init(allServices)
	services = allServices
	town = TownBuilder.Build(workspace)
end

function TownService:Start()
	town.pullBoard.rows[1].Text = "Nothing yet. Pull a Legendary!"
	task.spawn(function()
		task.wait(8)
		saveScores()
		refreshBoards()
		local saveTimer, boardTimer = 0, 0
		while true do
			task.wait(STAND_INTERVAL)
			refreshStands()
			saveTimer += STAND_INTERVAL
			boardTimer += STAND_INTERVAL
			if saveTimer >= SAVE_INTERVAL then
				saveTimer = 0
				task.spawn(saveScores)
			end
			if boardTimer >= BOARD_INTERVAL then
				boardTimer = 0
				task.spawn(refreshBoards)
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		names[player.UserId] = player.DisplayName
	end)
	task.delay(3, refreshStands)
end

return TownService
