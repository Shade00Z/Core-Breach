-- PowerController
-- Your Core Power's abilities (PowerData) on the client:
--   * Q, F and R (or the three round buttons on the right) cast slot 1-3.
--     Locked abilities show the mastery level that unlocks them.
--   * Each ability is drawn right away (fireball, ice shard, lava pool,
--     nova, ice spikes) with predicted damage numbers, so it feels instant.
--     The server (AbilityService) decides the real damage.
-- With no power equipped the buttons are hidden; open a Power Crystal in
-- the Powers menu (CrystalController) to get one.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local PowerData = require(Shared:WaitForChild("PowerData"))

local BUTTON_SIZE = 76

local PowerController = {}

local UIController
local SoundController
local EnemyRenderer
local Combat -- CombatController's shared helpers
local abilityRemote: RemoteEvent

type Slot = { button: TextButton, shade: Frame, timer: TextLabel, title: TextLabel }
local slots: { Slot } = {}
local lastCast: { [string]: number } = {} -- ability id -> os.clock()

------------------------------------------------------------------------
-- What's equipped
------------------------------------------------------------------------

local function equipped(): (PowerData.Power?, number)
	local powers = UIController.Stats.powers
	if type(powers) ~= "table" then
		return nil, 1
	end
	local power = PowerData.Get(powers.equipped)
	local state = power and powers.owned and powers.owned[power.id]
	if not power or not state then
		return nil, 1
	end
	return power, state.level or 1
end

------------------------------------------------------------------------
-- Hits shown right away (the server sends the real ones)
------------------------------------------------------------------------

local function abilityDamage(ability: PowerData.Ability, mastery: number): number
	return Combat.SwingDamage() * ability.damage * PowerData.MasteryBonus(mastery)
end

local function showCircleHits(center: Vector3, radius: number, damage: number, color: Color3)
	for _, enemy in EnemyRenderer:FindInRange(center, radius + Combat.MaxEnemyRadius) do
		local dx, dz = enemy.position.X - center.X, enemy.position.Z - center.Z
		local reach = radius + Combat.EnemyRadius(enemy.kind)
		if dx * dx + dz * dz <= reach * reach then
			EnemyRenderer:Flash(enemy.id)
			Combat.ShowDamage(enemy.position, damage, color)
		end
	end
	for _, boss in Combat.BossesNear(center, radius + 4) do
		if Combat.CanHurtBoss(boss.model) then
			Combat.ShowDamage(boss.position + Vector3.new(0, 8, 0), damage, color)
		end
	end
end

-- Same aim assist the server uses: the nearest enemy within the cone, or a boss
local function pickTarget(origin: Vector3, look: Vector3, ability: PowerData.Ability): (number?, Vector3?, Model?)
	local range, cone = ability.range or 60, ability.cone or 35
	local minDot = math.cos(math.rad(cone))
	local bestId, bestPosition, bestDistance = nil, nil, math.huge
	for _, enemy in EnemyRenderer:FindInRange(origin, range) do
		local offset = Vector3.new(enemy.position.X - origin.X, 0, enemy.position.Z - origin.Z)
		local distance = offset.Magnitude
		if (distance < 1 or offset.Unit:Dot(look) >= minDot) and distance < bestDistance then
			bestId, bestPosition, bestDistance = enemy.id, enemy.position, distance
		end
	end
	if bestId then
		return bestId, bestPosition, nil
	end
	for _, boss in Combat.BossesNear(origin, range) do
		if boss.offset.Magnitude < 1 or boss.offset.Unit:Dot(look) >= minDot then
			return nil, boss.position, boss.model
		end
	end
	return nil, nil, nil
end

------------------------------------------------------------------------
-- Effects for each kind of ability
------------------------------------------------------------------------

