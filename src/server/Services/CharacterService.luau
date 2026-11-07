-- CharacterService
-- Your hero: the pickaxe-hammer in your hand, and what a swing hits.
--
-- The client (CombatController) plays the swing and sends SwingWeapon. The
-- server checks the cooldown and works out the hits itself from where your
-- character is and which way it faces, so a player can't fake hits.
-- A swing damages enemies in front of you and chips any wall rock you've
-- paid to dig (DigService).
--
-- Week 4 adds XP, levels and stat points here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local LaneConfig = require(Shared:WaitForChild("LaneConfig"))

local HANDLE_COLOR = Color3.fromRGB(110, 75, 45)
local HEAD_COLOR = Color3.fromRGB(90, 95, 105)

-- Swings arriving a little early are allowed (network timing isn't exact)
local COOLDOWN_TOLERANCE = 0.8

local CharacterService = {}

local services
local lastSwing: { [Player]: number } = {}

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
	local head = weldedPart("Head", Vector3.new(0.6, 1.9, 0.7), HEAD_COLOR, Enum.Material.Metal, handle, CFrame.new(0, -0.35, -1.2))
	head.Parent = model
	model.PrimaryPart = handle
	model.Parent = character
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
		local damage = HeroConfig.SwingDamage(services.GearService:GetTotalDps(player))
		for id, enemy in lane.enemies do
			local position = WaveService.EnemyPosition(lane, enemy)
			local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
			local distance = offset.Magnitude
			local reach = HeroConfig.Swing.Range + LaneConfig.Enemies[enemy.kind].radius
			if distance <= reach and (distance < 1 or offset.Unit:Dot(look) >= HeroConfig.Swing.ArcDot) then
				WaveService:DamageEnemy(lane, id, damage)
				hitEnemy = true
			end
		end
	end

	-- Wall rock you're digging
	services.DigService:Hit(player, origin, look, hitEnemy)
end

------------------------------------------------------------------------

function CharacterService:Init(allServices)
	services = allServices
	Players.RespawnTime = HeroConfig.Health.RespawnSeconds
end

function CharacterService:Start()
	Remotes.Event("SwingWeapon").OnServerEvent:Connect(onSwing)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(giveWeapon)
		if player.Character then
			task.spawn(giveWeapon, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

return CharacterService
