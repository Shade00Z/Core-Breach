-- CrateController
-- The crate reveal panel (Buy / Skip). A roll waits until you choose, so
-- you can walk off and save up for it.
-- Rolling happens on the server: walk up to your crate and press E (or tap
-- the prompt on mobile). The server sends back what you rolled.
-- Walk away with a reveal still open and the panel slides off screen; the
-- gear floats above your crate instead. Walk back and the panel slides back in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GearData = require(Shared:WaitForChild("GearData"))
local CrateConfig = require(Shared:WaitForChild("CrateConfig"))
local Format = require(Shared:WaitForChild("Format"))

-- How long the "rolling" suspense lasts, by rarity (rarer = longer). The
-- color cycle slows down toward the end like a slot machine, and the crate
-- shakes harder the longer it goes.
local SUSPENSE = { Common = 0.5, Rare = 0.9, Epic = 1.4, Legendary = 2.0, Mythic = 2.6 }
local CYCLE_FAST = 0.05 -- seconds per color at the start of the roll
local CYCLE_SLOW = 0.28 -- extra seconds per color by the end

-- Reveal effects by rarity order (1 Common ... 5 Mythic):
--   beam     light beam shooting up from the crate (Rare and up)
--   ring     shockwave ring on the ground (Epic and up)
--   shake    camera shake strength and duration (Epic and up)
local REVEAL_FX = {
	[1] = {},
	[2] = { beam = 1.6 },
	[3] = { beam = 2.6, ring = 24, shake = 0.2, shakeTime = 0.3 },
	[4] = { beam = 4, ring = 36, shake = 0.5, shakeTime = 0.5 },
	[5] = { beam = 6, ring = 50, shake = 0.9, shakeTime = 0.8 },
}
local BEAM_HEIGHT = 70
local CYCLE_COLORS = { Color3.fromRGB(190, 190, 190), Color3.fromRGB(70, 150, 255), Color3.fromRGB(170, 80, 255), Color3.fromRGB(255, 180, 40) }

-- Walking away from the crate
local HIDE_DISTANCE = CrateConfig.MaxRollDistance + 2 -- further than this: panel tucks away, gear floats above the crate
local SHOW_DISTANCE = CrateConfig.MaxRollDistance - 1 -- closer than this: panel comes back
local TRANSITION_SPEED = 8 -- higher = snappier slide
local PANEL_SHOWN = UDim2.new(0.5, 0, 1, -16)
local PANEL_HIDDEN = UDim2.new(0.5, 0, 1, 260) -- just below the bottom of the screen
local PREVIEW_HEIGHT = 2.6 -- how far above the crate the gear floats
local PREVIEW_SCALE = 1.8 -- bigger than on the wall, so it reads from a distance
local ROLLING_SIZE = Vector3.new(1.6, 1.6, 1.6)
local HIDDEN = CFrame.new(0, -500, 0)

local CrateController = {}

local UIController
local SoundController
local openButton: TextButton
local myCrate: BasePart?
local decisionRemote: RemoteEvent

local panel: Frame
local stroke: UIStroke
local rarityLabel: TextLabel
local nameLabel: TextLabel
local statsLabel: TextLabel
local ownedLabel: TextLabel
local priceLabel: TextLabel
local buyButton: TextButton
local skipButton: TextButton

type Ownership = { level: number, copies: number, needed: number, maxed: boolean }
local current: { gearId: string, price: number, owned: Ownership?, revealed: boolean }? = nil
local revealToken = 0

-- Floating preview above the crate
local preview: BasePart
local previewTag: BillboardGui
local previewRarity: TextLabel
local previewName: TextLabel
local previewInfo: TextLabel
local previewSize = ROLLING_SIZE
local previewHidden = true
local away = false -- standing away from the crate
local blend = 0 -- 0 = panel on screen, 1 = gear floating above the crate

------------------------------------------------------------------------
-- UI helpers
------------------------------------------------------------------------

