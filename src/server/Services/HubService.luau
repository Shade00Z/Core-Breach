-- HubService
-- Builds the layer hub (Modules/HubBuilder) and handles the doors between
-- the hub and the players' lanes:
--   * Tunnel doors 1-6 in the hub: your own door takes you into your lane.
--     Each door shows whose tunnel it is.
--   * The exit door at the back of your lane takes you to the hub, in front
--     of your own tunnel door.
-- Your gear wall keeps fighting while you're away from your lane.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HubBuilder = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("HubBuilder"))

local TELEPORT_COOLDOWN = 1

local HubService = {}

local services
local notify: RemoteEvent
local hub: HubBuilder.Hub
local lastTeleport: { [Player]: number } = {}

function HubService:GetHub(): HubBuilder.Hub
	return hub
end

local function canTeleport(player: Player): Model?
	local now = os.clock()
	if lastTeleport[player] and now - lastTeleport[player] < TELEPORT_COOLDOWN then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	lastTeleport[player] = now
	return character
end

-- Into your own lane, just behind the barricade
function HubService:ToLane(player: Player)
	local lane = services.WaveService:GetLane(player)
	local character = canTeleport(player)
	if lane and character then
		character:PivotTo(lane.origin * CFrame.new(0, 4, -1))
	end
end

-- Out to the hub, in front of your tunnel door
function HubService:ToHub(player: Player)
	local lane = services.WaveService:GetLane(player)
	local character = canTeleport(player)
	if lane and character then
		local index = lane.model:GetAttribute("LaneIndex") or 1
		character:PivotTo(hub.spawnInFront(index))
	end
end

local function onLaneCreated(lane)
	local index = lane.model:GetAttribute("LaneIndex")
	local player = lane.owner
	if index and hub.doorLabels[index] then
		hub.doorLabels[index].Text = player.DisplayName .. "'s tunnel"
		hub.doors[index]:SetAttribute("OwnerUserId", player.UserId)
	end
	-- The exit door at the back of the lane
	local exit = lane.model:FindFirstChild("ExitDoor")
	local prompt = exit and exit:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(who)
			if who == player then
				HubService:ToHub(player)
			end
		end)
	end
end

local function onLaneRemoved(lane)
	local index = lane.model:GetAttribute("LaneIndex")
	if index and hub.doorLabels[index] then
		hub.doorLabels[index].Text = "Empty"
		hub.doors[index]:SetAttribute("OwnerUserId", 0)
	end
end

function HubService:Init(allServices)
	services = allServices
	hub = HubBuilder.Build(workspace)
end

function HubService:Start()
	notify = Remotes.Event("Notify")
	local WaveService = services.WaveService

	for index, door in hub.doors do
		local prompt = door:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				local lane = WaveService:GetLane(player)
				local mine = lane and lane.model:GetAttribute("LaneIndex")
				if mine == index then
					HubService:ToLane(player)
				elseif mine then
					notify:FireClient(player, "That's someone else's tunnel. Yours is door " .. mine .. ".")
				end
			end)
		end
	end

	WaveService.LaneCreated:Connect(onLaneCreated)
	WaveService.LaneRemoved:Connect(onLaneRemoved)
	for _, lane in WaveService.Lanes do
		onLaneCreated(lane)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
	end)
end

return HubService
