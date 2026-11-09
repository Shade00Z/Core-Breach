-- HubController
-- Client side of the hubs (one per layer):
--   * Only your own tunnel door shows its "Enter your tunnel" prompt.
--   * Rock chips and sounds when ore veins are hit and broken (the server
--     sets each vein's HP and Broken attributes; see MiningService).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local HubController = {}

local SoundController

local function chips(part: BasePart, color: Color3, count: number, speed: number)
	for _ = 1, count do
		local chip = Instance.new("Part")
		local s = 0.35 + math.random() * 0.5
		chip.Size = Vector3.new(s, s, s)
		chip.Color = if math.random() < 0.5 then color else Color3.fromRGB(95, 85, 80)
		chip.Material = Enum.Material.Slate
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.CastShadow = false
		chip.CFrame = part.CFrame * CFrame.new((math.random() - 0.5) * part.Size.X, part.Size.Y * 0.4, (math.random() - 0.5) * part.Size.Z)
		chip.Parent = workspace
		chip.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * speed, speed * (0.6 + math.random() * 0.6), (math.random() - 0.5) * speed)
		Debris:AddItem(chip, 0.8)
	end
end

local function watchVein(vein: Instance)
	if not vein:IsA("Model") then
		return
	end
	local rock = vein:WaitForChild("Rock", 5)
	local ore = vein:FindFirstChild("Ore")
	if not rock or not rock:IsA("BasePart") then
		return
	end
	local color = if ore and ore:IsA("BasePart") then ore.Color else Color3.new(1, 1, 1)
	local lastHp = vein:GetAttribute("HP") or 1
	vein:GetAttributeChangedSignal("HP"):Connect(function()
		local hp = vein:GetAttribute("HP") or 1
		if hp < lastHp then
			SoundController:PlayAt("RockHit", rock.Position)
			chips(rock, color, 4, 16)
		end
		lastHp = hp
	end)
	vein:GetAttributeChangedSignal("Broken"):Connect(function()
		if vein:GetAttribute("Broken") then
			SoundController:PlayAt("RockBreak", rock.Position)
			chips(rock, color, 14, 28)
		end
	end)
end

-- Hide the prompt on doors that aren't yours (local only)
local function watchDoor(door: Instance)
	local prompt = door:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end
	local function update()
		prompt.Enabled = door:GetAttribute("OwnerUserId") == player.UserId
	end
	door:GetAttributeChangedSignal("OwnerUserId"):Connect(update)
	update()
end

function HubController:Init(controllers)
	SoundController = controllers.SoundController
end

-- One layer's hub (workspace.Hubs.Layer1, Layer2...)
local function watchHub(hub: Instance)
	for index = 1, 6 do
		local door = hub:WaitForChild("Door" .. index, 10)
		if door then
			watchDoor(door)
		end
	end
	local veins = hub:WaitForChild("Veins", 10)
	if veins then
		veins.ChildAdded:Connect(watchVein)
		for _, vein in veins:GetChildren() do
			task.spawn(watchVein, vein)
		end
	end
end

function HubController:Start()
	task.spawn(function()
		local hubs = workspace:WaitForChild("Hubs", 30)
		if not hubs then
			return
		end
		hubs.ChildAdded:Connect(watchHub)
		for _, hub in hubs:GetChildren() do
			task.spawn(watchHub, hub)
		end
	end)
end

return HubController
