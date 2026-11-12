-- UIKit
-- Small helpers for building the HUD panels in code, so they all look alike:
-- a dark rounded panel with a title and a close button, text labels and
-- buttons. Used by the week 7 panels (Elevator, Daily, Index, Re-Drill).

local UIKit = {}

UIKit.Colors = {
	Panel = Color3.fromRGB(22, 20, 28),
	Row = Color3.fromRGB(36, 34, 44),
	Gold = Color3.fromRGB(255, 210, 110),
	Green = Color3.fromRGB(60, 170, 80),
	Gray = Color3.fromRGB(90, 90, 100),
	Dim = Color3.fromRGB(170, 170, 180),
	Red = Color3.fromRGB(180, 50, 50),
}

function UIKit.Label(parent: Instance, text: string, textSize: number, color: Color3?, order: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextSize = textSize
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.LayoutOrder = order or 0
	l.Parent = parent
	return l
end

function UIKit.Button(parent: Instance, text: string, color: Color3, size: UDim2, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 16
	b.TextWrapped = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	b.Activated:Connect(onClick)
	return b
end

-- A HUD toggle button on the left side
function UIKit.HudButton(gui: Instance, text: string, color: Color3, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Name = text .. "Toggle"
	b.Size = UDim2.new(0, 90, 0, 40)
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 18
	b.Text = text
	b.Parent = gui
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end

-- A small red "!" badge on a button
function UIKit.Badge(button: GuiObject): TextLabel
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -2, 0, 2)
	badge.Size = UDim2.new(0, 20, 0, 20)
	badge.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
	badge.Font = Enum.Font.GothamBlack
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.TextSize = 14
	badge.Text = "!"
	badge.Visible = false
	badge.Parent = button
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	return badge
end

export type Panel = {
	frame: Frame,
	body: Frame, -- add content here (vertical list)
	title: TextLabel,
	open: () -> (),
	close: () -> (),
}

-- A centered panel with a title, an X button and a scrolling body
function UIKit.Panel(gui: Instance, name: string, title: string, width: number, height: number): Panel
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(0, width, 0, height)
	frame.BackgroundColor3 = UIKit.Colors.Panel
	frame.BackgroundTransparency = 0.04
	frame.Visible = false
	frame.ZIndex = 10 -- over the HUD buttons
	frame.Active = true -- taps don't fall through to buttons underneath
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(width, height)
	limit.Parent = frame
	-- Shrink to fit small (phone) screens
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function fit()
		local camera = workspace.CurrentCamera
		if camera then
			local viewport = camera.ViewportSize
			scale.Scale = math.min(1, (viewport.X - 24) / width, (viewport.Y - 24) / height)
		end
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 16, 0, 10)
	titleLabel.Size = UDim2.new(1, -70, 0, 30)
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextColor3 = UIKit.Colors.Gold
	titleLabel.TextSize = 24
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = title
	titleLabel.Parent = frame

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.new(0, 16, 0, 48)
	body.Size = UDim2.new(1, -32, 1, -60)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	body.Parent = frame
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body

	local panel: Panel
	local close = UIKit.Button(frame, "X", UIKit.Colors.Red, UDim2.new(0, 36, 0, 36), function()
		panel.close()
	end)
	close.Position = UDim2.new(1, -46, 0, 8)

	panel = {
		frame = frame,
		body = body :: any,
		title = titleLabel,
		open = function()
			-- Only one big panel at a time
			for _, other in gui:GetChildren() do
				if other ~= frame and other:IsA("Frame") and other:GetAttribute("UIKitPanel") then
					other.Visible = false
				end
			end
			frame.Visible = true
		end,
		close = function()
			frame.Visible = false
		end,
	}
	frame:SetAttribute("UIKitPanel", true)
	return panel
end

-- Removes everything in a panel body except its layout
function UIKit.Clear(body: Instance)
	for _, child in body:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

-- A row container (horizontal or plain frame) with automatic height
function UIKit.Row(parent: Instance, order: number, horizontal: boolean?): Frame
	local row = Instance.new("Frame")
	row.BackgroundColor3 = UIKit.Colors.Row
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = order
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = row
	local list = Instance.new("UIListLayout")
	list.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = row
	return row
end

return UIKit
