-- HubBuilder
-- Builds one layer's floor in code (gray box), from the same template for
-- every layer (colors and ores come from LayerConfig). North = +Z:
--
--              [ NPC outpost ]
--   [ mine ]   ( elevator plaza )   [ tunnel doors 1-6 ]
--              [  boss arena  ]
--
-- The six numbered doors lead to the players' private lanes (built by
-- LaneBuilder elsewhere in the world; the doors teleport you). The forge
-- stands in the mine next to the ore veins (MiningService places the veins).
-- The quest giver at the outpost has a "Talk" prompt (QuestService); the
-- boss arena has a "Challenge" prompt on its seal (BossService).
-- The elevator is a placeholder until week 7.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LayerConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LayerConfig"))

local HubBuilder = {}

HubBuilder.Size = 270 -- square floor, studs per side
HubBuilder.ArenaOffset = Vector3.new(0, 0, -95) -- arena center, from the hub center
HubBuilder.ArenaRadius = 35

local FLOOR_Y = 0.4 -- top of the floor, above the hub center (same height as the lanes)

-- Colors shared by every layer (the rest come from LayerConfig)
local COMMON = {
	Metal = Color3.fromRGB(75, 75, 82),
	Wood = Color3.fromRGB(120, 80, 45),
	Door = Color3.fromRGB(105, 70, 40),
	Hazard = Color3.fromRGB(240, 200, 40),
	Pillar = Color3.fromRGB(90, 80, 75),
}

