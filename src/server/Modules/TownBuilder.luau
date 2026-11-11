-- TownBuilder
-- Builds Drill Town, the shared town on the surface, in code (gray box).
-- North = +Z:
--
--              [ leaderboards ]
--   [ display    ( elevator      [ daily board ]
--     stands ]     headframe )   [ pull board  ]
--              [ the Big Drill ]
--
-- The elevator headframe takes you down to your unlocked layers (the same
-- elevator panel as in every layer's plaza). The Big Drill is where you
-- Re-Drill. TownService fills the boards and stands.

local TownBuilder = {}

TownBuilder.Center = Vector3.new(-220, 0, 430)
TownBuilder.Size = 230

local FLOOR_Y = 0.4

local COLORS = {
	Grass = Color3.fromRGB(95, 150, 70),
	Path = Color3.fromRGB(190, 160, 115),
	Plaza = Color3.fromRGB(150, 145, 135),
	Hill = Color3.fromRGB(80, 125, 60),
	Steel = Color3.fromRGB(150, 60, 45),
	Metal = Color3.fromRGB(75, 75, 82),
	Wood = Color3.fromRGB(120, 80, 45),
	Board = Color3.fromRGB(30, 28, 36),
	Lamp = Color3.fromRGB(255, 210, 120),
	Stone = Color3.fromRGB(170, 165, 160),
	Gold = Color3.fromRGB(255, 200, 60),
}

export type Board = { title: TextLabel, rows: { TextLabel } }

export type Town = {
	model: Model,
	elevatorCall: BasePart,
	plaza: CFrame, -- where you arrive in town
	bigDrill: BasePart,
	dailyBoard: BasePart,
	leaderboards: { [string]: Board }, -- "Level", "Depth", "DPS"
	pullBoard: Board,
	stands: { { pedestal: BasePart, label: TextLabel } }, -- 1st, 2nd, 3rd
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

local function sign(parent: BasePart, text: string, size: UDim2, offset: Vector3, color: Color3?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 160
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

-- A board with a title and rows of text on its front (the -Z face looks
-- toward the town center when facing is the board's look direction)
local function board(parent: Instance, name: string, title: string, rowCount: number, cframe: CFrame, size: Vector3, titleColor: Color3): (BasePart, Board)
	local p = part(parent, name, size, cframe, COLORS.Board, Enum.Material.SmoothPlastic)
	part(parent, name .. "Frame", size + Vector3.new(0.6, 0.6, -0.4), cframe * CFrame.new(0, 0, 0.4), COLORS.Wood, Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, 400 * size.Y / size.X)
	gui.LightInfluence = 0
	gui.Parent = p
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 2)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = gui
	local function row(text: string, height: number, color: Color3, order: number): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, height)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text
		l.LayoutOrder = order
		l.Parent = gui
		return l
	end
	local titleLabel = row(title, 40, titleColor, 0)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	local rows = {}
	local rowHeight = math.floor((gui.CanvasSize.Y - 64) / rowCount) - 2
	for i = 1, rowCount do
		rows[i] = row("", rowHeight, Color3.fromRGB(235, 235, 240), i)
	end
	return p, { title = titleLabel, rows = rows }
end

function TownBuilder.Build(parent: Instance): Town
	local C = TownBuilder.Center
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(C.X + x, C.Y + y, C.Z + z)
	end
	-- Facing the town center from (x, z)
	local function facingCenter(x: number, y: number, z: number): CFrame
		local position = at(x, y, z).Position
		local center = at(0, y, 0).Position
		return CFrame.lookAt(position, center) * CFrame.Angles(0, math.rad(180), 0)
	end
	local function lamp(model: Instance, x: number, z: number)
		part(model, "LampPost", Vector3.new(0.6, 8, 0.6), at(x, FLOOR_Y + 4, z), COLORS.Metal, Enum.Material.Metal)
		local bulb = part(model, "Lamp", Vector3.new(1.4, 1.4, 1.4), at(x, FLOOR_Y + 8.5, z), COLORS.Lamp, Enum.Material.Neon)
		bulb.CanCollide = false
	end

	local model = Instance.new("Model")
	model.Name = "DrillTown"
	local S = TownBuilder.Size
	local H = S / 2

	-- Ground, hills around the edge (it's the surface: open sky)
	part(model, "Ground", Vector3.new(S, 1, S), at(0, FLOOR_Y - 0.5, 0), COLORS.Grass, Enum.Material.Grass)
	for _, wall in {
		{ Vector3.new(S + 30, 14, 16), at(0, 6, H + 7) },
		{ Vector3.new(S + 30, 14, 16), at(0, 6, -H - 7) },
		{ Vector3.new(16, 14, S), at(H + 7, 6, 0) },
		{ Vector3.new(16, 14, S), at(-H - 7, 6, 0) },
	} do
		part(model, "Hill", wall[1], wall[2], COLORS.Hill, Enum.Material.Grass)
	end
	part(model, "PathNS", Vector3.new(14, 0.2, S - 20), at(0, FLOOR_Y + 0.1, 0), COLORS.Path, Enum.Material.Sand)
	part(model, "PathEW", Vector3.new(S - 20, 0.2, 14), at(0, FLOOR_Y + 0.1, 0), COLORS.Path, Enum.Material.Sand)
	local plaza = part(model, "Plaza", Vector3.new(0.4, 50, 50), at(0, FLOOR_Y + 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), COLORS.Plaza, Enum.Material.Cobblestone)
	plaza.Shape = Enum.PartType.Cylinder

	--------------------------------------------------------------------
	-- Center: the elevator headframe (down to the layers)
	--------------------------------------------------------------------
	part(model, "Shaft", Vector3.new(14, 6, 14), at(0, FLOOR_Y + 3, 0), COLORS.Metal, Enum.Material.DiamondPlate)
	for _, x in { -6, 6 } do
		part(model, "HeadframeLeg", Vector3.new(1.4, 34, 1.4), at(x, FLOOR_Y + 17, 4) * CFrame.Angles(0, 0, math.rad(x > 0 and 8 or -8)), COLORS.Steel, Enum.Material.Metal)
		part(model, "HeadframeBrace", Vector3.new(1.2, 30, 1.2), at(x, FLOOR_Y + 15, 14) * CFrame.Angles(math.rad(-28), 0, 0), COLORS.Steel, Enum.Material.Metal)
	end
	for i = 1, 4 do
		part(model, "HeadframeBar", Vector3.new(13 - i * 1.1, 0.8, 0.8), at(0, FLOOR_Y + i * 7, 4), COLORS.Steel, Enum.Material.Metal)
	end
	local wheel = part(model, "Wheel", Vector3.new(1, 9, 9), at(0, FLOOR_Y + 34, 4), COLORS.Metal, Enum.Material.Metal)
	wheel.Shape = Enum.PartType.Cylinder
	sign(wheel, "Drill Town", UDim2.fromScale(26, 4), Vector3.new(0, 8, 0), COLORS.Gold)
	local call = part(model, "ElevatorCall", Vector3.new(4, 5, 1), at(0, FLOOR_Y + 2.5, -7.5), COLORS.Metal, Enum.Material.Metal)
	sign(call, "Elevator", UDim2.fromScale(8, 1.6), Vector3.new(0, 4, 0), Color3.fromRGB(255, 230, 160))
	local elevatorPrompt = prompt(call, "ElevatorPrompt", "Ride elevator", "Elevator", 10)
	elevatorPrompt:SetAttribute("Layer", 0)
	for _, p in { { 20, 20 }, { -20, 20 }, { 20, -20 }, { -20, -20 } } do
		lamp(model, p[1], p[2])
	end

	-- A forge by the plaza (works like the ones in the layer hubs)
	local anvil = part(model, "Forge", Vector3.new(4, 2, 2), at(16, FLOOR_Y + 3.4, -14), Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
	part(model, "AnvilBase", Vector3.new(2, 2.4, 1.6), at(16, FLOOR_Y + 1.2, -14), Color3.fromRGB(70, 50, 35), Enum.Material.Wood)
	sign(anvil, "Forge", UDim2.fromScale(8, 2), Vector3.new(0, 4, 0), Color3.fromRGB(255, 160, 80))
	prompt(anvil, "ForgePrompt", "Use Forge", "Forge", 12)

	--------------------------------------------------------------------
	-- North: leaderboards (every server)
	--------------------------------------------------------------------
	local leaderboards = {}
	for i, info in { { "Level", "Top Level", Color3.fromRGB(120, 200, 255) }, { "Depth", "Deepest Drillers", Color3.fromRGB(255, 160, 80) }, { "DPS", "Top DPS", Color3.fromRGB(255, 90, 90) } } do
		local x = (i - 2) * 28
		local cframe = CFrame.lookAt(at(x, FLOOR_Y + 9, 70).Position, at(x, FLOOR_Y + 9, 0).Position)
		local _, b = board(model, "Leaderboard" .. info[1], info[2], 10, cframe, Vector3.new(22, 16, 1), info[3])
		part(model, "BoardPost", Vector3.new(1, 9, 1), at(x - 9, FLOOR_Y + 0.5, 70.6), COLORS.Wood, Enum.Material.Wood)
		part(model, "BoardPost", Vector3.new(1, 9, 1), at(x + 9, FLOOR_Y + 0.5, 70.6), COLORS.Wood, Enum.Material.Wood)
		leaderboards[info[1]] = b
	end

	--------------------------------------------------------------------
	-- West: display stands for the top players in this server
	--------------------------------------------------------------------
	local stands = {}
	local standSign = part(model, "StandsSign", Vector3.new(16, 3, 0.6), facingCenter(-62, FLOOR_Y + 12, 0), COLORS.Wood, Enum.Material.WoodPlanks)
	sign(standSign, "Top miners in this server", UDim2.fromScale(18, 2.4), Vector3.new(0, 2.5, 0), COLORS.Gold)
	for i, z in { 0, -14, 14 } do
		local height = ({ 5, 3.5, 2.5 })[i]
		local pedestal = part(model, "Stand" .. i, Vector3.new(6, height, 6), at(-56, FLOOR_Y + height / 2, z), COLORS.Stone, Enum.Material.Marble)
		local label = sign(pedestal, "-", UDim2.fromScale(12, 2.6), Vector3.new(0, height / 2 + 6, 0), if i == 1 then COLORS.Gold else Color3.new(1, 1, 1))
		stands[i] = { pedestal = pedestal, label = label }
	end

	--------------------------------------------------------------------
	-- East: daily board and the board of big pulls
	--------------------------------------------------------------------
	local dailyBoard = part(model, "DailyBoard", Vector3.new(1, 9, 14), at(58, FLOOR_Y + 6, -14), COLORS.Wood, Enum.Material.WoodPlanks)
	sign(dailyBoard, "Daily\nRewards & Quests", UDim2.fromScale(12, 3.6), Vector3.new(0, 7, 0), Color3.fromRGB(150, 255, 170))
	prompt(dailyBoard, "DailyPrompt", "Open", "Daily board", 12)
	local pullCFrame = CFrame.lookAt(at(62, FLOOR_Y + 8, 18).Position, at(0, FLOOR_Y + 8, 18).Position)
	local _, pullBoard = board(model, "PullBoard", "Big pulls", 6, pullCFrame, Vector3.new(20, 12, 1), Color3.fromRGB(255, 90, 160))

	--------------------------------------------------------------------
	-- South: the Big Drill (Re-Drill)
	--------------------------------------------------------------------
	local base = part(model, "DrillBase", Vector3.new(16, 3, 16), at(0, FLOOR_Y + 1.5, -66), COLORS.Metal, Enum.Material.DiamondPlate)
	part(model, "DrillTower", Vector3.new(4, 22, 4), at(0, FLOOR_Y + 14, -66), COLORS.Steel, Enum.Material.Metal)
	local bit = part(model, "DrillBit", Vector3.new(7, 7, 7), at(0, FLOOR_Y + 4, -66), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
	bit.Shape = Enum.PartType.Ball
	local core = part(model, "DrillCore", Vector3.new(2.5, 2.5, 2.5), at(0, FLOOR_Y + 26, -66), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
	core.CanCollide = false
	sign(core, "The Big Drill\nRe-Drill", UDim2.fromScale(16, 4), Vector3.new(0, 5, 0), Color3.fromRGB(255, 160, 80))
	local drillPrompt = prompt(base, "ReDrillPrompt", "Re-Drill", "The Big Drill", 14)
	drillPrompt.HoldDuration = 0.3

	model.Parent = parent

	return {
		model = model,
		elevatorCall = call,
		plaza = CFrame.lookAt(at(0, FLOOR_Y + 3, -16).Position, at(0, FLOOR_Y + 3, -40).Position),
		bigDrill = base,
		dailyBoard = dailyBoard,
		leaderboards = leaderboards,
		pullBoard = pullBoard,
		stands = stands,
	}
end

return TownBuilder
