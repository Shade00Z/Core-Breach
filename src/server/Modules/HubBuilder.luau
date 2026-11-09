-- HubBuilder
-- Builds the layer's shared hub in code (gray box), laid out like the
-- concept art, with north = +Z:
--
--              [ NPC outpost ]
--   [ mine ]   ( elevator plaza )   [ tunnel doors 1-6 ]
--              [  boss arena  ]
--
-- The six numbered doors lead to the players' private lanes (built by
-- LaneBuilder elsewhere in the world; the doors teleport you). The forge
-- stands in the mine next to the ore veins.
-- The outpost, elevator and boss arena are placeholders until weeks 6-7.

local HubBuilder = {}

-- Hub center, well away from the lanes (lanes run along +X from x = 0)
HubBuilder.Center = Vector3.new(-220, 0, 110)
HubBuilder.Size = 270 -- square floor, studs per side

local C = HubBuilder.Center
local FLOOR_Y = 0.4 -- top of the floor (same height as the lanes)

local COLORS = {
	Floor = Color3.fromRGB(150, 110, 70),
	Path = Color3.fromRGB(175, 135, 90),
	Rock = Color3.fromRGB(120, 80, 70),
	Plaza = Color3.fromRGB(120, 115, 110),
	Metal = Color3.fromRGB(75, 75, 82),
	Wood = Color3.fromRGB(120, 80, 45),
	Door = Color3.fromRGB(105, 70, 40),
	Lamp = Color3.fromRGB(255, 190, 90),
	Lava = Color3.fromRGB(255, 90, 20),
	Arena = Color3.fromRGB(110, 70, 60),
	Hazard = Color3.fromRGB(240, 200, 40),
}

-- Ore vein spots, relative to the hub center. Deeper in the mine (further
-- west) = rarer ore.
HubBuilder.VeinSpots = {
	-- Copper, near the plaza
	{ ore = "copper_ore", x = -52, z = -30 }, { ore = "copper_ore", x = -60, z = -12 },
	{ ore = "copper_ore", x = -50, z = 8 }, { ore = "copper_ore", x = -62, z = 26 },
	{ ore = "copper_ore", x = -54, z = 44 }, { ore = "copper_ore", x = -72, z = -42 },
	{ ore = "copper_ore", x = -74, z = 0 }, { ore = "copper_ore", x = -70, z = 50 },
	-- Iron and ember, the middle of the mine
	{ ore = "iron_ore", x = -88, z = -30 }, { ore = "iron_ore", x = -92, z = 12 },
	{ ore = "iron_ore", x = -86, z = 38 }, { ore = "iron_ore", x = -98, z = -8 },
	{ ore = "ember_ore", x = -96, z = -48 }, { ore = "ember_ore", x = -102, z = 30 },
	-- Gold and frost, the far end
	{ ore = "gold_ore", x = -114, z = -20 }, { ore = "gold_ore", x = -118, z = 18 },
	{ ore = "gold_ore", x = -112, z = 48 }, { ore = "frost_geode", x = -120, z = -44 },
	{ ore = "frost_geode", x = -122, z = 0 },
}

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(C.X + x, y, C.Z + z)
end

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

local function lamp(parent: Instance, x: number, z: number, withLight: boolean)
	part(parent, "LampPost", Vector3.new(0.6, 7, 0.6), at(x, FLOOR_Y + 3.5, z), COLORS.Wood, Enum.Material.Wood)
	local bulb = part(parent, "Lamp", Vector3.new(1.2, 1.4, 1.2), at(x, FLOOR_Y + 7.5, z), COLORS.Lamp, Enum.Material.Neon)
	bulb.CanCollide = false
	if withLight then
		local light = Instance.new("PointLight")
		light.Color = COLORS.Lamp
		light.Range = 22
		light.Brightness = 1.5
		light.Parent = bulb
	end
end

