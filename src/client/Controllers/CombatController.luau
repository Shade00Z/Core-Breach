-- CombatController
-- Your hero's controls and the feel of fighting:
--   * Swing the pickaxe-hammer: left click (hold to keep swinging). On
--     mobile, tap anywhere on the game world, or hold the big Swing button
--     next to the jump button. Hits enemies in front of you and wall rock
--     you've paid to dig.
--   * Fire Blast: Q, or the Fire Blast button on the right. Flies where you
--     face and bends toward the nearest enemy in front (aim assist), or a
--     layer boss in the arena.
--   Both also hit a layer boss (if your level is high enough).
--   * A red flash and sound when enemies hurt you.
--   * Rock chips and sounds while digging out wall slots.
--
-- The server decides all damage (CharacterService, AbilityService). This
-- controller shows hits right away (flash and damage numbers) so it feels
-- instant, and the kills arrive from the server a moment later.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))
local Format = require(Shared:WaitForChild("Format"))

local player = Players.LocalPlayer

local FIRE_COLOR = Color3.fromRGB(255, 120, 30)
local ROCK_CHIP_COLOR = Color3.fromRGB(100, 85, 75)
local HIDDEN = CFrame.new(0, -500, 0)
local MAX_ENEMY_RADIUS = 5
local DAMAGE_NUMBER_POOL = 24
local SWING_BUTTON_SCALE = 1.15 -- mobile Swing button size, relative to Roblox's jump button

-- Swing animation: arm angle (degrees, forward from hanging down) over time
local SWING_KEYS = {
	{ t = 0, angle = 0 },
	{ t = 0.08, angle = 150 }, -- wind up overhead
	{ t = 0.18, angle = 15 }, -- slam down in front
	{ t = 0.36, angle = 0 }, -- back to rest
}
local SWING_HIT_DELAY = 0.12 -- when the head lands (for the hit flash)

local CombatController = {}

local UIController
local SoundController
local EnemyRenderer
local swingRemote: RemoteEvent
local abilityRemote: RemoteEvent

local fxFolder: Folder
local holdingSwing = false
local lastSwing = -math.huge
local lastCast = -math.huge
local swingStarted: number? = nil
local swingJoint: Motor6D? = nil
local baseC0: { [Motor6D]: CFrame } = {}

local abilityButton: TextButton
local swingButton: TextButton?
local cooldownShade: Frame
local cooldownLabel: TextLabel
local hurtOverlay: Frame

local damageNumbers: { { part: BasePart, label: TextLabel, gui: BillboardGui } } = {}
local nextDamageNumber = 1

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function getRoot(): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Your current swing and Fire Blast damage, as the server last sent them
-- (they depend on your level and Power stat)
local function heroDamage(): (number, number)
	local hero = UIController.Stats.hero
	if type(hero) == "table" then
		return hero.swingDamage or 0, hero.fireBlastDamage or 0
	end
	return HeroConfig.SwingDamage(1), HeroConfig.FireBlastDamage(1)
end

local function enemyRadius(kind: number): number
	local stats = LaneConfig.Enemies[kind]
	return if stats then stats.radius else 1.5
end