export type Hub = {
	layer: number,
	model: Model,
	center: Vector3,
	doors: { [number]: BasePart }, -- tunnel number -> door
	doorLabels: { [number]: TextLabel },
	forge: BasePart,
	veinFolder: Folder,
	questGiver: Model, -- the NPC with this layer's quests
	arenaCenter: Vector3, -- on the floor
	arenaSeal: BasePart, -- the disc in the middle of the arena (boss prompt)
	arenaSign: TextLabel, -- the sign over the arena gate
	plaza: CFrame, -- where you arrive in this layer
	spawnInFront: (index: number) -> CFrame, -- where you appear when leaving your lane
}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(parent: BasePart, text: string, size: UDim2, offset: Vector3, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function prompt(parent: Instance, name: string, action: string, object: string, distance: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.HoldDuration = 0
	p.Parent = parent
	return p
end

------------------------------------------------------------------------

function HubBuilder.Build(parent: Instance, layerId: number): Hub
	local layer = LayerConfig.Get(layerId)
	local palette = layer.hub
	local C = layer.hubCenter

	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(C.X + x, C.Y + y, C.Z + z)
	end

	local function lamp(parentModel: Instance, x: number, z: number, withLight: boolean)
		part(parentModel, "LampPost", Vector3.new(0.6, 7, 0.6), at(x, FLOOR_Y + 3.5, z), COMMON.Wood, Enum.Material.Wood)
		local bulb = part(parentModel, "Lamp", Vector3.new(1.2, 1.4, 1.2), at(x, FLOOR_Y + 7.5, z), palette.Lamp, Enum.Material.Neon)
		bulb.CanCollide = false
		if withLight then
			local light = Instance.new("PointLight")
			light.Color = palette.Lamp
			light.Range = 22
			light.Brightness = 1.5
			light.Parent = bulb
		end
	end

	-- A simple blocky NPC with a name tag, facing south (toward the plaza)
	local function npc(parentModel: Instance, name: string, x: number, z: number, shirt: Color3): Model
		local model = Instance.new("Model")
		model.Name = "NPC_" .. name
		local facing = at(x, 0, z) * CFrame.Angles(0, math.rad(180), 0)
		part(model, "Legs", Vector3.new(2, 2.4, 1), facing * CFrame.new(0, FLOOR_Y + 1.2, 0), Color3.fromRGB(60, 70, 110))
		local torso = part(model, "Torso", Vector3.new(2, 2, 1), facing * CFrame.new(0, FLOOR_Y + 3.4, 0), shirt)
		local head = part(model, "Head", Vector3.new(1.3, 1.3, 1.3), facing * CFrame.new(0, FLOOR_Y + 5.05, 0), Color3.fromRGB(245, 205, 150))
		sign(head, name, UDim2.fromScale(8, 1.4), Vector3.new(0, 2, 0), Color3.fromRGB(255, 230, 150))
		model.PrimaryPart = torso
		model:SetAttribute("NPC", name)
		model.Parent = parentModel
		return model
	end

	local model = Instance.new("Model")
	model.Name = "Layer" .. layer.id
	model:SetAttribute("Layer", layer.id)
	local S = HubBuilder.Size
	local H = S / 2

	-- Ground and the rock walls around it
	part(model, "Floor", Vector3.new(S, 1, S), at(0, FLOOR_Y - 0.5, 0), palette.Floor, Enum.Material.Ground)
	for _, wall in {
		{ Vector3.new(S + 20, 26, 10), at(0, 13, H + 5) },
		{ Vector3.new(S + 20, 26, 10), at(0, 13, -H - 5) },
		{ Vector3.new(10, 26, S), at(H + 5, 13, 0) },
		{ Vector3.new(10, 26, S), at(-H - 5, 13, 0) },
	} do
		part(model, "CaveWall", wall[1], wall[2], palette.Rock, Enum.Material.Rock)
	end

	-- Paths from the plaza to each area
	part(model, "PathNorth", Vector3.new(14, 0.2, 60), at(0, FLOOR_Y + 0.1, 55), palette.Path, Enum.Material.Sand)
	part(model, "PathSouth", Vector3.new(14, 0.2, 40), at(0, FLOOR_Y + 0.1, -45), palette.Path, Enum.Material.Sand)
	part(model, "PathEast", Vector3.new(70, 0.2, 14), at(60, FLOOR_Y + 0.1, 0), palette.Path, Enum.Material.Sand)
	part(model, "PathWest", Vector3.new(30, 0.2, 14), at(-40, FLOOR_Y + 0.1, 0), palette.Path, Enum.Material.Sand)

	--------------------------------------------------------------------
	-- Center: elevator plaza (the elevator itself arrives in week 7)
	--------------------------------------------------------------------
	local plaza = part(model, "Plaza", Vector3.new(0.4, 54, 54), at(0, FLOOR_Y + 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), palette.Plaza, Enum.Material.Cobblestone)
	plaza.Shape = Enum.PartType.Cylinder
	local ring = part(model, "HazardRing", Vector3.new(0.5, 24, 24), at(0, FLOOR_Y + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), COMMON.Hazard, Enum.Material.SmoothPlastic)
	ring.Shape = Enum.PartType.Cylinder
	local shaft = part(model, "Elevator", Vector3.new(14, 26, 14), at(0, FLOOR_Y + 13, 0), COMMON.Metal, Enum.Material.DiamondPlate)
	sign(shaft, "Layer " .. layer.id .. ": " .. layer.name, UDim2.fromScale(20, 3), Vector3.new(0, 18, 0), palette.Lamp)
	sign(shaft, "Elevator (opens in week 7)", UDim2.fromScale(14, 1.6), Vector3.new(0, 15.6, 0), Color3.fromRGB(220, 220, 220))
	for _, p in { { 24, 18 }, { -24, 18 }, { 24, -18 }, { -24, -18 } } do
		lamp(model, p[1], p[2], true)
	end

	--------------------------------------------------------------------
	-- North: NPC outpost (quest giver, quest board, shop)
	--------------------------------------------------------------------
	local board = part(model, "QuestBoard", Vector3.new(14, 9, 1), at(-22, FLOOR_Y + 6, 92), COMMON.Wood, Enum.Material.WoodPlanks)
	sign(board, "Quests\nTalk to " .. layer.questGiver, UDim2.fromScale(12, 3.5), Vector3.new(0, 7, 0))
	part(model, "BoardLegs", Vector3.new(14, 2, 0.8), at(-22, FLOOR_Y + 1, 92), COMMON.Wood, Enum.Material.Wood)
	local counter = part(model, "ShopCounter", Vector3.new(16, 4, 5), at(22, FLOOR_Y + 2, 90), COMMON.Wood, Enum.Material.WoodPlanks)
	for i = 0, 3 do
		local stripe = part(model, "Awning", Vector3.new(4, 0.6, 8), at(16 + i * 4, FLOOR_Y + 10, 90) * CFrame.Angles(math.rad(-12), 0, 0), if i % 2 == 0 then Color3.fromRGB(210, 50, 50) else Color3.new(1, 1, 1))
		stripe.CanCollide = false
	end
	part(model, "AwningPostL", Vector3.new(0.6, 9, 0.6), at(14.5, FLOOR_Y + 4.5, 87), COMMON.Wood)
	part(model, "AwningPostR", Vector3.new(0.6, 9, 0.6), at(29.5, FLOOR_Y + 4.5, 87), COMMON.Wood)
	sign(counter, "Shop\n(coming soon)", UDim2.fromScale(12, 3.5), Vector3.new(0, 11, 0))
	local giver = npc(model, layer.questGiver, -14, 86, if layer.id == 1 then Color3.fromRGB(150, 90, 40) else Color3.fromRGB(70, 110, 160))
	giver.Name = "QuestGiver"
	local talk = prompt(giver.PrimaryPart :: BasePart, "TalkPrompt", "Talk", layer.questGiver, 10)
	talk:SetAttribute("Layer", layer.id)
	-- A "!" over the quest giver (QuestController shows it when there's a quest to take or turn in)
	local marker = sign(giver:FindFirstChild("Head") :: BasePart, "!", UDim2.fromScale(2, 2.6), Vector3.new(0, 4.2, 0), Color3.fromRGB(255, 220, 60))
	marker.Parent.Name = "QuestMarker"
	npc(model, layer.trader, 22, 94, Color3.fromRGB(170, 60, 150))
	lamp(model, -34, 80, true)
	lamp(model, 34, 80, false)

	--------------------------------------------------------------------
	-- West: the mine (veins are placed by MiningService) and the forge
	--------------------------------------------------------------------
	for _, x in { -44, -80, -108 } do
		-- Timber frames over the mine
		for _, z in { -60, 60 } do
			part(model, "MinePost", Vector3.new(1.4, 14, 1.4), at(x, FLOOR_Y + 7, z), COMMON.Wood, Enum.Material.Wood)
		end
		part(model, "MineBeam", Vector3.new(1.6, 1.6, 122), at(x, FLOOR_Y + 14.5, 0), COMMON.Wood, Enum.Material.Wood)
	end
	for _, p in { { -66, -58 }, { -96, 58 }, { -126, 58 }, { -130, -58 } } do
		part(model, "RockPile", Vector3.new(14, 10, 12), at(p[1], FLOOR_Y + 5, p[2]) * CFrame.Angles(0, math.rad(p[1] * 7), 0), palette.Rock, Enum.Material.Rock)
	end
	lamp(model, -60, -20, true)
	lamp(model, -98, 22, true)
	local mineSign = part(model, "MineSign", Vector3.new(10, 3, 0.6), at(-30, FLOOR_Y + 9, 10) * CFrame.Angles(0, math.rad(90), 0), COMMON.Wood, Enum.Material.WoodPlanks)
	sign(mineSign, "The Mine", UDim2.fromScale(10, 2.2), Vector3.new(0, 3, 0), Color3.fromRGB(255, 220, 140))

	local veinFolder = Instance.new("Folder")
	veinFolder.Name = "Veins"
	veinFolder.Parent = model

	-- Forge: furnace + anvil, by the mine entrance
	part(model, "Furnace", Vector3.new(10, 10, 8), at(-38, FLOOR_Y + 5, -26), Color3.fromRGB(80, 70, 65), Enum.Material.Brick)
	local glow = part(model, "FurnaceGlow", Vector3.new(0.4, 4, 5), at(-32.9, FLOOR_Y + 3.5, -26), palette.Glow, Enum.Material.Neon)
	glow.CanCollide = false
	local fire = Instance.new("PointLight")
	fire.Color = palette.Glow
	fire.Range = 18
	fire.Brightness = 2
	fire.Parent = glow
	part(model, "Chimney", Vector3.new(3, 10, 3), at(-40, FLOOR_Y + 15, -27), Color3.fromRGB(70, 60, 55), Enum.Material.Brick)
	local anvil = part(model, "Forge", Vector3.new(4, 2, 2), at(-28, FLOOR_Y + 3.4, -18), Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
	part(model, "AnvilBase", Vector3.new(2, 2.4, 1.6), at(-28, FLOOR_Y + 1.2, -18), Color3.fromRGB(70, 50, 35), Enum.Material.Wood)
	sign(anvil, "Forge", UDim2.fromScale(8, 2), Vector3.new(0, 4, 0), Color3.fromRGB(255, 160, 80))
	prompt(anvil, "ForgePrompt", "Use Forge", "Forge", 12)

	--------------------------------------------------------------------
	-- East: the tunnel hall, six numbered doors to the players' lanes
	--------------------------------------------------------------------
	local hallX = 100
	part(model, "TunnelWall", Vector3.new(4, 22, 100), at(hallX + 2, FLOOR_Y + 11, 0), palette.Rock, Enum.Material.Rock)
	part(model, "HallBeam", Vector3.new(3, 2, 100), at(hallX - 1, FLOOR_Y + 15, 0), COMMON.Wood, Enum.Material.Wood)
	local doors, doorLabels = {}, {}
	for index = 1, 6 do
		local z = (3.5 - index) * 15 -- door 1 to the north, 6 to the south
		part(model, "DoorFrame", Vector3.new(1.4, 13, 11), at(hallX - 0.5, FLOOR_Y + 6.5, z), COMMON.Wood, Enum.Material.Wood)
		local door = part(model, "Door" .. index, Vector3.new(8, 11, 0.8), CFrame.lookAt(at(hallX - 1.5, FLOOR_Y + 5.5, z).Position, at(hallX - 10, FLOOR_Y + 5.5, z).Position), COMMON.Door, Enum.Material.WoodPlanks)
		door:SetAttribute("LaneIndex", index)
		local face = Instance.new("SurfaceGui")
		face.Face = Enum.NormalId.Front
		face.CanvasSize = Vector2.new(200, 280)
		face.LightInfluence = 0
		local number = Instance.new("TextLabel")
		number.BackgroundTransparency = 1
		number.Size = UDim2.fromScale(1, 0.6)
		number.Font = Enum.Font.GothamBlack
		number.TextScaled = true
		number.TextColor3 = Color3.fromRGB(255, 235, 200)
		number.Text = tostring(index)
		number.Parent = face
		face.Parent = door
		-- Owner label just above the door, in front of the beam (door-local: -Z is toward the plaza)
		doorLabels[index] = sign(door, "Empty", UDim2.fromScale(9, 1.5), Vector3.new(0, 6.6, -3), Color3.fromRGB(220, 220, 220))
		prompt(door, "DoorPrompt", "Enter your tunnel", "Tunnel " .. index, 10)
		lamp(model, hallX - 6, z + 7.5, index % 2 == 1)
		doors[index] = door
	end

	--------------------------------------------------------------------
	-- South: boss arena
	--------------------------------------------------------------------
	local A = HubBuilder.ArenaOffset
	local R = HubBuilder.ArenaRadius
	local arena = part(model, "Arena", Vector3.new(0.4, R * 2, R * 2), at(A.X, FLOOR_Y + 0.2, A.Z) * CFrame.Angles(0, 0, math.rad(90)), palette.Arena, Enum.Material.Slate)
	arena.Shape = Enum.PartType.Cylinder
	for i = 1, 6 do
		local angle = math.rad(i * 60)
		local crack = part(model, "ArenaCrack", Vector3.new(26, 0.1, 1), at(A.X + math.cos(angle) * 14, FLOOR_Y + 0.45, A.Z + math.sin(angle) * 14) * CFrame.Angles(0, -angle, 0), palette.Glow, Enum.Material.Neon)
		crack.CanCollide = false
	end
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		if i ~= 2 then -- leave a gap facing the plaza
			part(model, "ArenaPillar", Vector3.new(3, 6, 3), at(A.X + math.cos(angle) * (R + 2), FLOOR_Y + 3, A.Z + math.sin(angle) * (R + 2)), COMMON.Pillar, Enum.Material.Rock)
		end
	end
	-- The floor seal in the middle: challenge the boss here
	local seal = part(model, "ArenaSeal", Vector3.new(0.6, 12, 12), at(A.X, FLOOR_Y + 0.3, A.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 55, 55), Enum.Material.Metal)
	seal.Shape = Enum.PartType.Cylinder
	local gate = part(model, "ArenaGate", Vector3.new(16, 10, 1), at(A.X, FLOOR_Y + 5, A.Z + R + 2), Color3.fromRGB(70, 60, 55), Enum.Material.Metal)
	gate.CanCollide = false
	gate.Transparency = 0.6
	local boss = layer.boss
	local arenaSign = sign(gate, if boss then string.format("%s\nLayer Boss · Level %d", boss.name, boss.level) else "Sealed\n(next layer's boss: coming soon)", UDim2.fromScale(14, 3.5), Vector3.new(0, 8, 0), Color3.fromRGB(255, 120, 80))

	--------------------------------------------------------------------
	-- Stone Vault (and deeper): glowing crystal clusters on the walls
	--------------------------------------------------------------------
	if layer.id >= 2 then
		for i, p in { { -130, 120 }, { 120, 120 }, { -130, -120 }, { 125, -110 }, { 60, 125 }, { -60, -128 }, { 50, -60 }, { -128, 30 } } do
			local crystal
			for j = 0, 2 do
				crystal = part(model, "Crystal", Vector3.new(2.2, 6 + j * 2.5, 2.2), at(p[1] + j * 2.4 - 2.4, FLOOR_Y + 3 + j, p[2]) * CFrame.Angles(math.rad(14 * (j - 1)), math.rad(37 * i), math.rad(18 * (j - 1))), palette.Glow, Enum.Material.Neon)
				crystal.CanCollide = false
			end
			if i % 2 == 0 then
				local light = Instance.new("PointLight")
				light.Color = palette.Glow
				light.Range = 24
				light.Brightness = 1.2
				light.Parent = crystal
			end
		end
	end

	model.Parent = parent

	return {
		layer = layer.id,
		model = model,
		center = C,
		doors = doors,
		doorLabels = doorLabels,
		forge = anvil,
		veinFolder = veinFolder,
		questGiver = giver,
		arenaCenter = Vector3.new(C.X + A.X, C.Y + FLOOR_Y, C.Z + A.Z),
		arenaSeal = seal,
		arenaSign = arenaSign,
		plaza = CFrame.lookAt(at(0, FLOOR_Y + 3, -18).Position, at(0, FLOOR_Y + 3, -40).Position),
		spawnInFront = function(index: number): CFrame
			local door = doors[index]
			local position = door.Position + Vector3.new(-7, 0, 0)
			local y = C.Y + FLOOR_Y + 3
			return CFrame.lookAt(Vector3.new(position.X, y, position.Z), Vector3.new(position.X - 10, y, position.Z))
		end,
	}
end

-- World position of a vein spot in a layer
function HubBuilder.VeinPosition(layerId: number, spot): Vector3
	local C = LayerConfig.Get(layerId).hubCenter
	return Vector3.new(C.X + spot.x, C.Y + FLOOR_Y, C.Z + spot.z)
end

return HubBuilder
