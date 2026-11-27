-- Tiny UI kit so every screen shares one look: near-black panels, warm off-white serif text,
-- antique gold highlights (matching the gothic main menu).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Kit = {}

Kit.Colors = {
	Bg = Color3.fromRGB(8, 8, 10),
	Panel = Color3.fromRGB(16, 16, 20),
	PanelLight = Color3.fromRGB(28, 28, 34),
	Line = Color3.fromRGB(60, 56, 50),
	Text = Color3.fromRGB(236, 230, 218),
	Muted = Color3.fromRGB(150, 145, 136),
	Gold = Color3.fromRGB(205, 168, 92),
	GoldBright = Color3.fromRGB(255, 214, 128),
	Danger = Color3.fromRGB(220, 72, 72),
	Good = Color3.fromRGB(110, 210, 130),
	Team1 = Color3.fromRGB(90, 165, 255),
	Team2 = Color3.fromRGB(255, 95, 95),
}

Kit.Fonts = {
	Title = Enum.Font.GrenzeGotisch, -- blackletter title, gothic feel
	Serif = Enum.Font.Merriweather, -- menu items
	Body = Enum.Font.Gotham,
	Bold = Enum.Font.GothamBold,
	Heavy = Enum.Font.GothamBlack,
}

function Kit.new(className: string, props, children)
	local inst = Instance.new(className)
	for key, value in props or {} do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Kit.Corner(parent: Instance, radius: number?)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

function Kit.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return Kit.new("UIStroke", {
		Color = color or Kit.Colors.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.Padding(parent: Instance, px: number)
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function Kit.List(
	parent: Instance,
	direction: Enum.FillDirection?,
	padding: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
)
	return Kit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Kit.Frame(parent: Instance, props)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or Kit.Colors.Panel
	props.BorderSizePixel = 0
	props.Parent = parent
	return Kit.new("Frame", props)
end

function Kit.Label(parent: Instance, text: string, size: number?, props)
	props = props or {}
	props.Text = text
	props.TextSize = size or 16
	props.Font = props.Font or Kit.Fonts.Body
	props.TextColor3 = props.TextColor3 or Kit.Colors.Text
	props.BackgroundTransparency = 1
	props.Size = props.Size or UDim2.new(1, 0, 0, (size or 16) + 6)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextWrapped = props.TextWrapped ~= false
	props.Parent = parent
	return Kit.new("TextLabel", props)
end

function Kit.Button(parent: Instance, text: string, onClick: () -> (), props)
	props = props or {}
	local accent = props.Accent or Kit.Colors.Gold
	props.Accent = nil
	props.Text = text
	props.Font = props.Font or Kit.Fonts.Bold
	props.TextSize = props.TextSize or 16
	props.TextColor3 = props.TextColor3 or Kit.Colors.Text
	props.BackgroundColor3 = props.BackgroundColor3 or Kit.Colors.PanelLight
	props.AutoButtonColor = false
	props.BorderSizePixel = 0
	props.Size = props.Size or UDim2.new(0, 160, 0, 40)
	props.Parent = parent
	local button = Kit.new("TextButton", props)
	Kit.Corner(button, 6)
	local stroke = Kit.Stroke(button, Kit.Colors.Line, 1)
	stroke.Name = "Stroke"
	local restColor = props.TextColor3
	button.MouseEnter:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.12), { Color = accent }):Play()
		TweenService:Create(button, TweenInfo.new(0.12), { TextColor3 = Kit.Colors.GoldBright }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.12), { Color = button:GetAttribute("HighlightColor") or Kit.Colors.Line }):Play()
		TweenService:Create(button, TweenInfo.new(0.12), { TextColor3 = restColor }):Play()
	end)
	button.Activated:Connect(onClick)
	return button
end

-- Persistent outline on a Kit.Button (selected / equipped state).
function Kit.Highlight(button: TextButton, color: Color3)
	button:SetAttribute("HighlightColor", color)
	local stroke = button:FindFirstChild("Stroke") :: UIStroke
	if stroke then
		stroke.Color = color
		stroke.Thickness = 2
	end
end

-- Full-screen page with a gothic title and a back button. Returns (root, content).
function Kit.Page(parent: Instance, title: string, onBack: () -> ())
	local root = Kit.Frame(parent, {
		Name = title,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.Colors.Bg,
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 5,
	})
	Kit.Label(root, title, 56, {
		Font = Kit.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.fromOffset(0, 24),
		TextColor3 = Kit.Colors.Text,
	})
	Kit.Frame(root, {
		Size = UDim2.new(0, 260, 0, 1),
		Position = UDim2.new(0.5, -130, 0, 98),
		BackgroundColor3 = Kit.Colors.Gold,
		BackgroundTransparency = 0.3,
	})
	Kit.Button(root, "BACK", onBack, { Position = UDim2.fromOffset(24, 30), Size = UDim2.fromOffset(110, 36) })
	local content = Kit.Frame(root, {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 24, 0, 120),
		Size = UDim2.new(1, -48, 1, -144),
	})
	return root, content
