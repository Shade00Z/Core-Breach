-- QuestController
-- Quests on the client (server: QuestService, text: QuestConfig):
--   * Talk to the quest giver at your layer's outpost (E / tap the prompt)
--     to open a dialogue: take the next quest, see how it's going, or turn
--     it in.
--   * A tracker on the right side of the screen shows your current quest.
--   * A "!" over the giver means a quest is waiting; "?" means one is ready
--     to turn in.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local QuestConfig = require(Shared:WaitForChild("QuestConfig"))

local CLOSE_DISTANCE = 18 -- walk this far from the giver and the dialogue closes
local DARK = Color3.fromRGB(22, 20, 28)
local GOLD = Color3.fromRGB(255, 210, 110)
local GREEN = Color3.fromRGB(70, 170, 90)
local GRAY = Color3.fromRGB(70, 70, 80)

local QuestController = {}

local UIController
local SoundController
local actionRemote: RemoteEvent

local tracker: Frame
local trackerTitle: TextLabel
local trackerText: TextLabel
local dialog: Frame
local nameLabel: TextLabel
local bodyLabel: TextLabel
local goalLabel: TextLabel
local buttonRow: Frame
local talkingTo: BasePart? = nil
local talkingLayer = 0
local lastQuest: { [string]: any }? = nil

