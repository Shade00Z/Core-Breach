-- AbilityService
-- Hero abilities. Week 3 has one test ability, Fire Blast:
-- a fireball that flies the way you face, bends toward the nearest enemy
-- in front of you (aim assist), and explodes, hurting everything nearby.
--
-- The client picks the target with the same rules (so its fireball flies to
-- the same enemy) and sends its id. The server checks the cooldown and that
-- the target is really in front of you and in range; if not, it picks its own.
--
-- Week 8 adds Core Powers with their own abilities here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))

local COOLDOWN_TOLERANCE = 0.3 -- seconds early a cast may arrive (network timing)
local AIM_SLACK_DEGREES = 15 -- extra cone allowed when checking the client's chosen target
local RANGE_SLACK = 10 -- extra range allowed for the client's chosen target

local AbilityService = {}

local services
local lastCast: { [Player]: number } = {}

local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

-- True if the enemy is within range and the aim cone
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

local function castFireBlast(player: Player, claimedTarget: number?)
	local settings = HeroConfig.FireBlast
	local now = os.clock()
	if lastCast[player] and now - lastCast[player] < settings.Cooldown - COOLDOWN_TOLERANCE then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local WaveService = services.WaveService
	local lane = WaveService:GetLane(player)
	if not lane then
		return
	end
	lastCast[player] = now

	local origin = root.Position
	local look = flatLook(root)

	-- The client's target, if it checks out
	local targetId: number? = nil
	if claimedTarget and lane.enemies[claimedTarget] then
		local ok = inCone(origin, look, WaveService.EnemyPosition(lane, lane.enemies[claimedTarget]), settings.Range + RANGE_SLACK, settings.AimConeDegrees + AIM_SLACK_DEGREES)
		if ok then
			targetId = claimedTarget
		end
	end
	-- Otherwise the nearest enemy in the cone
	if not targetId then
		local best = math.huge
		for id, enemy in lane.enemies do
			local ok, distance = inCone(origin, look, WaveService.EnemyPosition(lane, enemy), settings.Range, settings.AimConeDegrees)
			if ok and distance < best then
				targetId, best = id, distance
			end
		end
	end

	local aimPoint = if targetId then WaveService.EnemyPosition(lane, lane.enemies[targetId]) else origin + look * settings.Range
	local travel = Vector3.new(aimPoint.X - origin.X, 0, aimPoint.Z - origin.Z).Magnitude / settings.Speed
	local damage = HeroConfig.FireBlastDamage(services.GearService:GetTotalDps(player))

	task.delay(travel, function()
		if WaveService:GetLane(player) ~= lane then
			return
		end
		-- The fireball follows its target, so it explodes wherever the target is now
		local target = targetId and lane.enemies[targetId]
		local impact = if target then WaveService.EnemyPosition(lane, target) else aimPoint
		for id, enemy in lane.enemies do
			local position = WaveService.EnemyPosition(lane, enemy)
			local reach = settings.SplashRadius + LaneConfig.Enemies[enemy.kind].radius
			local dx, dz = position.X - impact.X, position.Z - impact.Z
			if dx * dx + dz * dz <= reach * reach then
				WaveService:DamageEnemy(lane, id, damage)
			end
		end
	end)
end

function AbilityService:Init(allServices)
	services = allServices
end

function AbilityService:Start()
	Remotes.Event("UseAbility").OnServerEvent:Connect(function(player, ability, targetId)
		if ability == "FireBlast" then
			castFireBlast(player, if type(targetId) == "number" and targetId > 0 then targetId else nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastCast[player] = nil
	end)
end

return AbilityService
