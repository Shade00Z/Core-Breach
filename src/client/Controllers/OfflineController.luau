-- OfflineController
-- The "Welcome back" popup: what your gear wall earned while you were away
-- (EconomyService works it out when you join). Press Collect to add it to
-- your coins. If you leave without collecting, it's still there next time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Format"))

local OfflineController = {}

local UIController
local SoundController
local collectRemote: RemoteEvent
local popup: Frame
local awayLabel: TextLabel
local coinsLabel: TextLabel

local function formatDuration(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end
	return string.format("%dm", math.max(1, minutes))
end

local function label(parent: Instance, size: UDim2, position: UDim2, textSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextSize = textSize
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function show(offline)
	if type(offline) ~= "table" then
		popup.Visible = false
		return
	end
	awayLabel.Text = "You were away " .. formatDuration(offline.seconds or 0) .. ". Your gear wall kept earning:"
	coinsLabel.Text = "$ " .. Format.Number(offline.coins or 0)
	if not popup.Visible then
		popup.Visible = true
		local scale = popup:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.6
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
end

function OfflineController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()

	popup = Instance.new("Frame")
	popup.Name = "WelcomeBack"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.new(0.5, 0, 0.45, 0)
	popup.Size = UDim2.new(0, 360, 0, 220)
	popup.BackgroundColor3 = Color3.fromRGB(22, 20, 28)
	popup.Visible = false
	popup.ZIndex = 20
	popup.Parent = gui
	Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 14)
	Instance.new("UIScale", popup)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 70)
	stroke.Thickness = 2
	stroke.Parent = popup

	local title = label(popup, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 14), 26)
	title.Text = "Welcome back!"
	title.ZIndex = 21
	awayLabel = label(popup, UDim2.new(1, -40, 0, 40), UDim2.new(0, 20, 0, 52), 15, Color3.fromRGB(210, 210, 220))
	awayLabel.ZIndex = 21
	coinsLabel = label(popup, UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 96), 38, Color3.fromRGB(255, 215, 70))
	coinsLabel.ZIndex = 21

	local collect = Instance.new("TextButton")
	collect.AnchorPoint = Vector2.new(0.5, 1)
	collect.Position = UDim2.new(0.5, 0, 1, -16)
	collect.Size = UDim2.new(0, 200, 0, 50)
	collect.BackgroundColor3 = Color3.fromRGB(60, 170, 80)
	collect.Font = Enum.Font.GothamBold
	collect.TextColor3 = Color3.new(1, 1, 1)
	collect.TextSize = 22
	collect.Text = "Collect"
	collect.ZIndex = 21
	collect.Parent = popup
	Instance.new("UICorner", collect).CornerRadius = UDim.new(0, 10)
	collect.Activated:Connect(function()
		popup.Visible = false
		UIController.Stats.offline = false -- don't re-show before the server confirms
		collectRemote:FireServer()
		SoundController:Play("Purchase")
	end)
end

function OfflineController:Start()
	collectRemote = Remotes.Event("CollectOffline")
	UIController.StatsUpdated:Connect(function(stats)
		if stats.offline ~= nil then
			show(stats.offline)
		end
	end)
	show(UIController.Stats.offline)
end

return OfflineController
