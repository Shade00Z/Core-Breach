-- GearController
-- The gear panel: every gun you own, its level and DPS, and Equip/Unequip.
-- Open it with the Gear button on the left. The server sends the gear list
-- in StatsChanged (stats.gear) and does the equipping.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GearData = require(Shared:WaitForChild("GearData"))
local Format = require(Shared:WaitForChild("Format"))
local LootConfig = require(Shared:WaitForChild("LootConfig"))

local ROW_HEIGHT = 50

local GearController = {}

local UIController
local actionRemote: RemoteEvent
local panel: Frame
local list: ScrollingFrame
local header: TextLabel
local dirty = true

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextSize = textSize
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
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
	b.TextSize = 15
	b.Text = text
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end

local function rebuild()
	dirty = false
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local info = UIController.Stats.gear
	if type(info) ~= "table" then
		header.Text = "Loading..."
		return
	end

	-- Which gear is on the wall, and how many open slots there are
	local mountedIds, used, open = {}, 0, 0
	for _, id in info.slots do
		mountedIds[id] = true
		used += 1
	end
	for _ in info.unlocked do
		open += 1
	end
	header.Text = string.format("Your gear  ·  Wall %d/%d slots", used, open)

	-- Equipped first, then strongest first
	local rows = {}
	for gearId, owned in info.owned do
		local gear = GearData.Get(gearId)
		if gear then
			-- The server sends each gear's DPS with its forge bonus included
			table.insert(rows, { gear = gear, owned = owned, mounted = mountedIds[gearId] == true, dps = owned.dps or GearData.EffectiveDPS(gear, owned.level) })
		end
	end
	table.sort(rows, function(a, b)
		if a.mounted ~= b.mounted then
			return a.mounted
		end
		return a.dps > b.dps
	end)

	for i, row in rows do
		local gear, owned = row.gear, row.owned
		local rarity = GearData.Rarities[gear.rarity]

		local frame = Instance.new("Frame")
		frame.LayoutOrder = i
		frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		frame.BackgroundColor3 = Color3.fromRGB(36, 34, 42)
		frame.Parent = list
		Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 6, 1, -12)
		bar.Position = UDim2.new(0, 6, 0, 6)
		bar.BackgroundColor3 = rarity.color
		bar.BorderSizePixel = 0
		bar.Parent = frame
		Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 3)

		label(frame, gear.name, UDim2.new(0, 190, 0, 22), UDim2.new(0, 20, 0, 4), 17, rarity.color)
		local levelText = if owned.maxed then "MAX level" else string.format("Lv %d  ·  %d/%d to Lv %d", owned.level, owned.copies, owned.needed, owned.level + 1)
		if owned.forge then
			levelText ..= string.format("  ·  x%.2f", owned.forge.mult)
			for trait in owned.forge.traits or {} do
				levelText ..= " " .. LootConfig.Traits[trait].name
			end
		end
		label(frame, levelText, UDim2.new(0, 190, 0, 18), UDim2.new(0, 20, 0, 26), 13, Color3.fromRGB(200, 200, 210))
		local dpsLabel = label(frame, Format.Number(row.dps) .. " DPS", UDim2.new(0, 80, 1, 0), UDim2.new(0, 205, 0, 0), 15)
		dpsLabel.TextXAlignment = Enum.TextXAlignment.Right

		local actionButton = if row.mounted
			then button(frame, "Unequip", Color3.fromRGB(110, 110, 120), UDim2.new(0, 80, 0, 34), UDim2.new(1, -88, 0, 8))
			else button(frame, if used < open then "Equip" else "Swap in", Color3.fromRGB(60, 150, 90), UDim2.new(0, 80, 0, 34), UDim2.new(1, -88, 0, 8))
		actionButton.Activated:Connect(function()
			actionRemote:FireServer(if row.mounted then "Unequip" else "Equip", gear.id)
		end)
	end
end

function GearController:Init(controllers)
	UIController = controllers.UIController
	local gui = UIController:GetGui()

	local toggle = button(gui, "Gear", Color3.fromRGB(70, 90, 150), UDim2.new(0, 90, 0, 40), UDim2.new(0, 12, 0.5, -20))
	toggle.Name = "GearToggle"
	toggle.TextSize = 18

	panel = Instance.new("Frame")
	panel.Name = "GearPanel"
	panel.Position = UDim2.new(0, 112, 0.5, -170)
	panel.Size = UDim2.new(0, 400, 0, 340)
	panel.BackgroundColor3 = Color3.fromRGB(22, 20, 28)
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

	header = label(panel, "Your gear", UDim2.new(1, -60, 0, 30), UDim2.new(0, 14, 0, 8), 18)
	local close = button(panel, "X", Color3.fromRGB(150, 60, 60), UDim2.new(0, 32, 0, 32), UDim2.new(1, -42, 0, 8))

	list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 10, 0, 46)
	list.Size = UDim2.new(1, -20, 1, -56)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible and dirty then
			rebuild()
		end
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
end

function GearController:Start()
	actionRemote = Remotes.Event("GearAction")
	local lastGear = nil
	UIController.StatsUpdated:Connect(function(stats)
		-- Only rebuild when the gear list itself changed
		if stats.gear ~= lastGear then
			lastGear = stats.gear
			dirty = true
			if panel.Visible then
				rebuild()
			end
		end
	end)
end

return GearController
