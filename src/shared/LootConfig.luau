-- LootConfig
-- Loot, mining, pickaxes, the forge and salvage. Tune here, not in scripts.
--
-- Loot goes straight into your bag (no pickup). Every loot stack has a
-- forge VALUE; the forge turns value into a damage multiplier for one gear.
--   Ore        from ore veins in the mine (west of the hub)
--   Parts      from kills in your lane (chance per kill; Fortune raises it)
--   Boss cores from wave bosses (always drop)
--   Scrap      from salvaging gear you don't want

local LootConfig = {}

export type Item = {
	id: string,
	name: string,
	kind: "Ore" | "Part" | "Core" | "Scrap",
	color: Color3,
	value: number?, -- forge value of one (ore); parts/cores/scrap get their value when they drop
	trait: string?, -- forge trait it adds (see Traits)
}

LootConfig.Items = {
	copper_ore = { id = "copper_ore", name = "Copper Ore", kind = "Ore", color = Color3.fromRGB(205, 120, 70), value = 2 },
	iron_ore = { id = "iron_ore", name = "Iron Ore", kind = "Ore", color = Color3.fromRGB(170, 175, 190), value = 6 },
	ember_ore = { id = "ember_ore", name = "Ember Ore", kind = "Ore", color = Color3.fromRGB(255, 90, 30), value = 10, trait = "burn" },
	gold_ore = { id = "gold_ore", name = "Gold Ore", kind = "Ore", color = Color3.fromRGB(255, 200, 50), value = 15 },
	frost_geode = { id = "frost_geode", name = "Frost Geode", kind = "Ore", color = Color3.fromRGB(120, 210, 255), value = 25, trait = "slow" },
	crystal_ore = { id = "crystal_ore", name = "Vault Crystal", kind = "Ore", color = Color3.fromRGB(190, 140, 255), value = 40 }, -- Stone Vault
	magma_ore = { id = "magma_ore", name = "Magma Ore", kind = "Ore", color = Color3.fromRGB(255, 90, 20), value = 80, trait = "burn" }, -- Magma Belt
	grub_chitin = { id = "grub_chitin", name = "Grub Chitin", kind = "Part", color = Color3.fromRGB(140, 100, 70) },
	old_bone = { id = "old_bone", name = "Old Bone", kind = "Part", color = Color3.fromRGB(230, 225, 205) },
	golem_shard = { id = "golem_shard", name = "Golem Shard", kind = "Part", color = Color3.fromRGB(150, 150, 165) }, -- Stone Vault
	bat_wing = { id = "bat_wing", name = "Bat Wing", kind = "Part", color = Color3.fromRGB(110, 80, 130) }, -- Stone Vault
	magma_scale = { id = "magma_scale", name = "Magma Scale", kind = "Part", color = Color3.fromRGB(150, 60, 30) }, -- Magma Belt
	imp_horn = { id = "imp_horn", name = "Imp Horn", kind = "Part", color = Color3.fromRGB(230, 120, 60) }, -- Magma Belt
	boss_core = { id = "boss_core", name = "Boss Core", kind = "Core", color = Color3.fromRGB(255, 60, 90), trait = "core" },
	scrap = { id = "scrap", name = "Salvage Scrap", kind = "Scrap", color = Color3.fromRGB(150, 150, 160) },
} :: { [string]: Item }

-- Order items are listed in the bag and the forge
LootConfig.ItemOrder = { "copper_ore", "iron_ore", "ember_ore", "gold_ore", "frost_geode", "crystal_ore", "magma_ore", "grub_chitin", "old_bone", "golem_shard", "bat_wing", "magma_scale", "imp_horn", "boss_core", "scrap" }

------------------------------------------------------------------------
-- Drops from your lane
------------------------------------------------------------------------

LootConfig.Drops = {
	PartChance = 0.12, -- per kill, x the Fortune stat's luck bonus
	PartValue = 3, -- a part is worth this many times the coins its kill paid
	PartByEnemy = { [1] = "grub_chitin", [2] = "old_bone", [4] = "golem_shard", [5] = "bat_wing", [7] = "magma_scale", [8] = "imp_horn" }, -- enemy kind -> part
	CoreValue = 2, -- a boss core is worth this many times the boss wave's coins
}

------------------------------------------------------------------------
-- Mining (ore veins in the mine)
------------------------------------------------------------------------

