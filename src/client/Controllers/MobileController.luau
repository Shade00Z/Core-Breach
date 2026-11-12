-- MobileController
-- Rearranges the HUD for phones and small screens ("compact" mode), so
-- nothing sits on the thumbstick, the jump button or the lane:
--   * the HUD buttons (Gear, Stats, Bag, Daily, Index, Powers, Store,
--     Settings) fold into one Menu button at the top left. Tap it for a grid
--     of big buttons; picking one closes the grid.
--   * the Rebirth button moves from the bottom right (where the jump and
--     Swing buttons are) to the top right.
--   * the Gear, Stats and Bag panels slide to the left edge and Gear shrinks
--     to fit.
--   * the screen is locked to landscape (the HUD is built for it).
-- It also puts the older panels above the HUD buttons (ZIndex), on every
-- device.
-- (Other pieces handle themselves: UIController shrinks the wave panel and
-- moves messages to the left side, CrateController shrinks its buttons, UIKit panels and the crate panel shrink
-- to fit, and PowerController moves the ability buttons above Swing.)
-- Compact mode is on for touch devices without a keyboard, or any screen
-- under 500 px on its short side. For testing on a PC, set the HUD's
-- "ForceCompact" attribute to true.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UIKit = require(script.Parent.Parent:WaitForChild("UIKit"))
local ClientSettings = require(script.Parent.Parent:WaitForChild("ClientSettings"))

local SMALL_SCREEN = 500
local CELL = Vector2.new(118, 46)
local COLUMNS = 4
-- The buttons that fold into the menu, in order (by name, without "Toggle")
local ORDER = { "Gear", "Stats", "Bag", "Daily", "Index", "Powers", "Store", "Settings" }

local MobileController = {}

local UIController
local gui: ScreenGui
local menuButton: TextButton
local menuBadge: TextLabel
local menu: Frame
local compact = false
type Saved = { parent: Instance?, position: UDim2, size: UDim2, order: number }
local toggles: { [GuiButton]: Saved } = {}
local moved: { [GuiObject]: UDim2 } = {}
local gearScale: UIScale?

local function shouldBeCompact(): boolean
	if gui:GetAttribute("ForceCompact") then
		return true
	end
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	return (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) or math.min(viewport.X, viewport.Y) < SMALL_SCREEN
end

-- The HUD toggle buttons (named "<Something>Toggle") that belong in the menu
local function findToggles()
	for _, child in gui:GetChildren() do
		if child:IsA("GuiButton") and table.find(ORDER, (child.Name:gsub("Toggle$", ""))) and not toggles[child] then
			toggles[child] = { parent = child.Parent, position = child.Position, size = child.Size, order = child.LayoutOrder }
			child.Activated:Connect(function()
				if compact then
					menu.Visible = false
				end
			end)
		end
	end
end

local function setPosition(object: Instance?, position: UDim2)
	if object and object:IsA("GuiObject") then
		if not moved[object] then
			moved[object] = object.Position
		end
		object.Position = position
	end
end

local function fitGear()
	local panel = gui:FindFirstChild("GearPanel")
	local camera = workspace.CurrentCamera
	if not panel or not panel:IsA("GuiObject") or not camera then
		return
	end
	local uiScale = gearScale
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = panel
		gearScale = uiScale
	end
	local viewport = camera.ViewportSize
	local scale = if compact then math.min(1, (viewport.X - 24) / panel.Size.X.Offset, (viewport.Y - 24) / panel.Size.Y.Offset) else 1
	uiScale.Scale = scale
	if compact then
		-- Centered up and down at its shrunken size
		panel.Position = UDim2.new(0, 12, 0.5, -panel.Size.Y.Offset * scale / 2)
	end
end

-- The Bag grows with what's in it: shrink it if it's taller than the screen
local function fitBag()
	local panel = gui:FindFirstChild("BagPanel")
	local camera = workspace.CurrentCamera
	if not panel or not panel:IsA("GuiObject") or not camera then
		return
	end
	local uiScale = panel:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = panel
	end
	local fullHeight = panel.AbsoluteSize.Y / math.max(uiScale.Scale, 0.01)
	uiScale.Scale = if fullHeight > 0 then math.min(1, (camera.ViewportSize.Y - 24) / fullHeight) else 1
