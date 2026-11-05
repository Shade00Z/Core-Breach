-- CrateConfig
-- Core crate rolls: luck, odds, timing and the stash.
-- Base rarity weights live in GearData.Rarities.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearData"))

local CrateConfig = {
	RollCooldown = 1.2, -- seconds between rolls (also the reveal time)
	StashWaves = 5, -- a stashed item waits this many waves before it's gone
	MaxRollDistance = 14, -- how close you must be to your crate to roll

	-- Luck rises every LuckStepWaves waves by LuckPerStep.
	LuckStepWaves = 10,
	LuckPerStep = 0.15,
}

-- Luck for a given wave. Wave 1-9 = 1.0, wave 10-19 = 1.15, and so on.
function CrateConfig.LuckForWave(wave: number): number
	return 1 + CrateConfig.LuckPerStep * math.floor(wave / CrateConfig.LuckStepWaves)
end

-- Waves until the next luck increase.
function CrateConfig.WavesToNextLuck(wave: number): number
	local step = CrateConfig.LuckStepWaves
	return step - (wave % step)
end

-- Luck multiplies the weight of every rarity above Common, more for rarer
-- tiers: weight x luck^(order - 1).
function CrateConfig.Weights(luck: number): { [string]: number }
	local weights = {}
	for rarity, info in GearData.Rarities do
		if info.weight > 0 and #GearData.ByRarity(rarity) > 0 then
			weights[rarity] = info.weight * luck ^ (info.order - 1)
		end
	end
	return weights
end

-- Exact odds (0-1) per rarity at this luck. Used for the odds screen.
function CrateConfig.Odds(luck: number): { [string]: number }
	local weights = CrateConfig.Weights(luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local odds = {}
	for rarity, w in weights do
		odds[rarity] = w / total
	end
	return odds
end

-- Pick a rarity. rng is a Random object.
function CrateConfig.PickRarity(luck: number, rng: Random): string
	local weights = CrateConfig.Weights(luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	local fallback = "Common"
	for rarity, w in weights do
		roll -= w
		fallback = rarity
		if roll <= 0 then
			return rarity
		end
	end
	return fallback
end

return CrateConfig
