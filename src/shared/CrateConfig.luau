-- CrateConfig
-- Core crate rolls: luck, odds and timing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearData"))

local CrateConfig = {
	RollCooldown = 1.2, -- seconds between rolls (also the reveal time)
	MaxRollDistance = 14, -- how close you must be to your crate to roll

	-- Luck goes up by LuckPerStep each time you beat a new multiple of
	-- LuckStepWaves (wave 10, 20, 30...) for the first time. It's based on your
	-- best wave ever, so rebirths keep it.
	LuckStepWaves = 10,
	LuckPerStep = 0.15,
}

-- Luck from the best wave you've ever beaten. Best 0-9 = 1.0, 10-19 = 1.15...
function CrateConfig.LuckForBestWave(bestWave: number): number
	return 1 + CrateConfig.LuckPerStep * math.floor(bestWave / CrateConfig.LuckStepWaves)
end

-- The wave you need to beat for the next luck increase.
function CrateConfig.NextLuckWave(bestWave: number): number
	local step = CrateConfig.LuckStepWaves
	return (math.floor(bestWave / step) + 1) * step
end

-- ODDS -----------------------------------------------------------------
-- Every gear can be rolled. Gear further up the price ladder (GearData) is
-- rarer: each step up the list is Decay less likely. Luck flattens that
-- slope, pushing rolls up the list: the slope becomes
--   Decay - LuckDecay x ln(luck)   (but never below MinDecay)
-- Mythics are rarer still (x MythicFactor) so they stay special.
-- Roughly, per roll:
--   luck 1     mostly the first 10 gear, Legendary ~never
--   luck 3.3   1 in 10 rolls is gear #20 or higher, Legendary ~1.7%, Mythic ~1 in 4,000
--   luck 6.7   Legendary ~9%, Mythic ~1 in 460 (a Lucky Roll at luck 3.3)
CrateConfig.Odds = {
	Decay = 0.3,
	LuckDecay = 0.16,
	MinDecay = 0.04,
	MythicFactor = 0.05,
}

-- Roll weight of every gear (in GearData.Items order) at this luck
function CrateConfig.Weights(luck: number): { number }
	local settings = CrateConfig.Odds
	local slope = math.max(settings.MinDecay, settings.Decay - settings.LuckDecay * math.log(math.max(luck, 1)))
	local weights = {}
	for i, gear in GearData.Items do
		local weight = math.exp(-slope * (i - 1))
		if gear.rarity == "Mythic" then
			weight *= settings.MythicFactor
		end
		weights[i] = weight
	end
	return weights
end

-- Exact chance (0-1) of each gear at this luck, by gear id (for the odds screen)
function CrateConfig.GearOdds(luck: number): { [string]: number }
	local weights = CrateConfig.Weights(luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local odds = {}
	for i, gear in GearData.Items do
		odds[gear.id] = weights[i] / total
	end
	return odds
end

-- Pick a gear. rng is a Random object.
function CrateConfig.PickGear(luck: number, rng: Random): GearData.Gear
	local weights = CrateConfig.Weights(luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 then
			return GearData.Items[i]
		end
	end
	return GearData.Items[1]
end

return CrateConfig
