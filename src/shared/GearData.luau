-- GearData
-- Every piece of gear the crate can roll, plus how gear levels work.
-- Add new gear here, not in scripts.
--
-- All gear can be rolled from the very start. The list is a price ladder:
-- each gear costs about 1.86x the one before it (from $25 up to the
-- trillions), and the further up the list a gear is, the rarer it is to
-- roll (CrateConfig: luck pushes your rolls up the list). Rarity is just
-- the band of the list a gear sits in.
--
-- Strength is matched to the waves: a gear's price is about 3 waves of
-- coins at some wave W (for a player with the rebirth bonus typical by
-- then), and its DPS is what one of six wall slots needs at wave W, with
-- about x3 from levels, forging and stats. So buying gear lets you push a
-- bit further, never skip ahead dozens of waves. The cheapest gear (up to
-- about $6M) is a bit stronger than that so the first waves feel good.
-- The numbers were generated from that rule; scale them together.
--
-- Gear shoots anywhere in the lane (no range limit), so it starts firing as
-- soon as an enemy comes out of the breach.
--
-- Levels: rolling and buying gear you already own adds a copy toward its
-- next level (level N to N+1 takes N copies), or you can buy the next level
-- with coins in the gear panel (LevelCost, which keeps climbing). Every
-- level adds Levels.DamagePerLevel to its damage.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type Gear = {
	id: string,
	name: string,
	kind: "Pistol" | "Rifle" | "Turret" | "Drone" | "Launcher",
	rarity: Rarity,
	damage: number, -- damage per shot at level 1
	fireRate: number, -- shots per second
	splash: number, -- splash radius in studs, 0 = single target
	price: number, -- coin cost after it's revealed
}

local GearData = {}

GearData.Rarities = {
	Common = { order = 1, color = Color3.fromRGB(190, 190, 190) },
	Rare = { order = 2, color = Color3.fromRGB(70, 150, 255) },
	Epic = { order = 3, color = Color3.fromRGB(170, 80, 255) },
	Legendary = { order = 4, color = Color3.fromRGB(255, 180, 40) },
	Mythic = { order = 5, color = Color3.fromRGB(255, 60, 120) }, -- announced to the whole server
}

GearData.Levels = {
	MaxLevel = 25,
	DamagePerLevel = 0.5, -- +50% of level-1 damage per level (Lv 3 = 2x damage)
	-- Buying a level with coins: LevelCostShare x the gear's price, times
	-- LevelCostGrowth for every level it already has
	LevelCostShare = 0.5,
	LevelCostGrowth = 1.6,
}

-- Gray-box model shape for each kind of gear (used on the wall and above the crate)
GearData.Shapes = {
	Pistol = { size = Vector3.new(1, 1, 2.2), lift = 0 },
	Rifle = { size = Vector3.new(0.8, 0.8, 4), lift = 0 },
	Turret = { size = Vector3.new(2, 1.6, 2.6), lift = 0 },
	Drone = { size = Vector3.new(1.8, 1.8, 1.8), lift = 2.5, ball = true },
	Launcher = { size = Vector3.new(1.6, 1.6, 3.2), lift = 0 },
} :: { [string]: { size: Vector3, lift: number, ball: boolean? } }