local function burst(position: Vector3, radius: number, color: Color3, time: number)
	local ball = Combat.FxPart(Vector3.new(2, 2, 2), color, Enum.PartType.Ball)
	ball.CFrame = CFrame.new(position)
	ball.Transparency = 0.2
	local d = radius * 2
	TweenService:Create(ball, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(d, d * 0.6, d), Transparency = 1 }):Play()
	Debris:AddItem(ball, time + 0.05)
end

-- A ball that flies at its target (following it) and calls onHit where it lands
local function projectile(start: Vector3, targetId: number?, boss: Model?, aimPoint: Vector3, speed: number, color: Color3, size: number, onHit: (Vector3) -> ())
	local ball = Combat.FxPart(Vector3.new(size, size, size), color, Enum.PartType.Ball)
	ball.CFrame = CFrame.new(start)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 3
	light.Parent = ball
	local position, target = start, aimPoint
	local maxTime = Vector3.new(aimPoint.X - start.X, 0, aimPoint.Z - start.Z).Magnitude / speed + 0.3
	local born = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if targetId then
			target = EnemyRenderer:GetPosition(targetId) or target
		elseif boss and boss.PrimaryPart then
			target = boss.PrimaryPart.Position - Vector3.new(0, 4.5, 0)
		end
		local toTarget = target - position
		local step = speed * dt
		if toTarget.Magnitude <= step + 0.5 or os.clock() - born > maxTime then
			connection:Disconnect()
			ball:Destroy()
			onHit(target)
			return
		end
		position += toTarget.Unit * step
		ball.CFrame = CFrame.new(position)
	end)
end

