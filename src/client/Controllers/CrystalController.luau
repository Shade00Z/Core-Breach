-- CrystalController
-- The Powers menu (HUD button "Powers"):
--   * how many Power Crystals you have, and an Open button. Opening one
--     plays a short reveal (power names flick past, then your roll); a
--     power you already had turns into mastery XP instead.
--   * every power you own: its mastery level and bar, its 3 abilities and
--     the mastery level each unlocks at, and Equip / Unequip.
-- The panel is only rebuilt when something you'd click changes; mastery
-- bars update in place (rebuilding while you click would eat the click).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local PowerData = require(Shared:WaitForChild("PowerData"))
local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))

local REVEAL_TIME = 2

local CrystalController = {}

local UIController
local SoundController
local actionRemote: RemoteEvent
local panel: UIKit.Panel
local toggle: TextButton
local badge: TextLabel
local builtKey = ""
local revealing = false
-- In-place mastery bars: power id -> { label, fill }
local bars: { [string]: { label: TextLabel, fill: Frame } } = {}

local function powersStats()
	local powers = UIController.Stats.powers
	return if type(powers) == "table" then powers else nil
end

local function stateKey(powers): string
	local parts = { tostring(powers.crystals), powers.equipped or "", tostring(revealing) }
	for _, id in PowerData.Order do
		local state = powers.owned and powers.owned[id]
		if state then
			table.insert(parts, id .. ":" .. state.level)
		end
	end
	return table.concat(parts, "|")
end

local function masteryText(level: number, xp: number): (string, number)
	if level >= PowerData.Mastery.MaxLevel then
		return string.format("Mastery %d (max)", level), 1
	end
	local from, to = PowerData.XPForLevel(level), PowerData.XPForLevel(level + 1)
	return string.format("Mastery %d  ·  %d / %d XP", level, xp - from, to - from), (xp - from) / (to - from)
end

local function updateBars(powers)
	for id, bar in bars do
		local state = powers.owned and powers.owned[id]
		if state then
			local text, fraction = masteryText(state.level, state.xp)
			bar.label.Text = text
			bar.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		end
	end
end

local function build(powers)
	UIKit.Clear(panel.body)
	table.clear(bars)
	local C = UIKit.Colors
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	-- Crystals and the Open button
	local top = UIKit.Row(panel.body, nextOrder(), true)
	local count = UIKit.Label(top, string.format("Power Crystals: %d", powers.crystals), 18, Color3.fromRGB(200, 160, 255))
	count.Size = UDim2.new(1, -150, 0, 40)
	count.AutomaticSize = Enum.AutomaticSize.None
	count.TextYAlignment = Enum.TextYAlignment.Center
	local canOpen = powers.crystals > 0 and not revealing
	local openButton = UIKit.Button(top, if revealing then "Opening..." else "Open Crystal", if canOpen then Color3.fromRGB(130, 70, 200) else C.Gray, UDim2.new(0, 140, 0, 40), function()
		if canOpen then
			actionRemote:FireServer("Open")
		end
	end)
	openButton.AutoButtonColor = canOpen

	UIKit.Label(panel.body, "Crystals drop from layer bosses, sometimes from wave bosses, and from Magma Ore. Rolling a power you already have gives it +" .. PowerData.Mastery.DuplicateXP .. " mastery XP.", 13, C.Dim, nextOrder())

	local ownedAny = false
	for _, id in PowerData.Order do
		local power = PowerData.Powers[id]
		local state = powers.owned and powers.owned[id]
		if state then
			ownedAny = true
			local isEquipped = powers.equipped == id
			local row = UIKit.Row(panel.body, nextOrder())

			local header = Instance.new("Frame")
			header.BackgroundTransparency = 1
			header.Size = UDim2.new(1, 0, 0, 36)
			header.Parent = row
			local name = UIKit.Label(header, power.name .. (if isEquipped then "  (equipped)" else ""), 20, power.color)
			name.Size = UDim2.new(1, -130, 1, 0)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.TextYAlignment = Enum.TextYAlignment.Center
			local equip = UIKit.Button(header, if isEquipped then "Unequip" else "Equip", if isEquipped then C.Gray else C.Green, UDim2.new(0, 120, 0, 34), function()
				if isEquipped then
					actionRemote:FireServer("Unequip")
				else
					actionRemote:FireServer("Equip", id)
				end
			end)
			equip.Position = UDim2.new(1, -120, 0, 1)

			-- Mastery bar (updated in place)
			local label = UIKit.Label(row, "", 14, Color3.new(1, 1, 1))
			local track = Instance.new("Frame")
			track.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
			track.Size = UDim2.new(1, 0, 0, 10)
			track.Parent = row
			Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
			local fill = Instance.new("Frame")
			fill.BackgroundColor3 = power.color
			fill.Size = UDim2.fromScale(0, 1)
			fill.Parent = track
			Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
			bars[id] = { label = label, fill = fill }

			for slot, ability in power.abilities do
				local unlocked = state.level >= ability.mastery
				local status = if unlocked then string.format("[%s]", PowerData.Keys[slot]) else string.format("Mastery %d", ability.mastery)
				UIKit.Label(row, string.format("%s  %s  ·  %ds  —  %s", status, ability.name, ability.cooldown, ability.description), 13, if unlocked then Color3.new(1, 1, 1) else C.Dim)
			end
		end
	end
	if not ownedAny then
		UIKit.Label(panel.body, "You don't have a Core Power yet. Open a Power Crystal to get one! (Your first crystal comes at hero level 30.)", 15, C.Gold, nextOrder())
	else
		UIKit.Label(panel.body, "Abilities hit for a multiple of your pickaxe damage, +5% per mastery level. Every enemy they hit gives mastery XP.", 13, C.Dim, nextOrder())
	end
	updateBars(powers)
