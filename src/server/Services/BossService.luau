-- BossService
-- Layer bosses, fought in each hub's boss arena (south of the plaza).
--
--   * Challenge it at the floor seal in the middle of the arena. You need
--     the boss's level (LayerConfig boss.level) to challenge it or hurt it.
--   * It's shared: anyone in the arena can jump in. Its HP grows with the
--     number of players in the arena when it rises (extraFighterHp).
--   * It chases the nearest player, hurts heroes it touches, and has two
--     telegraphed attacks (a red circle shows where they'll land):
--       Slam   a big circle around itself
--       Roots  smaller circles under several players
--     Below half HP it gets faster.
--   * Everyone who hurt it gets XP, coins and Boss Cores. If it's the first
--     time they've beaten their layer's boss, the floor seal cracks open and
--     they drop into the next layer (HubService:MoveToLayer).
--   * Nobody left in the arena for a while and it sinks back down (full HP).
--
-- The boss is a gray-box model moved by the server. Clients read its
-- attributes (HP, MaxHP, Slam, Roots, Defeated...) for the HUD bar, sounds
-- and hit numbers (BossController, CombatController).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local LootConfig = require(Shared:WaitForChild("LootConfig"))
local Config = require(Shared:WaitForChild("ProgressionConfig"))
local Format = require(Shared:WaitForChild("Format"))
local HubBuilder = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("HubBuilder"))

local TAG = "LayerBoss"
local NAG_COOLDOWN = 3
local CONTACT_INTERVAL = 1 -- seconds between touch hits on the same hero
local ARENA_HEIGHT = 15 -- studs above the arena floor that still count as "in the arena"
local MOVE_DOWN_DELAY = 4 -- seconds between the kill and dropping to the next layer
local TELEGRAPH_COLOR = Color3.fromRGB(255, 40, 30)

type State = "Idle" | "Fighting" | "Cooldown"

type Arena = {
	layer: number,
	def: LayerConfig.Boss,
	hub: any,
	center: Vector3, -- arena floor center
	state: State,
	model: Model?,
	body: BasePart?,
	barFill: Frame?,
	position: Vector3, -- boss feet
	yaw: number,
	hp: number,
	maxHp: number,
	contributors: { [Player]: number },
	contactTimers: { [Player]: number },
	slamTimer: number,
	rootsTimer: number,
	busy: number, -- seconds it stands still (winding up an attack)
	emptyTimer: number,
	cooldownEnds: number,
	prompt: ProximityPrompt,
}

local BossService = {}

local services
local notify: RemoteEvent
local arenas: { Arena } = {}
local lastNag: { [Player]: number } = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function nag(player: Player, text: string)
	local now = os.clock()
	if not lastNag[player] or now - lastNag[player] > NAG_COOLDOWN then
		lastNag[player] = now
		notify:FireClient(player, text)
	end
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Living players standing in the arena
local function fightersIn(arena: Arena): { Player }
	local list = {}
	local reach = HubBuilder.ArenaRadius + 4
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local offset = root.Position - arena.center
			if flat(offset).Magnitude <= reach and offset.Y > -5 and offset.Y < ARENA_HEIGHT then
				table.insert(list, player)
			end
		end
	end
	return list
end

local function hurt(player: Player, amount: number)
	local _, humanoid = rootOf(player)
	local lane = services.WaveService:GetLane(player)
	if humanoid and not (lane and lane.cheatInvincible) then
		humanoid:TakeDamage(amount)
	end
end

local function setSign(arena: Arena, text: string)
	arena.hub.arenaSign.Text = text
end

local function idleSign(arena: Arena)
	setSign(arena, string.format("%s\nLayer Boss · Level %d", arena.def.name, arena.def.level))
end

------------------------------------------------------------------------
-- The boss model (gray box): a hulking mass of dirt and roots
------------------------------------------------------------------------

local function bossPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, body: BasePart?, offset: CFrame?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	if body and offset then
		p.CFrame = body.CFrame * offset
		p.Anchored = false
		p.CanCollide = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = p
		weld.Parent = p
	else
		p.Anchored = true
	end
	p.Parent = model
	return p
