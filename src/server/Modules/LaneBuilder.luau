-- LaneBuilder
-- Builds a gray-box lane in code, so every player's lane is identical and
-- lives in Git. Lanes sit side by side along X, each facing +Z.
--
-- Lane-local space: origin is the center of the player end on the floor.
-- Local -Z points up the lane toward the breach, so a point "dist" studs up
-- the lane and "lateral" studs to the side is origin * Vector3.new(lateral, y, -dist).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LaneConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LaneConfig"))

local LaneBuilder = {}

local COLORS = {
	Floor = Color3.fromRGB(58, 52, 46),
	Wall = Color3.fromRGB(110, 84, 58),
	Barricade = Color3.fromRGB(150, 110, 70),
	Breach = Color3.fromRGB(220, 40, 40),
	Slot = Color3.fromRGB(150, 150, 150),
	CratePad = Color3.fromRGB(240, 180, 40),
	Crate = Color3.fromRGB(160, 110, 60),
}

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Lane-local position of a gear slot ledge: (lateral, height, dist).
-- Slots 1-3 are on the left wall, 4-6 on the right, front to back.
function LaneBuilder.SlotLocal(slotIndex: number): (number, number, number)
	local perSide = #LaneConfig.SlotDistances
	local side = if slotIndex <= perSide then -1 else 1
	local dist = LaneConfig.SlotDistances[(slotIndex - 1) % perSide + 1]
	return side * (LaneConfig.Width / 2 - 1.5), 6, dist
end

function LaneBuilder.OriginFor(index: number): CFrame
	local x = (index - 1) * LaneConfig.Spacing
	local position = Vector3.new(x, 0, LaneConfig.StartZ)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

-- Returns the lane Model and its origin CFrame. Attributes are set before
-- the lane is parented, so clients always see them when the lane appears.
function LaneBuilder.Build(index: number, parent: Instance, attributes: { [string]: any }?): (Model, CFrame)
	local W, L = LaneConfig.Width, LaneConfig.Length
	local origin = LaneBuilder.OriginFor(index)

	local model = Instance.new("Model")
	model.Name = "Lane" .. index
	model:SetAttribute("LaneIndex", index)

	local function at(lateral: number, y: number, dist: number): CFrame
		return origin * CFrame.new(lateral, y, -dist)
	end

	-- Floor and walls
	makePart(model, "Floor", Vector3.new(W, 0.4, L + 10), at(0, 0.2, L / 2), COLORS.Floor, Enum.Material.Concrete)
	makePart(model, "WallLeft", Vector3.new(6, 16, L + 10), at(-(W / 2 + 3), 8, L / 2), COLORS.Wall, Enum.Material.Rock)
	makePart(model, "WallRight", Vector3.new(6, 16, L + 10), at(W / 2 + 3, 8, L / 2), COLORS.Wall, Enum.Material.Rock)
	makePart(model, "WallBack", Vector3.new(W + 12, 16, 4), at(0, 8, L + 7), COLORS.Wall, Enum.Material.Rock)

	-- Front wall behind the player end, with the exit door to the hub
	-- (HubService teleports you to your tunnel door there)
	makePart(model, "WallFront", Vector3.new(W + 12, 16, 4), at(0, 8, -7), COLORS.Wall, Enum.Material.Rock)
	local exit = makePart(model, "ExitDoor", Vector3.new(8, 11, 0.8), at(0, 5.5, -4.8), Color3.fromRGB(105, 70, 40), Enum.Material.WoodPlanks)
	local exitSign = Instance.new("SurfaceGui")
	exitSign.Face = Enum.NormalId.Front
	exitSign.CanvasSize = Vector2.new(240, 330)
	exitSign.LightInfluence = 0
	local exitText = Instance.new("TextLabel")
	exitText.BackgroundTransparency = 1
	exitText.Size = UDim2.fromScale(1, 0.35)
	exitText.Font = Enum.Font.GothamBlack
	exitText.TextScaled = true
	exitText.TextColor3 = Color3.fromRGB(255, 225, 170)
	exitText.Text = "MINE & FORGE"
	exitText.Parent = exitSign
	exitSign.Parent = exit
	local exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.ActionText = "Go to the mine"
	exitPrompt.ObjectText = "Exit"
	exitPrompt.KeyboardKeyCode = Enum.KeyCode.E
	exitPrompt.MaxActivationDistance = 9
	exitPrompt.RequiresLineOfSight = false
	exitPrompt.Parent = exit

	-- Breach hole (a glowing disc facing down the lane)
	local breach = makePart(model, "Breach", Vector3.new(1, 12, 12), at(0, 7, L + 4.5) * CFrame.Angles(0, math.rad(90), 0), COLORS.Breach, Enum.Material.Neon)
	breach.Shape = Enum.PartType.Cylinder
	breach.CanCollide = false

	-- Barricade
	local barricade = makePart(model, "Barricade", Vector3.new(W, 4, 2), at(0, 2, LaneConfig.BarricadeDistance), COLORS.Barricade, Enum.Material.WoodPlanks)
	barricade:SetAttribute("HP", LaneConfig.BarricadeMaxHP)
	barricade:SetAttribute("MaxHP", LaneConfig.BarricadeMaxHP)

	-- The barricade is 4 studs tall, so the hero can jump over it (about 7
	-- studs) into the lane to fight. DigService covers locked slots with rock.

	-- Gear wall slots: 3 ledges per side, locked until dug out
	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	slots.Parent = model
	for slotIndex = 1, #LaneConfig.SlotDistances * 2 do
		local lateral, height, dist = LaneBuilder.SlotLocal(slotIndex)
		local slot = makePart(slots, "Slot" .. slotIndex, Vector3.new(3, 0.6, 4), at(lateral, height, dist), COLORS.Slot, Enum.Material.Slate)
		slot:SetAttribute("SlotIndex", slotIndex)
		slot:SetAttribute("Unlocked", false)
		slot:SetAttribute("GearId", "")
	end

	-- Crate pad at the player end
	makePart(model, "CratePad", Vector3.new(6, 0.6, 6), at(0, 0.7, 6), COLORS.CratePad, Enum.Material.Metal)
	makePart(model, "Crate", Vector3.new(4, 3, 4), at(0, 2.5, 6), COLORS.Crate, Enum.Material.WoodPlanks)

	model.PrimaryPart = model:FindFirstChild("Floor") :: BasePart
	if attributes then
		for name, value in attributes do
			model:SetAttribute(name, value)
		end
	end
	model.Parent = parent
	return model, origin
end

return LaneBuilder