-- hp: swings to break with a tier-1 pickaxe (better pickaxes break faster)
-- tier: pickaxe tier needed; yield: ore per break {min, max}; respawn: seconds
LootConfig.Veins = {
	copper_ore = { hp = 5, tier = 1, yield = { 3, 5 }, respawn = 25 },
	iron_ore = { hp = 8, tier = 2, yield = { 2, 4 }, respawn = 35 },
	ember_ore = { hp = 10, tier = 2, yield = { 2, 3 }, respawn = 45 },
	gold_ore = { hp = 12, tier = 3, yield = { 2, 3 }, respawn = 50 },
	frost_geode = { hp = 14, tier = 3, yield = { 1, 2 }, respawn = 60 },
	crystal_ore = { hp = 12, tier = 2, yield = { 2, 3 }, respawn = 50 },
	magma_ore = { hp = 16, tier = 4, yield = { 2, 3 }, respawn = 60 },
}
LootConfig.MiningRange = 7 -- studs from your character to a vein's surface
LootConfig.MiningXP = 5 -- XP per point of ore value you mine

------------------------------------------------------------------------
-- Pickaxes
------------------------------------------------------------------------

-- power: how much each swing chips off a vein (x the Excavation stat)
-- cost: what upgrading TO this tier costs (coins + ore)
LootConfig.Pickaxes = {
	{ name = "Stone Pickaxe", power = 1, color = Color3.fromRGB(120, 120, 125) },
	{ name = "Iron Pickaxe", power = 2, color = Color3.fromRGB(190, 195, 210), cost = { coins = 500, items = { copper_ore = 40 } } },
	{ name = "Gold Pickaxe", power = 3.5, color = Color3.fromRGB(255, 200, 50), cost = { coins = 5000, items = { iron_ore = 30, ember_ore = 10 } } },
	{ name = "Obsidian Pickaxe", power = 5, color = Color3.fromRGB(70, 40, 80), cost = { coins = 5000000, items = { gold_ore = 30, crystal_ore = 20 } } },
}

-- Wall slots that need a better pickaxe to dig out (slot index -> tier).
-- The deepest slot on each side needs an Iron Pickaxe.
LootConfig.WallSlotTiers = { [3] = 2, [6] = 2 }

------------------------------------------------------------------------
-- Forge
------------------------------------------------------------------------

-- Multiplier from loot value, before randomness:
--   1 + log10(1 + value / (gear price x RefShare))
-- So loot worth the gear's price gives about x2, and every 10x more loot
-- adds +1x (it never caps). The strike then rolls +/- Randomness.
-- Forging a gear again keeps whichever multiplier is better.
LootConfig.Forge = {
	RefShare = 0.1,
	Randomness = 0.15,
}

-- Traits come from the loot you forge in, and stay on the gear forever.
LootConfig.Traits = {
	burn = { name = "Burn", color = Color3.fromRGB(255, 110, 40), damage = 0.25, blurb = "+25% damage (burns over time)" },
	slow = { name = "Slow", color = Color3.fromRGB(120, 210, 255), slowFactor = 0.7, slowSeconds = 1.5, blurb = "hits slow enemies by 30%" },
	core = { name = "Core", color = Color3.fromRGB(255, 60, 90), fireRate = 0.15, blurb = "+15% fire rate" },
}

-- Salvage: gear you don't want becomes scrap worth price x level x this
LootConfig.SalvageShare = 0.5

------------------------------------------------------------------------
-- Formulas
------------------------------------------------------------------------

function LootConfig.BaseMultiplier(value: number, gearPrice: number): number
	local ref = math.max(1, gearPrice * LootConfig.Forge.RefShare)
	return 1 + math.log10(1 + math.max(0, value) / ref)
end

-- Damage and fire-rate multipliers a forged gear gets from its forge data
function LootConfig.ForgeBonus(forge: { mult: number, traits: { [string]: boolean }? }?): (number, number)
	if not forge then
		return 1, 1
	end
	local damage = forge.mult or 1
	local rate = 1
	local traits = forge.traits
	if traits then
		if traits.burn then
			damage *= 1 + LootConfig.Traits.burn.damage
		end
		if traits.core then
			rate *= 1 + LootConfig.Traits.core.fireRate
		end
	end
	return damage, rate
end

function LootConfig.SalvageValue(gearPrice: number, level: number): number
	return math.floor(gearPrice * level * LootConfig.SalvageShare)
end

return LootConfig
