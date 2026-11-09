-- HubService
-- Builds every layer's hub (Modules/HubBuilder, one floor per layer in
-- LayerConfig) and handles moving between hubs, lanes and layers:
--   * Tunnel doors 1-6 in a hub: your own door (in your layer's hub) takes
--     you into your lane. Each door shows whose tunnel it is.
--   * The exit door at the back of your lane takes you to your layer's hub,
--     in front of your tunnel door.
--   * MoveToLayer: after beating a layer boss you drop into the next layer.
--     Your lane is reskinned, your wave keeps going, and you arrive in the
--     new layer's elevator plaza.
-- Your gear wall keeps fighting while you're away from your lane.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local HubBuilder = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("HubBuilder"))

local TELEPORT_COOLDOWN = 1

local HubService = {}

local services
local notify: RemoteEvent
local hubs: { [number]: HubBuilder.Hub } = {}
local lastTeleport: { [Player]: number } = {}

-- One layer's hub (Layer 1 if that layer doesn't exist)
function HubService:GetHub(layer: number?): HubBuilder.Hub
	return hubs[layer or 1] or hubs[1]
end

-- Every layer's hub
function HubService:GetHubs(): { HubBuilder.Hub }
	return hubs
end

function HubService:GetLayer(player: Player): number
	return LayerConfig.Get(services.DataService:Get(player).layer).id
end

local function canTeleport(player: Player, force: boolean?): Model?
	local now = os.clock()
	if not force and lastTeleport[player] and now - lastTeleport[player] < TELEPORT_COOLDOWN then
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

-- Out to your layer's hub, in front of your tunnel door
function HubService:ToHub(player: Player)
	local lane = services.WaveService:GetLane(player)
	local character = canTeleport(player)
	if lane and character then
		local index = lane.model:GetAttribute("LaneIndex") or 1
		character:PivotTo(self:GetHub(self:GetLayer(player)).spawnInFront(index))
	end
end

-- Door labels: your name on your door in your layer's hub, and only there
local function labelDoors(player: Player, index: number, layer: number?)
	for hubLayer, hub in hubs do
		local label = hub.doorLabels[index]
		local door = hub.doors[index]
		if label and door then
			if layer == hubLayer then
				label.Text = player.DisplayName .. "'s tunnel"
				door:SetAttribute("OwnerUserId", player.UserId)
			else
				label.Text = if layer then "In use" else "Empty"
				door:SetAttribute("OwnerUserId", 0)
			end
		end
	end
end

-- Drop a player into another layer (after beating a layer boss, or a dev
-- cheat). Saves it, reskins their lane and brings them to that layer's plaza.
function HubService:MoveToLayer(player: Player, layer: number)
	local target = LayerConfig.Layers[layer]
	if not target then
		return
	end
	local data = services.DataService:Get(player)
	data.layer = layer

	local lane = services.WaveService:GetLane(player)
	if lane then
		services.WaveService:SetLayer(player, layer)
		labelDoors(player, lane.model:GetAttribute("LaneIndex"), layer)
	end
	services.CharacterService:Refresh(player) -- the new layer's level cap
	services.CrateService:Refresh(player) -- the new layer's luck bonus
	services.QuestService:Refresh(player) -- the new layer's quest giver
	services.EconomyService:PushStats(player, { layer = layer, layerName = target.name })

	local character = canTeleport(player, true)
	if character then
		character:PivotTo(self:GetHub(layer).plaza)
	end
end

local function onLaneCreated(lane)
	local index = lane.model:GetAttribute("LaneIndex")
	local player = lane.owner
	if index then
		labelDoors(player, index, lane.layer)
	end
	services.EconomyService:PushStats(player, { layer = lane.layer, layerName = LayerConfig.Get(lane.layer).name })
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
	if index then
		labelDoors(lane.owner, index, nil)
	end
end

function HubService:Init(allServices)
	services = allServices
	local folder = Instance.new("Folder")
	folder.Name = "Hubs"
	folder.Parent = workspace
	for _, layer in LayerConfig.Layers do
		hubs[layer.id] = HubBuilder.Build(folder, layer.id)
	end
end

function HubService:Start()
	notify = Remotes.Event("Notify")
	local WaveService = services.WaveService

	for hubLayer, hub in hubs do
		for index, door in hub.doors do
			local prompt = door:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Triggered:Connect(function(player)
					local lane = WaveService:GetLane(player)
					local mine = lane and lane.model:GetAttribute("LaneIndex")
					if not mine then
						return
					end
					if mine == index and HubService:GetLayer(player) == hubLayer then
						HubService:ToLane(player)
					else
						notify:FireClient(player, "That's someone else's tunnel. Yours is door " .. mine .. ".")
					end
				end)
			end
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
