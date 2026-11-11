-- Boosts
-- Permanent bonuses that stay through rebirths:
--   * Re-Drill: x1.5 gear damage and +10% luck per Re-Drill (ProgressionConfig)
--   * Gear Index: each completed page of the collection book gives a bonus.
--     A page is complete when you've owned every gear on it at least once
--     (your "discovered" list, which nothing ever resets).
-- The server applies these through CharacterService:GetEffects; the client
-- shows them on the Index screen.

local Shared = script.Parent
local GearData = require(Shared:WaitForChild("GearData"))
local Config = require(Shared:WaitForChild("ProgressionConfig"))

export type Page = {
	id: string,
	name: string,
	gear: { string }, -- gear ids on this page
	bonus: { damage: number?, coins: number?, luck: number? }, -- added to the multiplier (0.1 = +10%)
	bonusText: string,
}

export type Totals = {
	damage: number, -- gear damage multiplier
	coins: number, -- coin multiplier (on top of rebirths)
	luck: number, -- crate luck multiplier
}

local Boosts = {}

-- Gear Index pages
local function gearWhere(test: (GearData.Gear) -> boolean): { string }
	local list = {}
	for _, gear in GearData.Items do
		if test(gear) then
			table.insert(list, gear.id)
		end
	end
	return list
end

local function page(rarity: string, bonus, bonusText: string): Page
	return {
		id = string.lower(rarity),
		name = rarity .. " gear",
		gear = gearWhere(function(gear)
			return gear.rarity == rarity
		end),
		bonus = bonus,
		bonusText = bonusText,
	}
end

-- One page per rarity
Boosts.Pages = {
	page("Common", { coins = 0.05 }, "+5% coins"),
	page("Rare", { damage = 0.1 }, "+10% gear damage"),
	page("Epic", { coins = 0.1 }, "+10% coins"),
	page("Legendary", { luck = 0.15 }, "+15% luck"),
	page("Mythic", { damage = 0.25 }, "+25% gear damage"),
} :: { Page }

-- How many gear on a page you've discovered
function Boosts.PageProgress(page: Page, discovered: { [string]: boolean }?): number
	local count = 0
	for _, gearId in page.gear do
		if discovered and discovered[gearId] then
			count += 1
		end
	end
	return count
end

function Boosts.PageComplete(page: Page, discovered: { [string]: boolean }?): boolean
	return #page.gear > 0 and Boosts.PageProgress(page, discovered) >= #page.gear
end

-- Everything added up, for a player's save data
function Boosts.For(data: { reDrills: number?, discovered: { [string]: boolean }? }): Totals
	local reDrills = data.reDrills or 0
	local totals: Totals = {
		damage = Config.ReDrill.DPSMult ^ reDrills,
		coins = 1,
		luck = 1 + Config.ReDrill.LuckBonus * reDrills,
	}
	for _, page in Boosts.Pages do
		if Boosts.PageComplete(page, data.discovered) then
			totals.damage *= 1 + (page.bonus.damage or 0)
			totals.coins *= 1 + (page.bonus.coins or 0)
			totals.luck *= 1 + (page.bonus.luck or 0)
		end
	end
	return totals
end

return Boosts