end

function Kit.Scroll(parent: Instance, props)
	props = props or {}
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.ScrollBarThickness = 4
	props.ScrollBarImageColor3 = Kit.Colors.Gold
	props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	props.CanvasSize = UDim2.new()
	props.Size = props.Size or UDim2.fromScale(1, 1)
	props.Parent = parent
	return Kit.new("ScrollingFrame", props)
end

function Kit.Slider(parent: Instance, label: string, min: number, max: number, value: number, step: number, onChange: (number) -> ())
	local row = Kit.Frame(parent, { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 })
	local text = Kit.Label(row, label, 15, { Size = UDim2.new(0.4, 0, 1, 0) })
	local bar =
		Kit.Frame(row, { Size = UDim2.new(0.45, 0, 0, 6), Position = UDim2.new(0.4, 0, 0.5, -3), BackgroundColor3 = Kit.Colors.PanelLight })
	Kit.Corner(bar, 3)
	local fill = Kit.Frame(bar, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Kit.Colors.Gold })
	Kit.Corner(fill, 3)
	local valueLabel = Kit.Label(
		row,
		"",
		15,
		{ Size = UDim2.new(0.13, 0, 1, 0), Position = UDim2.new(0.87, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }
	)
	local function render(v: number)
		fill.Size = UDim2.fromScale((v - min) / (max - min), 1)
		valueLabel.Text = step >= 1 and tostring(math.floor(v)) or string.format("%.2f", v)
	end
	render(value)
	local dragging = false
	local function setFromX(x: number)
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local v = min + alpha * (max - min)
		v = math.floor(v / step + 0.5) * step
		render(v)
		onChange(v)
	end
	local hit = Kit.new(
		"TextButton",
		{ Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0.5, -12), Parent = bar }
	)
	hit.MouseButton1Down:Connect(function(x)
		dragging = true
		setFromX(x)
	end)
	game:GetService("UserInputService").InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X)
		end
	end)
	game:GetService("UserInputService").InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	return row, text
end

function Kit.Toggle(parent: Instance, label: string, value: boolean, onChange: (boolean) -> ())
	local row = Kit.Frame(parent, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 })
	Kit.Label(row, label, 15, { Size = UDim2.new(0.6, 0, 1, 0) })
	local state = value
	local button
	button = Kit.Button(row, state and "ON" or "OFF", function()
		state = not state
		button.Text = state and "ON" or "OFF"
		button.TextColor3 = state and Kit.Colors.Good or Kit.Colors.Muted
		onChange(state)
	end, {
		Size = UDim2.fromOffset(80, 30),
		Position = UDim2.new(1, -80, 0.5, -15),
		TextColor3 = state and Kit.Colors.Good or Kit.Colors.Muted,
	})
	return row
end

-- Cycles through options with < > arrows.
function Kit.Stepper(parent: Instance, label: string, options: { any }, index: number, format: (any) -> string, onChange: (any) -> ())
	local row = Kit.Frame(parent, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 })
	Kit.Label(row, label, 15, { Size = UDim2.new(0.5, 0, 1, 0) })
	local current = math.clamp(index, 1, #options)
	local valueLabel = Kit.Label(row, format(options[current]), 15, {
		Size = UDim2.new(0, 140, 1, 0),
		Position = UDim2.new(1, -176, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Bold,
	})
	local function shift(delta: number)
		current = ((current - 1 + delta) % #options) + 1
		valueLabel.Text = format(options[current])
		onChange(options[current])
	end
	Kit.Button(row, "<", function()
		shift(-1)
	end, { Size = UDim2.fromOffset(32, 30), Position = UDim2.new(1, -212, 0.5, -15) })
	Kit.Button(row, ">", function()
		shift(1)
	end, { Size = UDim2.fromOffset(32, 30), Position = UDim2.new(1, -32, 0.5, -15) })
	return row, function(newIndex: number)
		current = math.clamp(newIndex, 1, #options)
		valueLabel.Text = format(options[current])
	end
end

local toastHolder: Frame?
function Kit.Toast(text: string, color: Color3?)
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not toastHolder or not toastHolder.Parent then
		local screen =
			Kit.new("ScreenGui", { Name = "Toasts", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50, Parent = gui })
		toastHolder =
			Kit.Frame(screen, { BackgroundTransparency = 1, Size = UDim2.new(0, 420, 1, -40), Position = UDim2.new(0.5, -210, 0, 20) })
		Kit.List(toastHolder :: Frame, nil, 6, Enum.HorizontalAlignment.Center)
	end
	local toast = Kit.Frame(
		toastHolder :: Frame,
		{ Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Kit.Colors.Panel, BackgroundTransparency = 0.1 }
	)
	Kit.Corner(toast, 6)
	Kit.Stroke(toast, color or Kit.Colors.Gold, 1, 0.3)
	Kit.Label(
		toast,
		text,
		15,
		{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = color or Kit.Colors.Text }
	)
	task.delay(3, function()
		toast:Destroy()
	end)
end

return Kit
