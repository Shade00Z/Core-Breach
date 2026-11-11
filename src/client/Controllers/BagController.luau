-- BagController
-- The Bag button (left side, under Stats): your loot and your pickaxe.
-- Loot is spent at the forge in the hub (by the mine).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LootConfig = require(Shared:WaitForChild("LootConfig"))
local Format = require(Shared:WaitForChild("Format"))

local BagController = {}

local UIController
local panel: Frame
local list: Frame
local pickaxeLabel: TextLabel

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

local function refresh()
	local bag = UIController.Stats.bag
	if type(bag) ~= "table" then
		return
	end
	local pickaxe = LootConfig.Pickaxes[bag.pickaxe or 1]
	pickaxeLabel.Text = "Pickaxe: " .. pickaxe.name
	pickaxeLabel.TextColor3 = pickaxe.color
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local order = 0
	for _, itemId in LootConfig.ItemOrder do
		local stack = bag.items and bag.items[itemId]
		if stack and stack.count > 0 then
			order += 1
			local item = LootConfig.Items[itemId]
			local row = label(list, string.format("%s  x%s   (%s value)", item.name, Format.Number(stack.count), Format.Number(math.floor(stack.value))), UDim2.new(1, 0, 0, 20), UDim2.new(), 14, item.color)
			row.LayoutOrder = order
		end
	end
	if order == 0 then
		label(list, "Empty. Mine ore in the hub, and kill monsters for parts.", UDim2.new(1, 0, 0, 20), UDim2.new(), 13, Color3.fromRGB(190, 190, 200))
	end
end

function BagController:Init(controllers)
	UIController = controllers.UIController
	local gui = UIController:GetGui()

	local toggle = Instance.new("TextButton")
	toggle.Name = "BagToggle"
	toggle.Size = UDim2.new(0, 90, 0, 40)
	toggle.Position = UDim2.new(0, 12, 0.5, 76)
	toggle.BackgroundColor3 = Color3.fromRGB(150, 100, 50)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.TextSize = 18
	toggle.Text = "Bag"
	toggle.Parent = gui
	Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)

	panel = Instance.new("Frame")
	panel.Name = "BagPanel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 210, 0.5, 0)
	panel.Size = UDim2.new(0, 320, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(22, 20, 28)
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = label(panel, "Bag", UDim2.new(1, 0, 0, 24), UDim2.new(), 20)
	title.LayoutOrder = 1
	pickaxeLabel = label(panel, "Pickaxe: Stone Pickaxe", UDim2.new(1, 0, 0, 18), UDim2.new(), 14)
	pickaxeLabel.LayoutOrder = 2
	list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = 3
	list.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	local hint = label(panel, "Spend loot at the forge, by the mine in the hub.", UDim2.new(1, 0, 0, 16), UDim2.new(), 12, Color3.fromRGB(170, 170, 180))
	hint.LayoutOrder = 4

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			for _, name in { "GearPanel", "StatsPanel" } do
				local other = gui:FindFirstChild(name)
				if other then
					other.Visible = false
				end
			end
			refresh()
		end
	end)
end

function BagController:Start()
	local lastBag = nil
	UIController.StatsUpdated:Connect(function(stats)
		if stats.bag ~= lastBag then
			lastBag = stats.bag
			if panel.Visible then
				refresh()
			end
		end
	end)
end

return BagController