local function label(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextSize = textSize
	l.Text = ""
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 20
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	return b
end

local function setButtonEnabled(b: TextButton, enabled: boolean)
	b.Active = enabled
	b.AutoButtonColor = enabled
	b.BackgroundTransparency = if enabled then 0 else 0.55
	b.TextTransparency = if enabled then 0 else 0.4
end

------------------------------------------------------------------------
-- Reveal panel
------------------------------------------------------------------------

local function refreshButtons()
	local stats = UIController.Stats
	if current then
		local coins = stats.coins or 0
		local owned = current.owned
		if owned and owned.maxed then
			buyButton.Text = "Max level"
			setButtonEnabled(buyButton, false)
		elseif coins >= current.price then
			buyButton.Text = if owned then "Level up" else "Buy"
			setButtonEnabled(buyButton, true)
		else
			buyButton.Text = "Need " .. Format.Number(math.ceil(current.price - coins))
			setButtonEnabled(buyButton, false)
		end
	end
end

local function ownedText(gear: GearData.Gear, owned: Ownership?): (string, Color3)
	if not owned then
		return "NEW", Color3.fromRGB(150, 255, 170)
	end
	if owned.maxed then
		return "You own this at MAX level", Color3.fromRGB(255, 140, 120)
	end
	local nextLevel = owned.level + 1
	local text = string.format("Owned Lv %d  ·  copy %d/%d to Lv %d", owned.level, owned.copies + 1, owned.needed, nextLevel)
	if owned.copies + 1 >= owned.needed then
		text ..= string.format("  (%s -> %s DPS)", Format.Number(GearData.DPS(gear, owned.level)), Format.Number(GearData.DPS(gear, nextLevel)))
	end
	return text, Color3.fromRGB(255, 215, 120)
end

------------------------------------------------------------------------
-- Floating preview above the crate
------------------------------------------------------------------------

local function previewInfoText(gear: GearData.Gear, price: number, owned: Ownership?): string
	local status
	if not owned then
		status = "NEW"
	elseif owned.maxed then
		status = "MAX level"
	elseif owned.copies + 1 >= owned.needed then
		status = "Level up to " .. (owned.level + 1)
	else
		status = string.format("Copy %d/%d", owned.copies + 1, owned.needed)
	end
	return "$ " .. Format.Number(price) .. "  ·  " .. status
end

-- Matches the floating preview to the current reveal
local function updatePreview()
	if not current then
		return
	end
	local gear = GearData.Get(current.gearId)
	if not gear then
		return
	end
	if not current.revealed then
		preview.Shape = Enum.PartType.Block
		preview.Material = Enum.Material.SmoothPlastic
		preview.Color = Color3.fromRGB(190, 190, 190)
		previewSize = ROLLING_SIZE
		previewRarity.Text = "ROLLING..."
		previewRarity.TextColor3 = Color3.fromRGB(190, 190, 190)
		previewName.Text = "?"
		previewName.TextColor3 = Color3.new(1, 1, 1)
		previewInfo.Text = ""
		return
	end
	local rarity = GearData.Rarities[gear.rarity]
	local shape = GearData.Shapes[gear.kind] or GearData.Shapes.Pistol
	preview.Shape = if shape.ball then Enum.PartType.Ball else Enum.PartType.Block
	preview.Material = if gear.rarity == "Legendary" or gear.rarity == "Mythic" then Enum.Material.Neon else Enum.Material.Metal
	preview.Color = rarity.color
	previewSize = shape.size * PREVIEW_SCALE
	previewRarity.Text = string.upper(gear.rarity)
	previewRarity.TextColor3 = rarity.color
	previewName.Text = gear.name
	previewName.TextColor3 = rarity.color
	previewInfo.Text = previewInfoText(gear, current.price, current.owned)
end

local function buildPreview()
	preview = Instance.new("Part")
	preview.Name = "CratePreview"
	preview.Anchored = true
	preview.CanCollide = false
	preview.CanQuery = false
	preview.CanTouch = false
	preview.CastShadow = false
	preview.TopSurface = Enum.SurfaceType.Smooth
	preview.BottomSurface = Enum.SurfaceType.Smooth
	preview.Transparency = 1
	preview.CFrame = HIDDEN
	preview.Parent = workspace

	previewTag = Instance.new("BillboardGui")
	previewTag.Name = "Info"
	previewTag.Size = UDim2.new(0, 260, 0, 78)
	previewTag.StudsOffset = Vector3.new(0, 2.6, 0)
	previewTag.LightInfluence = 0
	previewTag.MaxDistance = 250
	previewTag.Enabled = false
	previewTag.Parent = preview

	previewRarity = label(previewTag, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 0), 16)
	previewName = label(previewTag, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 18), 26)
	previewInfo = label(previewTag, UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 50), 17)
	previewInfo.TextColor3 = Color3.fromRGB(255, 215, 70)
end

local function crateDistance(): number?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not myCrate or not myCrate.Parent or not root or not root:IsA("BasePart") then
		return nil
	end
	return (root.Position - myCrate.Position).Magnitude
end