local function fxPart(size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	if shape then
		part.Shape = shape
	end
	part.Parent = fxFolder
	return part
end

-- Layer bosses fighting near a point (BossService tags them "LayerBoss").
-- position = the boss's feet.
local function bossesNear(position: Vector3, range: number): { { model: Model, position: Vector3, offset: Vector3 } }
	local found = {}
	for _, model in CollectionService:GetTagged("LayerBoss") do
		local body = model.PrimaryPart
		if body and not model:GetAttribute("Defeated") then
			local feet = body.Position - Vector3.new(0, 4.5, 0)
			local radius = model:GetAttribute("Radius") or 5
			local offset = Vector3.new(feet.X - position.X, 0, feet.Z - position.Z)
			if offset.Magnitude <= range + radius and math.abs(feet.Y - position.Y) < 15 then
				table.insert(found, { model = model, position = feet, offset = offset })
			end
		end
	end
	return found
end

-- Your hero is high enough level to hurt this boss
local function canHurtBoss(model: Model): boolean
	local hero = UIController.Stats.hero
	return type(hero) == "table" and hero.level >= (model:GetAttribute("Level") or 0)
end

------------------------------------------------------------------------
-- Damage numbers
------------------------------------------------------------------------

local function buildDamageNumbers()
	for _ = 1, DAMAGE_NUMBER_POOL do
		local part = fxPart(Vector3.new(0.1, 0.1, 0.1), Color3.new(), nil)
		part.Transparency = 1
		part.CFrame = HIDDEN
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, 100, 0, 30)
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		gui.Enabled = false
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 22
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		table.insert(damageNumbers, { part = part, label = label, gui = gui })
	end
end

