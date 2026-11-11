-- DailyService
-- The daily hooks (DailyConfig): login streak, 3 daily quests and the free
-- daily Lucky Roll. Open them with the Daily button (DailyController) or the
-- Daily board in Drill Town.
--
-- Everything is keyed to the day number (DailyConfig.Today, midnight UTC).
-- When the day changes (on join, or while you're playing) you get new daily
-- quests and today's Lucky Roll. The login streak only moves forward when
-- you claim, so a missed day pauses it rather than resetting it.
--
-- Daily quests count the same things as NPC quests: QuestService:Progress
-- passes every report on to DailyService:Progress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local DailyConfig = require(Shared:WaitForChild("DailyConfig"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local LootConfig = require(Shared:WaitForChild("LootConfig"))
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local Format = require(Shared:WaitForChild("Format"))

local PUSH_INTERVAL = 0.5
local DAY_CHECK_INTERVAL = 20 -- seconds between checks for a new day while playing
local CLAIM_COOLDOWN = 1

local DailyService = {}

local services
local notify: RemoteEvent
local dirty: { [Player]: boolean } = {}
local lastClaim: { [Player]: number } = {}

-- Brings a player's daily state up to today: new quests and today's Lucky
-- Roll if the day has changed. Returns the daily table.
local function rollover(player: Player)
	local data = services.DataService:Get(player)
	local daily = data.daily
	local day = DailyConfig.Today()
	if daily.day ~= day then
		daily.day = day
		daily.allDone = false
		daily.quests = {}
		for _, quest in DailyConfig.QuestsFor(player.UserId, day) do
			table.insert(daily.quests, { id = quest.id, progress = 0, done = false })
		end
	end
	if daily.lastLuckyDay ~= day then
		daily.lastLuckyDay = day
		daily.luckyRolls += DailyConfig.LuckyRollsPerDay
	end
	return daily
end

local function push(player: Player)
	local daily = rollover(player)
	local quests = {}
	for _, state in daily.quests do
		table.insert(quests, { id = state.id, progress = state.progress, done = state.done })
	end
	services.EconomyService:PushStats(player, {
		daily = {
			quests = quests,
			allDone = daily.allDone,
			streakDay = daily.streakDay, -- last day claimed (0-7)
			canClaim = daily.lastClaimDay ~= daily.day,
			luckyRolls = daily.luckyRolls,
			resetsAt = os.time() + DailyConfig.SecondsToNextDay(), -- when the next day starts
		},
	})
end

function DailyService:Refresh(player: Player)
	push(player)
end

-- Gives a reward; returns a short summary for the player
local function grant(player: Player, reward: DailyConfig.Reward): string
	local data = services.DataService:Get(player)
	local parts = {}
	if reward.coinWaves then
		local coins = services.EconomyService:WaveReward(player, reward.coinWaves)
		services.EconomyService:AddCoins(player, coins)
		table.insert(parts, "$" .. Format.Number(math.floor(coins)))
	end
	if reward.xpLevels then
		local xp = HeroConfig.XPToNext(data.level) * reward.xpLevels
		services.CharacterService:GiveXP(player, xp)
		table.insert(parts, "XP")
	end
	if reward.ore then
		local item = LootConfig.Items[reward.ore.item]
		services.LootService:Add(player, reward.ore.item, reward.ore.count)
		table.insert(parts, string.format("%d %s", reward.ore.count, if item then item.name else reward.ore.item))
	end
	if reward.cores then
		local value = Config.CoinsForWave(math.max(1, data.wave - 1)) * LootConfig.Drops.CoreValue * reward.cores
		services.LootService:Add(player, "boss_core", reward.cores, value)
		table.insert(parts, string.format("%d Boss Cores", reward.cores))
	end
	if reward.luckyRolls then
		data.daily.luckyRolls += reward.luckyRolls
		table.insert(parts, string.format("%d Lucky Roll%s", reward.luckyRolls, if reward.luckyRolls == 1 then "" else "s"))
	end
	return table.concat(parts, ", ")
end

local function claimStreak(player: Player)
	local now = os.clock()
	if lastClaim[player] and now - lastClaim[player] < CLAIM_COOLDOWN then
		return
	end
	lastClaim[player] = now
	local daily = rollover(player)
	if daily.lastClaimDay == daily.day then
		return
	end
	daily.lastClaimDay = daily.day
	daily.streakDay = daily.streakDay % #DailyConfig.Streak + 1
	local summary = grant(player, DailyConfig.Streak[daily.streakDay])
	notify:FireClient(player, string.format("Day %d login reward: %s", daily.streakDay, summary))
	push(player)
end

-- Something quest-worthy happened (from QuestService:Progress)
function DailyService:Progress(player: Player, kind: string, amount: number, _detail: any?)
	local daily = rollover(player)
	local changed = false
	for _, state in daily.quests do
		local quest = DailyConfig.QuestById(state.id)
		if quest and not state.done and quest.kind == kind then
			state.progress = math.min(quest.count, state.progress + amount)
			changed = true
			if state.progress >= quest.count then
				state.done = true
				local summary = grant(player, DailyConfig.QuestReward)
				notify:FireClient(player, string.format("Daily quest done: %s! %s", quest.text, summary))
			end
		end
	end
	if not changed then
		return
	end
	if not daily.allDone then
		local all = #daily.quests > 0
		for _, state in daily.quests do
			all = all and state.done
		end
		if all then
			daily.allDone = true
			daily.luckyRolls += DailyConfig.AllQuestsBonusRolls
			notify:FireClient(player, "All 3 daily quests done! +1 Lucky Roll. Use it at your crate.")
			push(player)
			return
		end
	end
	dirty[player] = true
end

-- Uses one Lucky Roll if the player has one (CrateService)
function DailyService:UseLuckyRoll(player: Player): boolean
	local daily = rollover(player)
	if daily.luckyRolls <= 0 then
		return false
	end
	daily.luckyRolls -= 1
	push(player)
	return true
end

-- Gives a Lucky Roll back (the roll couldn't happen after all)
function DailyService:RefundLuckyRoll(player: Player)
	services.DataService:Get(player).daily.luckyRolls += 1
	push(player)
end

-- Dev cheats
function DailyService:DevNewDay(player: Player)
	local daily = services.DataService:Get(player).daily
	daily.day = -1
	daily.lastLuckyDay = -1
	daily.lastClaimDay = -1
	push(player)
end

function DailyService:DevComplete(player: Player)
	local daily = rollover(player)
	for _, state in daily.quests do
		local quest = DailyConfig.QuestById(state.id)
		if quest and not state.done then
			self:Progress(player, quest.kind, quest.count)
		end
	end
end

function DailyService:Init(allServices)
	services = allServices
end

function DailyService:Start()
	notify = Remotes.Event("Notify")
	Remotes.Event("DailyAction").OnServerEvent:Connect(function(player, action)
		if action == "ClaimStreak" and services.DataService:IsLoaded(player) then
			claimStreak(player)
		end
	end)

	local DataService = services.DataService
	DataService.Loaded:Connect(push)
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			push(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastClaim[player] = nil
	end)

	local pushTimer, dayTimer = 0, 0
	local lastDay = DailyConfig.Today()
	RunService.Heartbeat:Connect(function(dt)
		pushTimer += dt
		dayTimer += dt
		if pushTimer >= PUSH_INTERVAL then
			pushTimer = 0
			for player in dirty do
				dirty[player] = nil
				if player.Parent == Players and DataService:IsLoaded(player) then
					push(player)
				end
			end
		end
		if dayTimer >= DAY_CHECK_INTERVAL then
			dayTimer = 0
			local day = DailyConfig.Today()
			if day ~= lastDay then
				lastDay = day
				for _, player in Players:GetPlayers() do
					if DataService:IsLoaded(player) then
						push(player)
						notify:FireClient(player, "A new day! New daily quests, a free Lucky Roll, and your login reward.")
					end
				end
			end
		end
	end)
end

return DailyService
