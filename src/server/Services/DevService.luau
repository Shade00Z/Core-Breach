-- DevService
-- Dev cheats for testing. Only works for players DebugConfig allows
-- (everyone in a Studio playtest; in the live game only the creator, and only
-- if DebugConfig's AllowInLiveGame is on). Every command is checked here on
-- the server, so a player can't use them by sending the remote themselves.
--
-- Commands (sent by client/Controllers/DevController):
--   Speed n        game speed for your lane (1, 2, 5 or 10)
--   Wave n         jump n waves forward (or back if negative)
--   ClearWave      kill everything in the current wave (coins still drop)
--   Coins n        add n coins
--   Invincible     toggle an unbreakable barricade and a hero that can't be hurt
--   Stress         toggle 150-enemy waves (performance test)
--   UnlockRebirth  allow a rebirth without losing a wave
--   UnlockSlots    open all six wall slots

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local DebugConfig = require(Shared:WaitForChild("DebugConfig"))

local SPEEDS = { [1] = true, [2] = true, [5] = true, [10] = true }
local MAX_COINS_PER_COMMAND = 1e12

local DevService = {}

local services

local function pushDevStats(player: Player, lane)
	services.EconomyService:PushStats(player, {
		devSpeed = lane.timeScale,
		devInvincible = lane.cheatInvincible,
		devStress = lane.enemyCountOverride > 0,
	})
end

local function run(player: Player, command: string, value: any)
	local WaveService = services.WaveService
	local lane = WaveService:GetLane(player)
	if not lane then
		return
	end
	local notify = Remotes.Event("Notify")

	if command == "Speed" and type(value) == "number" and SPEEDS[value] then
		lane.timeScale = value
		notify:FireClient(player, "[DEV] Speed x" .. value)
	elseif command == "Wave" and type(value) == "number" and value == math.floor(value) and math.abs(value) <= 1000 then
		local target = math.max(1, lane.wave + value)
		WaveService:ResetLane(player, target)
		notify:FireClient(player, "[DEV] Jumped to wave " .. target)
	elseif command == "ClearWave" then
		WaveService:KillAll(player)
	elseif command == "Coins" and type(value) == "number" and value > 0 and value <= MAX_COINS_PER_COMMAND then
		services.EconomyService:AddCoins(player, value)
	elseif command == "Invincible" then
		lane.cheatInvincible = not lane.cheatInvincible
		notify:FireClient(player, "[DEV] Invincible " .. (if lane.cheatInvincible then "ON" else "OFF"))
	elseif command == "Stress" then
		lane.enemyCountOverride = if lane.enemyCountOverride > 0 then 0 else 150
		WaveService:ResetLane(player, lane.wave)
		notify:FireClient(player, "[DEV] Stress test " .. (if lane.enemyCountOverride > 0 then "ON: 150 enemies per wave" else "OFF"))
	elseif command == "UnlockRebirth" then
		local data = services.DataService:Get(player)
		data.lostThisRun = true
		data.runBestWave = math.max(data.runBestWave, lane.wave - 1)
		services.EconomyService:RefreshRebirth(player)
		notify:FireClient(player, "[DEV] Rebirth unlocked")
	elseif command == "UnlockSlots" then
		for slotIndex = 1, 6 do
			services.GearService:UnlockSlot(player, slotIndex)
		end
		notify:FireClient(player, "[DEV] All wall slots open")
	else
		return
	end
	pushDevStats(player, lane)
end

function DevService:Init(allServices)
	services = allServices
end

function DevService:Start()
	Remotes.Event("DevCommand").OnServerEvent:Connect(function(player, command, value)
		if type(command) ~= "string" then
			return
		end
		if not DebugConfig.IsActive(player) then
			warn("[DevService] Blocked dev command from", player.Name, command)
			return
		end
		run(player, command, value)
	end)
end

return DevService