-- Every frame: slide the panel and the floating gear toward where they should be
local function onRender(dt: number)
	local distance = crateDistance()
	if distance then
		if away and distance < SHOW_DISTANCE then
			away = false
		elseif not away and distance > HIDE_DISTANCE then
			away = true
		end
	end

	local target = if current and away then 1 else 0
	blend += (target - blend) * math.min(1, dt * TRANSITION_SPEED)
	if math.abs(target - blend) < 0.002 then
		blend = target
	end

	-- The panel slides down off the screen as you walk away
	panel.Visible = current ~= nil and blend < 1
	if panel.Visible then
		panel.Position = PANEL_SHOWN:Lerp(PANEL_HIDDEN, blend)
	end

	-- The gear rises out of the crate and floats there, spinning
	local crate = myCrate
	if not current or blend <= 0 or not crate then
		if not previewHidden then
			previewHidden = true
			preview.CFrame = HIDDEN
			previewTag.Enabled = false
		end
		return
	end
	previewHidden = false
	previewTag.Enabled = true
	local now = os.clock()
	local height = crate.Size.Y / 2 + 0.5 + PREVIEW_HEIGHT * blend + math.sin(now * 2) * 0.25
	preview.Size = previewSize * math.max(0.05, blend)
	preview.Transparency = 1 - blend
	preview.CFrame = CFrame.new(crate.Position + Vector3.new(0, height, 0)) * CFrame.Angles(0, now * 1.2, 0)
	for _, l in { previewRarity, previewName, previewInfo } do
		l.TextTransparency = 1 - blend
		l.TextStrokeTransparency = 1 - 0.6 * blend
	end
end

------------------------------------------------------------------------

local function showGear(gearId: string, price: number)
	local gear = GearData.Get(gearId)
	if not gear then
		return
	end
	local owned = current and current.owned
	local rarity = GearData.Rarities[gear.rarity]
	rarityLabel.Text = string.upper(gear.rarity)
	rarityLabel.TextColor3 = rarity.color
	stroke.Color = rarity.color
	nameLabel.Text = gear.name
	local splash = if gear.splash > 0 then ("  ·  Splash " .. gear.splash) else ""
	statsLabel.Text = string.format("%s  ·  %s DPS%s", gear.kind, Format.Number(GearData.DPS(gear, if owned then owned.level else 1)), splash)
	ownedLabel.Text, ownedLabel.TextColor3 = ownedText(gear, owned)
	priceLabel.Text = "$ " .. Format.Number(price)
	buyButton.Visible, skipButton.Visible = true, true
	refreshButtons()
	if current then
		current.revealed = true
	end
	updatePreview()
end

local function hidePanel()
	current = nil
	revealToken += 1
	panel.Visible = false
	blend = 0
end

------------------------------------------------------------------------
-- Reveal effects
------------------------------------------------------------------------

local function shakeCamera(strength: number, duration: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if t >= 1 then
			connection:Disconnect()
			humanoid.CameraOffset = Vector3.zero
			return
		end
		local amount = strength * (1 - t)
		humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, (math.random() - 0.5) * amount)
	end)
end

local function effectPart(size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Cylinder
	part.Color = color
	part.Size = size
	part.Parent = workspace
	return part
end

local function playRevealFx(order: number, color: Color3)
	local fx = REVEAL_FX[order] or REVEAL_FX[1]
	local crate = myCrate
	if not crate then
		return
	end
	local base = crate.Position - Vector3.new(0, crate.Size.Y / 2, 0)
	local holdTime = 0.6 + 0.35 * order

	if fx.beam then
		-- Cylinders are long along X, so stand it up
		local beam = effectPart(Vector3.new(BEAM_HEIGHT, fx.beam, fx.beam), color)
		beam.Transparency = 0.15
		beam.CFrame = CFrame.new(base + Vector3.new(0, BEAM_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10 + 4 * order
		light.Brightness = 2 + order
		light.Parent = beam
		TweenService:Create(beam, TweenInfo.new(holdTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
			Size = Vector3.new(BEAM_HEIGHT, fx.beam * 0.3, fx.beam * 0.3),
		}):Play()
		Debris:AddItem(beam, holdTime + 0.1)
	end

	if fx.ring then
		local ring = effectPart(Vector3.new(0.3, 4, 4), color)
		ring.Transparency = 0.2
		ring.CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.3, fx.ring, fx.ring),
		}):Play()
		Debris:AddItem(ring, 0.7)
	end

	if fx.shake then
		shakeCamera(fx.shake, fx.shakeTime)
	end
end

