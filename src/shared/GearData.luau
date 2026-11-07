-- GearData
-- Every piece of gear the crate can roll, plus how gear levels work.
-- Add new gear here, not in scripts.
--
-- Gear shoots anywhere in the lane (no range limit), so it starts firing as
-- soon as an enemy comes out of the breach.
--
-- Levels: rolling and buying gear you already own adds a copy toward its
-- next level instead of giving you a second one. Going from level N to N+1
-- takes N copies (1, then 2, then 3...), and every level adds
-- Levels.DamagePerLevel to its damage.
--
-- Rarity weights are placeholders: tune them in playtests and show the real
-- odds on the odds screen (week 9).

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
	Common = { order = 1, weight = 60, color = Color3.fromRGB(190, 190, 190) },
	Rare = { order = 2, weight = 28, color = Color3.fromRGB(70, 150, 255) },
	Epic = { order = 3, weight = 10, color = Color3.fromRGB(170, 80, 255) },
	Legendary = { order = 4, weight = 2, color = Color3.fromRGB(255, 180, 40) },
	Mythic = { order = 5, weight = 0, color = Color3.fromRGB(255, 60, 120) }, -- no Mythics yet
}

GearData.Levels = {
	MaxLevel = 10,
	DamagePerLevel = 0.5, -- +50% of level-1 damage per level (Lv 3 = 2x damage)
}

-- Gray-box model shape for each kind of gear (used on the wall and above the crate)
GearData.Shapes = {
	Pistol = { size = Vector3.new(1, 1, 2.2), lift = 0 },
	Rifle = { size = Vector3.new(0.8, 0.8, 4), lift = 0 },
	Turret = { size = Vector3.new(2, 1.6, 2.6), lift = 0 },
	Drone = { size = Vector3.new(1.8, 1.8, 1.8), lift = 2.5, ball = true },
	Launcher = { size = Vector3.new(1.6, 1.6, 3.2), lift = 0 },
} :: { [string]: { size: Vector3, lift: number, ball: boolean? } }

local items: { Gear } = {
	-- Common
	{ id = "rusty_pistol", name = "Rusty Pistol", kind = "Pistol", rarity = "Common", damage = 4, fireRate = 1.5, splash = 0, price = 25 },
	{ id = "miners_rifle", name = "Miner's Rifle", kind = "Rifle", rarity = "Common", damage = 7, fireRate = 1, splash = 0, price = 40 },
	{ id = "scrap_turret", name = "Scrap Turret", kind = "Turret", rarity = "Common", damage = 3, fireRate = 3, splash = 0, price = 60 },

	-- Rare
	{ id = "lamp_drone", name = "Lamp Drone", kind = "Drone", rarity = "Rare", damage = 9, fireRate = 2, splash = 0, price = 180 },
	{ id = "twin_blaster", name = "Twin Blaster", kind = "Pistol", rarity = "Rare", damage = 8, fireRate = 3, splash = 0, price = 220 },
	{ id = "drill_cannon", name = "Drill Cannon", kind = "Launcher", rarity = "Rare", damage = 20, fireRate = 0.6, splash = 6, price = 300 },

	-- Epic
	{ id = "gatling_rig", name = "Gatling Rig", kind = "Turret", rarity = "Epic", damage = 6, fireRate = 8, splash = 0, price = 1200 },
	{ id = "seismic_mortar", name = "Seismic Mortar", kind = "Launcher", rarity = "Epic", damage = 60, fireRate = 0.4, splash = 10, price = 1500 },

	-- Legendary
	{ id = "core_lance", name = "Core Lance", kind = "Rifle", rarity = "Legendary", damage = 140, fireRate = 0.8, splash = 0, price = 9000 },
	{ id = "hive_drones", name = "Hive Drones", kind = "Drone", rarity = "Legendary", damage = 18, fireRate = 6, splash = 3, price = 12000 },
}

local byId: { [string]: Gear } = {}
for _, gear in items do
	byId[gear.id] = gear
end

GearData.Items = items

function GearData.Get(id: string): Gear?
	return byId[id]
end

function GearData.ByRarity(rarity: Rarity): { Gear }
	local list = {}
	for _, gear in items do
		if gear.rarity == rarity then
			table.insert(list, gear)
		end
	end
	return list
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
