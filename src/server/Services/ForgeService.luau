-- ForgeService
-- The forge, by the mine entrance in the hub. Three things happen here
-- (client: ForgeController; remote: ForgeAction):
--
--   Forge    pick a gear you own and feed it loot. The loot's total value
--            sets the gear's damage multiplier (LootConfig.BaseMultiplier),
--            then the strike rolls it +/- 15%. If the gear was forged
--            before, it keeps whichever multiplier is better. Element loot
--            adds traits (Ember Ore: Burn, Frost Geode: Slow, Boss Core:
--            Core), which stay on the gear for good.
--   Salvage  turn gear you don't want (not on your wall) into Salvage Scrap,
--            worth price x level x LootConfig.SalvageShare in forge value.
--   Pickaxe  upgrade your pickaxe with coins + ore (LootConfig.Pickaxes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LootConfig = require(Shared:WaitForChild("LootConfig"))
local GearData = require(Shared:WaitForChild("GearData"))
local Format = require(Shared:WaitForChild("Format"))

local ACTION_COOLDOWN = 0.4

local ForgeService = {}

local services
local notify: RemoteEvent
local resultRemote: RemoteEvent
local rng = Random.new()
local lastAction: { [Player]: number } = {}

local function isMounted(data, gearId: string): boolean
	for _, id in data.slots do
		if id == gearId then
			return true
		end
	end
	return false
end

local function forge(player: Player, gearId: unknown, selection: unknown)
	if type(gearId) ~= "string" or type(selection) ~= "table" then
		return
	end
	local data = services.DataService:Get(player)
	local owned = data.owned[gearId]
	local gear = GearData.Get(gearId)
	if not owned or not gear then
		return
	end
	-- Only known item ids
	local clean = {}
	for itemId, count in selection :: { [any]: any } do
		if type(itemId) ~= "string" or not LootConfig.Items[itemId] then
			return
		end
		clean[itemId] = count
	end

	local value, traits = services.LootService:Take(player, clean)
	if not value then
		notify:FireClient(player, "You don't have that much loot.")
		return
	end

	local base = LootConfig.BaseMultiplier(value, gear.price)
	local spread = LootConfig.Forge.Randomness
	local rolled = base * rng:NextNumber(1 - spread, 1 + spread)

	local forgeData = owned.forge or { mult = 1, traits = {} }
	local previous = forgeData.mult
	local improved = rolled > previous
	if improved then
		forgeData.mult = rolled
	end
	local newTraits = {}
	for trait in traits do
		if not forgeData.traits[trait] then
			forgeData.traits[trait] = true
			table.insert(newTraits, trait)
		end
	end
	owned.forge = forgeData

	services.GearService:RefreshGear(player, gearId)
	resultRemote:FireClient(player, {
		gearId = gearId,
		value = value,
		rolled = rolled,
		previous = previous,
		best = forgeData.mult,
		improved = improved,
		newTraits = newTraits,
	})
end

local function salvage(player: Player, gearId: unknown)
	if type(gearId) ~= "string" then
		return
	end
	local data = services.DataService:Get(player)
	local owned = data.owned[gearId]
	local gear = GearData.Get(gearId)
	if not owned or not gear then
		return
	end
	if isMounted(data, gearId) then
		notify:FireClient(player, "Take it off your wall first (Gear panel).")
		return
	end
	local value = LootConfig.SalvageValue(gear.price, owned.level)
	data.owned[gearId] = nil
	services.LootService:Add(player, "scrap", 1, value)
	services.GearService:RefreshDps(player)
	notify:FireClient(player, "Salvaged " .. gear.name .. " for " .. Format.Number(value) .. " forge value.")
end

local function upgradePickaxe(player: Player)
	local data = services.DataService:Get(player)
	local nextTier = data.pickaxeTier + 1
	local pickaxe = LootConfig.Pickaxes[nextTier]
	if not pickaxe or not pickaxe.cost then
		notify:FireClient(player, "Your pickaxe is already the best there is (for now).")
		return
	end
	local cost = pickaxe.cost
	if not services.LootService:Has(player, cost.items) then
		notify:FireClient(player, "You need more ore for the " .. pickaxe.name .. ".")
		return
	end
	if data.coins < cost.coins then
		notify:FireClient(player, "You need $" .. Format.Number(cost.coins) .. " for the " .. pickaxe.name .. ".")
		return
	end
	services.LootService:Take(player, cost.items)
	services.EconomyService:SpendCoins(player, cost.coins)
	data.pickaxeTier = nextTier
	services.CharacterService:RefreshPickaxe(player)
	services.DigService:Refresh(player)
	services.LootService:Refresh(player)
	notify:FireClient(player, "You got the " .. pickaxe.name .. "!")
end

-- Dev cheat: a pile of every loot type
function ForgeService:GiveTestLoot(player: Player)
	local LootService = services.LootService
	for _, itemId in LootConfig.ItemOrder do
		local item = LootConfig.Items[itemId]
		if item.kind == "Ore" then
			LootService:Add(player, itemId, 50)
		elseif item.kind == "Part" then
			LootService:Add(player, itemId, 20, 20 * 40)
		elseif item.kind == "Core" then
			LootService:Add(player, itemId, 2, 2 * 500)
		end
	end
end

function ForgeService:Init(allServices)
	services = allServices
end

function ForgeService:Start()
	notify = Remotes.Event("Notify")
	resultRemote = Remotes.Event("ForgeResult")
	Remotes.Event("ForgeAction").OnServerEvent:Connect(function(player, action, a, b)
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < ACTION_COOLDOWN then
			return
		end
		lastAction[player] = now
		if action == "Forge" then
			forge(player, a, b)
		elseif action == "Salvage" then
			salvage(player, a)
		elseif action == "UpgradePickaxe" then
			upgradePickaxe(player)
		end
	end)
end

return ForgeService
