-- LootService
-- Your bag of loot: ore, monster parts, boss cores and salvage scrap.
-- Loot goes straight into the bag (no pickup) with a "+3 Copper Ore" message.
--
-- Each stack is { count, value }: value is the total forge value of the
-- stack. Ore always has the same value per piece; monster parts and boss
-- cores are worth more the deeper the wave they dropped from.
--
-- Drops from your lane (LootConfig.Drops):
--   any kill   PartChance (x Fortune luck) to drop a monster part
--   boss kill  always drops a Boss Core

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LootConfig = require(Shared:WaitForChild("LootConfig"))
local Format = require(Shared:WaitForChild("Format"))

local MESSAGE_INTERVAL = 1.5 -- ore and cores are announced this often
local PART_MESSAGE_INTERVAL = 10 -- monster parts drop a lot; they're grouped over longer

local LootService = {}

local services
local notify: RemoteEvent
local rng = Random.new()
local gains: { [Player]: { [string]: number } } = {} -- waiting to be announced
local partGains: { [Player]: { [string]: number } } = {}

local function bagOf(player: Player): { [string]: { count: number, value: number } }
	return services.DataService:Get(player).loot
end

local function pushBag(player: Player)
	local data = services.DataService:Get(player)
	local items = {}
	for id, stack in data.loot do
		if stack.count > 0 then
			items[id] = { count = stack.count, value = stack.value }
		end
	end
	services.EconomyService:PushStats(player, {
		bag = { items = items, pickaxe = data.pickaxeTier },
	})
end

function LootService:Refresh(player: Player)
	pushBag(player)
end

-- Adds loot to the bag. value = total forge value of all of them (ore can
-- leave it out: it uses the ore's fixed value).
function LootService:Add(player: Player, itemId: string, count: number, value: number?)
	local item = LootConfig.Items[itemId]
	if not item or count <= 0 then
		return
	end
	local bag = bagOf(player)
	local stack = bag[itemId] or { count = 0, value = 0 }
	stack.count += count
	stack.value += value or (item.value or 0) * count
	bag[itemId] = stack
	pushBag(player)

	local queue = if item.kind == "Part" then partGains else gains
	local pending = queue[player] or {}
	pending[itemId] = (pending[itemId] or 0) + count
	queue[player] = pending
end

-- Takes loot out of the bag, e.g. { copper_ore = 10, boss_core = 1 }.
-- Returns the total value and the traits it carries, or nil if the player
-- doesn't have all of it (then nothing is taken).
function LootService:Take(player: Player, selection: { [string]: number }): (number?, { [string]: boolean })
	local bag = bagOf(player)
	local traits = {}
	-- Check first
	local any = false
	for itemId, count in selection do
		local stack = bag[itemId]
		if type(count) ~= "number" or count ~= math.floor(count) or count < 0 or not stack or stack.count < count then
			return nil, traits
		end
		if count > 0 then
			any = true
		end
	end
	if not any then
		return nil, traits
	end
	-- Then take
	local total = 0
	for itemId, count in selection do
		if count > 0 then
			local stack = bag[itemId]
			local value = stack.value * (count / stack.count) -- the average piece
			stack.count -= count
			stack.value -= value
			if stack.count <= 0 then
				bag[itemId] = nil
			end
			total += value
			local trait = LootConfig.Items[itemId].trait
			if trait then
				traits[trait] = true
			end
		end
	end
	pushBag(player)
	return total, traits
end

-- Can the player afford these items (e.g. a pickaxe upgrade)?
function LootService:Has(player: Player, items: { [string]: number }): boolean
	local bag = bagOf(player)
	for itemId, count in items do
		local stack = bag[itemId]
		if not stack or stack.count < count then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------
-- Drops from kills
------------------------------------------------------------------------

local function onEnemyKilled(lane, enemy)
	local player = lane.owner
	local WaveService = services.WaveService
	local drops = LootConfig.Drops
	if WaveService.IsBoss(lane.wave) and enemy.kind == 3 then
		LootService:Add(player, "boss_core", 1, WaveService.WaveCoins(lane.wave) * drops.CoreValue)
		return
	end
	local partId = drops.PartByEnemy[enemy.kind]
	if not partId then
		return
	end
	local luck = services.CharacterService:GetEffects(player).luck -- Fortune
	if rng:NextNumber() < drops.PartChance * luck then
		local killCoins = WaveService.WaveCoins(lane.wave) * (enemy.maxHp / lane.waveTotalHp)
		LootService:Add(player, partId, 1, math.max(1, killCoins * drops.PartValue))
	end
end

------------------------------------------------------------------------

function LootService:Init(allServices)
	services = allServices
end

function LootService:Start()
	notify = Remotes.Event("Notify")
	services.WaveService.EnemyKilled:Connect(onEnemyKilled)

	local DataService = services.DataService
	DataService.Loaded:Connect(pushBag)
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			pushBag(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		gains[player] = nil
		partGains[player] = nil
	end)

	-- "+3 Copper Ore, +1 Boss Core" every MESSAGE_INTERVAL; monster parts
	-- grouped over PART_MESSAGE_INTERVAL so they don't flood the screen
	local function announce(queue, interval: number)
		task.spawn(function()
			while true do
				task.wait(interval)
				for player, pending in queue do
					queue[player] = nil
					if player.Parent == Players then
						local parts = {}
						for _, itemId in LootConfig.ItemOrder do
							local count = pending[itemId]
							if count then
								table.insert(parts, "+" .. Format.Number(count) .. " " .. LootConfig.Items[itemId].name)
							end
						end
						if #parts > 0 then
							notify:FireClient(player, table.concat(parts, ", "))
						end
					end
				end
			end
		end)
	end
	announce(gains, MESSAGE_INTERVAL)
	announce(partGains, PART_MESSAGE_INTERVAL)
end

return LootService
