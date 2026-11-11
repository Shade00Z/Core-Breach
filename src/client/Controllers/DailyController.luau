-- DailyController
-- The Daily panel (server: DailyService, numbers: DailyConfig). Open it with
-- the Daily button on the left, or at the daily board in Drill Town:
--   * Login streak: 7 days of rewards. Claim once a day; missing a day
--     pauses the streak, it never resets.
--   * Today's 3 daily quests (they finish on their own).
--   * Lucky Rolls waiting (use them at your crate: double luck, half price).
-- The Daily button shows a "!" when today's reward is ready.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local DailyConfig = require(Shared:WaitForChild("DailyConfig"))
local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))

local DailyController = {}

local UIController
local SoundController
local panel: UIKit.Panel
local badge: TextLabel
local lastDaily = nil
local builtKey = "" -- what the panel was last built for (rebuilt only when this changes)
local questLabels: { { label: TextLabel, id: string } } = {}

local function timeLeft(resetsAt: number): string
	local seconds = math.max(0, resetsAt - os.time())
	return string.format("%dh %dm", seconds // 3600, (seconds % 3600) // 60)
end

local function refresh()
	local daily = UIController.Stats.daily
	if type(daily) ~= "table" then
		return
	end
	badge.Visible = daily.canClaim == true
	if not panel.frame.Visible then
		builtKey = ""
		return
	end

	-- Progress only: update the quest lines in place. Rebuilding the panel
	-- replaces its buttons, which can eat a click.
	local key = string.format("%s/%d/%s/%d", tostring(daily.canClaim), daily.streakDay or 0, tostring(daily.allDone), daily.luckyRolls or 0)
	for _, state in daily.quests or {} do
		key ..= "/" .. state.id .. tostring(state.done)
	end
	if key == builtKey then
		for i, entry in questLabels do
			local state = daily.quests[i]
			local quest = DailyConfig.QuestById(entry.id)
			if state and quest and not state.done then
				entry.label.Text = string.format("%s  (%d/%d)", quest.text, state.progress, quest.count)
			end
		end
		return
	end
	builtKey = key
	questLabels = {}
	UIKit.Clear(panel.body)
	local C = UIKit.Colors
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	UIKit.Label(panel.body, "New day in " .. timeLeft(daily.resetsAt or os.time()), 13, C.Dim, nextOrder())

	-- Login streak
	UIKit.Label(panel.body, "LOGIN STREAK", 16, C.Gold, nextOrder())
	local streak = Instance.new("Frame")
	streak.BackgroundTransparency = 1
	streak.Size = UDim2.new(1, 0, 0, 90)
	streak.LayoutOrder = nextOrder()
	streak.Parent = panel.body
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 7, -5, 1, 0)
	grid.CellPadding = UDim2.new(0, 5, 0, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = streak
	local claimed = daily.streakDay or 0
	local nextDay = claimed % #DailyConfig.Streak + 1
	for day, reward in DailyConfig.Streak do
		local box = Instance.new("TextLabel")
		box.LayoutOrder = day
		box.Font = Enum.Font.GothamBold
		box.TextScaled = true
		box.TextWrapped = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 12
		limit.Parent = box
		box.TextColor3 = Color3.new(1, 1, 1)
		local done = day <= claimed and not (daily.canClaim and claimed == #DailyConfig.Streak)
		local ready = daily.canClaim and day == nextDay
		box.BackgroundColor3 = if ready then C.Green elseif done then Color3.fromRGB(60, 60, 70) else C.Row
		box.Text = string.format("Day %d%s\n%s", day, if done and not ready then " ✓" else "", DailyConfig.Describe(reward))
		box.Parent = streak
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
	end
	if daily.canClaim then
		local claim = UIKit.Button(panel.body, string.format("Claim day %d reward", nextDay), C.Green, UDim2.new(1, 0, 0, 40), function()
			Remotes.Event("DailyAction"):FireServer("ClaimStreak")
			SoundController:Play("QuestDone")
		end)
		claim.LayoutOrder = nextOrder()
	else
		UIKit.Label(panel.body, "Today's reward claimed. Come back tomorrow! (Missing a day only pauses your streak.)", 13, C.Dim, nextOrder())
	end

	-- Daily quests
	UIKit.Label(panel.body, "DAILY QUESTS", 16, C.Gold, nextOrder())
	for _, state in daily.quests or {} do
		local quest = DailyConfig.QuestById(state.id)
		if quest then
			local row = UIKit.Row(panel.body, nextOrder())
			local text = if state.done then quest.text .. "  ✓ done" else string.format("%s  (%d/%d)", quest.text, state.progress, quest.count)
			local label = UIKit.Label(row, text, 15, if state.done then Color3.fromRGB(150, 255, 170) else nil, 1)
			table.insert(questLabels, { label = label, id = state.id })
		end
	end
	UIKit.Label(panel.body, "Each pays coins and XP. Finish all 3 for a Lucky Roll." .. (if daily.allDone then "  ✓" else ""), 13, C.Dim, nextOrder())

	-- Lucky Rolls
	UIKit.Label(panel.body, "LUCKY ROLLS", 16, C.Gold, nextOrder())
	UIKit.Label(panel.body, string.format("You have %d. Use them at your crate: double luck, and the gear is half price. You get one every day.", daily.luckyRolls or 0), 14, nil, nextOrder())
end

function DailyController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()
	panel = UIKit.Panel(gui, "DailyPanel", "Daily", 520, 470)
	local toggle = UIKit.HudButton(gui, "Daily", Color3.fromRGB(60, 150, 90), UDim2.new(0, 110, 0.5, -20))
	badge = UIKit.Badge(toggle)
	toggle.Activated:Connect(function()
		if panel.frame.Visible then
			panel.close()
		else
			panel.open()
			refresh()
		end
	end)
end

function DailyController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "DailyPrompt" then
			panel.open()
			refresh()
		end
	end)
	UIController.StatsUpdated:Connect(function(stats)
		if stats.daily ~= lastDaily then
			lastDaily = stats.daily
			refresh()
		end
	end)
	refresh()
end

return DailyController