end

local function buildBoss(arena: Arena): (Model, BasePart, Frame)
	local def = arena.def
	local model = Instance.new("Model")
	model.Name = "Boss_" .. def.name
	local dirt = Color3.fromRGB(105, 75, 50)
	local root = Color3.fromRGB(80, 55, 35)
	local body = bossPart(model, "Body", Vector3.new(8, 8, 7), dirt, Enum.Material.Ground)
	body.CFrame = CFrame.new(arena.position + Vector3.new(0, 4.5, 0))
	bossPart(model, "Head", Vector3.new(5.5, 4, 5), dirt, Enum.Material.Ground, body, CFrame.new(0, 5.5, -1.5))
	bossPart(model, "Jaw", Vector3.new(5, 1.4, 2), root, Enum.Material.Wood, body, CFrame.new(0, 3.6, -4))
	for _, x in { -1.3, 1.3 } do
		bossPart(model, "Eye", Vector3.new(1, 0.8, 0.3), Color3.fromRGB(255, 120, 30), Enum.Material.Neon, body, CFrame.new(x, 6.3, -4.1))
	end
	for _, x in { -5.6, 5.6 } do
		bossPart(model, "Arm", Vector3.new(2.6, 8, 2.6), root, Enum.Material.Wood, body, CFrame.new(x, -0.5, -1) * CFrame.Angles(math.rad(-20), 0, math.rad(x > 0 and -10 or 10)))
		bossPart(model, "Fist", Vector3.new(3.4, 3, 3.4), dirt, Enum.Material.Rock, body, CFrame.new(x * 1.08, -4.5, -2.4))
	end
	for i, a in { -50, -15, 20, 55 } do
		bossPart(model, "Root", Vector3.new(0.8, 7 + i, 0.8), root, Enum.Material.Wood, body, CFrame.new(math.sin(math.rad(a)) * 3, 4 + i * 0.6, 3) * CFrame.Angles(math.rad(-35), 0, math.rad(a)))
	end
	model.PrimaryPart = body

	-- Name and HP over its head
	local gui = Instance.new("BillboardGui")
	gui.Name = "BossTag"
	gui.Size = UDim2.fromScale(14, 2.4)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.5)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = Color3.fromRGB(255, 140, 90)
	name.TextStrokeTransparency = 0.2
	name.Text = def.name
	name.Parent = gui
	local back = Instance.new("Frame")
	back.Position = UDim2.fromScale(0, 0.58)
	back.Size = UDim2.fromScale(1, 0.34)
	back.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(220, 50, 40)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = body

	model:SetAttribute("BossName", def.name)
	model:SetAttribute("Level", def.level)
	model:SetAttribute("Radius", def.radius)
	model:SetAttribute("Layer", arena.layer)
	model:SetAttribute("Slam", 0)
	model:SetAttribute("Roots", 0)
	CollectionService:AddTag(model, TAG)
	return model, body, fill
end

local function placeBoss(arena: Arena)
	local body = arena.body
	if body then
		body.CFrame = CFrame.new(arena.position + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, arena.yaw, 0)
	end
end

local function setHp(arena: Arena, hp: number)
	arena.hp = math.max(0, hp)
	local model = arena.model
	if model then
		model:SetAttribute("HP", math.ceil(arena.hp))
	end
	if arena.barFill then
		arena.barFill.Size = UDim2.fromScale(arena.hp / arena.maxHp, 1)
	end
end

------------------------------------------------------------------------
-- Telegraphed attacks
------------------------------------------------------------------------