local function showDamage(position: Vector3, amount: number, color: Color3)
	local entry = damageNumbers[nextDamageNumber]
	nextDamageNumber = nextDamageNumber % #damageNumbers + 1
	local start = position + Vector3.new(math.random() * 1.6 - 0.8, 2, math.random() * 1.6 - 0.8)
	entry.part.CFrame = CFrame.new(start)
	entry.label.Text = Format.Number(math.floor(amount + 0.5))
	entry.label.TextColor3 = color
	entry.label.TextTransparency = 0
	entry.label.TextStrokeTransparency = 0.2
	entry.gui.Enabled = true
	local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(entry.part, info, { CFrame = CFrame.new(start + Vector3.new(0, 3, 0)) }):Play()
	TweenService:Create(entry.label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end

------------------------------------------------------------------------
-- Swinging
------------------------------------------------------------------------

local function shoulderJoint(): Motor6D?
	local character = player.Character
	if not character then
		return nil
	end
	local upperArm = character:FindFirstChild("RightUpperArm")
	local joint = upperArm and upperArm:FindFirstChild("RightShoulder")
	if not joint then
		local torso = character:FindFirstChild("Torso")
		joint = torso and torso:FindFirstChild("Right Shoulder")
	end
	return if joint and joint:IsA("Motor6D") then joint else nil
end

local function swingAngle(t: number): number?
	for i = 2, #SWING_KEYS do
		local a, b = SWING_KEYS[i - 1], SWING_KEYS[i]
		if t <= b.t then
			local alpha = (t - a.t) / (b.t - a.t)
			alpha = 1 - (1 - alpha) * (1 - alpha) -- ease out
			return a.angle + (b.angle - a.angle) * alpha
		end
	end
	return nil -- finished
end

local function animateSwing()
	local joint = swingJoint
	if not swingStarted or not joint then
		return
	end
	local base = baseC0[joint]
	local angle = swingAngle(os.clock() - swingStarted)
	if angle then
		-- Rotate the arm forward around the shoulder, in the torso's space
		joint.C0 = CFrame.new(base.Position) * CFrame.Angles(math.rad(angle), 0, 0) * base.Rotation
	else
		joint.C0 = base
		swingStarted = nil
	end
end

-- Flash and number the enemies this swing should hit (the server decides
-- the real damage; this just makes it feel instant)
local function showSwingHits(root: BasePart)
	local origin = root.Position
	local look = flatLook(root)
	local damage = heroDamage()
	local hit = false
	for _, enemy in EnemyRenderer:FindInRange(origin, HeroConfig.Swing.Range + MAX_ENEMY_RADIUS) do
		local offset = Vector3.new(enemy.position.X - origin.X, 0, enemy.position.Z - origin.Z)
		local distance = offset.Magnitude
		if distance <= HeroConfig.Swing.Range + enemyRadius(enemy.kind) and (distance < 1 or offset.Unit:Dot(look) >= HeroConfig.Swing.ArcDot) then
			EnemyRenderer:Flash(enemy.id)
			showDamage(enemy.position, damage, Color3.new(1, 1, 1))
			hit = true
		end
	end
	for _, boss in bossesNear(origin, HeroConfig.Swing.Range) do
		if canHurtBoss(boss.model) and (boss.offset.Magnitude < 1 or boss.offset.Unit:Dot(look) >= HeroConfig.Swing.ArcDot) then
			showDamage(boss.position + Vector3.new(0, 8, 0), damage, Color3.new(1, 1, 1))
			hit = true
		end
	end
	if hit then
		SoundController:Play("MeleeHit")
	end
end

local function trySwing()
	local root = getRoot()
	local now = os.clock()
	if not root or now - lastSwing < HeroConfig.Swing.Cooldown then
		return
	end
	lastSwing = now

	local joint = shoulderJoint()
	if joint then
		if not baseC0[joint] then
			baseC0[joint] = joint.C0
		end
		swingJoint = joint
		swingStarted = now
	end
	SoundController:Play("Swing")
	swingRemote:FireServer()
	task.delay(SWING_HIT_DELAY, function()
		local currentRoot = getRoot()
		if currentRoot then
			showSwingHits(currentRoot)
		end
	end)
end

------------------------------------------------------------------------
-- Fire Blast
------------------------------------------------------------------------

-- Same aim assist the server uses: the nearest enemy within the cone
local function pickTarget(origin: Vector3, look: Vector3): (number?, Vector3?)
	local settings = HeroConfig.FireBlast
	local minDot = math.cos(math.rad(settings.AimConeDegrees))
	local bestId, bestPosition, bestDistance = nil, nil, math.huge
	for _, enemy in EnemyRenderer:FindInRange(origin, settings.Range) do
		local offset = Vector3.new(enemy.position.X - origin.X, 0, enemy.position.Z - origin.Z)
		local distance = offset.Magnitude
		if (distance < 1 or offset.Unit:Dot(look) >= minDot) and distance < bestDistance then
			bestId, bestPosition, bestDistance = enemy.id, enemy.position, distance
		end
	end
	return bestId, bestPosition
end

local function explode(position: Vector3)
	local settings = HeroConfig.FireBlast
	SoundController:PlayAt("FireExplode", position)

	local blast = fxPart(Vector3.new(2, 2, 2), FIRE_COLOR, Enum.PartType.Ball)
	blast.CFrame = CFrame.new(position)
	local diameter = settings.SplashRadius * 2
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(blast, info, { Size = Vector3.new(diameter, diameter, diameter), Transparency = 1 }):Play()
	Debris:AddItem(blast, 0.4)

	local _, damage = heroDamage()
	for _, enemy in EnemyRenderer:FindInRange(position, settings.SplashRadius + MAX_ENEMY_RADIUS) do
		local dx, dz = enemy.position.X - position.X, enemy.position.Z - position.Z
		local reach = settings.SplashRadius + enemyRadius(enemy.kind)
		if dx * dx + dz * dz <= reach * reach then
			EnemyRenderer:Flash(enemy.id)
			showDamage(enemy.position, damage, FIRE_COLOR)
		end
	end
	for _, boss in bossesNear(position, settings.SplashRadius + 4) do
		if canHurtBoss(boss.model) then
			showDamage(boss.position + Vector3.new(0, 8, 0), damage, FIRE_COLOR)
		end
	end
end

-- The fireball flies toward its target and follows it if it moves
-- (a lane enemy by id, or a layer boss model)
local function launchFireball(start: Vector3, targetId: number?, aimPoint: Vector3, boss: Model?)
	local settings = HeroConfig.FireBlast
	local ball = fxPart(Vector3.new(2, 2, 2), FIRE_COLOR, Enum.PartType.Ball)
	ball.CFrame = CFrame.new(start)
	local light = Instance.new("PointLight")
	light.Color = FIRE_COLOR
	light.Range = 14
	light.Brightness = 3
	light.Parent = ball

	local position = start
	local target = aimPoint
	local flat = Vector3.new(aimPoint.X - start.X, 0, aimPoint.Z - start.Z).Magnitude
	local maxTime = flat / settings.Speed + 0.3
	local born = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if targetId then
			local current = EnemyRenderer:GetPosition(targetId)
			if current then
				target = current
			end
		elseif boss and boss.PrimaryPart then
			target = boss.PrimaryPart.Position - Vector3.new(0, 4.5, 0)
		end
		local toTarget = target - position
		local step = settings.Speed * dt
		if toTarget.Magnitude <= step + 0.5 or os.clock() - born > maxTime then
			connection:Disconnect()
			ball:Destroy()
			explode(Vector3.new(target.X, target.Y, target.Z))
			return
		end
		position += toTarget.Unit * step
		ball.CFrame = CFrame.new(position)
	end)
