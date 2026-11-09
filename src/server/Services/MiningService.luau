-- MiningService
-- Ore veins in each layer's mine (west side of the hub; which ores is set
-- per layer in LayerConfig). Swing your pickaxe at a vein
-- to chip it; when it breaks, everyone who hit it gets the ore (it isn't
-- split, so mining together never hurts). The vein comes back after a while.
--
-- Better ores need a better pickaxe (LootConfig.Veins tier). Your pickaxe's
-- power and the Excavation stat decide how fast veins break.
-- Clients get feedback from each vein model's attributes:
--   HP (0-1 fraction left), Broken (bool)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LootConfig = require(Shared:WaitForChild("LootConfig"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local HubBuilder = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("HubBuilder"))

local ROCK_COLOR = Color3.fromRGB(95, 85, 80)
local NAG_COOLDOWN = 3

type Vein = {
	ore: string,
	model: Model,
	rock: BasePart,
	maxHp: number,
	hp: number,
	broken: boolean,
	contributors: { [Player]: boolean },
}

local MiningService = {}

local services
local notify: RemoteEvent
local veins: { Vein } = {}
local lastNag: { [Player]: number } = {}
local rng = Random.new()

------------------------------------------------------------------------
-- Building veins
------------------------------------------------------------------------

local function buildVein(folder: Instance, layer: number, spot, index: number): Vein
	local item = LootConfig.Items[spot.ore]
	local settings = LootConfig.Veins[spot.ore]
	local base = HubBuilder.VeinPosition(layer, spot)
	local spin = CFrame.Angles(0, math.rad((index * 47) % 360), 0)

	local model = Instance.new("Model")
	model.Name = "Vein_" .. spot.ore
	local rock = Instance.new("Part")
	rock.Name = "Rock"
	rock.Anchored = true
	rock.Size = Vector3.new(6, 4.5, 6)
	rock.CFrame = CFrame.new(base + Vector3.new(0, 2.25, 0)) * spin
	rock.Color = ROCK_COLOR
	rock.Material = Enum.Material.Rock
	rock.Parent = model
	-- Ore crystals sticking out of the rock
	local glowing = spot.ore == "ember_ore" or spot.ore == "frost_geode" or spot.ore == "gold_ore" or spot.ore == "crystal_ore"
	for i, offset in { Vector3.new(1.6, 2.6, 0.8), Vector3.new(-1.2, 2.3, -1.4), Vector3.new(0.2, 2.9, -0.6), Vector3.new(-1.8, 1.4, 1.7), Vector3.new(2.2, 1.2, -1.8) } do
		local crystal = Instance.new("Part")
		crystal.Name = "Ore"
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.Size = Vector3.new(1.4, 1.8 + (i % 2) * 0.8, 1.4)
		crystal.CFrame = rock.CFrame * CFrame.new(offset) * CFrame.Angles(math.rad(20 * i), math.rad(35 * i), math.rad(15))
		crystal.Color = item.color
		crystal.Material = if glowing then Enum.Material.Neon else Enum.Material.Metal
		crystal.Parent = model
	end
	model.PrimaryPart = rock
	model:SetAttribute("Ore", spot.ore)
	model:SetAttribute("Tier", settings.tier)
	model:SetAttribute("HP", 1)
	model:SetAttribute("Broken", false)

	-- Name tag, with the pickaxe it needs
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromScale(7, 1.4)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	tag.MaxDistance = 45
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = item.color
	label.TextStrokeTransparency = 0.3
	label.Text = item.name .. (if settings.tier > 1 then "  ·  " .. LootConfig.Pickaxes[settings.tier].name else "")
	label.Parent = tag
	tag.Parent = rock

	model.Parent = folder
	return {
		ore = spot.ore,
		model = model,
		rock = rock,
		maxHp = settings.hp,
		hp = settings.hp,
		broken = false,
		contributors = {},
	}
end

local function setVisible(vein: Vein, visible: boolean)
	for _, p in vein.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = if visible then 0 else 1
			if p.Name == "Rock" then
				p.CanCollide = visible
			end
		elseif p:IsA("BillboardGui") then
			p.Enabled = visible
		end
	end
end

------------------------------------------------------------------------
-- Mining
------------------------------------------------------------------------

local function breakVein(vein: Vein)
	vein.broken = true
	vein.model:SetAttribute("Broken", true)
	local settings = LootConfig.Veins[vein.ore]
	local item = LootConfig.Items[vein.ore]
	for player in vein.contributors do
		if player.Parent == Players then
			local count = rng:NextInteger(settings.yield[1], settings.yield[2])
			services.LootService:Add(player, vein.ore, count)
			services.CharacterService:GiveXP(player, count * (item.value or 1) * LootConfig.MiningXP)
			services.QuestService:Progress(player, "mine", count, vein.ore)
		end
	end
	vein.contributors = {}
	task.delay(0.15, setVisible, vein, false)
	task.delay(settings.respawn, function()
		vein.hp = vein.maxHp
		vein.broken = false
		vein.model:SetAttribute("HP", 1)
		vein.model:SetAttribute("Broken", false)
		setVisible(vein, true)
	end)
end

-- Distance from a point to the vein rock's surface (flat)
local function distanceTo(vein: Vein, origin: Vector3): number
	local localPoint = vein.rock.CFrame:PointToObjectSpace(origin)
	local half = vein.rock.Size / 2
	local closest = vein.rock.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	))
	return Vector3.new(closest.X - origin.X, 0, closest.Z - origin.Z).Magnitude
end

-- Called by CharacterService on every swing. Returns true if it hit a vein.
function MiningService:Hit(player: Player, origin: Vector3): boolean
	-- The nearest unbroken vein in reach
	local target, best = nil, LootConfig.MiningRange
	for _, vein in veins do
		if not vein.broken then
			local d = distanceTo(vein, origin)
			if d <= best then
				target, best = vein, d
			end
		end
	end
	if not target then
		return false
	end

	local data = services.DataService:Get(player)
	local need = LootConfig.Veins[target.ore].tier
	if data.pickaxeTier < need then
		local now = os.clock()
		if not lastNag[player] or now - lastNag[player] > NAG_COOLDOWN then
			lastNag[player] = now
			notify:FireClient(player, "This needs an " .. LootConfig.Pickaxes[need].name .. ". Upgrade at the forge.")
		end
		return false
	end

	local pickaxe = LootConfig.Pickaxes[data.pickaxeTier]
	local power = pickaxe.power * services.CharacterService:GetEffects(player).digPower -- Excavation
	target.contributors[player] = true
	target.hp -= power
	if target.hp <= 0 then
		target.model:SetAttribute("HP", 0)
		breakVein(target)
	else
		target.model:SetAttribute("HP", target.hp / target.maxHp)
	end
	return true
end

------------------------------------------------------------------------

function MiningService:Init(allServices)
	services = allServices
end

function MiningService:Start()
	notify = Remotes.Event("Notify")
	for _, hub in services.HubService:GetHubs() do
		for index, spot in LayerConfig.Get(hub.layer).veins do
			table.insert(veins, buildVein(hub.veinFolder, hub.layer, spot, index))
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastNag[player] = nil
		for _, vein in veins do
			vein.contributors[player] = nil
		end
	end)
end

return MiningService
