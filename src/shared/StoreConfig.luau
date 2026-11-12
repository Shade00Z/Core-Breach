-- StoreConfig
-- Everything sold for Robux. Boosts and convenience only: nothing here
-- changes roll odds or buys rolls.
--
-- SETTING UP (Creator Dashboard > your experience > Monetization):
--   1. Create a Pass for each entry in Passes and paste its ID into
--      gamePassId. Set the price on the dashboard (robux here is only the
--      price shown before the real one loads, and a suggestion).
--   2. Create one Developer Product for PriceSkip and paste its ID into
--      productId.
-- While an ID is 0 the item isn't for sale: players see "Coming soon", and
-- in Studio (or debug mode) the Buy button just gives it to you for testing.
--
-- kind:
--   "coins"   multiplies coins by `coins`. Only your biggest one counts
--             (4x replaces 2x, 8x replaces 4x; they don't stack).
--   "always"  on all the time once owned
--   "toggle"  owned, then switched on and off in the Store (saved)

export type Pass = {
	key: string,
	name: string,
	description: string,
	kind: "coins" | "always" | "toggle",
	gamePassId: number,
	robux: number,
	coins: number?,
}

local StoreConfig = {}

StoreConfig.Passes = {
	{ key = "coins2", name = "2x Coins", description = "Every coin you earn is doubled, for good.", kind = "coins", coins = 2, gamePassId = 0, robux = 149 },
	{ key = "coins4", name = "4x Coins", description = "Coins x4. Replaces 2x Coins.", kind = "coins", coins = 4, gamePassId = 0, robux = 399 },
	{ key = "coins8", name = "8x Coins", description = "Coins x8. Replaces 4x Coins.", kind = "coins", coins = 8, gamePassId = 0, robux = 899 },
	{ key = "autoCollect", name = "Auto-Collect", description = "Coins fly to you on their own. No more walking over them.", kind = "always", gamePassId = 0, robux = 199 },
	{ key = "autoOpen", name = "Auto-Open", description = "Your crate opens itself whenever no roll is waiting, wherever you are.", kind = "toggle", gamePassId = 0, robux = 249 },
	{ key = "autoSkip", name = "Auto-Skip", description = "Rolls below the rarity you choose are skipped for you.", kind = "toggle", gamePassId = 0, robux = 149 },
	{ key = "fastRolls", name = "Fast Rolls", description = "No roll suspense, and the crate is ready again 3x sooner.", kind = "toggle", gamePassId = 0, robux = 99 },
	{ key = "offline", name = "Long Shift", description = "Offline earnings keep going for 16 hours instead of 8.", kind = "always", gamePassId = 0, robux = 129 },
	{ key = "speed2", name = "2x Game Speed", description = "Your lane runs at double speed: enemies, gear and coins.", kind = "toggle", gamePassId = 0, robux = 299 },
} :: { Pass }

StoreConfig.ByKey = {} :: { [string]: Pass }
for _, pass in StoreConfig.Passes do
	StoreConfig.ByKey[pass.key] = pass
end

-- Pay Robux instead of coins for the roll waiting at your crate. One flat
-- price for any gear. You still have to roll it first.
StoreConfig.PriceSkip = {
	name = "Price Skip",
	description = "Take the gear waiting at your crate without paying its coin price.",
	productId = 0,
	robux = 49,
}

StoreConfig.FastRollCooldown = 0.4 -- seconds between rolls with Fast Rolls (normally CrateConfig.RollCooldown)
StoreConfig.AutoCollectDelay = 0.7 -- seconds a coin lies on the ground before Auto-Collect takes it
StoreConfig.OfflineExtraHours = 8 -- Long Shift
StoreConfig.GameSpeed = 2

-- Auto-Skip choices: skip everything below this rarity
StoreConfig.SkipBelow = { "Rare", "Epic", "Legendary", "Mythic" }

-- Settings saved with the player (toggles default to on once owned)
export type Settings = { autoOpen: boolean, autoSkip: boolean, fastRolls: boolean, speed2: boolean, skipBelow: string }
StoreConfig.DefaultSettings = { autoOpen = true, autoSkip = true, fastRolls = true, speed2 = true, skipBelow = "Rare" } :: Settings

-- The coin multiplier from the passes someone owns (the biggest one)
function StoreConfig.CoinBoost(owned: { [string]: boolean }): number
	local best = 1
	for _, pass in StoreConfig.Passes do
		if pass.kind == "coins" and owned[pass.key] and (pass.coins or 1) > best then
			best = pass.coins or 1
		end
	end
	return best
end

return StoreConfig
