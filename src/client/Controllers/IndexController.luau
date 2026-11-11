-- IndexController
-- The Gear Index: a collection book of every gear (Boosts.Pages). Gear
-- you've owned at least once shows in its rarity color; the rest are "???".
-- Completing a page gives a permanent bonus. The top line shows all your
-- permanent boosts (Re-Drills and pages).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearData = require(Shared:WaitForChild("GearData"))
local Boosts = require(Shared:WaitForChild("Boosts"))
local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))

local IndexController = {}

local UIController
local panel: UIKit.Panel
local lastBoosts = nil

local function refresh()
	if not panel.frame.Visible then
		return
	end
	local info = UIController.Stats.boosts
	if type(info) ~= "table" then
		return
	end
	local discovered = {}
	for _, gearId in info.discovered or {} do
		discovered[gearId] = true
	end
	UIKit.Clear(panel.body)
	local C = UIKit.Colors
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	UIKit.Label(panel.body, string.format("Permanent boosts:  gear damage x%.2f  ·  luck x%.2f  ·  coins x%.2f  ·  Re-Drills %d", info.damage or 1, info.luck or 1, info.coins or 1, info.reDrills or 0), 14, Color3.fromRGB(150, 255, 170), nextOrder())

	for _, page in Boosts.Pages do
		local have = Boosts.PageProgress(page, discovered)
		local complete = have >= #page.gear
		UIKit.Label(panel.body, string.format("%s  %d/%d  ·  %s%s", page.name, have, #page.gear, page.bonusText, if complete then "  ✓ COMPLETE" else ""), 17, if complete then C.Gold else nil, nextOrder())
		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.LayoutOrder = nextOrder()
		grid.Parent = panel.body
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(1 / 3, -6, 0, 30)
		layout.CellPadding = UDim2.new(0, 6, 0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for i, gearId in page.gear do
			local gear = GearData.Get(gearId)
			local known = discovered[gearId] == true
			local cell = Instance.new("TextLabel")
			cell.LayoutOrder = (gear and GearData.Rarities[gear.rarity].order or 0) * 100 + i
			cell.BackgroundColor3 = C.Row
			cell.Font = Enum.Font.GothamBold
			cell.TextScaled = true
			cell.TextColor3 = if known and gear then GearData.Rarities[gear.rarity].color else C.Dim
			cell.Text = if known and gear then gear.name else "???"
			cell.Parent = grid
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 14
			limit.Parent = cell
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 4)
			pad.PaddingRight = UDim.new(0, 4)
			pad.Parent = cell
			Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 6)
		end
	end
	UIKit.Label(panel.body, "Every gear you've ever owned counts, even if you sold or salvaged it.", 13, C.Dim, nextOrder())
end

function IndexController:Init(controllers)
	UIController = controllers.UIController
	local gui = UIController:GetGui()
	panel = UIKit.Panel(gui, "IndexPanel", "Gear Index", 540, 470)
	local toggle = UIKit.HudButton(gui, "Index", Color3.fromRGB(150, 120, 50), UDim2.new(0, 110, 0.5, 28))
	toggle.Activated:Connect(function()
		if panel.frame.Visible then
			panel.close()
		else
			panel.open()
			refresh()
		end
	end)
end

function IndexController:Start()
	UIController.StatsUpdated:Connect(function(stats)
		if stats.boosts ~= lastBoosts then
			lastBoosts = stats.boosts
			refresh()
		end
	end)
end

return IndexController
