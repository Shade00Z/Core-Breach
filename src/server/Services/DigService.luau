-- DigService
-- Locked wall slots are buried behind rock. To open one:
--   1. Walk up to the rock and press E (or tap the prompt) to pay its price.
--   2. Swing your pickaxe at it until it breaks (HeroConfig.Dig.HitsToBreak).
-- The slot then opens and your strongest spare gear is mounted on it.
--
-- Prices go up with each slot you dig ($150, $1.5K, $15K, $150K), in any
-- order. The slots are past the barricade, so digging during a wave means
-- fighting in the lane; between waves is safer.
--
-- Clients get feedback from the rock's attributes:
--   Paid (bool), DigHits / DigNeeded (numbers), Broken (bool, just before it's removed)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))
local Format = require(Shared:WaitForChild("Format"))
local LaneBuilder = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("LaneBuilder"))

local ROCK_SIZE = Vector3.new(5, 10, 6.5) -- depth from the wall, height, length along the lane
local ROCK_COLOR = Color3.fromRGB(85, 70, 62)
local PAID_COLOR = Color3.fromRGB(120, 85, 55)
local SHRINK = 0.4 -- how much smaller the rock gets as you dig (0.4 = down to 60%)
local NAG_COOLDOWN = 3 -- seconds between "pay first" reminders

local DigService = {}

local services
local notify: RemoteEvent
local rocksByPlayer: { [Player]: { [number]: BasePart } } = {}
local lastNag: { [Player]: number } = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- How many slots this player has dug or paid for so far
local function digsSoFar(data): number
	local count = 0
	for _ in data.unlockedSlots do
		count += 1
	end
	count -= #LaneConfig.StarterSlots
	for _ in data.digging do
		count += 1
	end
	return math.max(0, count)
end

local function nextPrice(player: Player): number
	return HeroConfig.DigCost(digsSoFar(services.DataService:Get(player)) + 1)
end

-- Places the rock against the wall over its slot, smaller as it's dug.
local function placeRock(lane, rock: BasePart, slotIndex: number, progress: number)
	local lateral, _, dist = LaneBuilder.SlotLocal(slotIndex)
	local side = if lateral < 0 then -1 else 1
	local size = ROCK_SIZE * (1 - SHRINK * progress)
	local x = side * (LaneConfig.Width / 2 - size.X / 2)
	rock.Size = size
	rock.CFrame = lane.origin * CFrame.new(x, 0.4 + size.Y / 2, -dist)
end

local function setLabel(rock: BasePart, text: string)
	local label = rock:FindFirstChild("Info") and rock.Info:FindFirstChild("Text")
	if label then
		label.Text = text
	end
end

-- Updates every rock's price and prompt (prices change after each dig)
local function refreshRocks(player: Player)
	local rocks = rocksByPlayer[player]
	if not rocks then
		return
	end
	local data = services.DataService:Get(player)
	local price = nextPrice(player)
	for slotIndex, rock in rocks do
		local hits = data.digging[tostring(slotIndex)]
		local prompt = rock:FindFirstChildOfClass("ProximityPrompt")
		if hits then
			rock:SetAttribute("Paid", true)
			rock:SetAttribute("DigHits", hits)
			rock.Color = PAID_COLOR
			setLabel(rock, string.format("Swing to dig!  %d / %d", hits, HeroConfig.Dig.HitsToBreak))
			if prompt then
				prompt.Enabled = false
			end
		else
			rock:SetAttribute("Paid", false)
			setLabel(rock, "Dig out a gear slot\n$ " .. Format.Number(price))
			if prompt then
				prompt.Enabled = true
				prompt.ObjectText = "$ " .. Format.Number(price)
			end
		end
	end
end

local function removeRock(player: Player, slotIndex: number, broken: boolean)
	local rocks = rocksByPlayer[player]
	local rock = rocks and rocks[slotIndex]
	if not rock then
		return
	end
	rocks[slotIndex] = nil
	services.DataService:Get(player).digging[tostring(slotIndex)] = nil
	if broken then
		-- Let clients play the break effect before it disappears
		rock:SetAttribute("Broken", true)
		rock.CanCollide = false
		task.delay(0.15, function()
			rock:Destroy()
		end)
	else
		rock:Destroy()
	end
	refreshRocks(player)
end

------------------------------------------------------------------------
-- Paying and digging
------------------------------------------------------------------------

local function pay(player: Player, slotIndex: number)
	local data = services.DataService:Get(player)
	local key = tostring(slotIndex)
	if data.unlockedSlots[key] or data.digging[key] then
		return
	end
	local price = nextPrice(player)
	if not services.EconomyService:SpendCoins(player, price) then
		notify:FireClient(player, "You need $" .. Format.Number(price) .. " to dig out this slot.")
		return
	end
	data.digging[key] = 0
	refreshRocks(player)
	notify:FireClient(player, "Paid! Now swing your pickaxe at the rock to dig it out.")
end