end

local function refresh()
	local powers = powersStats()
	if not powers then
		return
	end
	badge.Visible = powers.crystals > 0
	if not panel.frame.Visible then
		return
	end
	local key = stateKey(powers)
	if key ~= builtKey then
		builtKey = key
		build(powers)
	else
		updateBars(powers)
	end
end

------------------------------------------------------------------------
-- The reveal
------------------------------------------------------------------------

local function reveal(result)
	local power = PowerData.Get(result.powerId)
	if not power then
		return
	end
	revealing = true
	refresh()

	local cover = Instance.new("Frame")
	cover.Name = "Reveal"
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BackgroundTransparency = 0.25
	cover.Size = UDim2.fromScale(1, 1)
	cover.ZIndex = 20
	cover.Parent = panel.frame
	Instance.new("UICorner", cover).CornerRadius = UDim.new(0, 12)
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.fromScale(0.5, 0.42)
	name.Size = UDim2.new(1, -40, 0, 60)
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 40
	name.TextStrokeTransparency = 0.3
	name.TextColor3 = Color3.new(1, 1, 1)
	name.ZIndex = 21
	name.Parent = cover
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.fromScale(0.5, 0.55)
	sub.Size = UDim2.new(1, -40, 0, 50)
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 18
	sub.TextWrapped = true
	sub.TextColor3 = UIKit.Colors.Dim
	sub.Text = "Opening Power Crystal..."
	sub.ZIndex = 21
	sub.Parent = cover

	-- Names flick past, slowing down
	SoundController:Play("RollStart")
	local started = os.clock()
	local i = 0
	while os.clock() - started < REVEAL_TIME do
		i += 1
		local shown = PowerData.Powers[PowerData.Order[(i % #PowerData.Order) + 1]]
		name.Text = shown.name
		name.TextColor3 = shown.color
		task.wait(0.06 + (os.clock() - started) * 0.12)
	end

	name.Text = power.name
	name.TextColor3 = power.color
	name.TextSize = 30
	TweenService:Create(name, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 46 }):Play()
	SoundController:Play(if result.duplicate then "RevealCommon" else "RevealEpic")
	if result.duplicate then
		sub.Text = string.format("You already have it: +%d mastery XP (now mastery %d)", PowerData.Mastery.DuplicateXP, result.level or 1)
	else
		sub.Text = "New Core Power! Use its abilities with " .. table.concat(PowerData.Keys, " / ") .. " or the buttons on the right."
		sub.TextColor3 = UIKit.Colors.Gold
	end
	task.wait(2.2)
	cover:Destroy()
	revealing = false
	refresh()
end

------------------------------------------------------------------------

function CrystalController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()
	panel = UIKit.Panel(gui, "PowersPanel", "Core Powers", 540, 470)
	toggle = UIKit.HudButton(gui, "Powers", Color3.fromRGB(130, 70, 200), UDim2.new(0, 110, 0.5, 76))
	badge = UIKit.Badge(toggle)
	toggle.Activated:Connect(function()
		if panel.frame.Visible then
			panel.close()
		else
			panel.open()
			builtKey = ""
			refresh()
		end
	end)
end

function CrystalController:Start()
	actionRemote = Remotes.Event("PowerAction")
	Remotes.Event("PowerResult").OnClientEvent:Connect(function(result)
		if type(result) == "table" then
			if not panel.frame.Visible then
				panel.open()
			end
			task.spawn(reveal, result)
		end
	end)
	local lastPowers = nil
	UIController.StatsUpdated:Connect(function(stats)
		if stats.powers ~= lastPowers then
			lastPowers = stats.powers
			refresh()
		end
	end)
	refresh()
end

return CrystalController
