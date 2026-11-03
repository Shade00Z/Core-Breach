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
	BasePerWave = 2,      -- coins from clearing wave 1
	Growth = 1.15,        -- coins grow 15% per wave (slower than HP, so you eventually stall)
}

-- REBIRTH (hours) -----------------------------------------------------
-- Resets wave + coins + gear on the wall. Keeps gear collection.
Config.Rebirth = {
	BaseWave = 40,        -- wave needed for the first rebirth
	WaveStep = 5,         -- each rebirth needs 5 more waves than the last
	CoinBonus = 0.25,     -- +25% coins per rebirth (additive: 4 rebirths = 2x)
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
}

-- FORMULAS ------------------------------------------------------------
function Config.WaveHP(wave: number): number
	local hp = Config.Wave.BaseHP * Config.Wave.HPGrowth ^ wave
	if wave % Config.Wave.BossEvery == 0 then
		hp *= Config.Wave.BossHPMult
	end
	return hp
end

function Config.CoinsForWave(wave: number, rebirths: number): number
	local mult = 1 + Config.Rebirth.CoinBonus * rebirths
	return Config.Money.BasePerWave * Config.Money.Growth ^ wave * mult
end

function Config.RebirthWave(rebirths: number): number
	return Config.Rebirth.BaseWave + Config.Rebirth.WaveStep * rebirths
end

function Config.GlobalDPSMult(reDrills: number, ascensions: number): number
	return Config.ReDrill.DPSMult ^ reDrills * Config.Ascension.DPSMult ^ ascensions
end

function Config.OfflineCoins(secondsAway: number, coinsPerSecondActive: number): number
	local capped = math.min(secondsAway, Config.Offline.MaxHours * 3600)
	return capped * coinsPerSecondActive * Config.Offline.Rate
end

return Config
