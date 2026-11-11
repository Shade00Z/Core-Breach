-- StatsController
-- The Stats screen: spend the stat points you get from leveling up
-- (3 per level). Open it with the Stats button on the left, under Gear. A
-- badge on the button shows how many points are waiting.
-- The server (CharacterService) checks and applies every point; this just
-- shows the numbers and sends SpendStat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local Format = require(Shared:WaitForChild("Format"))

local STAT_COLORS = {
	power = Color3.fromRGB(255, 120, 70),
	command = Color3.fromRGB(110, 170, 255),
	excavation = Color3.fromRGB(210, 170, 110),
	fortune = Color3.fromRGB(255, 215, 70),
	vitality = Color3.fromRGB(110, 220, 120),
}
local ROW_HEIGHT = 66
local ENABLED = Color3.fromRGB(60, 150, 90)
local DISABLED = Color3.fromRGB(70, 70, 78)

local StatsController = {}

local UIController
local SoundController
local spendRemote: RemoteEvent
local toggle: TextButton
local badge: TextLabel
local panel: Frame
local header: TextLabel
local footer: TextLabel
local rows: { [string]: { value: TextLabel, plusOne: TextButton, plusFive: TextButton } } = {}

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
	b.TextSize = 16
	b.Text = text
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end

local function refresh()
	local hero = UIController.Stats.hero
	if type(hero) ~= "table" then
		return
	end
	local points = hero.points or 0
	badge.Visible = points > 0
	badge.Text = tostring(points)

	header.Text = string.format("Level %d  ·  %d point%s to spend", hero.level, points, if points == 1 then "" else "s")
	for id, row in rows do
		local spent = hero.stats[id] or 0
		row.value.Text = string.format("%d pts  ·  %s", spent, HeroConfig.Describe(id, spent))
		row.plusOne.Active = points >= 1
		row.plusOne.BackgroundColor3 = if points >= 1 then ENABLED else DISABLED
		row.plusFive.Active = points >= 1
		row.plusFive.BackgroundColor3 = if points >= 1 then ENABLED else DISABLED
		row.plusFive.Text = if points >= 1 then "+" .. math.min(5, points) else "+5"
	end
	footer.Text = string.format(
		"Swing %s  ·  Core Powers hit for a multiple of this  ·  Level cap %d",
		Format.Number(hero.swingDamage or 0),
		hero.cap or HeroConfig.Levels.Cap
	)
end

local function spend(statId: string, count: number)
	local hero = UIController.Stats.hero
	if type(hero) ~= "table" or (hero.points or 0) < 1 then
		return
	end
	spendRemote:FireServer(statId, math.min(count, hero.points))
	SoundController:Play("Purchase")
end

function StatsController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()

	-- Button under Gear
	toggle = button(gui, "Stats", Color3.fromRGB(90, 70, 150), UDim2.new(0, 90, 0, 40), UDim2.new(0, 12, 0.5, 28))
	toggle.Name = "StatsToggle"
	toggle.TextSize = 18
	badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -2, 0, 2)
	badge.Size = UDim2.new(0, 24, 0, 24)
	badge.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	badge.Font = Enum.Font.GothamBlack
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.TextSize = 13
	badge.Visible = false
	badge.Parent = toggle
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0.5, 0)

	panel = Instance.new("Frame")
	panel.Name = "StatsPanel"
	local panelHeight = 46 + #HeroConfig.Stats * (ROW_HEIGHT + 6) + 34
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 210, 0.5, 0)
	panel.Size = UDim2.new(0, 420, 0, panelHeight)
	panel.BackgroundColor3 = Color3.fromRGB(22, 20, 28)
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
	-- Shrink to fit short screens (phones in landscape)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (viewport.Y - 24) / panelHeight, (viewport.X - 124) / 420)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	header = label(panel, "Stats", UDim2.new(1, -60, 0, 30), UDim2.new(0, 14, 0, 8), 18)
	local close = button(panel, "X", Color3.fromRGB(150, 60, 60), UDim2.new(0, 32, 0, 32), UDim2.new(1, -42, 0, 8))

	for i, stat in HeroConfig.Stats do
		local frame = Instance.new("Frame")
		frame.Position = UDim2.new(0, 10, 0, 46 + (i - 1) * (ROW_HEIGHT + 6))
		frame.Size = UDim2.new(1, -20, 0, ROW_HEIGHT)
		frame.BackgroundColor3 = Color3.fromRGB(36, 34, 42)
		frame.Parent = panel
		Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

		local color = STAT_COLORS[stat.id] or Color3.new(1, 1, 1)
		-- Name, what it does, then your points and what they give; buttons on the right
		label(frame, stat.name, UDim2.new(1, -140, 0, 20), UDim2.new(0, 12, 0, 4), 17, color)
		local blurb = label(frame, stat.blurb, UDim2.new(1, -140, 0, 14), UDim2.new(0, 12, 0, 25), 12, Color3.fromRGB(170, 170, 180))
		blurb.TextTruncate = Enum.TextTruncate.AtEnd
		local value = label(frame, "", UDim2.new(1, -140, 0, 16), UDim2.new(0, 12, 0, 43), 13, Color3.fromRGB(230, 230, 240))
		value.TextTruncate = Enum.TextTruncate.AtEnd

		local plusOne = button(frame, "+1", ENABLED, UDim2.new(0, 56, 0, 46), UDim2.new(1, -124, 0, 10))
		local plusFive = button(frame, "+5", ENABLED, UDim2.new(0, 56, 0, 46), UDim2.new(1, -62, 0, 10))
		plusOne.Activated:Connect(function()
			spend(stat.id, 1)
		end)
		plusFive.Activated:Connect(function()
			spend(stat.id, 5)
		end)
		rows[stat.id] = { value = value, plusOne = plusOne, plusFive = plusFive }
	end

	footer = label(panel, "", UDim2.new(1, -28, 0, 20), UDim2.new(0, 14, 1, -28), 13, Color3.fromRGB(200, 200, 210))

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
		-- Only one side panel at a time
		local gearPanel = gui:FindFirstChild("GearPanel")
		if panel.Visible and gearPanel then
			gearPanel.Visible = false
		end
		refresh()
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	-- Opening the gear panel closes this one
	task.defer(function()
		local gearPanel = gui:FindFirstChild("GearPanel")
		if gearPanel then
			gearPanel:GetPropertyChangedSignal("Visible"):Connect(function()
				if gearPanel.Visible then
					panel.Visible = false
				end
			end)
		end
	end)
end

function StatsController:Start()
	spendRemote = Remotes.Event("SpendStat")
	UIController.StatsUpdated:Connect(refresh)
	refresh()
end

return StatsController
