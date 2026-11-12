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
local ClientSettings = require(script.Parent.Parent:WaitForChild("ClientSettings"))

local STATE_TEXT = {
	[LaneSnapshot.States.Intermission] = "Next wave incoming...",
	[LaneSnapshot.States.Running] = "",
	[LaneSnapshot.States.Failed] = "Barricade broken! Dropping back a wave...",
}
local TOAST_TIME = 2.5
local MAX_TOASTS = 3
local MAX_TOASTS_COMPACT = 2 -- phones

local UIController = {}
local SoundController
UIController.Stats = {
	coins = 0,
	dps = 0,
	luck = 1,
	luckAt = 10,
	rebirths = 0,
	coinMultiplier = 1,
	runBestWave = 0,
	bestWaveEver = 0,
	rebirthGain = 0,
	canRebirth = false,
} :: { [string]: any }

local statsEvent = Signal.new()
UIController.StatsUpdated = statsEvent

local gui: ScreenGui
local waveLabel: TextLabel
local statusLabel: TextLabel
local bossBar: Frame
local bossFill: Frame
local lastBossHealth = 0
local luckLabel: TextLabel
local coinLabel: TextLabel
local dpsLabel: TextLabel
local levelLabel: TextLabel
local xpFill: Frame
local xpText: TextLabel
local debugLabel: TextLabel
local toastList: Frame
local toastCount = 0
local topPanel: Frame
local topScale: UIScale
local toastLayout: UIListLayout
local announceBanner: TextLabel
local announceToken = 0
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
	local dpsText = Format.Number(stats.dps or 0) .. " DPS"
	if (stats.rebirths or 0) > 0 then
		local boost = if type(stats.store) == "table" then stats.store.coinBoost or 1 else 1
		dpsText ..= string.format("  ·  Coins x%.2f%s", stats.coinMultiplier or 1, if boost > 1 then string.format(" (x%d pass)", boost) else "")
		-- Phones: keep this line short so it doesn't run under the wave panel
		if not ClientSettings.Get("compact") then
			dpsText ..= string.format("  ·  Record: wave %d", stats.bestWaveEver or 0)
		end
	end
	dpsLabel.Text = dpsText

	-- Hero level and XP bar
	local hero = stats.hero
	if type(hero) == "table" then
		levelLabel.Text = "Lv " .. hero.level
		if hero.xpNeeded > 0 then
			xpFill.Size = UDim2.new(math.clamp(hero.xp / hero.xpNeeded, 0, 1), 0, 1, 0)
			xpText.Text = Format.Number(math.floor(hero.xp)) .. " / " .. Format.Number(hero.xpNeeded) .. " XP"
		else
			xpFill.Size = UDim2.new(1, 0, 1, 0)
			xpText.Text = "MAX LEVEL (this layer)"
		end
	end
	luckLabel.Text = string.format("Luck x%.2f  ·  next: beat wave %d", stats.luck or 1, stats.luckAt or 10)
end

-- Show a short message at the bottom of the screen.
function UIController:Toast(text: string)
	toastCount += 1
	local compact = ClientSettings.Get("compact")
	local label = makeLabel(toastList, UDim2.new(1, 0, 0, 26), UDim2.new(), 18)
	if compact then
		-- Phones: small, left-aligned lines down the left side, off the lane
		label.Size = UDim2.new(0, 0, 0, 20)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.TextSize = 13
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = label
	end
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
	while #toasts > (if compact then MAX_TOASTS_COMPACT else MAX_TOASTS) do
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

