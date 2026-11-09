-- LayerConfig
-- The layers of the world, top to bottom. Each layer is a floor built from
-- the same template (Modules/HubBuilder): elevator plaza, NPC outpost, mine
-- and forge, tunnel doors to the lanes, and a boss arena. Each layer has its
-- own colors, lane enemies, ore, gear and boss.
--
-- You play in one layer at a time (your "current layer"): your lane is
-- reskinned to it and your lane's exit door leads to its hub. Beating a
-- layer's boss moves you down to the next one. Your wave keeps going.
-- Re-Drill (week 7) takes you back to Layer 1.

local LayerConfig = {}

export type Boss = {
	name: string,
	level: number, -- hero level needed to challenge and hurt it
	hp: number, -- HP when fought alone
	extraFighterHp: number, -- +this share of hp for every extra player in the arena
	radius: number, -- studs, for hits
	speed: number, -- studs per second while chasing
	enragedSpeed: number, -- below half HP
	contactDamage: number, -- to a hero it's touching, once a second
	slam: { every: number, windup: number, radius: number, damage: number },
	roots: { every: number, windup: number, radius: number, damage: number, count: number },
	leashSeconds: number, -- nobody in the arena this long and it resets
	respawnSeconds: number, -- after it's beaten, before it can be challenged again
	rewards: { xpLevels: number, coinWaves: number, cores: number },
}

export type Layer = {
	id: number,
	name: string,
	hubCenter: Vector3, -- center of the layer's hub floor
	levelCap: number, -- hero level cap while you're in this layer
	coinMultiplier: number, -- lane coins x this
	luckBonus: number, -- added to your crate luck
	enemies: { normal: number, alt: number, boss: number }, -- LaneConfig.Enemies kinds
	questGiver: string, -- the NPC with this layer's quests (QuestConfig)
	trader: string,
	hub: { [string]: Color3 }, -- hub colors
	lane: { [string]: Color3 }, -- lane colors
	veins: { { ore: string, x: number, z: number } }, -- ore veins, relative to hubCenter
	boss: Boss?, -- this layer's boss (beating it unlocks the next layer)
}

-- Mine vein spots are the same shape in every layer: near the plaza, the
-- middle of the mine, and the far end. Each layer fills them with its ores.
local function veins(near: string, mid1: string, mid2: string, far1: string, far2: string)
	return {
		{ ore = near, x = -52, z = -30 }, { ore = near, x = -60, z = -12 },
		{ ore = near, x = -50, z = 8 }, { ore = near, x = -62, z = 26 },
		{ ore = near, x = -54, z = 44 }, { ore = near, x = -72, z = -42 },
		{ ore = near, x = -74, z = 0 }, { ore = near, x = -70, z = 50 },
		{ ore = mid1, x = -88, z = -30 }, { ore = mid1, x = -92, z = 12 },
		{ ore = mid1, x = -86, z = 38 }, { ore = mid1, x = -98, z = -8 },
		{ ore = mid2, x = -96, z = -48 }, { ore = mid2, x = -102, z = 30 },
		{ ore = far1, x = -114, z = -20 }, { ore = far1, x = -118, z = 18 },
		{ ore = far1, x = -112, z = 48 }, { ore = far2, x = -120, z = -44 },
		{ ore = far2, x = -122, z = 0 },
	}
end

LayerConfig.Layers = {
	{
		id = 1,
		name = "Topsoil",
		hubCenter = Vector3.new(-220, 0, 110),
		levelCap = 60,
		coinMultiplier = 1,
		luckBonus = 0,
		enemies = { normal = 1, alt = 2, boss = 3 },
		questGiver = "Foreman Rusk",
		trader = "Trader Pip",
		hub = {
			Floor = Color3.fromRGB(150, 110, 70),
			Path = Color3.fromRGB(175, 135, 90),
			Rock = Color3.fromRGB(120, 80, 70),
			Plaza = Color3.fromRGB(120, 115, 110),
			Arena = Color3.fromRGB(110, 70, 60),
			Lamp = Color3.fromRGB(255, 190, 90),
			Glow = Color3.fromRGB(255, 90, 20), -- arena cracks and furnace
		},
		lane = {
			Floor = Color3.fromRGB(58, 52, 46),
			Wall = Color3.fromRGB(110, 84, 58),
			Barricade = Color3.fromRGB(150, 110, 70),
			Breach = Color3.fromRGB(220, 40, 40),
		},
		veins = veins("copper_ore", "iron_ore", "ember_ore", "gold_ore", "frost_geode"),
		boss = {
			name = "Rootmaw",
			level = 30,
			hp = 12000,
			extraFighterHp = 0.75,
			radius = 5,
			speed = 9,
			enragedSpeed = 13,
			contactDamage = 15,
			slam = { every = 5, windup = 1.2, radius = 13, damage = 35 },
			roots = { every = 9, windup = 1.4, radius = 6, damage = 25, count = 3 },
			leashSeconds = 12,
			respawnSeconds = 20,
			rewards = { xpLevels = 1.5, coinWaves = 10, cores = 3 },
		},
	},
	{
		id = 2,
		name = "Stone Vault",
		hubCenter = Vector3.new(-220, 0, -200),
		levelCap = 120,
		coinMultiplier = 1.5,
		luckBonus = 0.25,
		enemies = { normal = 4, alt = 5, boss = 6 },
		questGiver = "Warden Sela",
		trader = "Trader Pip",
		hub = {
			Floor = Color3.fromRGB(92, 96, 110),
			Path = Color3.fromRGB(120, 124, 140),
			Rock = Color3.fromRGB(68, 72, 88),
			Plaza = Color3.fromRGB(105, 108, 122),
			Arena = Color3.fromRGB(78, 82, 98),
			Lamp = Color3.fromRGB(150, 220, 255),
			Glow = Color3.fromRGB(110, 200, 255),
		},
		lane = {
			Floor = Color3.fromRGB(48, 50, 60),
			Wall = Color3.fromRGB(85, 88, 105),
			Barricade = Color3.fromRGB(120, 125, 140),
			Breach = Color3.fromRGB(80, 170, 255),
		},
		veins = veins("copper_ore", "iron_ore", "ember_ore", "crystal_ore", "crystal_ore"),
		boss = nil, -- the Stone Vault boss arrives with Layer 3 (week 8)
	},
} :: { Layer }

function LayerConfig.Get(layer: number?): Layer
	return LayerConfig.Layers[layer or 1] or LayerConfig.Layers[1]
end

-- Hero level cap in a layer
function LayerConfig.LevelCap(layer: number?): number
	return LayerConfig.Get(layer).levelCap
end

return LayerConfig