end

local function tryFireBlast()
	local root = getRoot()
	local now = os.clock()
	if not root or now - lastCast < HeroConfig.FireBlast.Cooldown then
		return
	end
	lastCast = now

	local look = flatLook(root)
	local targetId, targetPosition = pickTarget(root.Position, look)
	-- No lane enemy in front: a layer boss in the arena, if one's in the cone
	local boss: Model? = nil
	if not targetId then
		local minDot = math.cos(math.rad(HeroConfig.FireBlast.AimConeDegrees))
		for _, candidate in bossesNear(root.Position, HeroConfig.FireBlast.Range) do
			if candidate.offset.Magnitude < 1 or candidate.offset.Unit:Dot(look) >= minDot then
				boss, targetPosition = candidate.model, candidate.position
				break
			end
		end
	end
	local start = root.Position + look * 2 + Vector3.new(0, 1, 0)
	local aimPoint = targetPosition or (root.Position + look * HeroConfig.FireBlast.Range)
	abilityRemote:FireServer("FireBlast", targetId or 0)
	SoundController:Play("FireCast")
	launchFireball(start, targetId, aimPoint, boss)
end

local function updateCooldown()
	local cooldown = HeroConfig.FireBlast.Cooldown
	local remaining = math.max(0, cooldown - (os.clock() - lastCast))
	cooldownShade.Size = UDim2.new(1, 0, remaining / cooldown, 0)
	cooldownLabel.Text = if remaining > 0 then tostring(math.ceil(remaining)) else ""
end

------------------------------------------------------------------------
-- Getting hurt
------------------------------------------------------------------------

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	-- A new character means a new shoulder joint
	table.clear(baseC0)
	swingStarted = nil
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth - 0.5 then
			SoundController:Play("HeroHurt")
			-- Only visible while flashing, so it never gets in the way of clicks
			hurtOverlay.Visible = true
			hurtOverlay.BackgroundTransparency = 0.55
			local fade = TweenService:Create(hurtOverlay, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
			fade.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					hurtOverlay.Visible = false
				end
			end)
			fade:Play()
		end
		lastHealth = health
	end)
end

------------------------------------------------------------------------
-- Digging feedback (rock chips and sounds)
------------------------------------------------------------------------

local function burstChips(rock: BasePart, count: number, speed: number)
	for _ = 1, count do
		local chip = Instance.new("Part")
		local s = 0.4 + math.random() * 0.6
		chip.Size = Vector3.new(s, s, s)
		chip.Color = ROCK_CHIP_COLOR
		chip.Material = Enum.Material.Slate
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.CastShadow = false
		chip.CFrame = rock.CFrame * CFrame.new((math.random() - 0.5) * rock.Size.X, (math.random() - 0.3) * rock.Size.Y * 0.5, (math.random() - 0.5) * rock.Size.Z)
		chip.Parent = fxFolder
		chip.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * speed, speed * (0.6 + math.random() * 0.6), (math.random() - 0.5) * speed)
		Debris:AddItem(chip, 0.8)
	end
end