local function lavaPool(center: Vector3, ability: PowerData.Ability, damage: number, color: Color3)
	local radius = ability.radius or 8
	local pool = Combat.FxPart(Vector3.new(0.3, radius * 2, radius * 2), color, Enum.PartType.Cylinder)
	pool.CFrame = CFrame.new(Vector3.new(center.X, center.Y - 1.5, center.Z)) * CFrame.Angles(0, 0, math.rad(90))
	pool.Transparency = 0.25
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = radius * 2
	light.Brightness = 2
	light.Parent = pool
	local ticks, every = ability.ticks or 8, ability.tickEvery or 0.5
	task.spawn(function()
		for i = 1, ticks do
			task.wait(every)
			pool.Transparency = if i % 2 == 0 then 0.25 else 0.4
			showCircleHits(center, radius, damage, color)
		end
		TweenService:Create(pool, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		Debris:AddItem(pool, 0.45)
	end)
end

local function iceLine(origin: Vector3, look: Vector3, ability: PowerData.Ability, damage: number, color: Color3)
	local length, width = ability.length or 50, ability.width or 8
	local count = math.floor(length / 5)
	for i = 1, count do
		task.delay(i * 0.02, function()
			local spot = origin + look * (i * 5) + Vector3.new(0, -2, 0)
			local spike = Combat.FxPart(Vector3.new(2.4, 6 + (i % 3) * 2, 2.4), color, nil)
			spike.Material = Enum.Material.Ice
			spike.Transparency = 0.15
			spike.CFrame = CFrame.lookAt(spot, spot + look) * CFrame.Angles(math.rad(-15), 0, 0)
			TweenService:Create(spike, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { Transparency = 1 }):Play()
			Debris:AddItem(spike, 1.5)
		end)
	end
	-- Predicted hits along the line
	task.delay(0.2, function()
		for _, enemy in EnemyRenderer:FindInRange(origin, length + Combat.MaxEnemyRadius) do
			local offset = Vector3.new(enemy.position.X - origin.X, 0, enemy.position.Z - origin.Z)
			local along = offset:Dot(look)
			local side = (offset - look * along).Magnitude
			local radius = Combat.EnemyRadius(enemy.kind)
			if along >= -radius and along <= length + radius and side <= width / 2 + radius then
				EnemyRenderer:Flash(enemy.id)
				Combat.ShowDamage(enemy.position, damage, color)
			end
		end
	end)
end

------------------------------------------------------------------------
-- Casting
------------------------------------------------------------------------

local function cast(slot: number)
	local power, mastery = equipped()
	local ability = power and power.abilities[slot]
	if not power or not ability then
		return
	end
	if mastery < ability.mastery then
		UIController:Toast(string.format("%s unlocks at %s mastery %d.", ability.name, power.name, ability.mastery))
		return
	end
	local now = os.clock()
	if lastCast[ability.id] and now - lastCast[ability.id] < ability.cooldown then
		return
	end
	local root = Combat.GetRoot()
	if not root then
		return
	end
	lastCast[ability.id] = now

	local origin = root.Position
	local look = Combat.FlatLook(root)
	local color = power.color
	local damage = abilityDamage(ability, mastery)

	if ability.kind == "projectile" then
		local targetId, targetPosition, boss = pickTarget(origin, look, ability)
		local aimPoint = targetPosition or (origin + look * (ability.range or 60))
		abilityRemote:FireServer(slot, targetId or 0)
		SoundController:Play("FireCast")
		local start = origin + look * 2 + Vector3.new(0, 1, 0)
		local splash = ability.splash or 6
		projectile(start, targetId, boss, aimPoint, ability.speed or 90, color, if power.id == "frost" then 1.4 else 2, function(at)
			SoundController:PlayAt("FireExplode", at)
			burst(at, splash, color, 0.35)
			showCircleHits(at, splash, damage, color)
		end)
	elseif ability.kind == "pool" then
		local targetId, targetPosition = pickTarget(origin, look, ability)
		local center = targetPosition or (origin + look * 20)
		abilityRemote:FireServer(slot, targetId or 0)
		SoundController:PlayAt("FireExplode", center)
		lavaPool(center, ability, damage, color)
	elseif ability.kind == "nova" then
		abilityRemote:FireServer(slot, 0)
		SoundController:Play("FireExplode")
		burst(origin, ability.radius or 15, color, 0.5)
		task.delay(0.15, showCircleHits, origin, ability.radius or 15, damage, color)
	elseif ability.kind == "line" then
		abilityRemote:FireServer(slot, 0)
		SoundController:Play("FireCast")
		iceLine(origin, look, ability, damage, color)
	end
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------

local function buildButtons()
	local gui = UIController:GetGui()
	for slot = 1, 3 do
		local button = Instance.new("TextButton")
		button.Name = "AbilityButton" .. slot
		button.AnchorPoint = Vector2.new(1, 0.5)
		-- Stacked on the right side, slot 1 at the bottom
		button.Position = UDim2.new(1, -16, 0.5, 40 - (slot - 1) * (BUTTON_SIZE + 10))
		button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
		button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		button.Text = ""
		button.AutoButtonColor = true
		button.ClipsDescendants = true
		button.Visible = false
		button.Parent = gui
		Instance.new("UICorner", button).CornerRadius = UDim.new(0.5, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.4
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 1)
		title.Font = Enum.Font.GothamBold
		title.TextColor3 = Color3.new(1, 1, 1)
		title.TextScaled = true
		title.TextWrapped = true
		title.TextStrokeTransparency = 0.5
		title.ZIndex = 2
		title.Parent = button
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 14
		limit.Parent = title
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.12, 0)
		pad.PaddingRight = UDim.new(0.12, 0)
		pad.Parent = title

		local shade = Instance.new("Frame")
		shade.AnchorPoint = Vector2.new(0, 1)
		shade.Position = UDim2.fromScale(0, 1)
		shade.Size = UDim2.fromScale(1, 0)
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.45
		shade.BorderSizePixel = 0
		shade.Parent = button

		local timer = Instance.new("TextLabel")
		timer.BackgroundTransparency = 1
		timer.Size = UDim2.fromScale(1, 1)
		timer.Font = Enum.Font.GothamBlack
		timer.TextSize = 28
		timer.TextColor3 = Color3.new(1, 1, 1)
		timer.TextStrokeTransparency = 0.3
		timer.Text = ""
		timer.ZIndex = 3
		timer.Parent = button

		button.Activated:Connect(function()
			cast(slot)
		end)
		slots[slot] = { button = button, shade = shade, timer = timer, title = title }
	end
