-- OddsController
-- The Odds screen (the "Odds" button beside Open Crate): the exact chance of
-- every crate roll at your luck right now, by rarity and gear by gear, plus
-- Power Crystal odds. It uses the same tables the server rolls with
-- (CrateConfig, PowerData) and updates whenever your luck changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearData = require(Shared:WaitForChild("GearData"))
local CrateConfig = require(Shared:WaitForChild("CrateConfig"))
local DailyConfig = require(Shared:WaitForChild("DailyConfig"))
local PowerData = require(Shared:WaitForChild("PowerData"))
local Format = require(Shared:WaitForChild("Format"))
local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))

local RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

local OddsController = {}

local UIController
local panel: UIKit.Panel
local builtLuck = -1

-- 12.3%, 0.45%, or "1 in 4,000" for the really rare ones
local function chanceText(chance: number): string
	if chance >= 0.1 then
		return string.format("%.0f%%", chance * 100)
	elseif chance >= 0.01 then
		return string.format("%.1f%%", chance * 100)
	elseif chance >= 0.001 then
		return string.format("%.2f%%", chance * 100)
	elseif chance > 0 then
		return "1 in " .. Format.Number(math.floor(1 / chance + 0.5))
	end
	return "0%"
end

local function rarityOdds(luck: number): { [string]: number }
	local totals = {}
	for id, chance in CrateConfig.GearOdds(luck) do
		local gear = GearData.Get(id)
		if gear then
			totals[gear.rarity] = (totals[gear.rarity] or 0) + chance
		end
	end
	return totals
end

local function build()
	local luck = UIController.Stats.luck or 1
	builtLuck = luck
	UIKit.Clear(panel.body)
	local C = UIKit.Colors
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	UIKit.Label(panel.body, string.format("Core Crate at your luck (x%.2f)", luck), 18, C.Gold, nextOrder())
	local normal, lucky = rarityOdds(luck), rarityOdds(luck * DailyConfig.LuckyRollLuck)
	for _, rarity in RARITY_ORDER do
		UIKit.Label(
			panel.body,
			string.format("%s:  %s      (Lucky Roll: %s)", rarity, chanceText(normal[rarity] or 0), chanceText(lucky[rarity] or 0)),
			15,
			GearData.Rarities[rarity].color,
			nextOrder()
		)
	end
	UIKit.Label(panel.body, "Luck goes up with your best wave, deeper layers, the Fortune stat, Re-Drills and Gear Index pages. It can't be bought.", 13, C.Dim, nextOrder())

	UIKit.Label(panel.body, "Every gear", 18, C.Gold, nextOrder())
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = nextOrder()
	grid.Parent = panel.body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -4, 0, 24)
	layout.CellPadding = UDim2.new(0, 8, 0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local odds = CrateConfig.GearOdds(luck)
	for i, gear in GearData.Items do
		local cell = Instance.new("TextLabel")
		cell.LayoutOrder = i
		cell.BackgroundColor3 = C.Row
		cell.Font = Enum.Font.GothamBold
		cell.TextSize = 13
		cell.TextXAlignment = Enum.TextXAlignment.Left
		cell.TextTruncate = Enum.TextTruncate.AtEnd
		cell.TextColor3 = GearData.Rarities[gear.rarity].color
		cell.Text = string.format("  %s  ·  %s", chanceText(odds[gear.id] or 0), gear.name)
		cell.Parent = grid
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 6)
	end

	UIKit.Label(panel.body, "Power Crystals", 18, C.Gold, nextOrder())
	local total = 0
	for _, id in PowerData.Order do
		total += PowerData.Powers[id].weight
	end
	for _, id in PowerData.Order do
		local power = PowerData.Powers[id]
		UIKit.Label(panel.body, string.format("%s:  %s", power.name, chanceText(power.weight / total)), 15, power.color, nextOrder())
	end
	UIKit.Label(panel.body, "A power you already have turns into mastery XP. Crystals can't be bought.", 13, C.Dim, nextOrder())
end

function OddsController.Toggle()
	if panel.frame.Visible then
		panel.close()
	else
		panel.open()
		build()
	end
end

function OddsController:Init(controllers)
	UIController = controllers.UIController
	panel = UIKit.Panel(UIController:GetGui(), "OddsPanel", "Odds", 540, 470)
end

function OddsController:Start()
	UIController.StatsUpdated:Connect(function(stats)
		if panel.frame.Visible and (stats.luck or 1) ~= builtLuck then
			build()
		end
	end)
end

return OddsController