local function label(parent: Instance, textSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextSize = textSize
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = parent
	return l
end

local function button(text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 130, 1, 0)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 17
	b.Text = text
	b.Parent = buttonRow
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	b.Activated:Connect(onClick)
	return b
end

local function questInfo(): { [string]: any }?
	local quest = UIController.Stats.quest
	return if type(quest) == "table" then quest else nil
end

local function isComplete(info, quest: QuestConfig.Quest?): boolean
	return quest ~= nil and info.active and info.progress >= quest.count
end

------------------------------------------------------------------------
-- Dialogue
------------------------------------------------------------------------

local function close()
	dialog.Visible = false
	talkingTo = nil
end

local function showDialog()
	local info = questInfo()
	for _, child in buttonRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local line = QuestConfig.Lines[talkingLayer]
	nameLabel.Text = if line then line.giver else "Miner"
	goalLabel.Text = ""

	if not line or not info or info.layer ~= talkingLayer then
		bodyLabel.Text = if line then line.elsewhere else "..."
		button("Bye", GRAY, close)
	else
		local quest = QuestConfig.Get(talkingLayer, info.step)
		if not quest then
			bodyLabel.Text = line.allDone
			button("Bye", GRAY, close)
		elseif not info.active then
			bodyLabel.Text = quest.offer
			goalLabel.Text = string.format("NEW QUEST %d/%d: %s\nGoal: %s\nReward: XP and coins", info.step, info.total, quest.title, QuestConfig.Describe(quest, talkingLayer))
			button("Not now", GRAY, close)
			button("Accept", GREEN, function()
				actionRemote:FireServer("Accept")
				SoundController:Play("QuestAccept")
				close()
			end)
		elseif isComplete(info, quest) then
			bodyLabel.Text = quest.done
			goalLabel.Text = string.format("%s: done!", quest.title)
			button("Turn in", GREEN, function()
				actionRemote:FireServer("TurnIn")
				SoundController:Play("QuestDone")
				close()
			end)
		else
			bodyLabel.Text = quest.reminder
			goalLabel.Text = string.format("%s: %s (%d/%d)", quest.title, QuestConfig.Describe(quest, talkingLayer), info.progress, quest.count)
			button("OK", GRAY, close)
		end
	end
	dialog.Visible = true
end

------------------------------------------------------------------------
-- Tracker and the "!" over the giver
------------------------------------------------------------------------

local function refreshMarkers(info)
	local hubs = workspace:FindFirstChild("Hubs")
	if not hubs then
		return
	end
	for _, hub in hubs:GetChildren() do
		local head = hub:FindFirstChild("QuestGiver") and hub.QuestGiver:FindFirstChild("Head")
		local marker = head and head:FindFirstChild("QuestMarker")
		if marker and marker:IsA("BillboardGui") then
			local text = marker:FindFirstChildOfClass("TextLabel")
			local show, symbol = false, "!"
			if info and hub:GetAttribute("Layer") == info.layer then
				local quest = QuestConfig.Get(info.layer, info.step)
				if quest and not info.active then
					show = true
				elseif isComplete(info, quest) then
					show, symbol = true, "?"
				end
			end
			marker.Enabled = show
			if text then
				text.Text = symbol
			end
		end
	end
end

local function refresh()
	local info = questInfo()
	if not info then
		tracker.Visible = false
		return
	end
	local line = QuestConfig.Lines[info.layer]
	local quest = QuestConfig.Get(info.layer, info.step)
	tracker.Visible = line ~= nil and quest ~= nil
	if line and quest then
		if not info.active then
			trackerTitle.Text = "QUEST"
			trackerText.Text = string.format("Talk to %s at the outpost (north of the plaza) for a quest.", line.giver)
		elseif isComplete(info, quest) then
			trackerTitle.Text = "QUEST · " .. quest.title
			trackerText.Text = string.format("Done! Return to %s.", line.giver)
		else
			trackerTitle.Text = "QUEST · " .. quest.title
			trackerText.Text = string.format("%s  (%d/%d)", QuestConfig.Describe(quest, info.layer), info.progress, quest.count)
		end
	end
	refreshMarkers(info)
	if dialog.Visible then
		showDialog()
	end
end

------------------------------------------------------------------------

function QuestController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()

	-- Tracker, top right
	tracker = Instance.new("Frame")
	tracker.Name = "QuestTracker"
	tracker.AnchorPoint = Vector2.new(1, 0)
	tracker.Position = UDim2.new(1, -12, 0, 150)
	tracker.Size = UDim2.new(0, 250, 0, 0)
	tracker.AutomaticSize = Enum.AutomaticSize.Y
	tracker.BackgroundColor3 = DARK
	tracker.BackgroundTransparency = 0.3
	tracker.Visible = false
	tracker.Parent = gui
	Instance.new("UICorner", tracker).CornerRadius = UDim.new(0, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = tracker
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = tracker
	trackerTitle = label(tracker, 15, GOLD)
	trackerTitle.LayoutOrder = 1
	trackerText = label(tracker, 13)
	trackerText.LayoutOrder = 2

	-- Dialogue, bottom center
	dialog = Instance.new("Frame")
	dialog.Name = "QuestDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 1)
	dialog.Position = UDim2.new(0.5, 0, 1, -150)
	dialog.Size = UDim2.new(0.9, 0, 0, 0)
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.BackgroundColor3 = DARK
	dialog.BackgroundTransparency = 0.05
	dialog.Visible = false
	dialog.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, math.huge)
	limit.Parent = dialog
	Instance.new("UICorner", dialog).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.5
	stroke.Parent = dialog
	local dpad = Instance.new("UIPadding")
	dpad.PaddingTop = UDim.new(0, 12)
	dpad.PaddingBottom = UDim.new(0, 12)
	dpad.PaddingLeft = UDim.new(0, 16)
	dpad.PaddingRight = UDim.new(0, 16)
	dpad.Parent = dialog
	local dlist = Instance.new("UIListLayout")
	dlist.Padding = UDim.new(0, 8)
	dlist.SortOrder = Enum.SortOrder.LayoutOrder
	dlist.Parent = dialog
	nameLabel = label(dialog, 20, GOLD)
	nameLabel.LayoutOrder = 1
	bodyLabel = label(dialog, 16)
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.LayoutOrder = 2
	goalLabel = label(dialog, 14, Color3.fromRGB(150, 255, 170))
	goalLabel.LayoutOrder = 3
	buttonRow = Instance.new("Frame")
	buttonRow.BackgroundTransparency = 1
	buttonRow.Size = UDim2.new(1, 0, 0, 40)
	buttonRow.LayoutOrder = 4
	buttonRow.Parent = dialog
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Right
	row.Padding = UDim.new(0, 10)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = buttonRow
end

function QuestController:Start()
	actionRemote = Remotes.Event("QuestAction")

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "TalkPrompt" then
			talkingTo = prompt.Parent :: BasePart
			talkingLayer = prompt:GetAttribute("Layer") or 1
			showDialog()
		end
	end)

	UIController.StatsUpdated:Connect(function(stats)
		if stats.quest ~= lastQuest then
			lastQuest = stats.quest
			refresh()
		end
	end)
	refresh()
	-- The hubs may stream in after the first quest update
	task.delay(3, function()
		refreshMarkers(questInfo())
	end)

	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < 0.25 then
			return
		end
		timer = 0
		if dialog.Visible and talkingTo then
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or (root.Position - talkingTo.Position).Magnitude > CLOSE_DISTANCE then
				close()
			end
		end
	end)
end

return QuestController