-- Called by CharacterService on every swing. Returns true if it hit a rock.
-- fighting: the swing also hit an enemy (skip the "pay first" reminder)
function DigService:Hit(player: Player, origin: Vector3, look: Vector3, fighting: boolean?): boolean
	local rocks = rocksByPlayer[player]
	if not rocks then
		return false
	end
	local data = services.DataService:Get(player)
	for slotIndex, rock in rocks do
		-- Distance from you to the rock's surface, and roughly in front of you
		local localPoint = rock.CFrame:PointToObjectSpace(origin)
		local half = rock.Size / 2
		local closest = rock.CFrame:PointToWorldSpace(Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y, half.Y),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		))
		local offset = Vector3.new(closest.X - origin.X, 0, closest.Z - origin.Z)
		local inReach = offset.Magnitude <= HeroConfig.Dig.Range and (offset.Magnitude < 1 or offset.Unit:Dot(look) > 0)
		if inReach then
			local key = tostring(slotIndex)
			local hits = data.digging[key]
			if not hits then
				local now = os.clock()
				if not fighting and (not lastNag[player] or now - lastNag[player] > NAG_COOLDOWN) then
					lastNag[player] = now
					notify:FireClient(player, "Pay first: press E at the rock (or tap its button).")
				end
				return false
			end
			hits += 1
			data.digging[key] = hits
			local needed = HeroConfig.Dig.HitsToBreak
			if hits >= needed then
				removeRock(player, slotIndex, true)
				services.GearService:UnlockSlot(player, slotIndex)
				notify:FireClient(player, "Wall slot opened!")
			else
				rock:SetAttribute("DigHits", hits)
				placeRock(services.WaveService:GetLane(player), rock, slotIndex, hits / needed)
				setLabel(rock, string.format("Swing to dig!  %d / %d", hits, needed))
			end
			return true
		end
	end
	return false
end

------------------------------------------------------------------------
-- Building rocks
------------------------------------------------------------------------

local function buildRock(lane, folder: Folder, slotIndex: number): BasePart
	local player = lane.owner
	local rock = Instance.new("Part")
	rock.Name = "Rock" .. slotIndex
	rock.Anchored = true
	rock.Material = Enum.Material.Slate
	rock.Color = ROCK_COLOR
	rock.TopSurface = Enum.SurfaceType.Smooth
	rock.BottomSurface = Enum.SurfaceType.Smooth
	rock:SetAttribute("SlotIndex", slotIndex)
	rock:SetAttribute("DigNeeded", HeroConfig.Dig.HitsToBreak)
	rock:SetAttribute("DigHits", 0)
	placeRock(lane, rock, slotIndex, 0)

	local info = Instance.new("BillboardGui")
	info.Name = "Info"
	-- Sized in studs (not pixels) so it never grows into the lane wall when
	-- seen from far away, and pulled toward the middle of the lane
	info.Size = UDim2.fromScale(7, 1.8)
	local lateral = LaneBuilder.SlotLocal(slotIndex)
	local towardCenter = if lateral < 0 then 1 else -1
	-- (relative to the rock, whose X axis points across the lane)
	info.StudsOffsetWorldSpace = Vector3.new(towardCenter * 5, ROCK_SIZE.Y / 2 + 1.2, 0)
	info.MaxDistance = 70
	info.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 1, 0)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 215, 70)
	text.TextStrokeTransparency = 0.3
	text.Parent = info
	info.Parent = rock

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pay to dig"
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.3
	prompt.Parent = rock
	prompt.Triggered:Connect(function(who)
		if who == player then
			pay(player, slotIndex)
		end
	end)

	rock.Parent = folder
	return rock
end

local function setupLane(lane)
	local player = lane.owner
	local data = services.DataService:Get(player)
	local folder = Instance.new("Folder")
	folder.Name = "Rocks"
	folder.Parent = lane.model

	local rocks = {}
	rocksByPlayer[player] = rocks
	for _, slot in lane.model.Slots:GetChildren() do
		local slotIndex = slot:GetAttribute("SlotIndex")
		if slotIndex and not data.unlockedSlots[tostring(slotIndex)] then
			rocks[slotIndex] = buildRock(lane, folder, slotIndex)
		end
		-- Slots opened some other way (dev cheat) lose their rock too
		slot:GetAttributeChangedSignal("Unlocked"):Connect(function()
			if slot:GetAttribute("Unlocked") then
				removeRock(player, slotIndex, false)
			end
		end)
	end
	refreshRocks(player)
end

------------------------------------------------------------------------

function DigService:Init(allServices)
	services = allServices
end

function DigService:Start()
	notify = Remotes.Event("Notify")
	local WaveService = services.WaveService
	WaveService.LaneCreated:Connect(setupLane)
	WaveService.LaneRemoved:Connect(function(lane)
		rocksByPlayer[lane.owner] = nil
	end)
	for _, lane in WaveService.Lanes do
		if not rocksByPlayer[lane.owner] then
			setupLane(lane)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		rocksByPlayer[player] = nil
		lastNag[player] = nil
	end)
end

return DigService
