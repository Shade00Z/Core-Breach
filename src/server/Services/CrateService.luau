-- CrateService
-- The core crate: free rolls that reveal one piece of gear with a coin price.
-- The player then chooses:
--   Buy       pay the price and get the gear (GearService:Give). Gear you
--             already own gains a copy toward its next level instead.
--   Skip      throw it away and roll again
--   Stash     hold it for LaneConfig/CrateConfig.StashWaves waves while you save up
--   BuyStash  buy the stashed item later
--   DropStash throw away the stashed item
--
-- Rolls happen on the server only. Luck rises every 10 waves (CrateConfig).
-- Robux "skip cost" arrives in week 9; luck boosts are never sold for Robux.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearData = require(Shared:WaitForChild("GearData"))
local CrateConfig = require(Shared:WaitForChild("CrateConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Format"))

type Pending = { gearId: string, price: number }

local CrateService = {}

local DataService
local EconomyService
local GearService
local WaveService

local rng = Random.new()
local pending: { [Player]: Pending } = {}
local lastRoll: { [Player]: number } = {}
local luckAnnounced: { [Player]: number } = {}
local resultRemote: RemoteEvent
local notifyRemote: RemoteEvent

local DECISIONS = { Buy = true, Skip = true, Stash = true, BuyStash = true, DropStash = true }

local function notify(player: Player, text: string)
	notifyRemote:FireClient(player, text)
end

local function currentWave(player: Player): number
	local lane = WaveService:GetLane(player)
	return if lane then lane.wave else 1
end

local function stashInfo(player: Player)
	local stash = DataService:Get(player).stash
	if not stash then
		return false -- "false" so the client knows the stash is now empty
	end
	return {
		gearId = stash.gearId,
		price = stash.price,
		wavesLeft = math.max(0, stash.expiresAfterWave - currentWave(player) + 1),
	}
end

local function pushCrateStats(player: Player)
	local wave = currentWave(player)
	EconomyService:PushStats(player, {
		luck = CrateConfig.LuckForWave(wave),
		luckIn = CrateConfig.WavesToNextLuck(wave),
		stash = stashInfo(player),
	})
end

local function pickGear(rarity: string): GearData.Gear?
	local options = GearData.ByRarity(rarity)
	if #options == 0 then
		options = GearData.ByRarity("Common")
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
	local waiting = pending[player]
	if waiting then
		sendResult(player, waiting, false)
		return
	end

	local now = os.clock()
	if lastRoll[player] and now - lastRoll[player] < CrateConfig.RollCooldown then
		return
	end
	lastRoll[player] = now

	local luck = CrateConfig.LuckForWave(lane.wave)
	local gear = pickGear(CrateConfig.PickRarity(luck, rng))
	if not gear then
		return
	end

	local roll: Pending = { gearId = gear.id, price = gear.price }
	pending[player] = roll
	DataService:Get(player).totalRolls += 1
	sendResult(player, roll, true)
end

function CrateService:Decide(player: Player, choice: string)
	local data = DataService:Get(player)
	local roll = pending[player]

	if choice == "Buy" then
		if not roll then
			return
		end
		local ok, reason = GearService:CanReceive(player, roll.gearId)
		if not ok then
			pending[player] = nil
			notify(player, reason or "You can't get that.")
			pushCrateStats(player)
			return
		end
		if not EconomyService:SpendCoins(player, roll.price) then
			notify(player, "Not enough coins. Stash it and save up?")
			return
		end
		pending[player] = nil
		notify(player, GearService:Give(player, roll.gearId))
	elseif choice == "Skip" then
		pending[player] = nil
	elseif choice == "Stash" then
		if not roll then
			return
		end
		if data.stash then
			notify(player, "Your stash is full. Buy or drop the stashed item first.")
			return
		end
		data.stash = {
			gearId = roll.gearId,
			price = roll.price,
			expiresAfterWave = currentWave(player) + CrateConfig.StashWaves - 1,
		}
		pending[player] = nil
		local gear = GearData.Get(roll.gearId)
		notify(player, (if gear then gear.name else "Item") .. " stashed for " .. CrateConfig.StashWaves .. " waves.")
	elseif choice == "BuyStash" then
		local stash = data.stash
		if not stash then
			return
		end
		local ok, reason = GearService:CanReceive(player, stash.gearId)
		if not ok then
			data.stash = nil
			notify(player, reason or "You can't get that.")
			pushCrateStats(player)
			return
		end
		if not EconomyService:SpendCoins(player, stash.price) then
			notify(player, "Not enough coins yet. You need " .. Format.Number(math.ceil(stash.price - data.coins)) .. " more.")
			return
		end
		data.stash = nil
		notify(player, GearService:Give(player, stash.gearId))
	elseif choice == "DropStash" then
		data.stash = nil
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
	prompt.Parent = crate
	prompt.Triggered:Connect(function(player)
		if player == lane.owner then
			CrateService:Roll(player)
		end
	end)
	pushCrateStats(lane.owner)
end

local function onWaveStarted(lane)
	local player = lane.owner
	local data = DataService:Get(player)
	local stash = data.stash
	if stash and lane.wave > stash.expiresAfterWave then
		data.stash = nil
		local gear = GearData.Get(stash.gearId)
		notify(player, "Your stashed " .. (if gear then gear.name else "item") .. " expired.")
	end
	-- Announce luck going up only the first time a wave is reached, not on retries
	if lane.wave % CrateConfig.LuckStepWaves == 0 and lane.wave > (luckAnnounced[player] or 0) then
		luckAnnounced[player] = lane.wave
		notify(player, "Luck increased to x" .. string.format("%.2f", CrateConfig.LuckForWave(lane.wave)) .. "!")
	end
	pushCrateStats(player)
end

function CrateService:Init(services)
	DataService = services.DataService
	EconomyService = services.EconomyService
	GearService = services.GearService
	WaveService = services.WaveService
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
	WaveService.WaveStarted:Connect(onWaveStarted)
	for _, lane in WaveService.Lanes do
		if not lane.model:FindFirstChild("Crate"):FindFirstChildWhichIsA("ProximityPrompt") then
			setupLane(lane)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastRoll[player] = nil
		luckAnnounced[player] = nil
	end)
end

return CrateService
