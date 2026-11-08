--!strict
-- ProgressionConfig (ReplicatedStorage.Shared.ProgressionConfig)
-- All balance numbers for Core Breach in one place. Tune here, not in scripts.

local Config = {}

-- WAVES ---------------------------------------------------------------
Config.Wave = {
	BaseHP = 40,          -- total enemy HP on wave 1
	HPGrowth = 1.16,      -- each wave has 16% more HP
	BossEvery = 20,       -- boss wave interval
	BossHPMult = 5,       -- boss waves have 5x HP
	MinSeconds = 20,      -- a wave never ends faster than this (keeps pacing readable)
}

-- MONEY ---------------------------------------------------------------
Config.Money = {
	BasePerWave = 15,     -- coins from wave 1 (sized so a first purchase comes after about 2 waves)
	Growth = 1.15,        -- coins grow 15% per wave (slower than HP, so you eventually stall)
}

-- REBIRTH -------------------------------------------------------------
-- Available once you've LOST a wave this run (you've hit your limit).
-- Rebirthing sends you back to wave 1 and keeps everything else: coins,
-- gear, gear levels, opened slots. In return your coin multiplier
-- goes up for good, so the next climb pays more and you get further.
--
-- How much it goes up depends on the best wave you beat this run:
--   gain = GainScale x (best wave / 10)^2
--   wave 10: +0.10   wave 20: +0.40   wave 30: +0.90   wave 40: +1.60
-- Gains add up across rebirths. Squaring the wave means pushing further
-- pays much more than rebirthing early. Because you must lose a wave first,
-- rebirthing at a wave you can easily beat isn't possible.
Config.Rebirth = {
	MinWave = 1, -- a run must beat at least this wave to give any gain
	GainScale = 0.1,
}

-- RE-DRILL (days) -----------------------------------------------------
-- Resets rebirths + depth. Permanent luck and forge power.
Config.ReDrill = {
	RebirthsNeeded = 12,
	DPSMult = 1.5,        -- multiplicative per Re-Drill
	LuckBonus = 0.10,     -- +10% crate luck per Re-Drill
}

-- CORE ASCENSION (weeks) ----------------------------------------------
-- Resets nearly everything. Unlocks the next gear tier.
Config.Ascension = {
	ReDrillsNeeded = 6,
	DPSMult = 5,          -- multiplicative per Ascension
}

-- OFFLINE -------------------------------------------------------------
Config.Offline = {
	MaxHours = 8,         -- earnings stop after this, so players return daily
	Rate = 0.25,          -- 25% of active earning speed
	AverageWaveSeconds = 32, -- "active speed" = what your current wave pays, once per this many seconds
}

-- FORMULAS ------------------------------------------------------------
function Config.WaveHP(wave: number): number
	local hp = Config.Wave.BaseHP * Config.Wave.HPGrowth ^ wave
	if wave % Config.Wave.BossEvery == 0 then
		hp *= Config.Wave.BossHPMult
	end
	return hp
end

-- Coins a wave is worth, times the player's coin multiplier.
function Config.CoinsForWave(wave: number, multiplier: number?): number
	return Config.Money.BasePerWave * Config.Money.Growth ^ wave * (multiplier or 1)
end

-- Coin multiplier gained by rebirthing after beating this wave (0 if too early).
function Config.RebirthGain(bestWave: number): number
	if bestWave < Config.Rebirth.MinWave then
		return 0
	end
	return Config.Rebirth.GainScale * (bestWave / 10) ^ 2
end

function Config.GlobalDPSMult(reDrills: number, ascensions: number): number
	return Config.ReDrill.DPSMult ^ reDrills * Config.Ascension.DPSMult ^ ascensions
end

function Config.OfflineCoins(secondsAway: number, coinsPerSecondActive: number): number
	local capped = math.min(secondsAway, Config.Offline.MaxHours * 3600)
	return capped * coinsPerSecondActive * Config.Offline.Rate
end

return Config