-- In ladder order: cheapest and most common first
local items: { Gear } = {
	-- Common
	{ id = "rusty_pistol", name = "Rusty Pistol", kind = "Pistol", rarity = "Common", damage = 4.0, fireRate = 1.5, splash = 0, price = 25 },
	{ id = "miners_rifle", name = "Miner's Rifle", kind = "Rifle", rarity = "Common", damage = 8.4, fireRate = 1.0, splash = 0, price = 46 },
	{ id = "scrap_turret", name = "Scrap Turret", kind = "Turret", rarity = "Common", damage = 3.0, fireRate = 4.0, splash = 0, price = 86 },
	{ id = "lamp_drone", name = "Lamp Drone", kind = "Drone", rarity = "Common", damage = 6.7, fireRate = 2.5, splash = 0, price = 160 },
	{ id = "twin_blaster", name = "Twin Blaster", kind = "Pistol", rarity = "Common", damage = 16, fireRate = 1.5, splash = 0, price = 300 },
	{ id = "drill_cannon", name = "Drill Cannon", kind = "Launcher", rarity = "Common", damage = 42, fireRate = 0.5, splash = 6, price = 560 },
	{ id = "nail_driver", name = "Nail Driver", kind = "Rifle", rarity = "Common", damage = 46, fireRate = 1.0, splash = 0, price = 1000 },
	{ id = "pebble_mortar", name = "Pebble Mortar", kind = "Launcher", rarity = "Common", damage = 83, fireRate = 0.5, splash = 6, price = 1900 },
	{ id = "gatling_rig", name = "Gatling Rig", kind = "Turret", rarity = "Common", damage = 24, fireRate = 4.0, splash = 0, price = 3600 },
	{ id = "dust_drone", name = "Dust Drone", kind = "Drone", rarity = "Common", damage = 45, fireRate = 2.5, splash = 2, price = 6700 },
	{ id = "seismic_mortar", name = "Seismic Mortar", kind = "Launcher", rarity = "Common", damage = 180, fireRate = 0.5, splash = 10, price = 12000 },
	{ id = "rivet_rifle", name = "Rivet Rifle", kind = "Rifle", rarity = "Common", damage = 260, fireRate = 1.0, splash = 0, price = 23000 },

	-- Rare
	{ id = "quartz_repeater", name = "Quartz Repeater", kind = "Rifle", rarity = "Rare", damage = 370, fireRate = 1.0, splash = 0, price = 43000 },
	{ id = "coil_turret", name = "Coil Turret", kind = "Turret", rarity = "Rare", damage = 130, fireRate = 4.0, splash = 0, price = 80000 },
	{ id = "geode_turret", name = "Geode Turret", kind = "Turret", rarity = "Rare", damage = 190, fireRate = 4.0, splash = 0, price = 150000 },
	{ id = "echo_drone", name = "Echo Drone", kind = "Drone", rarity = "Rare", damage = 350, fireRate = 2.5, splash = 2, price = 280000 },
	{ id = "core_lance", name = "Core Lance", kind = "Rifle", rarity = "Rare", damage = 1500, fireRate = 1.0, splash = 0, price = 510000 },
	{ id = "shard_scattergun", name = "Shard Scattergun", kind = "Pistol", rarity = "Rare", damage = 1100, fireRate = 1.5, splash = 3, price = 950000 },
	{ id = "hive_drones", name = "Hive Drones", kind = "Drone", rarity = "Rare", damage = 920, fireRate = 2.5, splash = 3, price = 1800000 },
	{ id = "magma_mortar", name = "Magma Mortar", kind = "Launcher", rarity = "Rare", damage = 4600, fireRate = 0.5, splash = 8, price = 3300000 },
	{ id = "ember_repeater", name = "Ember Repeater", kind = "Rifle", rarity = "Rare", damage = 5900, fireRate = 1.0, splash = 0, price = 6100000 },
	{ id = "frost_turret", name = "Frost Turret", kind = "Turret", rarity = "Rare", damage = 2400, fireRate = 4.0, splash = 0, price = 11000000 },
	{ id = "tunnel_drone", name = "Tunnel Drone", kind = "Drone", rarity = "Rare", damage = 5700, fireRate = 2.5, splash = 2, price = 21000000 },

	-- Epic
	{ id = "crystal_launcher", name = "Crystal Launcher", kind = "Launcher", rarity = "Epic", damage = 35000, fireRate = 0.5, splash = 8, price = 40000000 },
	{ id = "vault_breaker", name = "Vault Breaker", kind = "Rifle", rarity = "Epic", damage = 54000, fireRate = 1.0, splash = 0, price = 73000000 },
	{ id = "storm_coil", name = "Storm Coil", kind = "Turret", rarity = "Epic", damage = 20000, fireRate = 4.0, splash = 2, price = 140000000 },
	{ id = "basalt_cannon", name = "Basalt Cannon", kind = "Launcher", rarity = "Epic", damage = 170000, fireRate = 0.5, splash = 10, price = 250000000 },
	{ id = "phase_pistol", name = "Phase Pistol", kind = "Pistol", rarity = "Epic", damage = 210000, fireRate = 1.5, splash = 0, price = 470000000 },
	{ id = "swarm_hive", name = "Swarm Hive", kind = "Drone", rarity = "Epic", damage = 160000, fireRate = 2.5, splash = 4, price = 880000000 },
	{ id = "gravel_gatling", name = "Gravel Gatling", kind = "Turret", rarity = "Epic", damage = 240000, fireRate = 4.0, splash = 0, price = 1600000000 },
	{ id = "thunder_drill", name = "Thunder Drill", kind = "Rifle", rarity = "Epic", damage = 1800000, fireRate = 1.0, splash = 0, price = 3000000000 },
	{ id = "quake_launcher", name = "Quake Launcher", kind = "Launcher", rarity = "Epic", damage = 2900000, fireRate = 0.5, splash = 12, price = 5700000000 },
	{ id = "sentinel_drone", name = "Sentinel Drone", kind = "Drone", rarity = "Epic", damage = 1900000, fireRate = 2.5, splash = 3, price = 11000000000 },

	-- Legendary
	{ id = "core_repeater", name = "Core Repeater", kind = "Rifle", rarity = "Legendary", damage = 11000000, fireRate = 1.0, splash = 0, price = 20000000000 },
	{ id = "molten_maw", name = "Molten Maw", kind = "Launcher", rarity = "Legendary", damage = 19000000, fireRate = 0.5, splash = 10, price = 36000000000 },
	{ id = "aurora_drones", name = "Aurora Drones", kind = "Drone", rarity = "Legendary", damage = 10000000, fireRate = 2.5, splash = 4, price = 68000000000 },
	{ id = "titan_gatling", name = "Titan Gatling", kind = "Turret", rarity = "Legendary", damage = 16000000, fireRate = 4.0, splash = 0, price = 130000000000 },
	{ id = "star_driller", name = "Star Driller", kind = "Rifle", rarity = "Legendary", damage = 110000000, fireRate = 1.0, splash = 0, price = 230000000000 },
	{ id = "nova_mortar", name = "Nova Mortar", kind = "Launcher", rarity = "Legendary", damage = 190000000, fireRate = 0.5, splash = 12, price = 440000000000 },
	{ id = "obsidian_sentry", name = "Obsidian Sentry", kind = "Turret", rarity = "Legendary", damage = 80000000, fireRate = 4.0, splash = 2, price = 810000000000 },
	{ id = "dragonbone_rifle", name = "Dragonbone Rifle", kind = "Rifle", rarity = "Legendary", damage = 700000000, fireRate = 1.0, splash = 0, price = 1500000000000 },

	-- Mythic
	{ id = "breach_eater", name = "Breach Eater", kind = "Drone", rarity = "Mythic", damage = 370000000, fireRate = 2.5, splash = 4, price = 2800000000000 },
	{ id = "rootbreaker", name = "Rootbreaker", kind = "Launcher", rarity = "Mythic", damage = 2400000000, fireRate = 0.5, splash = 10, price = 5200000000000 },
	{ id = "prism_lance", name = "Prism Lance", kind = "Rifle", rarity = "Mythic", damage = 4500000000, fireRate = 1.0, splash = 0, price = 9700000000000 },
	{ id = "core_heart", name = "Core Heart", kind = "Turret", rarity = "Mythic", damage = 1600000000, fireRate = 4.0, splash = 3, price = 18000000000000 },
	{ id = "planet_splitter", name = "Planet Splitter", kind = "Launcher", rarity = "Mythic", damage = 13000000000, fireRate = 0.5, splash = 14, price = 34000000000000 },
}

