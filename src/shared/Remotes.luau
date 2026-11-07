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
	"UseAbility", -- client -> server: ability key or button pressed (weeks 3 and 8)

	-- Crate, digging, forge
	"CrateRoll", -- client -> server: request a roll (week 2)
	"CrateResult", -- server -> client: the item you rolled and its price (week 2)
	"CrateDecision", -- client -> server: "Buy" | "Skip" | "Stash" (week 2)
	"ForgeStrike", -- client -> server: forge a weapon with chosen loot (week 5)
	"GearAction", -- client -> server: ("Equip" | "Unequip", gearId) from the gear panel

	-- Rebirth
	"RequestRebirth", -- client -> server: the player confirmed a rebirth

	-- Dev cheats (Studio only, checked on the server)
	"DevCommand", -- client -> server: (command, value)

	-- Player state and messages
	"StatsChanged", -- server -> client: coins, level, XP, rebirths
	"Notify", -- server -> client: popups and server-wide announcements
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
