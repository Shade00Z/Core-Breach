-- CharacterService
-- Your hero: level, XP, stat points, health, the pickaxe-hammer in your
-- hand, and what a swing hits.
--
-- XP: every kill gives XP equal to the enemy's max HP; kills by your gear
-- wall give a quarter of that (HeroConfig.Levels). Each level gives 3 stat
-- points, spent on the Stats screen (SpendStat remote). Levels never reset.
--
-- Stats (HeroConfig.Stats) turn into multipliers other services ask for
-- with :GetEffects(player): Power (your damage), Command (gear wall),
-- Excavation (digging), Fortune (crate luck), Vitality (health, barricade).
--
-- Swings: the client (CombatController) plays the swing and sends
-- SwingWeapon. The server checks the cooldown and works out the hits itself
-- from where your character is and which way it faces, so a player can't
-- fake hits. A swing damages enemies in front of you and chips any wall rock
-- you've paid to dig (DigService), ore veins in the mine (MiningService),
-- and a layer boss in the arena (BossService).
-- The level cap depends on your layer (LayerConfig levelCap).
-- The pickaxe head's color shows your pickaxe tier.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))
local LootConfig = require(Shared:WaitForChild("LootConfig"))
local LayerConfig = require(Shared:WaitForChild("LayerConfig"))
local Boosts = require(Shared:WaitForChild("Boosts"))

local HANDLE_COLOR = Color3.fromRGB(110, 75, 45)
local HEAD_COLOR = Color3.fromRGB(90, 95, 105)

