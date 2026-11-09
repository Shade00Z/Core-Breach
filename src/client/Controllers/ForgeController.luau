-- ForgeController
-- The forge screen. Opens when you use the forge in the hub (by the mine),
-- closes when you walk away. Three tabs:
--   Forge    1. pick a gear  2. add loot  3. Strike. The meter shows the
--            multiplier range the strike can roll (+/- 15%). Forging a gear
--            again keeps the better multiplier.
--   Salvage  turn gear that isn't on your wall into forge value.
--   Pickaxe  upgrade your pickaxe (better ore, faster mining, deep slots).
-- The server (ForgeService) does everything; this only builds requests.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LootConfig = require(Shared:WaitForChild("LootConfig"))
local GearData = require(Shared:WaitForChild("GearData"))
local Format = require(Shared:WaitForChild("Format"))

local PANEL_W, PANEL_H = 660, 430
local CLOSE_DISTANCE = 22 -- walk this far from the forge and it closes
local DARK = Color3.fromRGB(22, 20, 28)
local ROW = Color3.fromRGB(36, 34, 42)
local SELECTED = Color3.fromRGB(70, 55, 35)
local GREEN = Color3.fromRGB(60, 150, 90)
local GRAY = Color3.fromRGB(70, 70, 78)
local ORANGE = Color3.fromRGB(230, 110, 30)

local ForgeController = {}

local UIController
local SoundController
local actionRemote: RemoteEvent
local panel: Frame
local tabs: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Forge"
local forgePart: BasePart?

-- Forge tab state
local selectedGear: string? = nil
local selection: { [string]: number } = {}
local gearList: ScrollingFrame
local lootList: ScrollingFrame
local meterFill: Frame
local meterText: TextLabel
local traitText: TextLabel
local strikeButton: TextButton
local resultLabel: TextLabel
-- Salvage / Pickaxe tabs
local salvageList: ScrollingFrame
local pickaxeInfo: TextLabel
local pickaxeCost: TextLabel
local upgradeButton: TextButton

------------------------------------------------------------------------
-- Small UI helpers
------------------------------------------------------------------------

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextSize = textSize
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2, textSize: number?): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = textSize or 14
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local function scroller(parent: Instance, size: UDim2, position: UDim2): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Size = size
	s.Position = position
	s.BackgroundColor3 = Color3.fromRGB(28, 26, 34)
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.Parent = parent
	Instance.new("UICorner", s).CornerRadius = UDim.new(0, 8)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = s
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = s
	return s
end

