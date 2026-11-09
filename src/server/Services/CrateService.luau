-- CrateService
-- The core crate: free rolls that reveal one piece of gear with a coin price.
-- The player then chooses:
--   Buy       pay the price and get the gear (GearService:Give). Gear you
--             already own gains a copy toward its next level instead.
--   Skip      throw it away and roll again
-- Until you choose, the roll waits at the crate (walk away and it floats
-- above it), so you can save up for something you can't afford yet.
--
-- Rolls happen on the server only. Luck rises each time you beat a new
-- multiple of 10 waves for the first time, and rebirths keep it (CrateConfig).
-- Deeper layers add luck and their own gear set (LayerConfig, GearData).
-- Robux "skip cost" arrives in week 9; luck boosts are never sold for Robux.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearData = require(Shared:WaitForChild("GearData"))
local CrateConfig = require(Shared:WaitForChild("CrateConfig"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

type Pending = { gearId: string, price: number }

local CrateService = {}

local DataService
local EconomyService
local GearService
local WaveService
local CharacterService

local rng = Random.new()
local lastRoll: { [Player]: number } = {}

local resultRemote: RemoteEvent
local notifyRemote: RemoteEvent

local DECISIONS = { Buy = true, Skip = true }
local luckSteps: { [Player]: number } = {} -- luck steps already earned (and announced)

-- The roll waiting at your crate is part of your save, so it's still there
-- after you leave and rejoin.
local function getPending(player: Player): Pending?
	return DataService:Get(player).pendingRoll
end

local function setPending(player: Player, roll: Pending?)
	DataService:Get(player).pendingRoll = roll
end

local function notify(player: Player, text: string)
	notifyRemote:FireClient(player, text)
end

-- Your luck: from the best wave you've ever beaten, plus your layer's
-- bonus (deeper layers are luckier), times the Fortune stat
local function luckFor(player: Player): number
	local data = DataService:Get(player)
	local base = CrateConfig.LuckForBestWave(data.bestWaveEver) + LayerConfig.Get(data.layer).luckBonus
	return base * CharacterService:GetEffects(player).luck
end

local function pushCrateStats(player: Player)
	EconomyService:PushStats(player, {
		luck = luckFor(player),
		luckAt = CrateConfig.NextLuckWave(DataService:Get(player).bestWaveEver),
	})
end

-- A random gear of this rarity from the ones your layer can roll
local function pickGear(rarity: string, layer: number): GearData.Gear?
	local options = GearData.ByRarity(rarity, layer)
	if #options == 0 then
		options = GearData.ByRarity("Common", layer)
	end
	if #options == 0 then
		return nil
	end
	return options[rng:NextInteger(1, #options)]
end

local function sendResult(player: Player, roll: Pending, fresh: boolean)
	local gear = GearData.Get(roll.gearId)
	if not gear then
		return
	end
	resultRemote:FireClient(player, {
		gearId = gear.id,
		price = roll.price,
		fresh = fresh,
		owned = GearService:GetOwnership(player, gear.id) or false,
	})
end

------------------------------------------------------------------------
-- Rolling and decisions
------------------------------------------------------------------------

function CrateService:Roll(player: Player)
	local lane = WaveService:GetLane(player)
	if not lane then
		return
	end

	-- Must be standing near your own crate
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local crate = lane.model:FindFirstChild("Crate")
	if not root or not crate or (root.Position - crate.Position).Magnitude > CrateConfig.MaxRollDistance then
		return
	end

	-- A reveal is waiting for a decision: show it again instead of rolling
	local waiting = getPending(player)
	if waiting then
		sendResult(player, waiting, false)
		return
	end

	local now = os.clock()
	if lastRoll[player] and now - lastRoll[player] < CrateConfig.RollCooldown then
		return
	end
	lastRoll[player] = now

	local luck = luckFor(player)
	local gear = pickGear(CrateConfig.PickRarity(luck, rng), DataService:Get(player).layer)
	if not gear then
		return
	end

	local roll: Pending = { gearId = gear.id, price = gear.price }
	setPending(player, roll)
	DataService:Get(player).totalRolls += 1
	sendResult(player, roll, true)
end

function CrateService:Decide(player: Player, choice: string)
	local roll = getPending(player)

	if choice == "Buy" then
		if not roll then
			return
		end
		local ok, reason = GearService:CanReceive(player, roll.gearId)
		if not ok then
			setPending(player, nil)
			notify(player, reason or "You can't get that.")
			pushCrateStats(player)
			return
		end
		if not EconomyService:SpendCoins(player, roll.price) then
			notify(player, "Not enough coins yet. It'll wait at your crate while you save up.")
			return
		end
		setPending(player, nil)
		notify(player, GearService:Give(player, roll.gearId))
	elseif choice == "Skip" then
		setPending(player, nil)
	end

	pushCrateStats(player)
end

------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------

local function setupLane(lane)
	local crate = lane.model:FindFirstChild("Crate")
	if not crate then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Core Crate"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom -- no default popup; the HUD shows an Open Crate button
	prompt.Parent = crate
	prompt.Triggered:Connect(function(player)
		if player == lane.owner then
			CrateService:Roll(player)
		end
	end)
	luckSteps[lane.owner] = math.floor(DataService:Get(lane.owner).bestWaveEver / CrateConfig.LuckStepWaves)
	pushCrateStats(lane.owner)

	-- A roll you hadn't decided on last time is waiting at the crate again
	local waiting = getPending(lane.owner)
	if waiting then
		if GearData.Get(waiting.gearId) then
			sendResult(lane.owner, waiting, false)
		else
			setPending(lane.owner, nil) -- that gear no longer exists
		end
	end
end

-- Luck goes up when you beat a new multiple of 10 for the first time ever
local function onWaveCleared(lane, cleared: number)
	local player = lane.owner
	local steps = math.floor(cleared / CrateConfig.LuckStepWaves)
	local earned = luckSteps[player] or math.floor(DataService:Get(player).bestWaveEver / CrateConfig.LuckStepWaves)
	local leveledUp = steps > earned
	if leveledUp then
		luckSteps[player] = steps
	end
	-- EconomyService records the new best wave from this same event, so
	-- wait a moment before reading it
	task.defer(function()
		if leveledUp then
			notify(player, "Luck increased to x" .. string.format("%.2f", luckFor(player)) .. "!")
		end
		pushCrateStats(player)
	end)
end

-- Re-sends luck info (after a rebirth or a Fortune stat change).
function CrateService:Refresh(player: Player)
	pushCrateStats(player)
end

function CrateService:Init(services)
	DataService = services.DataService
	EconomyService = services.EconomyService
	GearService = services.GearService
	WaveService = services.WaveService
	CharacterService = services.CharacterService
	resultRemote = Remotes.Event("CrateResult")
	notifyRemote = Remotes.Event("Notify")
end

function CrateService:Start()
	Remotes.Event("CrateRoll").OnServerEvent:Connect(function(player)
		CrateService:Roll(player)
	end)
	Remotes.Event("CrateDecision").OnServerEvent:Connect(function(player, choice)
		if type(choice) == "string" and DECISIONS[choice] then
			CrateService:Decide(player, choice)
		end
	end)

	WaveService.LaneCreated:Connect(setupLane)
	WaveService.WaveCleared:Connect(onWaveCleared)
	for _, lane in WaveService.Lanes do
		if not lane.model:FindFirstChild("Crate"):FindFirstChildWhichIsA("ProximityPrompt") then
			setupLane(lane)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		luckSteps[player] = nil
	end)
end

return CrateService