end

-- Panels made before UIKit existed: above the HUD, and taps don't fall through
local LAYERS = { GearPanel = 10, StatsPanel = 10, BagPanel = 10, ForgePanel = 10, QuestDialog = 10, MenuGrid = 11, RebirthConfirm = 12, DevPanel = 15 }
local function layerPanels()
	for name, zIndex in LAYERS do
		local panel = gui:FindFirstChild(name)
		if panel and panel:IsA("GuiObject") then
			panel.ZIndex = zIndex
			panel.Active = true
		end
	end
end

local function apply()
	fitBag()
	local want = shouldBeCompact()
	if want == compact then
		if compact then
			fitGear()
		end
		return
	end
	compact = want
	ClientSettings.Set("compact", compact)
	menuButton.Visible = compact
	menu.Visible = false

	if compact then
		findToggles()
		for toggle in toggles do
			toggle.LayoutOrder = table.find(ORDER, (toggle.Name:gsub("Toggle$", ""))) or 99
			toggle.Parent = menu
		end
		setPosition(gui:FindFirstChild("RebirthButton"), UDim2.new(1, -202, 0, 70))
		setPosition(gui:FindFirstChild("GearPanel"), UDim2.new(0, 12, 0.5, -170))
		setPosition(gui:FindFirstChild("StatsPanel"), UDim2.new(0, 12, 0.5, 0))
		setPosition(gui:FindFirstChild("BagPanel"), UDim2.new(0, 12, 0.5, 0))
	else
		for toggle, saved in toggles do
			toggle.Parent = saved.parent
			toggle.Position = saved.position
			toggle.Size = saved.size
			toggle.LayoutOrder = saved.order
		end
		for object, position in moved do
			object.Position = position
		end
		table.clear(moved)
	end
	fitGear()
end

function MobileController:Init(controllers)
	UIController = controllers.UIController
	gui = UIController:GetGui()

	menuButton = UIKit.HudButton(gui, "Menu", Color3.fromRGB(60, 62, 78), UDim2.new(0, 12, 0, 144))
	menuButton.Name = "MenuButton"
	menuButton.Size = UDim2.new(0, 96, 0, 44)
	menuButton.Visible = false
	menuBadge = UIKit.Badge(menuButton)

	menu = Instance.new("Frame")
	menu.Name = "MenuGrid"
	menu.Position = UDim2.new(0, 116, 0, 144)
	menu.Size = UDim2.new(0, COLUMNS * (CELL.X + 6) + 6, 0, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.BackgroundColor3 = UIKit.Colors.Panel
	menu.BackgroundTransparency = 0.05
	menu.Visible = false
	menu.Parent = gui
	Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = menu
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = menu
	-- Shrink the grid if the screen is narrower than it
	local scale = Instance.new("UIScale")
	scale.Parent = menu
	menuButton.Activated:Connect(function()
		local camera = workspace.CurrentCamera
		if camera then
			scale.Scale = math.min(1, (camera.ViewportSize.X - 124) / menu.Size.X.Offset)
		end
		menu.Visible = not menu.Visible
	end)
end

function MobileController:Start()
	layerPanels()
	-- Phones: landscape only (does nothing on PC)
	Players.LocalPlayer:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	gui:GetAttributeChangedSignal("ForceCompact"):Connect(apply)
	task.spawn(function()
		while true do
			apply() -- also catches rotating the phone and plugging in a keyboard
			-- "!" on Menu while any button inside has one
			local any = false
			if compact then
				for toggle in toggles do
					local badge = toggle:FindFirstChild("Badge")
					if badge and badge:IsA("GuiObject") and badge.Visible then
						any = true
					end
				end
			end
			menuBadge.Visible = any
			task.wait(1)
		end
	end)
end

return MobileController
