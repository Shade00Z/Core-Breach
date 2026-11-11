-- Remotes
-- Every RemoteEvent and RemoteFunction the game uses, defined in one place.
-- The server creates them on startup; clients wait for them to exist.
--
-- Usage (server or client):
--   local Remotes = require(ReplicatedStorage.Shared.Remotes)
--   Remotes.Event("CrateRoll"):FireServer()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- Waves and combat
	"EnemySnapshot", -- server -> client: packed wave state + enemy positions for YOUR lane (week 1)
	"LaneFX", -- server -> client: packed shots and kills for tracers and coin effects (week 2)
	"SwingWeapon", -- client -> server: hero weapon attack (week 3)
	"UseAbility", -- client -> server: (slot 1-3, aimed enemy id or 0) a Core Power ability
	"PowerAction", -- client -> server: "Open" a Power Crystal | ("Equip", powerId) | "Unequip"
	"PowerResult", -- server -> client: what a Power Crystal revealed { powerId, duplicate, level }

	-- Crate, digging, forge
	"CrateRoll", -- client -> server: request a roll (week 2)
	"CrateResult", -- server -> client: the item you rolled and its price (week 2)
	"CrateDecision", -- client -> server: "Buy" | "Skip" (week 2)
	"SpendStat", -- client -> server: (stat id, points) spend stat points (week 4)
	"CollectOffline", -- client -> server: collect offline earnings (week 4)
	"ForgeAction", -- client -> server: ("Forge", gearId, {itemId = count}) | ("Salvage", gearId) | ("UpgradePickaxe") (week 5)
	"ForgeResult", -- server -> client: what a forge strike rolled (week 5)
	"ForgeStrike", -- client -> server: forge a weapon with chosen loot (week 5)
	"GearAction", -- client -> server: ("Equip" | "Unequip" | "BuyLevel", gearId) from the gear panel
	"QuestAction", -- client -> server: ("Accept" | "TurnIn", layer) at a quest giver (week 6)
	"ElevatorTravel", -- client -> server: destination (0 = Drill Town, n = layer n) (week 7)
	"DailyAction", -- client -> server: "ClaimStreak" (week 7)

	-- Rebirth and Re-Drill
	"RequestRebirth", -- client -> server: the player confirmed a rebirth
	"RequestReDrill", -- client -> server: the player confirmed a Re-Drill at the Big Drill (week 7)

	-- Dev cheats (Studio only, checked on the server)
	"DevCommand", -- client -> server: (command, value)

	-- Player state and messages
	"StatsChanged", -- server -> client: coins, level, XP, rebirths
	"Notify", -- server -> client: popups
	"Announce", -- server -> every client: big banner for server-wide news (Mythic pulls) (week 7)
}

local FUNCTIONS = {
	"GetPlayerData", -- client asks for a copy of its saved data on join
}

local Remotes = {}

local folder: Instance
if RunService:IsServer() then
	-- Reuse the folder if it already exists, so requiring this module twice
	-- never replaces remotes that clients are already listening to.
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	local remotesFolder = existing or Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	for _, name in EVENTS do
		if not remotesFolder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotesFolder
		end
	end
	for _, name in FUNCTIONS do
		if not remotesFolder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = remotesFolder
		end
	end
	remotesFolder.Parent = ReplicatedStorage
	folder = remotesFolder
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

function Remotes.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
