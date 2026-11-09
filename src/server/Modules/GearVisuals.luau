-- GearVisuals
-- Gray-box models for mounted gear: one Part per gear, shaped by kind and
-- colored by rarity, with a small tag above it: level, and the forge
-- multiplier once it's been forged ("Lv 3  x2.4"). The client turns the
-- part to face whatever it's shooting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearData"))

local SHAPES = GearData.Shapes

local GearVisuals = {}

local function levelText(level: number, forge: { mult: number }?): string
	local text = if level >= GearData.Levels.MaxLevel then "MAX" else ("Lv " .. level)
	if forge and forge.mult and forge.mult > 1.005 then
		text ..= string.format("  x%.2f", forge.mult)
	end
	return text
end

-- Builds the gear model on top of a slot ledge, facing up the lane.
function GearVisuals.Build(gear: GearData.Gear, level: number, slotPart: BasePart, upLane: Vector3, forge: { mult: number }?): BasePart
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
	tag.Size = UDim2.new(0, 110, 0, 22)
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
	text.Text = levelText(level, forge)
	text.Parent = tag
	tag.Parent = part

	part.Parent = slotPart
	return part
end

-- Updates the level tag on an existing gear model.
function GearVisuals.SetLevel(part: BasePart, level: number, forge: { mult: number }?)
	local tag = part:FindFirstChild("LevelTag")
	local text = tag and tag:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		text.Text = levelText(level, forge)
	end
end

return GearVisuals
