-- CrateController
-- The crate reveal panel (Buy / Skip / Stash) and the stash panel.
-- Rolling happens on the server: walk up to your crate and press E (or tap
-- the prompt on mobile). The server sends back what you rolled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GearData = require(Shared:WaitForChild("GearData"))
local CrateConfig = require(Shared:WaitForChild("CrateConfig"))
local Format = require(Shared:WaitForChild("Format"))

-- How long the "rolling" suspense lasts, by rarity (rarer = longer)
local SUSPENSE = { Common = 0.35, Rare = 0.6, Epic = 0.9, Legendary = 1.3, Mythic = 1.8 }
local CYCLE_COLORS = { Color3.fromRGB(190, 190, 190), Color3.fromRGB(70, 150, 255), Color3.fromRGB(170, 80, 255), Color3.fromRGB(255, 180, 40) }

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
local stashButton: TextButton

local stashPanel: Frame
local stashLabel: TextLabel
local stashBuyButton: TextButton

type Ownership = { level: number, copies: number, needed: number, maxed: boolean }
local current: { gearId: string, price: number, owned: Ownership? }? = nil
local revealToken = 0

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
		setButtonEnabled(stashButton, not stats.stash)
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
	buyButton.Visible, skipButton.Visible, stashButton.Visible = true, true, true
	refreshButtons()
end

local function hidePanel()
	current = nil
	revealToken += 1
	panel.Visible = false
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
	}
	revealToken += 1
	local token = revealToken
	panel.Visible = true

	if not result.fresh then
		showGear(result.gearId, result.price)
		return
	end

	-- Suspense: cycle rarity colors, longer for rarer pulls
	SoundController:Play("RollStart")
	buyButton.Visible, skipButton.Visible, stashButton.Visible = false, false, false
	rarityLabel.Text = "ROLLING..."
	nameLabel.Text = "?"
	statsLabel.Text = ""
	ownedLabel.Text = ""
	priceLabel.Text = ""
	local duration = SUSPENSE[gear.rarity] or 0.5
	local started = os.clock()
	local i = 0
	while os.clock() - started < duration do
		if token ~= revealToken then
			return
		end
		i += 1
		local color = CYCLE_COLORS[(i - 1) % #CYCLE_COLORS + 1]
		rarityLabel.TextColor3 = color
		stroke.Color = color
		task.wait(0.07)
	end
	if token ~= revealToken then
		return
	end

	showGear(result.gearId, result.price)

	-- Pop the panel; bigger (and louder) for rarer pulls
	local order = GearData.Rarities[gear.rarity].order
	SoundController:Play(if order >= 4 then "RevealLegendary" elseif order >= 3 then "RevealEpic" else "RevealCommon")
	local scale = panel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 1 + 0.08 * order
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

------------------------------------------------------------------------
-- Stash panel
------------------------------------------------------------------------

local function refreshStash()
	local stash = UIController.Stats.stash
	if type(stash) ~= "table" then
		stashPanel.Visible = false
		return
	end
	local gear = GearData.Get(stash.gearId)
	if not gear then
		stashPanel.Visible = false
		return
	end
	stashPanel.Visible = true
	stashLabel.Text = string.format("Stash: %s  ($ %s)  ·  %d waves left", gear.name, Format.Number(stash.price), stash.wavesLeft or 0)
	stashLabel.TextColor3 = GearData.Rarities[gear.rarity].color
	local coins = UIController.Stats.coins or 0
	stashBuyButton.Text = if coins >= stash.price then "Buy" else ("Need " .. Format.Number(math.ceil(stash.price - coins)))
	setButtonEnabled(stashBuyButton, coins >= stash.price)
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
	panel.Position = UDim2.new(0.5, 0, 1, -16)
	panel.Size = UDim2.new(0, 380, 0, 222)
	panel.BackgroundColor3 = Color3.fromRGB(24, 22, 28)
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	Instance.new("UIScale", panel)
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

	local w, gap = 104, 10
	local left = (380 - (3 * w + 2 * gap)) / 2
	buyButton = button(panel, "Buy", Color3.fromRGB(60, 170, 80), UDim2.new(0, w, 0, 52), UDim2.new(0, left, 1, -66))
	skipButton = button(panel, "Skip", Color3.fromRGB(110, 110, 120), UDim2.new(0, w, 0, 52), UDim2.new(0, left + w + gap, 1, -66))
	stashButton = button(panel, "Stash", Color3.fromRGB(60, 120, 200), UDim2.new(0, w, 0, 52), UDim2.new(0, left + 2 * (w + gap), 1, -66))

	-- Stash panel, left side under coins
	stashPanel = Instance.new("Frame")
	stashPanel.Name = "StashPanel"
	stashPanel.Position = UDim2.new(0, 12, 0, 122)
	stashPanel.Size = UDim2.new(0, 330, 0, 76)
	stashPanel.BackgroundColor3 = Color3.fromRGB(24, 22, 28)
	stashPanel.BackgroundTransparency = 0.2
	stashPanel.Visible = false
	stashPanel.Parent = gui
	Instance.new("UICorner", stashPanel).CornerRadius = UDim.new(0, 10)
	stashLabel = label(stashPanel, UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 6), 15)
	stashLabel.TextXAlignment = Enum.TextXAlignment.Left
	stashLabel.TextScaled = true
	stashBuyButton = button(stashPanel, "Buy", Color3.fromRGB(60, 170, 80), UDim2.new(0, 150, 0, 36), UDim2.new(0, 8, 0, 34))
	local dropButton = button(stashPanel, "Drop", Color3.fromRGB(150, 60, 60), UDim2.new(0, 150, 0, 36), UDim2.new(0, 170, 0, 34))

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
	stashButton.Activated:Connect(function()
		if current and stashButton.Active then
			decisionRemote:FireServer("Stash")
			hidePanel()
		end
	end)
	stashBuyButton.Activated:Connect(function()
		if stashBuyButton.Active then
			decisionRemote:FireServer("BuyStash")
		end
	end)
	dropButton.Activated:Connect(function()
		decisionRemote:FireServer("DropStash")
	end)
end

local function findMyCrate()
	local Players = game:GetService("Players")
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
	local Players = game:GetService("Players")
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local near = myCrate ~= nil and root ~= nil and myCrate.Parent ~= nil
		and ((root :: BasePart).Position - (myCrate :: BasePart).Position).Magnitude <= CrateConfig.MaxRollDistance - 1
	openButton.Visible = near and not panel.Visible
end

function CrateController:Start()
	decisionRemote = Remotes.Event("CrateDecision")
	task.spawn(findMyCrate)
	task.spawn(function()
		while true do
			updateOpenButton()
			task.wait(0.2)
		end
	end)
	Remotes.Event("CrateResult").OnClientEvent:Connect(function(result)
		task.spawn(onResult, result)
	end)
	UIController.StatsUpdated:Connect(function()
		refreshButtons()
		refreshStash()
	end)
	refreshStash()
end

-- For the odds screen (week 9): current odds at your luck.
function CrateController:GetOdds()
	return CrateConfig.Odds(UIController.Stats.luck or 1)
end

return CrateController