-- Phone layout (MobileController switches "compact" on): the HUD may use the
-- strip beside Roblox's own buttons, the wave panel and boss bar shrink, and
-- messages move from the middle of the screen to the left side.
local function applyCompact()
	local compact = ClientSettings.Get("compact") == true
	gui.ScreenInsets = if compact then Enum.ScreenInsets.DeviceSafeInsets else Enum.ScreenInsets.CoreUISafeInsets
	topScale.Scale = if compact then 0.8 else 1
	topPanel.Position = UDim2.new(0.5, 0, 0, if compact then 4 else 8)
	bossBar.Size = if compact then UDim2.new(0, 280, 0, 16) else UDim2.new(0, 420, 0, 22)
	bossBar.Position = UDim2.new(0.5, 0, 0, if compact then 78 else 100)
	if compact then
		toastList.AnchorPoint = Vector2.new(0, 0)
		toastList.Position = UDim2.new(0, 12, 0, 196) -- under the Menu button
		toastList.Size = UDim2.new(0, 300, 0, 60)
		toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	else
		toastList.AnchorPoint = Vector2.new(0.5, 1)
		toastList.Position = UDim2.new(0.5, 0, 1, -230)
		toastList.Size = UDim2.new(0, 420, 0, 100)
		toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	for _, child in toastList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy() -- sized for the other layout
		end
	end
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

