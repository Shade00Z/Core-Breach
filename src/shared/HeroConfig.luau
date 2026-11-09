-- HeroConfig
-- Numbers for your own character: levels and XP, the five stats, the
-- pickaxe-hammer, the Fire Blast ability, hero health, and digging out
-- wall slots.
--
-- Hero damage grows with your level and your Power stat. It's tuned so an
-- active player's hero deals roughly half as much as their gear wall
-- (checked with the balance sim). Levels never reset, not even on rebirth.

local HeroConfig = {}

------------------------------------------------------------------------
-- Levels and XP
------------------------------------------------------------------------

-- XP from a kill = the enemy's max HP. Kills by your own hero give all of
-- it; kills by your gear wall give GearKillShare of it.
-- XP to go from level L to L + 1 = XPBase x XPGrowth^L
HeroConfig.Levels = {
	Cap = 60, -- default only: each layer has its own cap (LayerConfig levelCap)
	XPBase = 150,
	XPGrowth = 1.1,
	GearKillShare = 0.25,
	PointsPerLevel = 3,
}

-- Swing damage = Flat + Base x Growth^(level - 1), then x your Power bonus
--   level 1: 5.5   level 10: 7.5   level 30: 30   level 60: ~460
HeroConfig.Damage = {
	Flat = 4,
	Base = 1.5,
	Growth = 1.1,
}

------------------------------------------------------------------------
-- Stats: 3 points per level, spent on the Stats screen
------------------------------------------------------------------------

-- Each point gives the bonuses listed. Order here = order on the Stats screen.
HeroConfig.Stats = {
	{ id = "power", name = "Power", blurb = "Your pickaxe and ability damage", heroDamage = 0.03 },
	{ id = "command", name = "Command", blurb = "Damage and fire rate of your gear wall", gearDamage = 0.02, gearRate = 0.01 },
	{ id = "excavation", name = "Excavation", blurb = "Digging speed (mining arrives in week 5)", digPower = 0.04 },
	{ id = "fortune", name = "Fortune", blurb = "Crate luck", luck = 0.01 },
	{ id = "vitality", name = "Vitality", blurb = "Your health and the barricade's strength", maxHealth = 4, barricade = 0.01 },
}

------------------------------------------------------------------------
-- Combat
------------------------------------------------------------------------

-- Pickaxe-hammer (click, or tap / the Swing button on mobile; hold to keep swinging)
HeroConfig.Swing = {
	Cooldown = 0.5, -- seconds between swings
	Range = 6, -- studs from your character to the edge of an enemy
	ArcDot = -0.1, -- how wide the swing is: hits anything not behind you
}

-- Fire Blast (Q, or the Fire Blast button)
HeroConfig.FireBlast = {
	Cooldown = 8,
	Range = 70, -- how far it can reach a target
	AimConeDegrees = 35, -- aim assist: bends toward the nearest enemy within this angle of where you face
	Speed = 90, -- studs per second
	SplashRadius = 10,
	DamageMultiplier = 5, -- x one swing's damage, to everything in the splash
}

-- Hero health. Enemies hurt you when you're in the lane with them
-- (damage per kind is in LaneConfig.Enemies). At 0 HP you respawn behind
-- the barricade.
HeroConfig.Health = {
	Base = 100,
	RespawnSeconds = 4,
	EnemyHitCooldown = 1, -- each enemy can hit you once per this many seconds
}

-- Digging out locked wall slots: pay, then swing at the rock.
-- Each swing adds 1 dig power (more with Excavation) until HitsToBreak.
HeroConfig.Dig = {
	HitsToBreak = 10,
	Range = 7, -- studs from your character to the rock's surface
	Costs = { 150, 1500, 15000, 150000 }, -- 1st, 2nd, 3rd, 4th slot you dig
}

------------------------------------------------------------------------
-- Formulas
------------------------------------------------------------------------

export type Effects = {
	heroDamage: number, -- multipliers (1 = no bonus)
	gearDamage: number,
	gearRate: number,
	digPower: number,
	luck: number,
	barricade: number,
	maxHealth: number, -- hit points
}

-- XP needed to go from this level to the next
function HeroConfig.XPToNext(level: number): number
	local levels = HeroConfig.Levels
	return math.floor(levels.XPBase * levels.XPGrowth ^ level)
end

-- Stat points earned by this level (spent or not)
function HeroConfig.PointsForLevel(level: number): number
	return (level - 1) * HeroConfig.Levels.PointsPerLevel
end

-- Everything the player's stat points add up to
function HeroConfig.Effects(stats: { [string]: number }?): Effects
	local effects: Effects = {
		heroDamage = 1,
		gearDamage = 1,
		gearRate = 1,
		digPower = 1,
		luck = 1,
		barricade = 1,
		maxHealth = HeroConfig.Health.Base,
	}
	for _, stat in HeroConfig.Stats do
		local points = stats and stats[stat.id] or 0
		if points > 0 then
			effects.heroDamage += (stat.heroDamage or 0) * points
			effects.gearDamage += (stat.gearDamage or 0) * points
			effects.gearRate += (stat.gearRate or 0) * points
			effects.digPower += (stat.digPower or 0) * points
			effects.luck += (stat.luck or 0) * points
			effects.barricade += (stat.barricade or 0) * points
			effects.maxHealth += (stat.maxHealth or 0) * points
		end
	end
	return effects
end

-- What a stat's points currently give, for the Stats screen
function HeroConfig.Describe(statId: string, points: number): string
	local pct = function(x: number): string
		return string.format("+%d%%", math.floor(x * 100 + 0.5))
	end
	for _, stat in HeroConfig.Stats do
		if stat.id == statId then
			if statId == "power" then
				return pct(stat.heroDamage * points) .. " hero damage"
			elseif statId == "command" then
				return pct(stat.gearDamage * points) .. " gear damage, " .. pct(stat.gearRate * points) .. " fire rate"
			elseif statId == "excavation" then
				return pct(stat.digPower * points) .. " digging speed"
			elseif statId == "fortune" then
				return pct(stat.luck * points) .. " crate luck"
			elseif statId == "vitality" then
				return string.format("+%d health, %s barricade", stat.maxHealth * points, pct(stat.barricade * points))
			end
		end
	end
	return ""
end

function HeroConfig.SwingDamage(level: number, effects: Effects?): number
	local d = HeroConfig.Damage
	local base = d.Flat + d.Base * d.Growth ^ (math.max(1, level) - 1)
	return base * (if effects then effects.heroDamage else 1)
end

function HeroConfig.FireBlastDamage(level: number, effects: Effects?): number
	return HeroConfig.SwingDamage(level, effects) * HeroConfig.FireBlast.DamageMultiplier
end

-- Coin cost of the nth slot you dig (1 = your first)
function HeroConfig.DigCost(nth: number): number
	local costs = HeroConfig.Dig.Costs
	return costs[nth] or costs[#costs] * 10 ^ (nth - #costs)
end

return HeroConfig
