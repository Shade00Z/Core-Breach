-- DevController
-- The dev cheats panel. Only appears when DebugConfig allows it (always in
-- Studio playtests). Click DEV at the top right to open or close it.
-- The buttons just send commands; DevService on the server checks and runs them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local DebugConfig = require(Shared:WaitForChild("DebugConfig"))

local DevController = {}

local UIController
local remote: RemoteEvent
local panel: Frame
local speedButtons: { [number]: TextButton } = {}
local invincibleButton: TextButton
local stressButton: TextButton

local BUTTON_COLOR = Color3.fromRGB(60, 60, 72)
local ACTIVE_COLOR = Color3.fromRGB(60, 150, 90)

local function send(command: string, value: any?)
	remote:FireServer(command, value)
end

local function makeButton(parent: Instance, text: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 78, 0, 30)
	b.BackgroundColor3 = BUTTON_COLOR
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 14
	b.Text = text
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	b.Activated:Connect(onClick)
	return b
end

local function makeRow(title: string, order: number): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 52)
	row.LayoutOrder = order
	row.Parent = panel

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(255, 200, 60)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = title
	label.Parent = row

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.new(0, 0, 0, 18)
	buttons.Size = UDim2.new(1, 0, 0, 30)
	buttons.Parent = row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = buttons
	return buttons
end

local function refresh()
	local stats = UIController.Stats
	local speed = stats.devSpeed or 1
	for value, b in speedButtons do
		b.BackgroundColor3 = if value == speed then ACTIVE_COLOR else BUTTON_COLOR
	end
	invincibleButton.BackgroundColor3 = if stats.devInvincible then ACTIVE_COLOR else BUTTON_COLOR
	invincibleButton.Text = if stats.devInvincible then "ON" else "OFF"
	stressButton.BackgroundColor3 = if stats.devStress then ACTIVE_COLOR else BUTTON_COLOR
end

function DevController:Init(controllers)
	UIController = controllers.UIController
	if not DebugConfig.IsActive(Players.LocalPlayer) then
		return
	end
	local gui = UIController:GetGui()

	local toggle = Instance.new("TextButton")
	toggle.Name = "DevToggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 56)
	toggle.Size = UDim2.new(0, 60, 0, 30)
	toggle.BackgroundColor3 = Color3.fromRGB(200, 150, 30)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.TextSize = 16
	toggle.Text = "DEV"
	toggle.Parent = gui
	Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)

	panel = Instance.new("Frame")
	panel.Name = "DevPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 92)
	panel.Size = UDim2.new(0, 352, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	local speedRow = makeRow("Game speed", 1)
	for _, value in { 1, 2, 5, 10 } do
		speedButtons[value] = makeButton(speedRow, value .. "x", function()
			send("Speed", value)
		end)
	end

	local waveRow = makeRow("Waves", 2)
	makeButton(waveRow, "-1", function()
		send("Wave", -1)
	end)
	makeButton(waveRow, "+1", function()
		send("Wave", 1)
	end)
	makeButton(waveRow, "+10", function()
		send("Wave", 10)
	end)
	makeButton(waveRow, "Clear", function()
		send("ClearWave")
	end)

	local coinRow = makeRow("Coins", 3)
	makeButton(coinRow, "+1K", function()
		send("Coins", 1e3)
	end)
	makeButton(coinRow, "+100K", function()
		send("Coins", 1e5)
	end)
	makeButton(coinRow, "+1M", function()
		send("Coins", 1e6)
	end)

	local otherRow = makeRow("Invincible  ·  Unlock", 4)
	invincibleButton = makeButton(otherRow, "OFF", function()
		send("Invincible")
	end)
	makeButton(otherRow, "Rebirth", function()
		send("UnlockRebirth")
	end)
	makeButton(otherRow, "All slots", function()
		send("UnlockSlots")
	end)

	local testRow = makeRow("Performance  ·  Hero  ·  Save", 5)
	stressButton = makeButton(testRow, "150 foes", function()
		send("Stress")
	end)
	makeButton(testRow, "+5 levels", function()
		send("Levels", 5)
	end)
	makeButton(testRow, "Away 2h", function()
		send("Away", 7200)
	end)
	-- Needs a second click within 3 seconds, so it's never hit by accident
	local wipeButton: TextButton
	local armedUntil = 0
	wipeButton = makeButton(testRow, "Wipe save", function()
		if os.clock() < armedUntil then
			send("Wipe")
			return
		end
		armedUntil = os.clock() + 3
		wipeButton.Text = "Sure?"
		wipeButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
		task.delay(3, function()
			wipeButton.Text = "Wipe save"
			wipeButton.BackgroundColor3 = BUTTON_COLOR
		end)
	end)

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

function DevController:Start()
	remote = Remotes.Event("DevCommand")
	if not panel then
		return
	end
	UIController.StatsUpdated:Connect(refresh)
	refresh()
end

return DevController