local function clear(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function rowFrame(list: Instance, order: number, height: number, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, 0, 0, height)
	f.BackgroundColor3 = color or ROW
	f.Parent = list
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
	return f
end

------------------------------------------------------------------------
-- Data from the server
------------------------------------------------------------------------

local function bagItems(): { [string]: { count: number, value: number } }
	local bag = UIController.Stats.bag
	return if type(bag) == "table" and bag.items then bag.items else {}
end

local function ownedGear(): { [string]: any }
	local gear = UIController.Stats.gear
	return if type(gear) == "table" and gear.owned then gear.owned else {}
end

local function isMounted(gearId: string): boolean
	local gear = UIController.Stats.gear
	if type(gear) == "table" and gear.slots then
		for _, id in gear.slots do
			if id == gearId then
				return true
			end
		end
	end
	return false
end

-- Total value and traits of the loot picked so far
local function selectionValue(): (number, { string })
	local items = bagItems()
	local total = 0
	local traits = {}
	for itemId, count in selection do
		local stack = items[itemId]
		if stack and count > 0 then
			total += stack.value * (count / stack.count)
			local trait = LootConfig.Items[itemId].trait
			if trait and not table.find(traits, trait) then
				table.insert(traits, trait)
			end
		end
	end
	return total, traits
end

------------------------------------------------------------------------
-- Forge tab
------------------------------------------------------------------------

local function refreshMeter()
	local value, traits = selectionValue()
	local gear = selectedGear and GearData.Get(selectedGear)
	local owned = selectedGear and ownedGear()[selectedGear]
	local current = if owned and owned.forge then owned.forge.mult else 1
	if not gear then
		meterFill.Size = UDim2.new(0, 0, 1, 0)
		meterText.Text = "Pick a gear on the left"
		traitText.Text = ""
		strikeButton.BackgroundColor3 = GRAY
		strikeButton.Active = false
		return
	end
	local base = LootConfig.BaseMultiplier(value, gear.price)
	local spread = LootConfig.Forge.Randomness
	-- Meter: x1 empty, x4 full
	meterFill.Size = UDim2.new(math.clamp((base - 1) / 3, 0, 1), 0, 1, 0)
	if value <= 0 then
		meterText.Text = string.format("Add loot  ·  now x%.2f", current)
	else
		meterText.Text = string.format("Value %s  ->  x%.2f to x%.2f   (now x%.2f)", Format.Number(math.floor(value)), base * (1 - spread), base * (1 + spread), current)
	end
	local names = {}
	for _, trait in traits do
		local already = owned and owned.forge and owned.forge.traits and owned.forge.traits[trait]
		if not already then
			table.insert(names, LootConfig.Traits[trait].name .. " (" .. LootConfig.Traits[trait].blurb .. ")")
		end
	end
	traitText.Text = if #names > 0 then "Adds: " .. table.concat(names, ", ") else ""
	local ready = value > 0
	strikeButton.BackgroundColor3 = if ready then ORANGE else GRAY
	strikeButton.Active = ready
end

local function refreshLoot()
	clear(lootList)
	local items = bagItems()
	local order = 0
	for _, itemId in LootConfig.ItemOrder do
		local stack = items[itemId]
		if stack and stack.count > 0 then
			order += 1
			local item = LootConfig.Items[itemId]
			local picked = math.min(selection[itemId] or 0, stack.count)
			selection[itemId] = if picked > 0 then picked else nil
			local row = rowFrame(lootList, order, 46, if picked > 0 then SELECTED else ROW)
			label(row, item.name, UDim2.new(0, 150, 0, 18), UDim2.new(0, 8, 0, 4), 14, item.color)
			label(row, string.format("%s / %s  ·  %s value", Format.Number(picked), Format.Number(stack.count), Format.Number(math.floor(stack.value))), UDim2.new(0, 170, 0, 16), UDim2.new(0, 8, 0, 24), 12, Color3.fromRGB(200, 200, 210))
			local function add(n: number)
				selection[itemId] = math.clamp((selection[itemId] or 0) + n, 0, stack.count)
				if selection[itemId] == 0 then
					selection[itemId] = nil
				end
				refreshLoot()
				refreshMeter()
			end
			button(row, "-", GRAY, UDim2.new(0, 30, 0, 34), UDim2.new(1, -176, 0, 6)).Activated:Connect(function()
				add(-math.max(1, math.floor(stack.count / 10)))
			end)
			button(row, "+1", GREEN, UDim2.new(0, 36, 0, 34), UDim2.new(1, -142, 0, 6)).Activated:Connect(function()
				add(1)
			end)
			button(row, "+10", GREEN, UDim2.new(0, 42, 0, 34), UDim2.new(1, -102, 0, 6)).Activated:Connect(function()
				add(10)
			end)
			button(row, "All", GREEN, UDim2.new(0, 52, 0, 34), UDim2.new(1, -56, 0, 6)).Activated:Connect(function()
				add(stack.count)
			end)
		end
	end
	if order == 0 then
		label(lootList, "No loot yet. Mine ore here, and kill monsters in your lane for parts and boss cores.", UDim2.new(1, 0, 0, 60), UDim2.new(), 13, Color3.fromRGB(190, 190, 200)).TextWrapped = true
	end
end

local function refreshGearList()
	clear(gearList)
	local owned = ownedGear()
	local rows = {}
	for gearId, o in owned do
		local gear = GearData.Get(gearId)
		if gear then
			table.insert(rows, { gear = gear, owned = o })
		end
	end
	table.sort(rows, function(a, b)
		return (a.owned.dps or 0) > (b.owned.dps or 0)
	end)
	if selectedGear and not owned[selectedGear] then
		selectedGear = nil
	end
	for i, row in rows do
		local gear, o = row.gear, row.owned
		local rarity = GearData.Rarities[gear.rarity]
		local f = rowFrame(gearList, i, 44, if gear.id == selectedGear then SELECTED else ROW)
		label(f, gear.name, UDim2.new(1, -12, 0, 18), UDim2.new(0, 8, 0, 4), 14, rarity.color)
		local mult = if o.forge then string.format("x%.2f", o.forge.mult) else "not forged"
		local traits = {}
		if o.forge and o.forge.traits then
			for trait in o.forge.traits do
				table.insert(traits, LootConfig.Traits[trait].name)
			end
		end
		label(f, "Lv " .. o.level .. "  ·  " .. mult .. (if #traits > 0 then "  ·  " .. table.concat(traits, ", ") else ""), UDim2.new(1, -12, 0, 16), UDim2.new(0, 8, 0, 23), 12, Color3.fromRGB(200, 200, 210))
		local click = Instance.new("TextButton")
		click.BackgroundTransparency = 1
		click.Size = UDim2.fromScale(1, 1)
		click.Text = ""
		click.Parent = f
		click.Activated:Connect(function()
			selectedGear = gear.id
			refreshGearList()
			refreshMeter()
		end)
	end
end

------------------------------------------------------------------------
-- Salvage and Pickaxe tabs
------------------------------------------------------------------------

local function refreshSalvage()
	clear(salvageList)
	local order = 0
	for gearId, o in ownedGear() do
		local gear = GearData.Get(gearId)
		if gear and not isMounted(gearId) then
			order += 1
			local rarity = GearData.Rarities[gear.rarity]
			local f = rowFrame(salvageList, order, 46)
			label(f, gear.name .. "  ·  Lv " .. o.level, UDim2.new(1, -150, 0, 18), UDim2.new(0, 8, 0, 4), 14, rarity.color)
			label(f, "Salvages into " .. Format.Number(LootConfig.SalvageValue(gear.price, o.level)) .. " forge value", UDim2.new(1, -150, 0, 16), UDim2.new(0, 8, 0, 24), 12, Color3.fromRGB(200, 200, 210))
			local b = button(f, "Salvage", Color3.fromRGB(150, 70, 60), UDim2.new(0, 120, 0, 34), UDim2.new(1, -126, 0, 6))
			local armedUntil = 0
			b.Activated:Connect(function()
				if os.clock() < armedUntil then
					actionRemote:FireServer("Salvage", gearId)
					return
				end
				armedUntil = os.clock() + 3
				b.Text = "Sure?"
				task.delay(3, function()
					if b.Parent then
						b.Text = "Salvage"
					end
				end)
			end)
		end
	end
	if order == 0 then
		label(salvageList, "Only gear that isn't on your wall can be salvaged. Take gear off in the Gear panel first.", UDim2.new(1, 0, 0, 60), UDim2.new(), 13, Color3.fromRGB(190, 190, 200)).TextWrapped = true
	end
end

local function refreshPickaxe()
	local bag = UIController.Stats.bag
	local tier = if type(bag) == "table" and bag.pickaxe then bag.pickaxe else 1
	local current = LootConfig.Pickaxes[tier]
	local nextPick = LootConfig.Pickaxes[tier + 1]
	pickaxeInfo.Text = string.format("You have: %s  (mining power %s)", current.name, tostring(current.power))
	pickaxeInfo.TextColor3 = current.color
	if not nextPick then
		pickaxeCost.Text = "That's the best pickaxe for now. Deeper layers bring better ones."
		upgradeButton.Visible = false
		return
	end
	upgradeButton.Visible = true
	local items = bagItems()
	local lines = { string.format("Next: %s  (mining power %s)", nextPick.name, tostring(nextPick.power)) }
	local coins = UIController.Stats.coins or 0
	local canAfford = coins >= nextPick.cost.coins
	table.insert(lines, string.format("$ %s  (you have $ %s)", Format.Number(nextPick.cost.coins), Format.Number(coins)))
	for itemId, need in nextPick.cost.items do
		local have = if items[itemId] then items[itemId].count else 0
		canAfford = canAfford and have >= need
		table.insert(lines, string.format("%s: %d / %d", LootConfig.Items[itemId].name, have, need))
	end
	local unlocks = {}
	for ore, vein in LootConfig.Veins do
		if vein.tier == tier + 1 then
			table.insert(unlocks, LootConfig.Items[ore].name)
		end
	end
	for _, slotTier in LootConfig.WallSlotTiers do
		if slotTier == tier + 1 then
			table.insert(unlocks, "deep wall slots")
			break
		end
	end
	if #unlocks > 0 then
		table.insert(lines, "Unlocks: " .. table.concat(unlocks, ", "))
	end
	pickaxeCost.Text = table.concat(lines, "\n")
	upgradeButton.BackgroundColor3 = if canAfford then GREEN else GRAY
	upgradeButton.Active = canAfford
end

local function refreshAll()
	if not panel.Visible then
		return
	end
	if currentTab == "Forge" then
		refreshGearList()
		refreshLoot()
		refreshMeter()
	elseif currentTab == "Salvage" then
		refreshSalvage()
	else
		refreshPickaxe()
	end
end

local function showTab(name: string)
	currentTab = name
	for tabName, frame in tabs do
		frame.Visible = tabName == name
		tabButtons[tabName].BackgroundColor3 = if tabName == name then ORANGE else GRAY
	end
	refreshAll()
end

local function open()
	panel.Visible = true
	resultLabel.Text = ""
	-- Only one big panel at a time
	local gui = UIController:GetGui()
	for _, name in { "GearPanel", "StatsPanel", "BagPanel" } do
		local other = gui:FindFirstChild(name)
		if other then
			other.Visible = false
		end
	end
	showTab(currentTab)
end

------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------

local function onResult(result)
	local gear = GearData.Get(result.gearId)
	if not gear then
		return
	end
	selection = {}
	local text
	if result.improved then
		text = string.format("%s is now x%.2f!", gear.name, result.best)
		SoundController:Play(if result.best - result.previous > 0.5 then "RevealEpic" else "RevealCommon")
	else
		text = string.format("Rolled x%.2f, kept your x%.2f.", result.rolled, result.best)
		SoundController:Play("RevealCommon")
	end
	if result.newTraits and #result.newTraits > 0 then
		local names = {}
		for _, trait in result.newTraits do
			table.insert(names, LootConfig.Traits[trait].name)
		end
		text ..= "  New trait: " .. table.concat(names, ", ") .. "!"
	end
	resultLabel.Text = text
	resultLabel.TextColor3 = if result.improved then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(210, 210, 220)
	local scale = resultLabel:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.4
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	refreshAll()
end

------------------------------------------------------------------------

function ForgeController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()

	panel = Instance.new("Frame")
	panel.Name = "ForgePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 10)
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.BackgroundColor3 = DARK
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
	stroke.Thickness = 2
	stroke.Parent = panel
	-- Shrink to fit phones
	local fitScale = Instance.new("UIScale")
	fitScale.Parent = panel
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		fitScale.Scale = math.min(1, (viewport.Y - 30) / PANEL_H, (viewport.X - 30) / PANEL_W)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	label(panel, "Forge", UDim2.new(0, 120, 0, 30), UDim2.new(0, 16, 0, 10), 22, Color3.fromRGB(255, 170, 90))
	for i, name in { "Forge", "Salvage", "Pickaxe" } do
		local b = button(panel, name, GRAY, UDim2.new(0, 100, 0, 30), UDim2.new(0, 120 + (i - 1) * 108, 0, 10), 15)
		b.Activated:Connect(function()
			showTab(name)
		end)
		tabButtons[name] = b
	end
	button(panel, "X", Color3.fromRGB(150, 60, 60), UDim2.new(0, 32, 0, 32), UDim2.new(1, -44, 0, 9), 16).Activated:Connect(function()
		panel.Visible = false
	end)

	local function tabFrame(name: string): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Position = UDim2.new(0, 12, 0, 50)
		f.Size = UDim2.new(1, -24, 1, -62)
		f.Visible = false
		f.Parent = panel
		tabs[name] = f
		return f
	end

	-- Forge tab
	local forgeTab = tabFrame("Forge")
	label(forgeTab, "1. Pick a gear", UDim2.new(0, 220, 0, 18), UDim2.new(0, 0, 0, 0), 14, Color3.fromRGB(255, 200, 140))
	gearList = scroller(forgeTab, UDim2.new(0, 230, 1, -112), UDim2.new(0, 0, 0, 22))
	label(forgeTab, "2. Add loot", UDim2.new(0, 220, 0, 18), UDim2.new(0, 242, 0, 0), 14, Color3.fromRGB(255, 200, 140))
	lootList = scroller(forgeTab, UDim2.new(1, -242, 1, -112), UDim2.new(0, 242, 0, 22))

	local meter = Instance.new("Frame")
	meter.Position = UDim2.new(0, 0, 1, -84)
	meter.Size = UDim2.new(1, -150, 0, 22)
	meter.BackgroundColor3 = Color3.fromRGB(40, 30, 25)
	meter.BorderSizePixel = 0
	meter.Parent = forgeTab
	Instance.new("UICorner", meter).CornerRadius = UDim.new(0, 8)
	meterFill = Instance.new("Frame")
	meterFill.Size = UDim2.new(0, 0, 1, 0)
	meterFill.BackgroundColor3 = ORANGE
	meterFill.BorderSizePixel = 0
	meterFill.Parent = meter
	Instance.new("UICorner", meterFill).CornerRadius = UDim.new(0, 8)
	meterText = label(meter, "", UDim2.new(1, -12, 1, 0), UDim2.new(0, 8, 0, 0), 13)
	meterText.ZIndex = 2
	traitText = label(forgeTab, "", UDim2.new(1, -150, 0, 16), UDim2.new(0, 0, 1, -58), 12, LootConfig.Traits.burn.color)
	resultLabel = label(forgeTab, "", UDim2.new(1, -150, 0, 24), UDim2.new(0, 0, 1, -34), 16, Color3.fromRGB(255, 200, 80))
	resultLabel.TextXAlignment = Enum.TextXAlignment.Left
	Instance.new("UIScale", resultLabel)

	strikeButton = button(forgeTab, "STRIKE", GRAY, UDim2.new(0, 136, 0, 76), UDim2.new(1, -136, 1, -84), 22)
	strikeButton.Activated:Connect(function()
		if not strikeButton.Active or not selectedGear then
			return
		end
		local send = {}
		for itemId, count in selection do
			if count > 0 then
				send[itemId] = count
			end
		end
		if next(send) == nil then
			return
		end
		SoundController:Play("Anvil")
		actionRemote:FireServer("Forge", selectedGear, send)
	end)

	-- Salvage tab
	local salvageTab = tabFrame("Salvage")
	label(salvageTab, "Turn gear you don't want into forge value. It's gone for good, but you can roll it again.", UDim2.new(1, 0, 0, 18), UDim2.new(), 13, Color3.fromRGB(200, 200, 210))
	salvageList = scroller(salvageTab, UDim2.new(1, 0, 1, -26), UDim2.new(0, 0, 0, 24))

	-- Pickaxe tab
	local pickaxeTab = tabFrame("Pickaxe")
	pickaxeInfo = label(pickaxeTab, "", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 6), 18)
	pickaxeCost = label(pickaxeTab, "", UDim2.new(1, 0, 0, 160), UDim2.new(0, 0, 0, 44), 15, Color3.fromRGB(220, 220, 230))
	pickaxeCost.TextYAlignment = Enum.TextYAlignment.Top
	pickaxeCost.TextWrapped = true
	pickaxeCost.TextTruncate = Enum.TextTruncate.None
	upgradeButton = button(pickaxeTab, "Upgrade pickaxe", GRAY, UDim2.new(0, 220, 0, 50), UDim2.new(0, 0, 0, 220), 18)
	upgradeButton.Activated:Connect(function()
		if upgradeButton.Active then
			actionRemote:FireServer("UpgradePickaxe")
		end
	end)
end

function ForgeController:Start()
	actionRemote = Remotes.Event("ForgeAction")
	Remotes.Event("ForgeResult").OnClientEvent:Connect(onResult)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "ForgePrompt" then
			forgePart = prompt.Parent :: BasePart
			open()
		end
	end)
	-- Rebuild the lists only when the bag or gear actually changed (coins
	-- update many times a second); the pickaxe tab also shows coins
	local lastBag, lastGear = nil, nil
	UIController.StatsUpdated:Connect(function(stats)
		if not panel.Visible then
			return
		end
		if stats.bag ~= lastBag or stats.gear ~= lastGear then
			lastBag, lastGear = stats.bag, stats.gear
			refreshAll()
		elseif currentTab == "Pickaxe" then
			refreshPickaxe()
		end
	end)
	-- Close when you walk away from the forge
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.Visible and forgePart then
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position - forgePart.Position).Magnitude > CLOSE_DISTANCE then
					panel.Visible = false
				end
			end
		end
	end)
end

return ForgeController
