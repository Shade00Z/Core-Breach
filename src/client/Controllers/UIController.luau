-- UIController
-- The HUD: wave and barricade health (top), coins and DPS (top left),
-- luck (under the wave), messages from the server (bottom), and a DEBUG
-- label whenever DebugConfig is changing normal play.
--
-- It also keeps the latest stats from the server in UIController.Stats and
-- fires UIController.StatsUpdated, so other controllers (like the crate)
-- can read coins without asking the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LaneSnapshot = require(Shared:WaitForChild("LaneSnapshot"))
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Signal = require(Shared:WaitForChild("Signal"))

local STATE_TEXT = {
	[LaneSnapshot.States.Intermission] = "Next wave incoming...",
	[LaneSnapshot.States.Running] = "",
	[LaneSnapshot.States.Failed] = "Barricade broken! Retrying wave...",
}
local TOAST_TIME = 2.5
local MAX_TOASTS = 3

local UIController = {}
UIController.Stats = { coins = 0, dps = 0, luck = 1, luckIn = 10, stash = false } :: { [string]: any }

local statsEvent = Signal.new()
UIController.StatsUpdated = statsEvent

local gui: ScreenGui
local waveLabel: TextLabel
local statusLabel: TextLabel
local luckLabel: TextLabel
local coinLabel: TextLabel
local dpsLabel: TextLabel
local debugLabel: TextLabel
local toastList: Frame
local toastCount = 0
local hpFill: Frame

local function makeLabel(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.TextSize = textSize
	label.Text = ""
	label.Parent = parent
	return label
end

local gainLabel: TextLabel
local lastCoins: number? = nil
local gainTotal, gainToken = 0, 0

-- Shows "+$X" next to your coins when they go up, adding up quick pickups.
local function showGain(amount: number)
	gainTotal += amount
	gainToken += 1
	local token = gainToken
	gainLabel.Text = "+$" .. Format.Number(gainTotal)
	gainLabel.TextTransparency = 0
	gainLabel.TextStrokeTransparency = 0.5
	task.delay(1.2, function()
		if token == gainToken then
			gainTotal = 0
			TweenService:Create(gainLabel, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function refreshStats()
	local stats = UIController.Stats
	local coins = stats.coins or 0
	if lastCoins and coins > lastCoins then
		showGain(coins - lastCoins)
	end
	lastCoins = coins
	coinLabel.Text = "$ " .. Format.Number(coins)
	dpsLabel.Text = Format.Number(stats.dps or 0) .. " DPS"
	luckLabel.Text = string.format("Luck x%.2f  ·  up in %d waves", stats.luck or 1, stats.luckIn or 10)
end

-- Show a short message at the bottom of the screen.
function UIController:Toast(text: string)
	toastCount += 1
	local label = makeLabel(toastList, UDim2.new(1, 0, 0, 26), UDim2.new(), 18)
	label.LayoutOrder = toastCount
	label.Text = text
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	label.BackgroundTransparency = 0.35
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)

	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #toasts > MAX_TOASTS do
		table.remove(toasts, 1):Destroy()
	end

	task.delay(TOAST_TIME, function()
		if label.Parent then
			local tween = TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			label:Destroy()
		end
	end)
end

local function watchDebugFlag()
	local player = Players.LocalPlayer
	local lanes = workspace:WaitForChild("Lanes")

	local function check(model: Instance)
		if model:GetAttribute("OwnerUserId") == player.UserId then
			local function refresh()
				debugLabel.Visible = model:GetAttribute("Debug") == true
			end
			model:GetAttributeChangedSignal("Debug"):Connect(refresh)
			refresh()
		end
	end

	lanes.ChildAdded:Connect(check)
	for _, model in lanes:GetChildren() do
		check(model)
	end
end

function UIController:Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false

	-- Top center: wave, barricade, status, luck
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 8)
	panel.Size = UDim2.new(0, 280, 0, 86)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	waveLabel = makeLabel(panel, UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 0, 0), 26)
	waveLabel.Text = "Wave -"

	local hpBack = Instance.new("Frame")
	hpBack.Size = UDim2.new(1, 0, 0, 12)
	hpBack.Position = UDim2.new(0, 0, 0, 32)
	hpBack.BackgroundColor3 = Color3.fromRGB(40, 30, 25)
	hpBack.BorderSizePixel = 0
	hpBack.Parent = panel
	Instance.new("UICorner", hpBack).CornerRadius = UDim.new(0, 6)

	hpFill = Instance.new("Frame")
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(200, 150, 80)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBack
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 6)

	luckLabel = makeLabel(panel, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 48), 15)
	luckLabel.TextColor3 = Color3.fromRGB(150, 255, 170)
	statusLabel = makeLabel(panel, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 68), 16)

	-- Top left: coins and DPS (below Roblox's menu buttons)
	coinLabel = makeLabel(gui, UDim2.new(0, 220, 0, 36), UDim2.new(0, 12, 0, 56), 32)
	coinLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinLabel.TextColor3 = Color3.fromRGB(255, 215, 70)
	dpsLabel = makeLabel(gui, UDim2.new(0, 220, 0, 20), UDim2.new(0, 14, 0, 92), 17)
	dpsLabel.TextXAlignment = Enum.TextXAlignment.Left
	gainLabel = makeLabel(gui, UDim2.new(0, 160, 0, 26), UDim2.new(0, 150, 0, 61), 22)
	gainLabel.TextXAlignment = Enum.TextXAlignment.Left
	gainLabel.TextColor3 = Color3.fromRGB(150, 255, 120)
	gainLabel.TextTransparency = 1
	gainLabel.TextStrokeTransparency = 1

	-- Bottom center: messages (above the crate panel)
	toastList = Instance.new("Frame")
	toastList.AnchorPoint = Vector2.new(0.5, 1)
	toastList.Position = UDim2.new(0.5, 0, 1, -230)
	toastList.Size = UDim2.new(0, 420, 0, 100)
	toastList.BackgroundTransparency = 1
	toastList.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toastList

	debugLabel = makeLabel(gui, UDim2.new(0, 160, 0, 20), UDim2.new(0, 8, 1, -28), 14)
	debugLabel.TextXAlignment = Enum.TextXAlignment.Left
	debugLabel.TextColor3 = Color3.fromRGB(255, 200, 60)
	debugLabel.Text = "DEBUG MODE"
	debugLabel.Visible = false

	refreshStats()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- The ScreenGui other controllers add their panels to.
function UIController:GetGui(): ScreenGui
	return gui
end

function UIController:Start()
	Remotes.Event("EnemySnapshot").OnClientEvent:Connect(function(buf: buffer)
		local header = LaneSnapshot.ReadHeader(buf)
		local isBoss = header.wave % Config.Wave.BossEvery == 0
		waveLabel.Text = if isBoss then ("Wave " .. header.wave .. "  (BOSS)") else ("Wave " .. header.wave)
		hpFill.Size = UDim2.new(math.clamp(header.barricadeHp / math.max(1, header.barricadeMax), 0, 1), 0, 1, 0)
		statusLabel.Text = STATE_TEXT[header.state] or ""
	end)

	Remotes.Event("StatsChanged").OnClientEvent:Connect(function(changes: { [string]: any })
		if type(changes) ~= "table" then
			return
		end
		for key, value in changes do
			UIController.Stats[key] = value
		end
		refreshStats()
		statsEvent:Fire(UIController.Stats)
	end)

	Remotes.Event("Notify").OnClientEvent:Connect(function(text: string)
		if type(text) == "string" then
			UIController:Toast(text)
		end
	end)

	task.spawn(watchDebugFlag)
end

return UIController
