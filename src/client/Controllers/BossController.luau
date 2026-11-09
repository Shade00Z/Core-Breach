-- BossController
-- Client side of the layer bosses (server: BossService):
--   * A health bar at the top of the screen while you're near a boss fight
--   * A roar when it rises, a quake (sound and camera shake) when it slams,
--     and a fanfare when it falls
--   * A white flash when it's hit
-- Everything is read from the boss model's attributes; the server decides
-- all damage.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local TAG = "LayerBoss"
local BAR_DISTANCE = 90 -- show the HUD bar within this many studs of the boss
local SOUND_DISTANCE = 200
local SHAKE_DISTANCE = 30
local SHAKE_TIME = 0.35
local FLASH_TIME = 0.07

local BossController = {}

local UIController
local SoundController
local bar: Frame
local fill: Frame
local text: TextLabel
local shakeUntil = 0

local function myPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function bossPosition(model: Model): Vector3?
	local body = model.PrimaryPart
	return if body then body.Position else nil
end

local function near(model: Model, distance: number): boolean
	local me, boss = myPosition(), bossPosition(model)
	return me ~= nil and boss ~= nil and (me - boss).Magnitude <= distance
end

local flashing: { [Model]: boolean } = {}

local function flash(model: Model)
	if flashing[model] then
		return -- already white; don't save white as its real color
	end
	flashing[model] = true
	local originals = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Material ~= Enum.Material.Neon then
			originals[p] = p.Color
			p.Color = Color3.new(1, 1, 1)
		end
	end
	task.delay(FLASH_TIME, function()
		for p, color in originals do
			p.Color = color
		end
		flashing[model] = nil
	end)
end

local function watch(model: Instance)
	if not model:IsA("Model") then
		return
	end
	if near(model, SOUND_DISTANCE) then
		SoundController:Play("BossRoar")
	end
	local lastHp = model:GetAttribute("HP") or 0
	model:GetAttributeChangedSignal("HP"):Connect(function()
		local hp = model:GetAttribute("HP") or 0
		if hp < lastHp then
			flash(model)
		end
		lastHp = hp
	end)
	model:GetAttributeChangedSignal("Slam"):Connect(function()
		local position = bossPosition(model)
		if position then
			SoundController:PlayAt("BossSlam", position)
			if near(model, SHAKE_DISTANCE) then
				shakeUntil = os.clock() + SHAKE_TIME
			end
		end
	end)
	model:GetAttributeChangedSignal("Roots"):Connect(function()
		local position = bossPosition(model)
		if position then
			SoundController:PlayAt("RockBreak", position)
		end
	end)
	model:GetAttributeChangedSignal("Defeated"):Connect(function()
		if model:GetAttribute("Defeated") and near(model, SOUND_DISTANCE) then
			SoundController:Play("BossDown")
		end
	end)
end

-- The nearest fighting boss within BAR_DISTANCE
local function nearestBoss(): Model?
	local best, bestDistance = nil, BAR_DISTANCE
	local me = myPosition()
	if not me then
		return nil
	end
	for _, model in CollectionService:GetTagged(TAG) do
		local position = bossPosition(model)
		if position and not model:GetAttribute("Defeated") then
			local d = (position - me).Magnitude
			if d <= bestDistance then
				best, bestDistance = model, d
			end
		end
	end
	return best
end

function BossController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	local gui = UIController:GetGui()

	bar = Instance.new("Frame")
	bar.Name = "LayerBossBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 130)
	bar.Size = UDim2.new(0, 460, 0, 26)
	bar.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 140, 60)
	stroke.Thickness = 2
	stroke.Parent = bar
	fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(210, 90, 30)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 8)
	text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.TextSize = 16
	text.ZIndex = 2
	text.Parent = bar
end

function BossController:Start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
	for _, model in CollectionService:GetTagged(TAG) do
		watch(model)
	end

	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < 0.1 then
			return
		end
		timer = 0
		local boss = nearestBoss()
		bar.Visible = boss ~= nil
		if boss then
			local hp = boss:GetAttribute("HP") or 0
			local maxHp = math.max(1, boss:GetAttribute("MaxHP") or 1)
			fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
			local enraged = if boss:GetAttribute("Enraged") then "  ·  ENRAGED" else ""
			text.Text = string.format("%s  ·  %s / %s%s", boss:GetAttribute("BossName") or "Boss", Format.Number(hp), Format.Number(maxHp), enraged)
		end
	end)

	-- Camera shake after a nearby slam
	RunService:BindToRenderStep("BossShake", Enum.RenderPriority.Camera.Value + 1, function()
		if os.clock() < shakeUntil then
			local strength = (shakeUntil - os.clock()) / SHAKE_TIME * 0.6
			local camera = workspace.CurrentCamera
			camera.CFrame *= CFrame.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
		end
	end)
end

return BossController
