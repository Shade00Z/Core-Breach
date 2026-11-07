-- GearVisuals
-- Gray-box models for mounted gear: one Part per gear, shaped by kind and
-- colored by rarity, with a small level tag above it. The client turns the
-- part to face whatever it's shooting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearData"))

local SHAPES = GearData.Shapes

local GearVisuals = {}

local function levelText(level: number): string
	return if level >= GearData.Levels.MaxLevel then "MAX" else ("Lv " .. level)
end

-- Builds the gear model on top of a slot ledge, facing up the lane.
function GearVisuals.Build(gear: GearData.Gear, level: number, slotPart: BasePart, upLane: Vector3): BasePart
	local shape = SHAPES[gear.kind] or SHAPES.Pistol
	local rarity = GearData.Rarities[gear.rarity]

	local part = Instance.new("Part")
	part.Name = "Gear"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = shape.size
	part.Color = rarity and rarity.color or Color3.new(1, 1, 1)
	part.Material = if gear.rarity == "Legendary" or gear.rarity == "Mythic" then Enum.Material.Neon else Enum.Material.Metal
	if shape.ball then
		part.Shape = Enum.PartType.Ball
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local position = slotPart.Position + Vector3.new(0, slotPart.Size.Y / 2 + shape.size.Y / 2 + shape.lift, 0)
	part.CFrame = CFrame.lookAt(position, position + upLane)
	part:SetAttribute("GearId", gear.id)
	part:SetAttribute("Rarity", gear.rarity)

	-- Level tag
	local tag = Instance.new("BillboardGui")
	tag.Name = "LevelTag"
	tag.Size = UDim2.new(0, 60, 0, 22)
	tag.StudsOffset = Vector3.new(0, shape.size.Y / 2 + 1.2, 0)
	tag.MaxDistance = 120
	tag.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 1, 0)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = rarity and rarity.color or Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = levelText(level)
	text.Parent = tag
	tag.Parent = part

	part.Parent = slotPart
	return part
end

-- Updates the level tag on an existing gear model.
function GearVisuals.SetLevel(part: BasePart, level: number)
	local tag = part:FindFirstChild("LevelTag")
	local text = tag and tag:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		text.Text = levelText(level)
	end
end

return GearVisuals
