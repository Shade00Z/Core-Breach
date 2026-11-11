-- PowerService
-- Core Powers (PowerData): Power Crystals, opening them, equipping a power
-- and mastery. Casting the abilities is AbilityService.
--
--   * Crystals come from layer bosses (BossService), lane wave bosses
--     (LootService), Magma Ore veins (MiningService), and one free crystal
--     when you reach level 30.
--   * Opening one rolls a power. A new power is yours (and equipped if you
--     had none); one you already have gets a big chunk of mastery instead.
--   * Abilities give mastery XP for every enemy they hit (AddMastery).
--
-- The client gets { powers = { crystals, equipped, owned = { [id] = { xp,
-- level } } } } stats, and a PowerResult event after opening a crystal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local PowerData = require(Shared:WaitForChild("PowerData"))

local STARTER_LEVEL = 30 -- level that gives your first crystal
local ACTION_COOLDOWN = 0.5
local OPEN_COOLDOWN = 2.5 -- the reveal takes about this long
local PUSH_INTERVAL = 0.5

local PowerService = {}

local services
local notify: RemoteEvent
local resultRemote: RemoteEvent
local rng = Random.new()
local lastAction: { [Player]: number } = {}
local lastOpen: { [Player]: number } = {}
local dirty: { [Player]: boolean } = {}

local function powersOf(player: Player)
	return services.DataService:Get(player).powers
end

local function push(player: Player)
	local powers = powersOf(player)
	local owned = {}
	for id, state in powers.owned do
		owned[id] = { xp = state.xp, level = PowerData.MasteryLevel(state.xp) }
	end
	services.EconomyService:PushStats(player, {
		powers = { crystals = powers.crystals, equipped = powers.equipped, owned = owned },
	})
end

function PowerService:Refresh(player: Player)
	push(player)
end

function PowerService:GiveCrystals(player: Player, count: number)
	if count <= 0 or not services.DataService:IsLoaded(player) then
		return
	end
	powersOf(player).crystals += count
	notify:FireClient(player, string.format("+%d Power Crystal%s! Open %s in the Powers menu.", count, if count == 1 then "" else "s", if count == 1 then "it" else "them"))
	push(player)
end

-- The equipped power and its mastery level (nil if none)
function PowerService:GetEquipped(player: Player): (PowerData.Power?, number)
	local powers = powersOf(player)
	local power = PowerData.Get(powers.equipped)
	local state = power and powers.owned[power.id]
	if not power or not state then
		return nil, 1
	end
	return power, PowerData.MasteryLevel(state.xp)
end

-- Mastery XP for a power (its abilities hit something)
function PowerService:AddMastery(player: Player, powerId: string, xp: number)
	local state = powersOf(player).owned[powerId]
	if not state or xp <= 0 then
		return
	end
	local before = PowerData.MasteryLevel(state.xp)
	state.xp += xp
	local after = PowerData.MasteryLevel(state.xp)
	if after > before then
		local power = PowerData.Powers[powerId]
		local unlocked = ""
		for _, ability in power.abilities do
			if ability.mastery > before and ability.mastery <= after then
				unlocked = "  New ability: " .. ability.name .. "!"
			end
		end
		notify:FireClient(player, string.format("%s mastery %d!%s", power.name, after, unlocked))
		push(player)
	else
		dirty[player] = true
	end
end

local function open(player: Player)
	local now = os.clock()
	if lastOpen[player] and now - lastOpen[player] < OPEN_COOLDOWN then
		return
	end
	local powers = powersOf(player)
	if powers.crystals <= 0 then
		return
	end
	lastOpen[player] = now
	powers.crystals -= 1

	local power = PowerData.Roll(rng)
	local state = powers.owned[power.id]
	local duplicate = state ~= nil
	if duplicate then
		state.xp += PowerData.Mastery.DuplicateXP
	else
		powers.owned[power.id] = { xp = 0 }
		if powers.equipped == "" then
			powers.equipped = power.id
		end
	end
	resultRemote:FireClient(player, {
		powerId = power.id,
		duplicate = duplicate,
		level = PowerData.MasteryLevel(powers.owned[power.id].xp),
	})
	-- After the reveal, so the screen doesn't show the result early
	task.delay(OPEN_COOLDOWN - 0.3, function()
		if player.Parent == Players then
			push(player)
		end
	end)
end

local function onAction(player: Player, action: unknown, powerId: unknown)
	if not services.DataService:IsLoaded(player) then
		return
	end
	if action == "Open" then
		open(player)
		return
	end
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now
	local powers = powersOf(player)
	if action == "Equip" and type(powerId) == "string" and powers.owned[powerId] then
		powers.equipped = powerId
		push(player)
	elseif action == "Unequip" then
		powers.equipped = ""
		push(player)
	end
end

-- The free crystal at level 30 (also covers saves from before Core Powers)
local function checkStarter(player: Player)
	local data = services.DataService:Get(player)
	if not data.powers.starterGiven and data.level >= STARTER_LEVEL then
		data.powers.starterGiven = true
		PowerService:GiveCrystals(player, 1)
	end
end

function PowerService:Init(allServices)
	services = allServices
end

function PowerService:Start()
	notify = Remotes.Event("Notify")
	resultRemote = Remotes.Event("PowerResult")
	Remotes.Event("PowerAction").OnServerEvent:Connect(onAction)

	local DataService = services.DataService
	local function onLoaded(player: Player)
		push(player)
		checkStarter(player)
	end
	DataService.Loaded:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			onLoaded(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastOpen[player] = nil
		dirty[player] = nil
	end)

	local timer, starterTimer = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		starterTimer += dt
		if timer >= PUSH_INTERVAL then
			timer = 0
			for player in dirty do
				dirty[player] = nil
				if player.Parent == Players and DataService:IsLoaded(player) then
					push(player)
				end
			end
		end
		if starterTimer >= 5 then
			starterTimer = 0
			for _, player in Players:GetPlayers() do
				if DataService:IsLoaded(player) then
					checkStarter(player)
				end
			end
		end
	end)
end

return PowerService
