-- LaneConfig
-- Size, layout and wave tuning for player lanes. Tune here, not in scripts.

local LaneConfig = {
	-- Layout (studs)
	Width = 30, -- inside width of a lane
	Length = 220, -- player end to breach hole
	Spacing = 60, -- distance between lanes side by side
	StartZ = 10, -- where lane 1's player end sits
	MaxLanes = 6, -- one lane per player in the server

	-- Barricade
	BarricadeDistance = 14, -- how far up the lane the barricade sits
	BarricadeMaxHP = 100, -- refills at the start of every wave

	-- How hard leaks hit. If an entire wave reaches the barricade untouched,
	-- it deals LeakDamage x the barricade's max HP. Each enemy deals its share
	-- of that, based on the HP it still has left. At 4, letting more than a
	-- quarter of a wave's HP through breaks the barricade, so you can't just
	-- let it tank: you must kill at least 75% of every wave.
	LeakDamage = 4,

	-- Gear wall slots (distance up the lane, 3 per side = 6 slots)
	SlotDistances = { 30, 55, 80 },

	-- Wave size: count = BaseEnemyCount + EnemiesPerWave x wave, up to
	-- MaxEnemyCount. Past the cap, waves get tougher (more HP), not bigger.
	BaseEnemyCount = 7,
	EnemiesPerWave = 1.3,
	MaxEnemyCount = 50,
	SwarmEvery = 10, -- every 10th wave (that isn't a boss wave) is a swarm wave
	SwarmMultiplier = 1.5, -- swarm waves have 1.5x the enemies...
	SwarmMax = 90, -- ...up to this many
	BossMinions = 8, -- grubs that come with each boss
	BossCoinMultiplier = 3, -- boss waves pay 3x coins

	-- Gear slots open from the start (the rest are dug out in week 3), and
	-- the gear a new player starts with. Slots: 1-3 left wall, 4-6 right wall,
	-- front to back.
	StarterSlots = { 1, 4 },
	StarterGear = { [1] = "rusty_pistol" },
	SpawnSpread = 8, -- seconds over which a wave's enemies spawn
	IntermissionSeconds = 3, -- pause between waves
	FailRestartSeconds = 4, -- pause before retrying a failed wave

	-- Coin drops: kills drop coins that land on the player's side of the
	-- barricade. Walk over them to collect (they only count once collected).
	CoinDrops = {
		PickupRadius = 6, -- studs from your character
		MaxOnGround = 60, -- more than this and new coins join existing piles
		LandMinDistance = 2, -- landing area, measured up the lane from the player end
		LandMaxDistance = 11,
		KeepClearOfCenter = 3.5, -- don't land on the crate
	},

	-- Network
	SnapshotRate = 5, -- enemy updates sent per second

	-- Enemy kinds (id = number sent to clients). Speed in studs per second.
	-- breaksBarricade: reaching the barricade breaks it instantly, so the
	-- wave is lost and restarts (bosses must be killed).
	Enemies = {
		[1] = { name = "BurrowGrub", speed = 11 },
		[2] = { name = "SkeletonMiner", speed = 8 },
		[3] = { name = "LayerBoss", speed = 5, breaksBarricade = true },
	},
}

return LaneConfig
