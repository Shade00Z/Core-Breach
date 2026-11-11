-- AbilityService
-- Casting Core Power abilities (PowerData). The client sends which slot it
-- cast (1-3, Q/F/R) and, for aimed abilities, the enemy it aimed at. The
-- server checks you have the power equipped, the ability is unlocked by
-- mastery, it's off cooldown, and your aim is believable; then it deals the
-- damage itself:
--   projectile  flies to its target (aim assist), explodes after the travel time
--   pool        ticks of damage at the target point
--   nova        one burst around you
--   line        one hit along a line straight ahead
-- Every ability also hits a layer boss in the arena (BossService) and gives
-- your power mastery XP for each enemy it hits (PowerService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local PowerData = require(Shared:WaitForChild("PowerData"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))

local COOLDOWN_TOLERANCE = 0.3 -- seconds early a cast may arrive (network timing)
local AIM_SLACK_DEGREES = 15 -- extra cone allowed when checking the client's chosen target
local RANGE_SLACK = 10 -- extra range allowed for the client's chosen target
local BOSS_SLACK = 4 -- a boss may move a little before the hit lands

local AbilityService = {}

local services
local lastCast: { [Player]: { [string]: number } } = {}

local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

-- True if the point is within range and the aim cone
local function inCone(origin: Vector3, look: Vector3, position: Vector3, range: number, coneDegrees: number): (boolean, number)
	local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
	local distance = offset.Magnitude
	if distance > range then
		return false, distance
	end
	if distance < 1 then
		return true, distance
	end
	return offset.Unit:Dot(look) >= math.cos(math.rad(coneDegrees)), distance
end

-- The enemy the ability aims at: the client's choice if it checks out,
-- otherwise the nearest one in the cone
local function pickTarget(lane, origin: Vector3, look: Vector3, ability: PowerData.Ability, claimed: number?): number?
	local WaveService = services.WaveService
	local range, cone = ability.range or 60, ability.cone or 35
	if claimed and lane.enemies[claimed] then
		if inCone(origin, look, WaveService.EnemyPosition(lane, lane.enemies[claimed]), range + RANGE_SLACK, cone + AIM_SLACK_DEGREES) then
			return claimed
		end
	end
	local best, bestId = math.huge, nil
	for id, enemy in lane.enemies do
		local ok, distance = inCone(origin, look, WaveService.EnemyPosition(lane, enemy), range, cone)
		if ok and distance < best then
			best, bestId = distance, id
		end
	end
	return bestId
end

-- Hurts (and slows) every lane enemy within radius of a point. Returns how many were hit.
local function hitCircle(lane, center: Vector3, radius: number, damage: number, slow): number
	local WaveService = services.WaveService
	local hits = 0
	for id, enemy in lane.enemies do
		local position = WaveService.EnemyPosition(lane, enemy)
		local reach = radius + LaneConfig.Enemies[enemy.kind].radius
		local dx, dz = position.X - center.X, position.Z - center.Z
		if dx * dx + dz * dz <= reach * reach then
			if slow then
				WaveService:SlowEnemy(lane, id, slow.factor, slow.seconds)
			end
			WaveService:DamageEnemy(lane, id, damage, "hero")
			hits += 1
		end
	end
	return hits
end

local function cast(player: Player, slot: number, claimedTarget: number?)
	local power, mastery = services.PowerService:GetEquipped(player)
	local ability = power and power.abilities[slot]
	if not power or not ability or mastery < ability.mastery then
		return
	end
	local now = os.clock()
	local casts = lastCast[player]
	if not casts then
		casts = {}
		lastCast[player] = casts
	end
	if casts[ability.id] and now - casts[ability.id] < ability.cooldown - COOLDOWN_TOLERANCE then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local WaveService = services.WaveService
	local BossService = services.BossService
	local lane = WaveService:GetLane(player)
	if not lane then
		return
	end
	casts[ability.id] = now
	services.QuestService:Progress(player, "ability", 1)

	local origin = root.Position
	local look = flatLook(root)
	local damage = services.CharacterService:SwingDamage(player) * ability.damage * PowerData.MasteryBonus(mastery)
	local function addMastery(laneHits: number, bossHit: boolean)
		local xp = laneHits * PowerData.Mastery.XPPerHit + (if bossHit then PowerData.Mastery.XPPerBossHit else 0)
		services.PowerService:AddMastery(player, power.id, xp)
	end

	if ability.kind == "projectile" or ability.kind == "pool" then
		local targetId = pickTarget(lane, origin, look, ability, claimedTarget)
		local range = ability.range or 60
		-- No lane enemy in front: a layer boss in the arena, if one's in the cone
		local bossPoint = if targetId then nil else BossService:AimPoint(origin, look, range, ability.cone or 35)
		local fallback = origin + look * (if ability.kind == "pool" then 20 else range)
		local aimPoint = if targetId then WaveService.EnemyPosition(lane, lane.enemies[targetId]) else bossPoint or fallback
		local bossSlack = if bossPoint then BOSS_SLACK else 0

		if ability.kind == "projectile" then
			local travel = Vector3.new(aimPoint.X - origin.X, 0, aimPoint.Z - origin.Z).Magnitude / (ability.speed or 90)
			task.delay(travel, function()
				local splash = ability.splash or 6
				local bossHit = BossService:Blast(player, aimPoint, splash + bossSlack, damage)
				if WaveService:GetLane(player) ~= lane then
					return
				end
				-- The projectile follows its target, so it explodes wherever the target is now
				local target = targetId and lane.enemies[targetId]
				local impact = if target then WaveService.EnemyPosition(lane, target) else aimPoint
				addMastery(hitCircle(lane, impact, splash, damage, ability.slow), bossHit == true)
			end)
		else
			-- Pool: ticks of damage where it landed
			task.spawn(function()
				local radius = ability.radius or 8
				for _ = 1, ability.ticks or 8 do
					task.wait(ability.tickEvery or 0.5)
					if WaveService:GetLane(player) ~= lane then
						return
					end
					local bossHit = BossService:Blast(player, aimPoint, radius + bossSlack, damage)
					addMastery(hitCircle(lane, aimPoint, radius, damage, ability.slow), bossHit == true)
				end
			end)
		end
	elseif ability.kind == "nova" then
		task.delay(0.15, function()
			local radius = ability.radius or 15
			local bossHit = BossService:Blast(player, origin, radius, damage)
			addMastery(hitCircle(lane, origin, radius, damage, ability.slow), bossHit == true)
		end)
	elseif ability.kind == "line" then
		task.delay(0.2, function()
			local length, width = ability.length or 50, ability.width or 8
			local bossHit = BossService:Line(player, origin, look, length, width, damage)
			local hits = 0
			for id, enemy in lane.enemies do
				local position = WaveService.EnemyPosition(lane, enemy)
				local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
				local along = offset:Dot(look)
				local side = (offset - look * along).Magnitude
				local radius = LaneConfig.Enemies[enemy.kind].radius
				if along >= -radius and along <= length + radius and side <= width / 2 + radius then
					if ability.slow then
						WaveService:SlowEnemy(lane, id, ability.slow.factor, ability.slow.seconds)
					end
					WaveService:DamageEnemy(lane, id, damage, "hero")
					hits += 1
				end
			end
			addMastery(hits, bossHit == true)
		end)
	end
end

-- Dev cheat: reset all cooldowns
function AbilityService:ResetCooldowns(player: Player)
	lastCast[player] = nil
end

function AbilityService:Init(allServices)
	services = allServices
end

function AbilityService:Start()
	Remotes.Event("UseAbility").OnServerEvent:Connect(function(player, slot, targetId)
		if slot == 1 or slot == 2 or slot == 3 then
			cast(player, slot, if type(targetId) == "number" and targetId > 0 then targetId else nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastCast[player] = nil
	end)
end

return AbilityService
