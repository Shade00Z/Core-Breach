-- RebirthController
-- The Rebirth button (bottom right) and its confirm panel.
-- The button appears once you've lost a wave this run, and shows how much
-- your coin multiplier would go up. Rebirthing sends you back to wave 1 and
-- keeps everything else. The server does the rebirth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local RebirthController = {}

local UIController
local button: TextButton
local buttonGain: TextLabel
local confirm: Frame
local confirmText: TextLabel
local pulse: Tween? = nil

local function label(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextSize = textSize
	l.TextWrapped = true
	l.Text = ""
	l.Parent = parent
	return l
end

local function makeButton(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 22
	b.Text = text
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
	return b
end

local function refresh()
	local stats = UIController.Stats
	local best = stats.runBestWave or 0
	local gain = stats.rebirthGain or 0
	local current = stats.coinMultiplier or 1

	button.Visible = stats.canRebirth == true
	buttonGain.Text = string.format("x%.2f  ->  x%.2f", current, current + gain)
	if not button.Visible then
		confirm.Visible = false
	end
	if confirm.Visible then
		confirmText.Text = string.format(
			"You beat wave %d this run (record: wave %d).\nCoins: x%.2f -> x%.2f\n\nYou go back to wave 1.\nYou keep your coins, gear, opened slots and hero level.",
			best,
			stats.bestWaveEver or best,
			current,
			current + gain
		)
	end
end

-- Pulse the button when the player is losing waves, to suggest rebirthing.
function RebirthController:Nudge()
	if not button.Visible or pulse then
		return
	end
	local scale = button:FindFirstChildOfClass("UIScale") :: UIScale
	pulse = TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true), { Scale = 1.12 })
	pulse:Play()
	pulse.Completed:Once(function()
		scale.Scale = 1
		pulse = nil
	end)
end

function RebirthController:Init(controllers)
	UIController = controllers.UIController
	local gui = UIController:GetGui()

	button = makeButton(gui, "", Color3.fromRGB(200, 160, 30), UDim2.new(0, 190, 0, 64), UDim2.new(1, -206, 1, -150))
	button.Name = "RebirthButton"
	button.Visible = false
	Instance.new("UIScale", button)
	local title = label(button, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 4), 24)
	title.Text = "Rebirth"
	buttonGain = label(button, UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 36), 16)
	buttonGain.TextColor3 = Color3.fromRGB(255, 245, 200)

	confirm = Instance.new("Frame")
	confirm.Name = "RebirthConfirm"
	confirm.AnchorPoint = Vector2.new(0.5, 0.5)
	confirm.Position = UDim2.new(0.5, 0, 0.45, 0)
	confirm.Size = UDim2.new(0, 380, 0, 250)
	confirm.BackgroundColor3 = Color3.fromRGB(24, 22, 28)
	confirm.BackgroundTransparency = 0.05
	confirm.Visible = false
	confirm.Parent = gui
	Instance.new("UICorner", confirm).CornerRadius = UDim.new(0, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(230, 185, 40)
	stroke.Parent = confirm

	local heading = label(confirm, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 12), 28)
	heading.Text = "Rebirth?"
	heading.TextColor3 = Color3.fromRGB(255, 210, 70)
	confirmText = label(confirm, UDim2.new(1, -30, 0, 120), UDim2.new(0, 15, 0, 50), 17)

	local yes = makeButton(confirm, "Rebirth", Color3.fromRGB(200, 160, 30), UDim2.new(0, 160, 0, 50), UDim2.new(0.5, -170, 1, -66))
	local no = makeButton(confirm, "Not yet", Color3.fromRGB(110, 110, 120), UDim2.new(0, 160, 0, 50), UDim2.new(0.5, 10, 1, -66))

	button.Activated:Connect(function()
		confirm.Visible = true
		refresh()
	end)
	no.Activated:Connect(function()
		confirm.Visible = false
	end)
	yes.Activated:Connect(function()
		confirm.Visible = false
		Remotes.Event("RequestRebirth"):FireServer()
	end)
end

function RebirthController:Start()
	UIController.StatsUpdated:Connect(refresh)
	refresh()

	-- Suggest rebirthing when a wave is lost (the button appears at that moment)
	Remotes.Event("Notify").OnClientEvent:Connect(function(text)
		if type(text) == "string" and text:find("Back to wave") then
			task.delay(0.3, function()
				RebirthController:Nudge()
			end)
		end
	end)
end

return RebirthController