function UIController:Init(controllers)
	SoundController = controllers.SoundController
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	-- Children draw over their parents, and ZIndex orders things side by
	-- side: panels (ZIndex 10+) cover the HUD buttons underneath them
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Top center: wave, barricade, status, luck
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 8)
	panel.Size = UDim2.new(0, 280, 0, 86)
	panel.BackgroundTransparency = 1
	panel.Parent = gui
	topPanel = panel
	topScale = Instance.new("UIScale")
	topScale.Parent = panel

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

	-- Boss health bar, under the wave panel
	bossBar = Instance.new("Frame")
	bossBar.Name = "BossBar"
	bossBar.AnchorPoint = Vector2.new(0.5, 0)
	bossBar.Position = UDim2.new(0.5, 0, 0, 100)
	bossBar.Size = UDim2.new(0, 420, 0, 22)
	bossBar.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	bossBar.BorderSizePixel = 0
	bossBar.Visible = false
	bossBar.Parent = gui
	Instance.new("UICorner", bossBar).CornerRadius = UDim.new(0, 8)
	local bossStroke = Instance.new("UIStroke")
	bossStroke.Color = Color3.fromRGB(255, 80, 60)
	bossStroke.Thickness = 2
	bossStroke.Parent = bossBar
	bossFill = Instance.new("Frame")
	bossFill.Size = UDim2.new(1, 0, 1, 0)
	bossFill.BackgroundColor3 = Color3.fromRGB(220, 50, 40)
	bossFill.BorderSizePixel = 0
	bossFill.Parent = bossBar
	Instance.new("UICorner", bossFill).CornerRadius = UDim.new(0, 8)
	local bossName = makeLabel(bossBar, UDim2.new(1, 0, 1, 0), UDim2.new(), 16)
	bossName.Text = "WAVE BOSS"
	bossName.ZIndex = 2

	-- Top left: coins and DPS (below Roblox's menu buttons)
	coinLabel = makeLabel(gui, UDim2.new(0, 220, 0, 36), UDim2.new(0, 12, 0, 56), 32)
	coinLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinLabel.TextColor3 = Color3.fromRGB(255, 215, 70)
	dpsLabel = makeLabel(gui, UDim2.new(0, 420, 0, 20), UDim2.new(0, 14, 0, 92), 17)
	dpsLabel.TextXAlignment = Enum.TextXAlignment.Left
	-- Under that: hero level and XP bar
	levelLabel = makeLabel(gui, UDim2.new(0, 56, 0, 20), UDim2.new(0, 14, 0, 114), 17)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.TextColor3 = Color3.fromRGB(140, 210, 255)
	levelLabel.Text = "Lv 1"
	local xpBack = Instance.new("Frame")
	xpBack.Name = "XPBar"
	xpBack.Position = UDim2.new(0, 72, 0, 117)
	xpBack.Size = UDim2.new(0, 170, 0, 14)
	xpBack.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
	xpBack.BackgroundTransparency = 0.2
	xpBack.BorderSizePixel = 0
	xpBack.Parent = gui
	Instance.new("UICorner", xpBack).CornerRadius = UDim.new(0, 7)
	xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = Color3.fromRGB(80, 170, 255)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBack
	Instance.new("UICorner", xpFill).CornerRadius = UDim.new(0, 7)
	xpText = makeLabel(xpBack, UDim2.new(1, 0, 1, 0), UDim2.new(), 11)
	xpText.ZIndex = 2

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
	toastList.ZIndex = 30
	toastList.Parent = gui
	local layout = Instance.new("UIListLayout")
	toastLayout = layout
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toastList

	debugLabel = makeLabel(gui, UDim2.new(0, 160, 0, 20), UDim2.new(0, 8, 1, -28), 14)
	debugLabel.TextXAlignment = Enum.TextXAlignment.Left
	debugLabel.TextColor3 = Color3.fromRGB(255, 200, 60)
	debugLabel.Text = "DEBUG MODE"
	debugLabel.Visible = false

	-- Server-wide announcements (Mythic pulls, Re-Drills), under the wave bar
	announceBanner = makeLabel(gui, UDim2.new(0, 520, 0, 40), UDim2.new(0.5, -260, 0, 168), 22)
	announceBanner.Name = "Announcement"
	announceBanner.BackgroundColor3 = Color3.fromRGB(40, 10, 30)
	announceBanner.BackgroundTransparency = 0.15
	announceBanner.TextColor3 = Color3.fromRGB(255, 120, 190)
	announceBanner.Visible = false
	Instance.new("UICorner", announceBanner).CornerRadius = UDim.new(0, 10)
	local announceStroke = Instance.new("UIStroke")
	announceStroke.Color = Color3.fromRGB(255, 60, 140)
	announceStroke.Thickness = 2
	announceStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	announceStroke.Parent = announceBanner

	refreshStats()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- A big banner for news the whole server hears about
function UIController:Announce(text: string, kind: string?)
	announceToken += 1
	local token = announceToken
	announceBanner.Text = text
	announceBanner.TextColor3 = if kind == "ReDrill" then Color3.fromRGB(255, 190, 110) else Color3.fromRGB(255, 120, 190)
	announceBanner.Visible = true
	SoundController:Play(if kind == "Mythic" then "RevealLegendary" else "NewRecord")
	task.delay(6, function()
		if announceToken == token then
			announceBanner.Visible = false
		end
	end)
end

-- The ScreenGui other controllers add their panels to.
function UIController:GetGui(): ScreenGui
	return gui
end

function UIController:Start()
	ClientSettings.Changed:Connect(function(key)
		if key == "compact" then
			applyCompact()
		end
	end)
	Remotes.Event("EnemySnapshot").OnClientEvent:Connect(function(buf: buffer)
		local header = LaneSnapshot.ReadHeader(buf)
		local isBoss = header.wave % Config.Wave.BossEvery == 0
		waveLabel.Text = if isBoss then ("Wave " .. header.wave .. "  (BOSS)") else ("Wave " .. header.wave)
		hpFill.Size = UDim2.new(math.clamp(header.barricadeHp / math.max(1, header.barricadeMax), 0, 1), 0, 1, 0)
		if header.state == LaneSnapshot.States.Running and header.total > 0 then
			statusLabel.Text = string.format("%d / %d enemies left", header.remaining, header.total)
		else
			statusLabel.Text = STATE_TEXT[header.state] or ""
		end
		local bossShown = header.bossHealth ~= nil and header.state == LaneSnapshot.States.Running
		if bossShown and not bossBar.Visible and (header.bossHealth or 0) > 0 then
			SoundController:Play("BossRoar")
		end
		if bossBar.Visible and lastBossHealth > 0 and header.bossHealth == 0 then
			SoundController:Play("BossDown")
		end
		lastBossHealth = header.bossHealth or 0
		bossBar.Visible = bossShown
		if header.bossHealth then
			bossFill.Size = UDim2.new(math.clamp(header.bossHealth, 0, 1), 0, 1, 0)
		end
	end)

	Remotes.Event("Announce").OnClientEvent:Connect(function(text, kind)
		if type(text) == "string" then
			UIController:Announce(text, kind)
		end
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
			if text:find("leveled up") or text:find("^Level %d+!") then
				SoundController:Play("LevelUp")
			elseif text:find("New record") then
				SoundController:Play("NewRecord")
			elseif text:find("^Rebirth %d") then
				SoundController:Play("Rebirth")
			end
		end
	end)

	task.spawn(watchDebugFlag)
end

return UIController