local function watchRock(rock: Instance)
	if not rock:IsA("BasePart") then
		return
	end
	local lastHits = rock:GetAttribute("DigHits") or 0
	rock:GetAttributeChangedSignal("DigHits"):Connect(function()
		local hits = rock:GetAttribute("DigHits") or 0
		if hits > lastHits then
			SoundController:PlayAt("RockHit", rock.Position)
			burstChips(rock, 4, 18)
		end
		lastHits = hits
	end)
	rock:GetAttributeChangedSignal("Paid"):Connect(function()
		if rock:GetAttribute("Paid") then
			SoundController:Play("Purchase")
		end
	end)
	rock:GetAttributeChangedSignal("Broken"):Connect(function()
		if rock:GetAttribute("Broken") then
			SoundController:PlayAt("RockBreak", rock.Position)
			burstChips(rock, 14, 30)
		end
	end)
end

local function watchLanes()
	local lanes = workspace:WaitForChild("Lanes")
	local function onLane(model: Instance)
		if model:GetAttribute("OwnerUserId") ~= player.UserId then
			return
		end
		local rocks = model:WaitForChild("Rocks", 10)
		if not rocks then
			return
		end
		rocks.ChildAdded:Connect(watchRock)
		for _, rock in rocks:GetChildren() do
			watchRock(rock)
		end
	end
	lanes.ChildAdded:Connect(onLane)
	for _, model in lanes:GetChildren() do
		task.spawn(onLane, model)
	end
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------

local function buildUi()
	local gui = UIController:GetGui()

	-- Fire Blast button, right side (works with a mouse and with thumbs)
	abilityButton = Instance.new("TextButton")
	abilityButton.Name = "FireBlastButton"
	abilityButton.AnchorPoint = Vector2.new(1, 0.5)
	abilityButton.Position = UDim2.new(1, -16, 0.5, 0)
	abilityButton.Size = UDim2.new(0, 86, 0, 86)
	abilityButton.BackgroundColor3 = Color3.fromRGB(200, 80, 20)
	abilityButton.Font = Enum.Font.GothamBold
	abilityButton.TextColor3 = Color3.new(1, 1, 1)
	abilityButton.TextSize = 15
	abilityButton.TextWrapped = true
	abilityButton.Text = if UserInputService.KeyboardEnabled then "Fire Blast\n[Q]" else "Fire Blast"
	abilityButton.ClipsDescendants = true
	abilityButton.Parent = gui
	Instance.new("UICorner", abilityButton).CornerRadius = UDim.new(0, 43)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 190, 90)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = abilityButton

	cooldownShade = Instance.new("Frame")
	cooldownShade.AnchorPoint = Vector2.new(0, 1)
	cooldownShade.Position = UDim2.new(0, 0, 1, 0)
	cooldownShade.Size = UDim2.new(1, 0, 0, 0)
	cooldownShade.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldownShade.BackgroundTransparency = 0.45
	cooldownShade.BorderSizePixel = 0
	cooldownShade.Parent = abilityButton

	cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Size = UDim2.new(1, 0, 1, 0)
	cooldownLabel.Font = Enum.Font.GothamBlack
	cooldownLabel.TextSize = 30
	cooldownLabel.TextColor3 = Color3.new(1, 1, 1)
	cooldownLabel.TextStrokeTransparency = 0.3
	cooldownLabel.Text = ""
	cooldownLabel.ZIndex = 3
	cooldownLabel.Parent = abilityButton

	abilityButton.Activated:Connect(tryFireBlast)

	-- How to swing (keyboard and mouse only; phones get a Swing button)
	if UserInputService.KeyboardEnabled then
		local hint = Instance.new("TextLabel")
		hint.AnchorPoint = Vector2.new(1, 0)
		hint.Position = UDim2.new(1, -8, 0.5, 50)
		hint.Size = UDim2.new(0, 104, 0, 18)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.GothamBold
		hint.TextSize = 13
		hint.TextColor3 = Color3.fromRGB(220, 220, 220)
		hint.TextStrokeTransparency = 0.4
		hint.Text = "Click: swing"
		hint.Parent = gui
	end

	-- Red flash when you get hurt
	hurtOverlay = Instance.new("Frame")
	hurtOverlay.Name = "HurtFlash"
	hurtOverlay.Size = UDim2.new(1, 0, 1, 0)
	hurtOverlay.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
	hurtOverlay.BackgroundTransparency = 1
	hurtOverlay.BorderSizePixel = 0
	hurtOverlay.Active = false
	hurtOverlay.Visible = false
	hurtOverlay.ZIndex = 0
	hurtOverlay.Parent = gui