end

-- Desktop: a column on the right side. Touch: a row just above the Swing
-- button (thumb reach), smaller.
local function layoutButtons()
	local gui = UIController:GetGui()
	local swing = gui:FindFirstChild("SwingButton")
	if UserInputService.TouchEnabled and swing and swing:IsA("GuiObject") and swing.Visible and swing.AbsoluteSize.X > 0 then
		local size = 60
		local right = swing.AbsolutePosition.X + swing.AbsoluteSize.X - gui.AbsolutePosition.X
		local top = swing.AbsolutePosition.Y - gui.AbsolutePosition.Y - 10
		for slot, ui in slots do
			ui.button.AnchorPoint = Vector2.new(1, 1)
			ui.button.Size = UDim2.fromOffset(size, size)
			ui.button.Position = UDim2.fromOffset(right - (slot - 1) * (size + 8), top)
		end
	else
		for slot, ui in slots do
			ui.button.AnchorPoint = Vector2.new(1, 0.5)
			ui.button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
			ui.button.Position = UDim2.new(1, -16, 0.5, 40 - (slot - 1) * (BUTTON_SIZE + 10))
		end
	end
end

local function refreshButtons()
	local power, mastery = equipped()
	for slot, ui in slots do
		local ability = power and power.abilities[slot]
		ui.button.Visible = ability ~= nil
		if ability and power then
			local unlocked = mastery >= ability.mastery
			local key = if UserInputService.KeyboardEnabled then string.format("\n[%s]", PowerData.Keys[slot]) else ""
			ui.title.Text = if unlocked then ability.name .. key else string.format("%s\nMastery %d", ability.name, ability.mastery)
			ui.button.BackgroundColor3 = if unlocked then power.color:Lerp(Color3.new(0, 0, 0), 0.25) else Color3.fromRGB(55, 55, 62)
			ui.title.TextTransparency = if unlocked then 0 else 0.35
		end
	end
end

local function updateCooldowns()
	local power = equipped()
	if not power then
		return
	end
	local now = os.clock()
	for slot, ui in slots do
		local ability = power.abilities[slot]
		if ability then
			local remaining = math.max(0, ability.cooldown - (now - (lastCast[ability.id] or -math.huge)))
			ui.shade.Size = UDim2.fromScale(1, remaining / ability.cooldown)
			ui.timer.Text = if remaining > 0 then tostring(math.ceil(remaining)) else ""
		end
	end
end

-- Dev cheat
function PowerController.ResetCooldowns()
	table.clear(lastCast)
end

------------------------------------------------------------------------

function PowerController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	EnemyRenderer = controllers.EnemyRenderer
	Combat = controllers.CombatController
	buildButtons()
end

function PowerController:Start()
	abilityRemote = Remotes.Event("UseAbility")
	local keys = { { Enum.KeyCode.Q, Enum.KeyCode.ButtonX }, { Enum.KeyCode.F, Enum.KeyCode.ButtonY }, { Enum.KeyCode.R, Enum.KeyCode.ButtonB } }
	for slot, codes in keys do
		ContextActionService:BindAction("CoreAbility" .. slot, function(_, state)
			if state == Enum.UserInputState.Begin then
				cast(slot)
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(codes))
	end

	local lastPowers = nil
	UIController.StatsUpdated:Connect(function(stats)
		if stats.powers ~= lastPowers then
			lastPowers = stats.powers
			refreshButtons()
		end
	end)
	refreshButtons()
	RunService.RenderStepped:Connect(updateCooldowns)
	-- The Swing button moves when the phone's jump button appears or the screen turns
	task.spawn(function()
		while true do
			layoutButtons()
			task.wait(1)
		end
	end)
end

return PowerController
