-- HeroConfig
-- Numbers for your own character: the pickaxe-hammer, the Fire Blast
-- ability, hero health, and digging out wall slots.
--
-- Hero damage scales with your gear wall's DPS for now, so swinging stays
-- useful as your army grows. Week 4 replaces that with hero level and the
-- Power stat.

local HeroConfig = {}

-- Pickaxe-hammer (click, or the Swing button on mobile; hold to keep swinging)
HeroConfig.Swing = {
	Cooldown = 0.5, -- seconds between swings
	Range = 6, -- studs from your character to the edge of an enemy
	ArcDot = -0.1, -- how wide the swing is: hits anything not behind you
	BaseDamage = 8,
	WallDpsShare = 0.2, -- + this much of your wall's total DPS per swing
}

-- Fire Blast (Q, or the Fire button on mobile)
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
	RespawnSeconds = 4,
	EnemyHitCooldown = 1, -- each enemy can hit you once per this many seconds
}

-- Digging out locked wall slots: pay, then swing at the rock.
HeroConfig.Dig = {
	HitsToBreak = 10,
	Range = 7, -- studs from your character to the rock's surface
	Costs = { 150, 1500, 15000, 150000 }, -- 1st, 2nd, 3rd, 4th slot you dig
}

function HeroConfig.SwingDamage(wallDps: number): number
	local swing = HeroConfig.Swing
	return swing.BaseDamage + swing.WallDpsShare * math.max(0, wallDps)
end

function HeroConfig.FireBlastDamage(wallDps: number): number
	return HeroConfig.SwingDamage(wallDps) * HeroConfig.FireBlast.DamageMultiplier
end

-- Coin cost of the nth slot you dig (1 = your first)
function HeroConfig.DigCost(nth: number): number
	local costs = HeroConfig.Dig.Costs
	return costs[nth] or costs[#costs] * 10 ^ (nth - #costs)
end

return HeroConfig
