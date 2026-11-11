-- PowerData
-- Core Powers: elemental powers your hero wields, each with 3 abilities
-- on Q, F and R (and buttons on phones). Server: PowerService (crystals,
-- mastery, equipping) and AbilityService (casting). Client: PowerController
-- (casting and effects) and CrystalController (the Powers screen).
--
-- Getting powers: Power Crystals drop from layer bosses, now and then from
-- lane wave bosses, and from Magma Ore veins. Opening one rolls a random
-- power (weight). Rolling a power you already have gives it mastery instead.
--
-- Mastery: every enemy your power's abilities hit gives that power mastery
-- XP. Mastery unlocks its 2nd and 3rd abilities and adds damage.
--
-- Damage: each ability hits for `damage` x your pickaxe swing damage (so
-- it grows with your level and the Power stat), +5% per mastery level.
--
-- Ability kinds (how they hit):
--   projectile  flies toward the nearest enemy in front of you (aim assist)
--               and explodes, hurting everything within `splash`
--   pool        a pool at the nearest enemy in front (or ahead of you) that
--               hurts everything inside it every `tickEvery` seconds
--   nova        a burst around you, hurting everything within `radius`
--   line        a wall of spikes straight ahead, `length` long, `width` wide
-- slow = { factor, seconds }: enemies hit move at factor x speed for a while
-- (0.05 is a near-freeze).

export type Ability = {
	id: string,
	name: string,
	kind: "projectile" | "pool" | "nova" | "line",
	mastery: number, -- mastery level that unlocks it
	cooldown: number,
	damage: number, -- x swing damage, per hit (per tick for pools)
	range: number?, -- projectile and pool: how far it reaches
	cone: number?, -- projectile and pool: aim assist angle (degrees)
	speed: number?, -- projectile studs per second
	splash: number?, -- projectile explosion radius
	radius: number?, -- pool and nova
	ticks: number?, -- pool: how many times it hurts
	tickEvery: number?, -- pool: seconds between ticks
	length: number?, -- line
	width: number?, -- line
	slow: { factor: number, seconds: number }?,
	description: string,
}

export type Power = {
	id: string,
	name: string,
	color: Color3,
	weight: number, -- crystal roll weight
	abilities: { Ability }, -- slot 1, 2, 3 (Q, F, R)
}

local PowerData = {}

PowerData.Keys = { "Q", "F", "R" } -- keyboard key for each ability slot

PowerData.Powers = {
	magma = {
		id = "magma",
		name = "Magma Core",
		color = Color3.fromRGB(255, 110, 30),
		weight = 60,
		abilities = {
			{
				id = "fire_blast",
				name = "Fire Blast",
				kind = "projectile",
				mastery = 0,
				cooldown = 8,
				damage = 5,
				range = 70,
				cone = 35,
				speed = 90,
				splash = 10,
				description = "A fireball that flies at the nearest enemy in front of you and explodes.",
			},
			{
				id = "lava_pool",
				name = "Lava Pool",
				kind = "pool",
				mastery = 3,
				cooldown = 14,
				damage = 1.2,
				range = 40,
				cone = 40,
				radius = 9,
				ticks = 10,
				tickEvery = 0.5,
				description = "Pours a pool of lava under the enemies ahead. Burns everything in it for 5 seconds.",
			},
			{
				id = "eruption",
				name = "Eruption",
				kind = "nova",
				mastery = 8,
				cooldown = 28,
				damage = 16,
				radius = 22,
				description = "The ground explodes around you. Huge damage to everything nearby.",
			},
		},
	},
	frost = {
		id = "frost",
		name = "Frost Core",
		color = Color3.fromRGB(120, 210, 255),
		weight = 40,
		abilities = {
			{
				id = "ice_shard",
				name = "Ice Shard",
				kind = "projectile",
				mastery = 0,
				cooldown = 6,
				damage = 3.5,
				range = 80,
				cone = 30,
				speed = 140,
				splash = 5,
				slow = { factor = 0.5, seconds = 2.5 },
				description = "A fast shard of ice. Slows what it hits.",
			},
			{
				id = "frost_nova",
				name = "Frost Nova",
				kind = "nova",
				mastery = 3,
				cooldown = 14,
				damage = 4,
				radius = 18,
				slow = { factor = 0.35, seconds = 4 },
				description = "A blast of cold around you. Slows everything nearby to a crawl.",
			},
			{
				id = "glacier_spike",
				name = "Glacier Spike",
				kind = "line",
				mastery = 8,
				cooldown = 26,
				damage = 12,
				length = 60,
				width = 8,
				slow = { factor = 0.05, seconds = 2.5 },
				description = "A wall of ice spikes straight ahead. Freezes everything it hits.",
			},
		},
	},
} :: { [string]: Power }

PowerData.Order = { "magma", "frost" }

PowerData.Mastery = {
	MaxLevel = 20,
	XPPerHit = 1, -- per lane enemy an ability hits
	XPPerBossHit = 5, -- per layer boss hit
	DuplicateXP = 600, -- rolling a power you already have
	DamagePerLevel = 0.05, -- +5% ability damage per mastery level
}

PowerData.Crystals = {
	WaveBossChance = 0.2, -- chance a lane wave boss drops one
	MagmaVeinChance = 0.04, -- chance per player when a Magma Ore vein breaks
}

-- Total mastery XP needed to reach a level (level 1 = 0)
function PowerData.XPForLevel(level: number): number
	return 40 * (level - 1) ^ 2
end

function PowerData.MasteryLevel(xp: number): number
	local level = 1
	while level < PowerData.Mastery.MaxLevel and xp >= PowerData.XPForLevel(level + 1) do
		level += 1
	end
	return level
end

function PowerData.Get(id: string?): Power?
	return if id then PowerData.Powers[id] else nil
end

-- Damage multiplier from mastery
function PowerData.MasteryBonus(level: number): number
	return 1 + PowerData.Mastery.DamagePerLevel * (level - 1)
end

-- Roll a power by weight. rng is a Random object.
function PowerData.Roll(rng: Random): Power
	local total = 0
	for _, id in PowerData.Order do
		total += PowerData.Powers[id].weight
	end
	local pick = rng:NextNumber() * total
	for _, id in PowerData.Order do
		pick -= PowerData.Powers[id].weight
		if pick <= 0 then
			return PowerData.Powers[id]
		end
	end
	return PowerData.Powers[PowerData.Order[1]]
end

return PowerData