-- A red circle on the floor; after windup, hurts everyone inside it
local function telegraph(arena: Arena, center: Vector3, radius: number, windup: number, damage: number, onLand: () -> ())
	local ring = Instance.new("Part")
	ring.Name = "BossTelegraph"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = TELEGRAPH_COLOR
	ring.Transparency = 0.6
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(Vector3.new(center.X, arena.center.Y + 0.55, center.Z)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = arena.hub.model
	task.delay(windup, function()
		ring:Destroy()
		if arena.state ~= "Fighting" then
			return
		end
		for _, player in fightersIn(arena) do
			local root = rootOf(player)
			if root and flat(root.Position - center).Magnitude <= radius + 1 then
				hurt(player, damage)
			end
		end
		onLand()
	end)
end

local function slam(arena: Arena)
	local s = arena.def.slam
	arena.busy = s.windup + 0.3
	telegraph(arena, arena.position, s.radius, s.windup, s.damage, function()
		if arena.model then
			arena.model:SetAttribute("Slam", (arena.model:GetAttribute("Slam") or 0) + 1)
		end
	end)
end

local function roots(arena: Arena, fighters: { Player })
	local r = arena.def.roots
	-- Under random fighters (several circles can land on the same one, a bit apart)
	for i = 1, r.count do
		local player = fighters[math.random(1, #fighters)]
		local root = rootOf(player)
		if root then
			local jitter = if i == 1 then Vector3.zero else Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
			telegraph(arena, root.Position + jitter, r.radius, r.windup, r.damage, function()
				if arena.model and i == 1 then
					arena.model:SetAttribute("Roots", (arena.model:GetAttribute("Roots") or 0) + 1)
				end
			end)
		end
	end
end

------------------------------------------------------------------------
-- Fight
------------------------------------------------------------------------

local function despawn(arena: Arena)
	if arena.model then
		arena.model:Destroy()
	end
	arena.model, arena.body, arena.barFill = nil, nil, nil
	arena.contributors = {}
	arena.contactTimers = {}
end

local function resetToIdle(arena: Arena)
	despawn(arena)
	arena.state = "Idle"
	arena.prompt.Enabled = true
	idleSign(arena)
end

local function summon(arena: Arena, player: Player)
	if arena.state ~= "Idle" then
		return
	end
	local def = arena.def
	local data = services.DataService:Get(player)
	if data.level < def.level then
		notify:FireClient(player, string.format("You need to be level %d to challenge %s. You're level %d.", def.level, def.name, data.level))
		return
	end

	local fighters = fightersIn(arena)
	local count = math.max(1, #fighters)
	arena.maxHp = def.hp * (1 + def.extraFighterHp * (count - 1))
	arena.position = arena.center
	arena.yaw = 0
	arena.contributors = {}
	arena.contactTimers = {}
	arena.slamTimer = def.slam.every * 0.6
	arena.rootsTimer = def.roots.every * 0.8
	arena.busy = 1.5 -- rises from the seal before attacking
	arena.emptyTimer = 0
	arena.state = "Fighting"
	arena.prompt.Enabled = false
	setSign(arena, def.name .. " is awake!")

	local model, body, fill = buildBoss(arena)
	arena.model, arena.body, arena.barFill = model, body, fill
	model:SetAttribute("MaxHP", math.ceil(arena.maxHp))
	setHp(arena, arena.maxHp)
	placeBoss(arena)
	model.Parent = arena.hub.model

	for _, fighter in fighters do
		notify:FireClient(fighter, def.name .. " rises from the floor seal!")
	end
end

local function reward(arena: Arena, player: Player)
	local def = arena.def
	local data = services.DataService:Get(player)
	local rewards = def.rewards

	local xp = HeroConfig.XPToNext(data.level) * rewards.xpLevels
	services.CharacterService:GiveXP(player, xp)

	local multiplier = data.coinMultiplier * LayerConfig.Get(data.layer).coinMultiplier
	local coins = Config.CoinsForWave(math.max(1, data.wave - 1), multiplier) * rewards.coinWaves
	services.EconomyService:AddCoins(player, coins)

	local coreValue = Config.CoinsForWave(math.max(1, data.wave - 1)) * LootConfig.Drops.CoreValue
	services.LootService:Add(player, "boss_core", rewards.cores, coreValue * rewards.cores)

	notify:FireClient(player, string.format("%s defeated! +%s XP, +$%s, +%d Boss Cores", def.name, Format.Number(math.floor(xp)), Format.Number(math.floor(coins)), rewards.cores))
	services.QuestService:Progress(player, "boss", 1, arena.layer)

	-- First win on your own layer: the floor seal cracks open
	local key = tostring(arena.layer)
	local nextLayer = LayerConfig.Layers[arena.layer + 1]
	if not data.bossesBeaten[key] then
		data.bossesBeaten[key] = true
		if nextLayer and data.layer == arena.layer then
			notify:FireClient(player, string.format("The floor seal cracks open! Dropping into Layer %d: %s...", nextLayer.id, nextLayer.name))
			task.delay(MOVE_DOWN_DELAY, function()
				if player.Parent == Players and services.DataService:Get(player).layer == arena.layer then
					services.HubService:MoveToLayer(player, nextLayer.id)
					notify:FireClient(player, string.format("Welcome to the %s! New enemies, new ore and a new gear set. Coins x%.1f, luck +%.2f.", nextLayer.name, nextLayer.coinMultiplier, nextLayer.luckBonus))
				end
			end)
		end
	end
end

local function defeat(arena: Arena)
	arena.state = "Cooldown"
	local model = arena.model
	if model then
		model:SetAttribute("Defeated", true)
	end
	for player, damage in arena.contributors do
		if player.Parent == Players and damage > 0 then
			reward(arena, player)
		end
	end
	arena.contributors = {}
	task.delay(1.5, function()
		if arena.model == model then
			despawn(arena)
		end
	end)
	arena.cooldownEnds = os.clock() + arena.def.respawnSeconds
end

local function stepArena(arena: Arena, dt: number)
	if arena.state == "Cooldown" then
		local left = arena.cooldownEnds - os.clock()
		if left <= 0 then
			resetToIdle(arena)
		else
			setSign(arena, string.format("%s returns in %ds", arena.def.name, math.ceil(left)))
		end
		return
	end
	if arena.state ~= "Fighting" then
		return
	end

	local def = arena.def
	local fighters = fightersIn(arena)
	if #fighters == 0 then
		arena.emptyTimer += dt
		if arena.emptyTimer >= def.leashSeconds then
			resetToIdle(arena)
		end
		return
	end
	arena.emptyTimer = 0

	-- Nearest fighter
	local target, targetDistance = nil, math.huge
	for _, player in fighters do
		local root = rootOf(player)
		if root then
			local d = flat(root.Position - arena.position).Magnitude
			if d < targetDistance then
				target, targetDistance = root, d
			end
		end
	end

	local enraged = arena.hp < arena.maxHp * 0.5
	if arena.model and arena.model:GetAttribute("Enraged") ~= enraged then
		arena.model:SetAttribute("Enraged", enraged)
	end

	-- Chase (stands still while winding up an attack)
	if arena.busy > 0 then
		arena.busy -= dt
	elseif target and targetDistance > def.radius + 2.5 then
		local direction = flat(target.Position - arena.position).Unit
		local speed = if enraged then def.enragedSpeed else def.speed
		local nextPosition = arena.position + direction * math.min(speed * dt, targetDistance - def.radius - 2.5)
		-- Stay inside the arena
		local fromCenter = flat(nextPosition - arena.center)
		local limit = HubBuilder.ArenaRadius - def.radius
		if fromCenter.Magnitude > limit then
			nextPosition = arena.center + fromCenter.Unit * limit
		end
		arena.position = Vector3.new(nextPosition.X, arena.center.Y, nextPosition.Z)
	end
	if target then
		local look = flat(target.Position - arena.position)
		if look.Magnitude > 0.1 then
			arena.yaw = math.atan2(-look.X, -look.Z)
		end
	end
	placeBoss(arena)

	-- Touching it hurts
	for _, player in fighters do
		local root = rootOf(player)
		local timer = arena.contactTimers[player] or 0
		if timer > 0 then
			arena.contactTimers[player] = timer - dt
		elseif root and flat(root.Position - arena.position).Magnitude <= def.radius + 2 then
			arena.contactTimers[player] = CONTACT_INTERVAL
			hurt(player, def.contactDamage)
		end
	end

	-- Attacks
	local pace = if enraged then 0.7 else 1
	arena.slamTimer -= dt
	arena.rootsTimer -= dt
	if arena.busy <= 0 then
		if arena.slamTimer <= 0 then
			arena.slamTimer = def.slam.every * pace
			slam(arena)
		elseif arena.rootsTimer <= 0 then
			arena.rootsTimer = def.roots.every * pace
			roots(arena, fighters)
		end
	end
end

------------------------------------------------------------------------
-- Damage from heroes (CharacterService swings, AbilityService Fire Blast)
------------------------------------------------------------------------

local function damage(arena: Arena, player: Player, amount: number)
	if arena.state ~= "Fighting" or amount <= 0 then
		return
	end
	local data = services.DataService:Get(player)
	if data.level < arena.def.level then
		nag(player, string.format("You need level %d to hurt %s.", arena.def.level, arena.def.name))
		return
	end
	arena.contributors[player] = (arena.contributors[player] or 0) + amount
	setHp(arena, arena.hp - amount)
	if arena.hp <= 0 then
		defeat(arena)
	end
end

-- The fighting boss near a point, if any
local function activeNear(origin: Vector3, range: number): Arena?
	for _, arena in arenas do
		if arena.state == "Fighting" then
			local offset = arena.position - origin
			if flat(offset).Magnitude <= range + arena.def.radius and math.abs(offset.Y) < ARENA_HEIGHT then
				return arena
			end
		end
	end
	return nil
end

-- A pickaxe swing from origin, facing look
function BossService:Swing(player: Player, origin: Vector3, look: Vector3, amount: number)
	local arena = activeNear(origin, HeroConfig.Swing.Range)
	if not arena then
		return
	end
	local offset = flat(arena.position - origin)
	if offset.Magnitude < 1 or offset.Unit:Dot(look) >= HeroConfig.Swing.ArcDot then
		damage(arena, player, amount)
	end
end

-- Where Fire Blast should aim if no lane enemy is in front of you: a
-- fighting boss within range and the aim cone
function BossService:AimPoint(origin: Vector3, look: Vector3, range: number, coneDegrees: number): Vector3?
	local arena = activeNear(origin, range)
	if not arena then
		return nil
	end
	local offset = flat(arena.position - origin)
	if offset.Magnitude < 1 or offset.Unit:Dot(look) >= math.cos(math.rad(coneDegrees)) then
		return arena.position
	end
	return nil
end

-- An explosion at impact (Fire Blast splash)
function BossService:Blast(player: Player, impact: Vector3, splash: number, amount: number)
	local arena = activeNear(impact, splash)
	if arena then
		damage(arena, player, amount)
	end
end

------------------------------------------------------------------------

function BossService:Init(allServices)
	services = allServices
end

function BossService:Start()
	notify = Remotes.Event("Notify")
	for _, hub in services.HubService:GetHubs() do
		local def = LayerConfig.Get(hub.layer).boss
		if def then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BossPrompt"
			prompt.ActionText = "Challenge " .. def.name
			prompt.ObjectText = "Floor Seal · Level " .. def.level
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.HoldDuration = 0.6
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = hub.arenaSeal
			local arena: Arena = {
				layer = hub.layer,
				def = def,
				hub = hub,
				center = hub.arenaCenter,
				state = "Idle",
				position = hub.arenaCenter,
				yaw = 0,
				hp = 0,
				maxHp = 1,
				contributors = {},
				contactTimers = {},
				slamTimer = 0,
				rootsTimer = 0,
				busy = 0,
				emptyTimer = 0,
				cooldownEnds = 0,
				prompt = prompt,
			}
			prompt.Triggered:Connect(function(player)
				summon(arena, player)
			end)
			idleSign(arena)
			table.insert(arenas, arena)
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, arena in arenas do
			stepArena(arena, dt)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastNag[player] = nil
		for _, arena in arenas do
			arena.contributors[player] = nil
			arena.contactTimers[player] = nil
		end
	end)
end

return BossService
