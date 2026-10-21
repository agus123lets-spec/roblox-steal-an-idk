--!strict
-- Small UI toolkit so every screen shares the same rounded, outlined, bouncy look.

local TweenService: TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Colors = {
	panel = Color3.fromRGB(30, 34, 60),
	panelLight = Color3.fromRGB(48, 54, 92),
	row = Color3.fromRGB(40, 45, 78),
	stroke = Color3.fromRGB(12, 13, 26),
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(178, 186, 216),
	coins = Color3.fromRGB(255, 208, 66),
	speed = Color3.fromRGB(92, 222, 255),
	feathers = Color3.fromRGB(255, 152, 212),
	good = Color3.fromRGB(96, 214, 110),
	warn = Color3.fromRGB(255, 172, 62),
	danger = Color3.fromRGB(255, 86, 86),
	rare = Color3.fromRGB(202, 122, 255),
	info = Color3.fromRGB(92, 162, 255),
	button = Color3.fromRGB(84, 196, 120),
	buttonDisabled = Color3.fromRGB(96, 100, 124),
}

UIKit.Font = Enum.Font.FredokaOne
UIKit.BodyFont = Enum.Font.GothamBold

function UIKit.kindColor(kind: string?): Color3
	local c = UIKit.Colors
	if kind == "success" then
		return c.good
	elseif kind == "warn" then
		return c.warn
	elseif kind == "danger" then
		return c.danger
	elseif kind == "rare" then
		return c.rare
	elseif kind == "speed" then
		return c.speed
	elseif kind == "coins" then
		return c.coins
	end
	return c.info
end

function UIKit.corner(parent: GuiObject, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 12)
	corner.Parent = parent
	return corner
end

function UIKit.stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or UIKit.Colors.stroke
	stroke.Thickness = thickness or 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UIKit.textStroke(parent: TextLabel | TextButton, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UIKit.Colors.stroke
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = parent
end

function UIKit.gradient(parent: GuiObject, top: Color3, bottom: Color3): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = parent
	return gradient
end

function UIKit.padding(parent: GuiObject, pixels: number)
	local padding = Instance.new("UIPadding")
	local p = UDim.new(0, pixels)
	padding.PaddingTop = p
	padding.PaddingBottom = p
	padding.PaddingLeft = p
	padding.PaddingRight = p
	padding.Parent = parent
end

function UIKit.list(parent: GuiObject, direction: Enum.FillDirection, spacing: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

function UIKit.frame(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	color: Color3,
	transparency: number?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

function UIKit.label(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3?,
	font: Enum.Font?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or UIKit.Colors.text
	label.FontFace = Font.fromEnum(font or UIKit.Font)
	label.TextScaled = true
	label.RichText = true
	label.Parent = parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 40
	constraint.Parent = label
	return label
end

function UIKit.button(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3,
	onClick: () -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = text
	button.TextColor3 = UIKit.Colors.text
	button.FontFace = Font.fromEnum(UIKit.Font)
	button.TextScaled = true
	button.Parent = parent
	UIKit.corner(button)
	UIKit.stroke(button, UIKit.Colors.stroke, 2.5)
	UIKit.textStroke(button, 1.5)
	UIKit.gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 30
	constraint.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		UIKit.tween(scale, 0.12, { Scale = 1.06 })
	end)
	button.MouseLeave:Connect(function()
		UIKit.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.06, { Scale = 0.94 })
	end)
	button.Activated:Connect(function()
		UIKit.tween(scale, 0.12, { Scale = 1 })
		onClick()
	end)
	return button
end

function UIKit.tween(
	instance: Instance,
	seconds: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Quick bounce, used when a number changes or a panel opens.
-- Only use on objects without their own UIScale (a GuiObject honours a single UIScale).
function UIKit.pop(target: GuiObject, amount: number?)
	local existing = target:FindFirstChild("Pop")
	local scale: UIScale
	if existing and existing:IsA("UIScale") then
		scale = existing
	else
		scale = Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = target
	end
	scale.Scale = 1 + (amount or 0.12)
	UIKit.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

return UIKit