local function onResult(result)
	if type(result) ~= "table" or type(result.gearId) ~= "string" then
		return
	end
	local gear = GearData.Get(result.gearId)
	if not gear then
		return
	end
	current = {
		gearId = result.gearId,
		price = result.price,
		owned = if type(result.owned) == "table" then result.owned else nil,
		revealed = false,
	}
	revealToken += 1
	local token = revealToken

	if not result.fresh then
		showGear(result.gearId, result.price)
		return
	end

	-- Suspense: cycle rarity colors, longer for rarer pulls
	SoundController:Play("RollStart")
	buyButton.Visible, skipButton.Visible = false, false
	updatePreview()
	rarityLabel.Text = "ROLLING..."
	nameLabel.Text = "?"
	statsLabel.Text = ""
	ownedLabel.Text = ""
	priceLabel.Text = ""
	local duration = SUSPENSE[gear.rarity] or 0.5
	local started = os.clock()
	local crate = myCrate
	local crateHome = crate and crate.CFrame
	local i = 0
	while os.clock() - started < duration do
		if token ~= revealToken then
			break
		end
		local progress = (os.clock() - started) / duration
		i += 1
		local color = CYCLE_COLORS[(i - 1) % #CYCLE_COLORS + 1]
		rarityLabel.TextColor3 = color
		stroke.Color = color
		if crate and crateHome then
			-- Rattle the crate, harder as the roll goes on
			local amount = 0.05 + 0.25 * progress
			crate.CFrame = crateHome
				* CFrame.new((math.random() - 0.5) * amount, 0, (math.random() - 0.5) * amount)
				* CFrame.Angles(0, (math.random() - 0.5) * amount * 0.5, (math.random() - 0.5) * amount * 0.5)
		end
		task.wait(CYCLE_FAST + CYCLE_SLOW * progress * progress)
	end
	if crate and crateHome then
		crate.CFrame = crateHome
	end
	if token ~= revealToken then
		return
	end

	showGear(result.gearId, result.price)

	-- Pop the panel; bigger (and louder) for rarer pulls
	local order = GearData.Rarities[gear.rarity].order
	playRevealFx(order, GearData.Rarities[gear.rarity].color)
	SoundController:Play(if order >= 4 then "RevealLegendary" elseif order >= 3 then "RevealEpic" else "RevealCommon")
	local scale = panel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 1 + 0.08 * order
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

------------------------------------------------------------------------

function CrateController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()

	-- Open Crate button: shows when you're near your crate and no reveal is open
	openButton = button(gui, "Open Crate  [E]", Color3.fromRGB(210, 150, 40), UDim2.new(0, 220, 0, 56), UDim2.new(0.5, -110, 1, -76))
	openButton.Name = "OpenCrateButton"
	openButton.TextSize = 22
	openButton.Visible = false
	openButton.Activated:Connect(function()
		Remotes.Event("CrateRoll"):FireServer()
	end)

	-- Reveal panel, bottom center
	panel = Instance.new("Frame")
	panel.Name = "CratePanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = PANEL_SHOWN
	panel.Size = UDim2.new(0, 380, 0, 222)
	panel.BackgroundColor3 = Color3.fromRGB(24, 22, 28)
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	Instance.new("UIScale", panel)
	buildPreview()
	stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = panel

	rarityLabel = label(panel, UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 10), 18)
	nameLabel = label(panel, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 32), 30)
	statsLabel = label(panel, UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 0, 70), 15)
	statsLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	ownedLabel = label(panel, UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 0, 92), 15)
	priceLabel = label(panel, UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 0, 114), 26)
	priceLabel.TextColor3 = Color3.fromRGB(255, 215, 70)

	-- Two big buttons side by side
	local w, gap = 160, 12
	local left = (380 - (2 * w + gap)) / 2
	buyButton = button(panel, "Buy", Color3.fromRGB(60, 170, 80), UDim2.new(0, w, 0, 52), UDim2.new(0, left, 1, -66))
	skipButton = button(panel, "Skip", Color3.fromRGB(110, 110, 120), UDim2.new(0, w, 0, 52), UDim2.new(0, left + w + gap, 1, -66))

	buyButton.Activated:Connect(function()
		if current and buyButton.Active then
			decisionRemote:FireServer("Buy")
			hidePanel()
		end
	end)
	skipButton.Activated:Connect(function()
		if current then
			decisionRemote:FireServer("Skip")
			hidePanel()
		end
	end)
end

local function findMyCrate()
	local lanes = workspace:WaitForChild("Lanes")
	while not myCrate do
		for _, lane in lanes:GetChildren() do
			if lane:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
				local crate = lane:FindFirstChild("Crate")
				if crate and crate:IsA("BasePart") then
					myCrate = crate
				end
			end
		end
		task.wait(0.5)
	end
end

local function updateOpenButton()
	local distance = crateDistance()
	local near = distance ~= nil and distance <= CrateConfig.MaxRollDistance - 1
	openButton.Visible = near and current == nil
end

function CrateController:Start()
	decisionRemote = Remotes.Event("CrateDecision")
	task.spawn(findMyCrate)
	RunService.RenderStepped:Connect(onRender)
	task.spawn(function()
		while true do
			updateOpenButton()
			task.wait(0.2)
		end
	end)
	Remotes.Event("CrateResult").OnClientEvent:Connect(function(result)
		task.spawn(onResult, result)
	end)
	UIController.StatsUpdated:Connect(refreshButtons)
end

-- For the odds screen (week 9): current odds at your luck.
function CrateController:GetOdds()
	return CrateConfig.Odds(UIController.Stats.luck or 1)
end

return CrateController