-- Swings arriving a little early are allowed (network timing isn't exact)
local COOLDOWN_TOLERANCE = 0.8
local PUSH_INTERVAL = 0.25 -- XP changes on every kill; send it at most this often
local MAX_POINTS_PER_REQUEST = 1000

local CharacterService = {}

local services
local notify: RemoteEvent
local lastSwing: { [Player]: number } = {}
local effectsCache: { [Player]: HeroConfig.Effects } = {}
local dirty: { [Player]: boolean } = {}

------------------------------------------------------------------------
-- Stats and effects
------------------------------------------------------------------------

-- Everything the player's stat points add up to (multipliers, max health),
-- with permanent boosts on top (Re-Drills and Gear Index pages: Boosts).
function CharacterService:GetEffects(player: Player): HeroConfig.Effects
	local effects = effectsCache[player]
	if not effects then
		local data = services.DataService:Get(player)
		effects = HeroConfig.Effects(data.stats)
		local boosts = Boosts.For(data)
		effects.gearDamage *= boosts.damage
		effects.luck *= boosts.luck
		effects.coins = boosts.coins
		effectsCache[player] = effects
	end
	return effects
end

function CharacterService:SwingDamage(player: Player): number
	return HeroConfig.SwingDamage(services.DataService:Get(player).level, self:GetEffects(player))
end

function CharacterService:FireBlastDamage(player: Player): number
	return HeroConfig.FireBlastDamage(services.DataService:Get(player).level, self:GetEffects(player))
end

-- Level cap: each layer has its own (LayerConfig levelCap). It follows the
-- deepest layer you've ever reached, so a Re-Drill never lowers it.
local function capFor(data): number
	return LayerConfig.LevelCap(math.max(data.layer, data.deepestEver or 1))
end

local function pointsSpent(data): number
	local total = 0
	for _, stat in HeroConfig.Stats do
		total += data.stats[stat.id] or 0
	end
	return total
end

local function pointsAvailable(data): number
	return math.max(0, HeroConfig.PointsForLevel(data.level) - pointsSpent(data))
end

-- Sends the hero's level, XP and stats to the client (HUD and Stats screen)
local function pushHero(player: Player)
	local data = services.DataService:Get(player)
	local cap = capFor(data)
	services.EconomyService:PushStats(player, {
		hero = {
			level = data.level,
			xp = data.xp,
			xpNeeded = if data.level >= cap then 0 else HeroConfig.XPToNext(data.level),
			cap = cap,
			points = pointsAvailable(data),
			stats = table.clone(data.stats),
			swingDamage = CharacterService:SwingDamage(player),
			fireBlastDamage = CharacterService:FireBlastDamage(player),
		},
	})
end

-- Max health follows Vitality. Keeps the same fraction of health you had.
local function applyHealth(player: Player, healFully: boolean?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local maxHealth = CharacterService:GetEffects(player).maxHealth
	local fraction = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	humanoid.MaxHealth = maxHealth
	humanoid.Health = if healFully then maxHealth else maxHealth * fraction
end

-- Gear Index and Re-Drill info for the Index screen
local function pushBoosts(player: Player)
	local data = services.DataService:Get(player)
	local boosts = Boosts.For(data)
	local discovered = {}
	for gearId in data.discovered do
		table.insert(discovered, gearId)
	end
	services.EconomyService:PushStats(player, {
		boosts = { damage = boosts.damage, coins = boosts.coins, luck = boosts.luck, reDrills = data.reDrills, discovered = discovered },
	})
end

-- Recalculate effects after stats change, and tell everything that uses them
local function statsChanged(player: Player)
	effectsCache[player] = nil
	applyHealth(player)
	services.GearService:RefreshDps(player) -- Command
	services.CrateService:Refresh(player) -- Fortune (luck shown on the HUD)
	pushHero(player)
end

-- Permanent boosts changed (a Re-Drill, or a gear discovered for the Index)
function CharacterService:RefreshBoosts(player: Player)
	statsChanged(player)
	pushBoosts(player)
end

-- A gear was owned for the first time. Announces a completed Index page.
function CharacterService:OnDiscovered(player: Player, gearId: string)
	local data = services.DataService:Get(player)
	for _, page in Boosts.Pages do
		if table.find(page.gear, gearId) and Boosts.PageComplete(page, data.discovered) then
			notify:FireClient(player, string.format("Gear Index page complete: %s! %s for good.", page.name, page.bonusText))
		end
	end
	self:RefreshBoosts(player)
end

local function spendStat(player: Player, statId: unknown, count: unknown)
	if type(statId) ~= "string" or type(count) ~= "number" or count ~= count then
		return
	end
	local known = false
	for _, stat in HeroConfig.Stats do
		if stat.id == statId then
			known = true
		end
	end
	if not known then
		return
	end
	local data = services.DataService:Get(player)
	local amount = math.min(math.floor(count), MAX_POINTS_PER_REQUEST, pointsAvailable(data))
	if amount <= 0 then
		return
	end
	data.stats[statId] = (data.stats[statId] or 0) + amount
	statsChanged(player)
end

------------------------------------------------------------------------
-- XP and levels
------------------------------------------------------------------------

function CharacterService:GiveXP(player: Player, amount: number)
	if amount <= 0 or amount ~= amount then
		return
	end
	local data = services.DataService:Get(player)
	local cap = capFor(data)
	if data.level >= cap then
		return
	end
	data.xp += amount
	local startLevel = data.level
	while data.level < cap and data.xp >= HeroConfig.XPToNext(data.level) do
		data.xp -= HeroConfig.XPToNext(data.level)
		data.level += 1
	end
	if data.level >= cap then
		data.xp = 0
	end

	if data.level > startLevel then
		local gained = data.level - startLevel
		local points = gained * HeroConfig.Levels.PointsPerLevel
		notify:FireClient(player, string.format("Level %d! +%d stat points. Open Stats to spend them.", data.level, points))
		applyHealth(player, true) -- leveling up heals you
		pushHero(player)
	else
		dirty[player] = true
	end
end

-- Dev cheat: jump levels
function CharacterService:AddLevels(player: Player, levels: number)
	local data = services.DataService:Get(player)
	local target = math.clamp(data.level + levels, 1, capFor(data))
	local xp = 0
	for level = data.level, target - 1 do
		xp += HeroConfig.XPToNext(level)
	end
	self:GiveXP(player, xp + 0.001 - data.xp)
end

local function onEnemyKilled(lane, enemy, source: string)
	local share = if source == "hero" then 1 else HeroConfig.Levels.GearKillShare
	CharacterService:GiveXP(lane.owner, enemy.maxHp * share)
end

------------------------------------------------------------------------
-- Pickaxe-hammer model
------------------------------------------------------------------------

local function weldedPart(name: string, size: Vector3, color: Color3, material: Enum.Material, attachTo: BasePart, offset: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = attachTo.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = attachTo
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	return part
end

-- Puts a gray-box pickaxe-hammer in the character's right hand. The handle
-- points forward from the hand and the head hangs down at the far end, so
-- an arm swing brings the head down in front of you.
local function giveWeapon(character: Model)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local old = character:FindFirstChild("PickaxeHammer")
	if old then
		old:Destroy()
	end
	local handOffset = if hand.Name == "RightHand" then CFrame.new(0, -0.1, -1.1) else CFrame.new(0, -0.9, -1.1)

	local model = Instance.new("Model")
	model.Name = "PickaxeHammer"
	local handle = weldedPart("Handle", Vector3.new(0.25, 0.25, 2.6), HANDLE_COLOR, Enum.Material.Wood, hand, handOffset)
	handle.Parent = model
	local player = Players:GetPlayerFromCharacter(character)
	local tier = if player and services.DataService:IsLoaded(player) then services.DataService:Get(player).pickaxeTier else 1
	local pickaxe = LootConfig.Pickaxes[tier] or LootConfig.Pickaxes[1]
	local head = weldedPart("Head", Vector3.new(0.6, 1.9, 0.7), pickaxe.color or HEAD_COLOR, Enum.Material.Metal, handle, CFrame.new(0, -0.35, -1.2))
	head.Parent = model
	model.PrimaryPart = handle
	model.Parent = character
end

-- Recolor the pickaxe head after an upgrade
function CharacterService:RefreshPickaxe(player: Player)
	local character = player.Character
	local model = character and character:FindFirstChild("PickaxeHammer")
	local head = model and model:FindFirstChild("Head")
	local pickaxe = LootConfig.Pickaxes[services.DataService:Get(player).pickaxeTier]
	if head and head:IsA("BasePart") and pickaxe then
		head.Color = pickaxe.color
	end
end

local function onCharacter(player: Player, character: Model)
	giveWeapon(character)
	if services.DataService:IsLoaded(player) then
		character:WaitForChild("Humanoid", 5)
		applyHealth(player, true)
	end
end

------------------------------------------------------------------------
-- Swings
------------------------------------------------------------------------

local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

local function onSwing(player: Player)
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < HeroConfig.Swing.Cooldown * COOLDOWN_TOLERANCE then
		return
	end
	lastSwing[player] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	local look = flatLook(root)
	local origin = root.Position

	-- Enemies in front of you, within reach
	local hitEnemy = false
	local WaveService = services.WaveService
	local lane = WaveService:GetLane(player)
	if lane and lane.state == "Running" then
		local damage = CharacterService:SwingDamage(player)
		for id, enemy in lane.enemies do
			local position = WaveService.EnemyPosition(lane, enemy)
			local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
			local distance = offset.Magnitude
			local reach = HeroConfig.Swing.Range + LaneConfig.Enemies[enemy.kind].radius
			if distance <= reach and (distance < 1 or offset.Unit:Dot(look) >= HeroConfig.Swing.ArcDot) then
				WaveService:DamageEnemy(lane, id, damage, "hero")
				hitEnemy = true
			end
		end
	end

	-- Wall rock you're digging
	services.DigService:Hit(player, origin, look, hitEnemy)

	-- Ore veins in the mine
	services.MiningService:Hit(player, origin)

	-- A layer boss in the arena
	services.BossService:Swing(player, origin, look, CharacterService:SwingDamage(player))
end

-- Re-sends hero info (after moving to a layer with a higher level cap)
function CharacterService:Refresh(player: Player)
	pushHero(player)
end

------------------------------------------------------------------------

function CharacterService:Init(allServices)
	services = allServices
	Players.RespawnTime = HeroConfig.Health.RespawnSeconds
end

function CharacterService:Start()
	notify = Remotes.Event("Notify")
	Remotes.Event("SwingWeapon").OnServerEvent:Connect(onSwing)
	Remotes.Event("SpendStat").OnServerEvent:Connect(spendStat)
	services.WaveService.EnemyKilled:Connect(onEnemyKilled)

	local DataService = services.DataService
	DataService.Loaded:Connect(function(player)
		effectsCache[player] = nil
		applyHealth(player, true)
		pushHero(player)
		pushBoosts(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			pushHero(player)
			pushBoosts(player)
		end
	end

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		effectsCache[player] = nil
		dirty[player] = nil
	end)

	-- XP from kills is sent a few times a second, not on every kill
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < PUSH_INTERVAL then
			return
		end
		timer = 0
		for player in dirty do
			dirty[player] = nil
			if player.Parent == Players and DataService:IsLoaded(player) then
				pushHero(player)
			end
		end
	end)
end

return CharacterService