end

------------------------------------------------------------------------
-- Mobile Swing button
------------------------------------------------------------------------

-- Puts the Swing button just left of Roblox's jump button, a bit bigger
-- than it, so it's under your right thumb.
local function placeSwingButton()
	local button = swingButton
	if not button then
		return
	end
	local gui = UIController:GetGui()
	local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
		local size = math.max(90, jump.AbsoluteSize.X * SWING_BUTTON_SCALE)
		local corner = jump.AbsolutePosition + jump.AbsoluteSize - gui.AbsolutePosition
		button.Size = UDim2.fromOffset(size, size)
		-- bottom-right corner of our button sits left of the jump button, same bottom line
		button.Position = UDim2.fromOffset(corner.X - jump.AbsoluteSize.X - 14, corner.Y)
	else
		local viewport = workspace.CurrentCamera.ViewportSize
		local small = math.min(viewport.X, viewport.Y) <= 500
		local size = if small then 90 else 130
		button.Size = UDim2.fromOffset(size, size)
		button.Position = UDim2.new(1, if small then -110 else -200, 1, if small then -16 else -60)
	end
	button:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
end

local function buildSwingButton()
	local gui = UIController:GetGui()
	local button = Instance.new("TextButton")
	button.Name = "SwingButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(70, 75, 90)
	button.BackgroundTransparency = 0.25
	button.Font = Enum.Font.GothamBlack
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.Text = "SWING"
	button.AutoButtonColor = true
	button.Parent = gui
	Instance.new("UICorner", button)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.18, 0)
	padding.PaddingRight = UDim.new(0.18, 0)
	padding.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(220, 220, 230)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	-- Hold to keep swinging
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingSwing = true
			trySwing()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingSwing = false
		end
	end)
	swingButton = button
	placeSwingButton()
end

------------------------------------------------------------------------

function CombatController:Init(controllers)
	UIController = controllers.UIController
	SoundController = controllers.SoundController
	EnemyRenderer = controllers.EnemyRenderer
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "HeroFX"
	fxFolder.Parent = workspace
	buildDamageNumbers()
	buildUi()
end

function CombatController:Start()
	swingRemote = Remotes.Event("SwingWeapon")
	abilityRemote = Remotes.Event("UseAbility")

	-- Swing: left mouse, gamepad R2, or a touch button. Holding keeps swinging.
	ContextActionService:BindAction("HeroSwing", function(_, state)
		if state == Enum.UserInputState.Begin then
			holdingSwing = true
			trySwing()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			holdingSwing = false
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	-- Mobile: tap the game world to swing, or hold the big Swing button
	UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
		if not processedByUI then
			trySwing()
		end
	end)
	if UserInputService.TouchEnabled then
		buildSwingButton()
		-- Re-place it when the jump button appears or the screen rotates
		player.CharacterAdded:Connect(function()
			task.delay(1, placeSwingButton)
		end)
		task.delay(1, placeSwingButton)
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.delay(0.2, placeSwingButton)
		end)
	end

	ContextActionService:BindAction("FireBlast", function(_, state)
		if state == Enum.UserInputState.Begin then
			tryFireBlast()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)

	RunService.RenderStepped:Connect(function()
		if holdingSwing then
			trySwing()
		end
		animateSwing()
		updateCooldown()
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	task.spawn(watchLanes)
end

return CombatController