local byId: { [string]: Gear } = {}
local indexOf: { [string]: number } = {}
for i, gear in items do
	byId[gear.id] = gear
	indexOf[gear.id] = i
end

GearData.Items = items

function GearData.Get(id: string): Gear?
	return byId[id]
end

-- A gear's place on the ladder (1 = cheapest)
function GearData.IndexOf(id: string): number?
	return indexOf[id]
end

-- Gear of a rarity
function GearData.ByRarity(rarity: Rarity): { Gear }
	local list = {}
	for _, gear in items do
		if gear.rarity == rarity then
			table.insert(list, gear)
		end
	end
	return list
end

-- Coins to buy the next level of a gear that's at this level
function GearData.LevelCost(gear: Gear, level: number): number
	return gear.price * GearData.Levels.LevelCostShare * GearData.Levels.LevelCostGrowth ^ (level - 1)
end

-- Damage multiplier at a level (Lv 1 = 1x).
function GearData.LevelMultiplier(level: number): number
	return 1 + GearData.Levels.DamagePerLevel * (level - 1)
end

-- Copies needed to go from this level to the next.
function GearData.CopiesToLevelUp(level: number): number
	return level
end

-- Damage per shot at a level.
function GearData.Damage(gear: Gear, level: number?): number
	return gear.damage * GearData.LevelMultiplier(level or 1)
end

-- Damage per second at a level (before splash).
function GearData.DPS(gear: Gear, level: number?): number
	return GearData.Damage(gear, level) * gear.fireRate
end

-- DPS counting splash: splash guns hit several enemies at once in a crowd.
-- Each stud of splash radius counts as +10% (a 10-stud splash = 2x).
-- Used for the HUD total and for deciding which gear is stronger.
function GearData.EffectiveDPS(gear: Gear, level: number?): number
	return GearData.DPS(gear, level) * (1 + gear.splash * 0.1)
end

-- Kept for older code: DPS at level 1.
function GearData.BaseDPS(gear: Gear): number
	return GearData.DPS(gear, 1)
end

return GearData
