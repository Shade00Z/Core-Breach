-- DailyConfig
-- Reasons to come back every day (DailyService, DailyController):
--   * Login streak: claim one reward a day. Missing a day PAUSES the streak
--     instead of resetting it; you carry on from the day you were on.
--     Day 7 is the big one, then it starts over at day 1.
--   * 3 daily quests, a new random set every day. Each pays coins and XP;
--     finishing all 3 gives a Lucky Roll.
--   * A free Lucky Roll every day: a crate roll at double luck, and whatever
--     it reveals is half price.
-- A new day starts at midnight UTC (4 pm Pacific).

local DailyConfig = {}

DailyConfig.LuckyRollLuck = 2 -- Lucky Rolls roll at this many times your luck
DailyConfig.LuckyRollPriceShare = 0.5 -- and what they reveal costs this share of its price
DailyConfig.LuckyRollsPerDay = 1
DailyConfig.AllQuestsBonusRolls = 1 -- Lucky Rolls for finishing all 3 daily quests

export type Reward = {
	coinWaves: number?, -- x what one of your current waves pays
	xpLevels: number?, -- x the XP for your next level
	cores: number?, -- Boss Cores
	ore: { item: string, count: number }?,
	luckyRolls: number?,
}

-- Login streak, day 1 to 7
DailyConfig.Streak = {
	{ coinWaves = 3 },
	{ ore = { item = "iron_ore", count = 10 } },
	{ coinWaves = 5 },
	{ cores = 2 },
	{ coinWaves = 8 },
	{ luckyRolls = 1 },
	{ coinWaves = 15, cores = 3, luckyRolls = 1 },
} :: { Reward }

export type DailyQuest = {
	id: string,
	kind: "kills" | "heroKills" | "mine" | "forge" | "waves",
	count: number,
	text: string,
}

-- Each day, 3 quests of different kinds are picked from this pool
DailyConfig.QuestPool = {
	{ id = "kills_100", kind = "kills", count = 100, text = "Defeat 100 enemies in your lane" },
	{ id = "kills_300", kind = "kills", count = 300, text = "Defeat 300 enemies in your lane" },
	{ id = "hero_25", kind = "heroKills", count = 25, text = "Defeat 25 enemies yourself" },
	{ id = "hero_60", kind = "heroKills", count = 60, text = "Defeat 60 enemies yourself" },
	{ id = "mine_20", kind = "mine", count = 20, text = "Mine 20 ore of any kind" },
	{ id = "mine_40", kind = "mine", count = 40, text = "Mine 40 ore of any kind" },
	{ id = "forge_2", kind = "forge", count = 2, text = "Strike the forge twice" },
	{ id = "waves_10", kind = "waves", count = 10, text = "Beat 10 waves" },
	{ id = "waves_20", kind = "waves", count = 20, text = "Beat 20 waves" },
} :: { DailyQuest }

DailyConfig.QuestReward = { coinWaves = 4, xpLevels = 0.5 } :: Reward

function DailyConfig.Today(): number
	return math.floor(os.time() / 86400)
end

-- Seconds until the next day starts
function DailyConfig.SecondsToNextDay(): number
	return 86400 - os.time() % 86400
end

-- The 3 quests for a player on a day (the same every time it's asked)
function DailyConfig.QuestsFor(userId: number, day: number): { DailyQuest }
	local rng = Random.new(day * 7919 + userId % 100000)
	local picked, kinds = {}, {}
	local pool = table.clone(DailyConfig.QuestPool)
	while #picked < 3 and #pool > 0 do
		local quest = table.remove(pool, rng:NextInteger(1, #pool))
		if not kinds[quest.kind] then
			kinds[quest.kind] = true
			table.insert(picked, quest)
		end
	end
	return picked
end

function DailyConfig.QuestById(id: string): DailyQuest?
	for _, quest in DailyConfig.QuestPool do
		if quest.id == id then
			return quest
		end
	end
	return nil
end

-- Short text for a reward ("$ x5 waves · 2 Boss Cores")
function DailyConfig.Describe(reward: Reward): string
	local parts = {}
	if reward.coinWaves then
		table.insert(parts, string.format("Coins (%d waves)", reward.coinWaves))
	end
	if reward.xpLevels then
		table.insert(parts, "XP")
	end
	if reward.ore then
		table.insert(parts, string.format("%d %s", reward.ore.count, if reward.ore.item == "iron_ore" then "Iron Ore" else reward.ore.item))
	end
	if reward.cores then
		table.insert(parts, string.format("%d Boss Cores", reward.cores))
	end
	if reward.luckyRolls then
		table.insert(parts, if reward.luckyRolls == 1 then "1 Lucky Roll" else string.format("%d Lucky Rolls", reward.luckyRolls))
	end
	return table.concat(parts, " · ")
end

return DailyConfig