-- A simple blocky NPC with a name tag (placeholder until week 6's NPCs)
local function npc(parent: Instance, name: string, x: number, z: number, shirt: Color3)
	local model = Instance.new("Model")
	model.Name = "NPC_" .. name
	local facing = CFrame.new(C.X + x, 0, C.Z + z) * CFrame.Angles(0, math.rad(180), 0)
	part(model, "Legs", Vector3.new(2, 2.4, 1), facing * CFrame.new(0, FLOOR_Y + 1.2, 0), Color3.fromRGB(60, 70, 110))
	part(model, "Torso", Vector3.new(2, 2, 1), facing * CFrame.new(0, FLOOR_Y + 3.4, 0), shirt)
	local head = part(model, "Head", Vector3.new(1.3, 1.3, 1.3), facing * CFrame.new(0, FLOOR_Y + 5.05, 0), Color3.fromRGB(245, 205, 150))
	sign(head, name, UDim2.fromScale(8, 1.4), Vector3.new(0, 2, 0), Color3.fromRGB(255, 230, 150))
	model.Parent = parent
end

------------------------------------------------------------------------

export type Hub = {
	model: Model,
	doors: { [number]: BasePart }, -- tunnel number -> door
	doorLabels: { [number]: TextLabel },
	forge: BasePart,
	veinFolder: Folder,
	spawnInFront: (index: number) -> CFrame, -- where you appear when leaving your lane
}

function HubBuilder.Build(parent: Instance): Hub
	local model = Instance.new("Model")
	model.Name = "Hub"
	local S = HubBuilder.Size
	local H = S / 2

	-- Ground and the rock walls around it
	part(model, "Floor", Vector3.new(S, 1, S), at(0, FLOOR_Y - 0.5, 0), COLORS.Floor, Enum.Material.Ground)
	for _, wall in {
		{ Vector3.new(S + 20, 26, 10), at(0, 13, H + 5) },
		{ Vector3.new(S + 20, 26, 10), at(0, 13, -H - 5) },
		{ Vector3.new(10, 26, S), at(H + 5, 13, 0) },
		{ Vector3.new(10, 26, S), at(-H - 5, 13, 0) },
	} do
		part(model, "CaveWall", wall[1], wall[2], COLORS.Rock, Enum.Material.Rock)
	end

	-- Paths from the plaza to each area
	part(model, "PathNorth", Vector3.new(14, 0.2, 60), at(0, FLOOR_Y + 0.1, 55), COLORS.Path, Enum.Material.Sand)
	part(model, "PathSouth", Vector3.new(14, 0.2, 40), at(0, FLOOR_Y + 0.1, -45), COLORS.Path, Enum.Material.Sand)
	part(model, "PathEast", Vector3.new(70, 0.2, 14), at(60, FLOOR_Y + 0.1, 0), COLORS.Path, Enum.Material.Sand)
	part(model, "PathWest", Vector3.new(30, 0.2, 14), at(-40, FLOOR_Y + 0.1, 0), COLORS.Path, Enum.Material.Sand)

	--------------------------------------------------------------------
	-- Center: elevator plaza (the elevator itself arrives in week 7)
	--------------------------------------------------------------------
	local plaza = part(model, "Plaza", Vector3.new(0.4, 54, 54), at(0, FLOOR_Y + 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Plaza, Enum.Material.Cobblestone)
	plaza.Shape = Enum.PartType.Cylinder
	local ring = part(model, "HazardRing", Vector3.new(0.5, 24, 24), at(0, FLOOR_Y + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Hazard, Enum.Material.SmoothPlastic)
	ring.Shape = Enum.PartType.Cylinder
	local shaft = part(model, "Elevator", Vector3.new(14, 26, 14), at(0, FLOOR_Y + 13, 0), COLORS.Metal, Enum.Material.DiamondPlate)
	sign(shaft, "Elevator\n(opens in week 7)", UDim2.fromScale(14, 4), Vector3.new(0, 16, 0), Color3.fromRGB(255, 220, 120))
	for _, p in { { 24, 18 }, { -24, 18 }, { 24, -18 }, { -24, -18 } } do
		lamp(model, p[1], p[2], true)
	end

	--------------------------------------------------------------------
	-- North: NPC outpost (quest board and shop arrive in week 6)
	--------------------------------------------------------------------
	local board = part(model, "QuestBoard", Vector3.new(14, 9, 1), at(-22, FLOOR_Y + 6, 92), COLORS.Wood, Enum.Material.WoodPlanks)
	sign(board, "Quest Board\n(week 6)", UDim2.fromScale(12, 3.5), Vector3.new(0, 7, 0))
	part(model, "BoardLegs", Vector3.new(14, 2, 0.8), at(-22, FLOOR_Y + 1, 92), COLORS.Wood, Enum.Material.Wood)
	local counter = part(model, "ShopCounter", Vector3.new(16, 4, 5), at(22, FLOOR_Y + 2, 90), COLORS.Wood, Enum.Material.WoodPlanks)
	for i = 0, 3 do
		local stripe = part(model, "Awning", Vector3.new(4, 0.6, 8), at(16 + i * 4, FLOOR_Y + 10, 90) * CFrame.Angles(math.rad(-12), 0, 0), if i % 2 == 0 then Color3.fromRGB(210, 50, 50) else Color3.new(1, 1, 1))
		stripe.CanCollide = false
	end
	part(model, "AwningPostL", Vector3.new(0.6, 9, 0.6), at(14.5, FLOOR_Y + 4.5, 87), COLORS.Wood)
	part(model, "AwningPostR", Vector3.new(0.6, 9, 0.6), at(29.5, FLOOR_Y + 4.5, 87), COLORS.Wood)
	sign(counter, "Shop\n(coming soon)", UDim2.fromScale(12, 3.5), Vector3.new(0, 11, 0))
	npc(model, "Foreman Rusk", -14, 86, Color3.fromRGB(150, 90, 40))
	npc(model, "Trader Pip", 22, 94, Color3.fromRGB(170, 60, 150))
	lamp(model, -34, 80, true)
	lamp(model, 34, 80, false)

	--------------------------------------------------------------------
	-- West: the mine (veins are placed by MiningService) and the forge
	--------------------------------------------------------------------
	for _, x in { -44, -80, -108 } do
		-- Timber frames over the mine
		for _, z in { -60, 60 } do
			part(model, "MinePost", Vector3.new(1.4, 14, 1.4), at(x, FLOOR_Y + 7, z), COLORS.Wood, Enum.Material.Wood)
		end
		part(model, "MineBeam", Vector3.new(1.6, 1.6, 122), at(x, FLOOR_Y + 14.5, 0), COLORS.Wood, Enum.Material.Wood)
	end
	for _, p in { { -66, -58 }, { -96, 58 }, { -126, 58 }, { -130, -58 } } do
		part(model, "RockPile", Vector3.new(14, 10, 12), at(p[1], FLOOR_Y + 5, p[2]) * CFrame.Angles(0, math.rad(p[1] * 7), 0), COLORS.Rock, Enum.Material.Rock)
	end
	lamp(model, -60, -20, true)
	lamp(model, -98, 22, true)
	local mineSign = part(model, "MineSign", Vector3.new(10, 3, 0.6), at(-30, FLOOR_Y + 9, 10) * CFrame.Angles(0, math.rad(90), 0), COLORS.Wood, Enum.Material.WoodPlanks)
	sign(mineSign, "The Mine", UDim2.fromScale(10, 2.2), Vector3.new(0, 3, 0), Color3.fromRGB(255, 220, 140))

	local veinFolder = Instance.new("Folder")
	veinFolder.Name = "Veins"
	veinFolder.Parent = model

	-- Forge: furnace + anvil, by the mine entrance
	local furnace = part(model, "Furnace", Vector3.new(10, 10, 8), at(-38, FLOOR_Y + 5, -26), Color3.fromRGB(80, 70, 65), Enum.Material.Brick)
	local glow = part(model, "FurnaceGlow", Vector3.new(0.4, 4, 5), at(-32.9, FLOOR_Y + 3.5, -26), COLORS.Lava, Enum.Material.Neon)
	glow.CanCollide = false
	local fire = Instance.new("PointLight")
	fire.Color = COLORS.Lava
	fire.Range = 18
	fire.Brightness = 2
	fire.Parent = glow
	part(model, "Chimney", Vector3.new(3, 10, 3), at(-40, FLOOR_Y + 15, -27), Color3.fromRGB(70, 60, 55), Enum.Material.Brick)
	local anvil = part(model, "Anvil", Vector3.new(4, 2, 2), at(-28, FLOOR_Y + 3.4, -18), Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
	part(model, "AnvilBase", Vector3.new(2, 2.4, 1.6), at(-28, FLOOR_Y + 1.2, -18), Color3.fromRGB(70, 50, 35), Enum.Material.Wood)
	anvil.Name = "Forge"
	sign(anvil, "Forge", UDim2.fromScale(8, 2), Vector3.new(0, 4, 0), Color3.fromRGB(255, 160, 80))
	local forgePrompt = Instance.new("ProximityPrompt")
	forgePrompt.Name = "ForgePrompt"
	forgePrompt.ActionText = "Use Forge"
	forgePrompt.ObjectText = "Forge"
	forgePrompt.KeyboardKeyCode = Enum.KeyCode.E
	forgePrompt.MaxActivationDistance = 12
	forgePrompt.RequiresLineOfSight = false
	forgePrompt.HoldDuration = 0
	forgePrompt.Parent = anvil

	--------------------------------------------------------------------
	-- East: the tunnel hall, six numbered doors to the players' lanes
	--------------------------------------------------------------------
	local hallX = 100
	part(model, "TunnelWall", Vector3.new(4, 22, 100), at(hallX + 2, FLOOR_Y + 11, 0), COLORS.Rock, Enum.Material.Rock)
	part(model, "HallBeam", Vector3.new(3, 2, 100), at(hallX - 1, FLOOR_Y + 15, 0), COLORS.Wood, Enum.Material.Wood)
	local doors, doorLabels = {}, {}
	for index = 1, 6 do
		local z = (3.5 - index) * 15 -- door 1 to the north, 6 to the south
		part(model, "DoorFrame", Vector3.new(1.4, 13, 11), at(hallX - 0.5, FLOOR_Y + 6.5, z), COLORS.Wood, Enum.Material.Wood)
		local door = part(model, "Door" .. index, Vector3.new(8, 11, 0.8), CFrame.lookAt(at(hallX - 1.5, FLOOR_Y + 5.5, z).Position, at(hallX - 10, FLOOR_Y + 5.5, z).Position), COLORS.Door, Enum.Material.WoodPlanks)
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
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DoorPrompt"
		prompt.ActionText = "Enter your tunnel"
		prompt.ObjectText = "Tunnel " .. index
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = door
		lamp(model, hallX - 6, z + 7.5, index % 2 == 1)
		doors[index] = door
	end

	--------------------------------------------------------------------
	-- South: boss arena (the layer boss arrives in week 6)
	--------------------------------------------------------------------
	local arena = part(model, "Arena", Vector3.new(0.4, 70, 70), at(0, FLOOR_Y + 0.2, -95) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Arena, Enum.Material.Slate)
	arena.Shape = Enum.PartType.Cylinder
	for i = 1, 6 do
		local angle = math.rad(i * 60)
		local crack = part(model, "LavaCrack", Vector3.new(26, 0.1, 1), at(math.cos(angle) * 14, FLOOR_Y + 0.45, -95 + math.sin(angle) * 14) * CFrame.Angles(0, -angle, 0), COLORS.Lava, Enum.Material.Neon)
		crack.CanCollide = false
	end
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		local x, z = math.cos(angle) * 37, -95 + math.sin(angle) * 37
		if not (i == 2) then -- leave a gap facing the plaza
			part(model, "ArenaPillar", Vector3.new(3, 6, 3), at(x, FLOOR_Y + 3, z), Color3.fromRGB(90, 80, 75), Enum.Material.Rock)
		end
	end
	local gate = part(model, "ArenaGate", Vector3.new(16, 10, 1), at(0, FLOOR_Y + 5, -58), Color3.fromRGB(70, 60, 55), Enum.Material.Metal)
	sign(gate, "Layer Boss\n(week 6)", UDim2.fromScale(12, 3.5), Vector3.new(0, 8, 0), Color3.fromRGB(255, 120, 80))

	model.Parent = parent

	return {
		model = model,
		doors = doors,
		doorLabels = doorLabels,
		forge = anvil,
		veinFolder = veinFolder,
		spawnInFront = function(index: number): CFrame
			local door = doors[index]
			local position = door.Position + Vector3.new(-7, 0, 0)
			return CFrame.lookAt(Vector3.new(position.X, FLOOR_Y + 3, position.Z), Vector3.new(position.X - 10, FLOOR_Y + 3, position.Z))
		end,
	}
end

-- World position of a vein spot
function HubBuilder.VeinPosition(spot): Vector3
	return Vector3.new(C.X + spot.x, FLOOR_Y, C.Z + spot.z)
end

return HubBuilder
