-- Main menu. The player's own character stands in a fog-drenched gothic street, back to the camera,
-- holding their equipped sword with an aura in their ability's colours. The gothic title sits over
-- them and the menu is a centred list:
--
--   PLAY / LOADOUT / SHOP / SETTINGS / INFORMATION
--
-- The street is built locally around the player's private menu stage (attribute "MenuStage").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VFX = require(Shared.Lib.VFX)
local Anim = require(Shared.Lib.Anim)
local Animations = require(Shared.Config.Animations)
local Abilities = require(Shared.Config.Abilities)
local State = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local Atmosphere = require(script.Parent.Parent.Atmosphere)

local Screens = script.Parent.Parent.UI.Screens
local PlayScreen = require(Screens.PlayScreen)
local LoadoutScreen = require(Screens.LoadoutScreen)
local ShopScreen = require(Screens.ShopScreen)
local SettingsScreen = require(Screens.SettingsScreen)
local InfoScreen = require(Screens.InfoScreen)

local LocalPlayer = Players.LocalPlayer
local C = Kit.Colors

local MenuController = {}

local VERSION = "v0.1.0"
local ITEMS = { "PLAY", "LOADOUT", "SHOP", "SETTINGS", "INFORMATION" }

local gui: ScreenGui
local mainFrame: Frame
local itemLabels = {}
local highlight: Frame
local selected = 1
local screens = {}
local openScreen: string? = nil
local scene: Model? = nil
local sceneOrigin: Vector3? = nil
local auraCleanup: (() -> ())? = nil
local auraAbility: string? = nil
local coinsLabel: TextLabel
local statusPill: Frame

---------------------------------------------------------------------------------------------------
-- Scene
---------------------------------------------------------------------------------------------------

local rgb = Color3.fromRGB

local function block(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Slate
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildScene(origin: Vector3)
	if scene then
		scene:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "MenuScene"
	local rng = Random.new(7)
	local ground = origin.Y

	-- Cobblestone street + kerbs
	block(model, Vector3.new(26, 1, 340), CFrame.new(origin.X, ground - 0.5, origin.Z - 150), rgb(48, 48, 52), Enum.Material.Cobblestone)
	for side = -1, 1, 2 do
		block(
			model,
			Vector3.new(8, 1.6, 340),
			CFrame.new(origin.X + side * 17, ground - 0.2, origin.Z - 150),
			rgb(40, 40, 44),
			Enum.Material.Slate
		)
	end

	-- Gothic buildings on both sides
	for side = -1, 1, 2 do
		local z = origin.Z + 30
		while z > origin.Z - 320 do
			local depth = rng:NextNumber(14, 26)
			local height = rng:NextNumber(34, 80)
			local width = rng:NextNumber(14, 22)
			local x = origin.X + side * (21 + width / 2 + rng:NextNumber(0, 4))
			local color = rgb(rng:NextInteger(26, 40), rng:NextInteger(26, 40), rng:NextInteger(30, 46))
			local cf = CFrame.new(x, ground + height / 2, z - depth / 2)
			block(model, Vector3.new(width, height, depth), cf, color, Enum.Material.Slate)
			-- Spire / gable
			if rng:NextNumber() < 0.6 then
				local spire = Instance.new("WedgePart")
				spire.Anchored, spire.CanCollide, spire.CanQuery = true, false, false
				spire.Size = Vector3.new(width * 0.6, rng:NextNumber(12, 30), depth * 0.5)
				spire.Color = color
				spire.Material = Enum.Material.Slate
				spire.CFrame = CFrame.new(x, ground + height + spire.Size.Y / 2, z - depth / 2) * CFrame.Angles(0, math.rad(side * 90), 0)
				spire.Parent = model
			end
			-- Dim warm windows facing the street
			for row = 1, math.floor(height / 12) do
				if rng:NextNumber() < 0.35 then
					local wz = z - rng:NextNumber(3, depth - 3)
					local window = block(
						model,
						Vector3.new(0.3, 4, 2.2),
						CFrame.new(x - side * (width / 2 + 0.1), ground + row * 11, wz),
						rgb(255, 180, 90),
						Enum.Material.Neon
					)
					window.Transparency = rng:NextNumber(0.35, 0.75)
				end
			end
			z -= depth + rng:NextNumber(0, 3)
		end
	end

	-- Street lamps
	for i = 0, 6 do
		for side = -1, 1, 2 do
			local z = origin.Z - 10 - i * 42 - (side > 0 and 21 or 0)
			local x = origin.X + side * 14
			block(model, Vector3.new(0.6, 14, 0.6), CFrame.new(x, ground + 7, z), rgb(20, 20, 22), Enum.Material.Metal)
			local lamp = block(model, Vector3.new(1.4, 1.8, 1.4), CFrame.new(x, ground + 14.5, z), rgb(255, 196, 120), Enum.Material.Neon)
			local light = Instance.new("PointLight")
			light.Color = rgb(255, 180, 110)
			light.Range = 22
			light.Brightness = 1.3
			light.Shadows = true
			light.Parent = lamp
		end
	end

	-- Cold light at the far end of the street (back-lights the character like a silhouette)
	local glow =
		block(model, Vector3.new(60, 120, 2), CFrame.new(origin.X, ground + 40, origin.Z - 300), rgb(170, 190, 220), Enum.Material.Neon)
	glow.Transparency = 0.55
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Back
	spot.Color = rgb(170, 195, 235)
	spot.Range = 60
	spot.Angle = 70
	spot.Brightness = 3
	local spotHolder = block(model, Vector3.new(1, 1, 1), CFrame.new(origin.X, ground + 22, origin.Z - 36), rgb(0, 0, 0))
	spotHolder.Transparency = 1
	spot.Parent = spotHolder

	-- Ground mist + drifting motes
	local mist = block(model, Vector3.new(40, 1, 120), CFrame.new(origin.X, ground + 0.5, origin.Z - 40), rgb(0, 0, 0))
	mist.Transparency = 1
	local fog = Instance.new("ParticleEmitter")
	fog.Texture = "rbxasset://textures/particles/smoke_main.dds"
	fog.Color = ColorSequence.new(rgb(120, 130, 150))
	fog.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.86), NumberSequenceKeypoint.new(1, 1) })
	fog.Size = NumberSequence.new(10, 16)
	fog.Lifetime = NumberRange.new(8, 12)
	fog.Rate = 6
	fog.Speed = NumberRange.new(0.5, 1.5)
	fog.SpreadAngle = Vector2.new(180, 10)
	fog.Acceleration = Vector3.new(0.4, 0, 0)
	fog.LightInfluence = 1
	fog.Parent = mist
	local motes = fog:Clone()
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Size = NumberSequence.new(0.15)
	motes.Transparency = NumberSequence.new(0.4, 1)
	motes.Rate = 10
	motes.Acceleration = Vector3.new(0.2, 0.4, 0)
	motes.LightEmission = 1
	motes.Parent = mist

	model.Parent = Workspace
	scene = model
	sceneOrigin = origin
end

local function refreshAura()
	local character = LocalPlayer.Character
	local abilityId = State.Data and State.Data.Equipped.Ability
	if not character or not abilityId then
		return
	end
	if auraAbility == abilityId and auraCleanup then
		return
	end
	if auraCleanup then
		auraCleanup()
	end
	local def = Abilities.ById[abilityId]
	auraCleanup = VFX.Aura(character, def.Theme, 1)
	auraAbility = abilityId
end

local function clearAura()
	if auraCleanup then
		auraCleanup()
	end
	auraCleanup = nil
	auraAbility = nil
end

---------------------------------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------------------------------

local function setSelected(index: number)
	selected = index
	for i, label in itemLabels do
		local active = i == index
		TweenService:Create(label, TweenInfo.new(0.15), { TextColor3 = active and C.GoldBright or C.Text }):Play()
	end
	local target = itemLabels[index]
	TweenService
		:Create(highlight, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, target.Position.Y.Offset + 4) })
		:Play()
end

local function openPage(name: string?)
	for key, screen in screens do
		if key == name then
			screen.Show()
		else
			screen.Hide()
		end
	end
	openScreen = name
	mainFrame.Visible = name == nil
end

local function activate(index: number)
	local item = ITEMS[index]
	if item == "PLAY" then
		openPage("Play")
	elseif item == "LOADOUT" then
		openPage("Loadout")
	elseif item == "SHOP" then
		openPage("Shop")
	elseif item == "SETTINGS" then
		openPage("Settings")
	elseif item == "INFORMATION" then
		openPage("Info")
	end
end

local function buildUI()
	gui = Kit.new("ScreenGui", {
		Name = "MainMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
	})

	-- Vignette: dark edges like a film still.
	local vignette = Kit.Frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0 })
	Kit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.28, 0.85),
			NumberSequenceKeypoint.new(0.72, 0.85),
			NumberSequenceKeypoint.new(1, 0.15),
		}),
		Parent = vignette,
	})

	mainFrame = Kit.Frame(gui, { Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })

	-- Title
	local title = Kit.Label(mainFrame, "Power Battles", 120, {
		Font = Kit.Fonts.Title,
		Size = UDim2.new(1, 0, 0.2, 0),
		Position = UDim2.fromScale(0, 0.27),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(245, 242, 235),
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		TextStrokeTransparency = 0.55,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 150, Parent = title })
	Kit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 168, 165)),
		Parent = title,
	})

	-- Menu list
	local list = Kit.Frame(
		mainFrame,
		{ Name = "Items", BackgroundTransparency = 1, Size = UDim2.fromOffset(420, #ITEMS * 46), Position = UDim2.new(0.5, -210, 0.6, 0) }
	)
	highlight = Kit.Frame(list, {
		Size = UDim2.new(1, 0, 0, 36),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		BackgroundColor3 = Color3.fromRGB(150, 110, 45),
		ZIndex = 1,
	})
	Kit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(0.7, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = highlight,
	})
	for i, item in ITEMS do
		local label = Kit.new("TextButton", {
			Text = item,
			Font = Kit.Fonts.Serif,
			TextSize = 26,
			TextColor3 = C.Text,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.fromOffset(0, (i - 1) * 46),
			ZIndex = 2,
			Parent = list,
		})
		label.MouseEnter:Connect(function()
			setSelected(i)
		end)
		label.Activated:Connect(function()
			activate(i)
		end)
		itemLabels[i] = label
	end

	-- Footer: coins + version
	coinsLabel = Kit.Label(mainFrame, "", 18, {
		Size = UDim2.fromOffset(300, 24),
		Position = UDim2.new(1, -324, 1, -78),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Gold,
		Font = Kit.Fonts.Serif,
	})
	Kit.Label(mainFrame, `App {VERSION}`, 16, {
		Size = UDim2.fromOffset(300, 22),
		Position = UDim2.new(1, -324, 1, -50),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(170, 140, 90),
		Font = Kit.Fonts.Serif,
	})

	-- Queue status pill (visible on every page)
	statusPill = Kit.Frame(gui, {
		Size = UDim2.fromOffset(360, 40),
		Position = UDim2.new(0.5, -180, 0, 16),
		BackgroundColor3 = C.Panel,
		Visible = false,
		ZIndex = 20,
	})
	Kit.Corner(statusPill, 20)
	Kit.Stroke(statusPill, C.Gold, 1, 0.3)
	Kit.Label(
		statusPill,
		"",
		15,
		{ Name = "Text", Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(18, 0), ZIndex = 21, Font = Kit.Fonts.Bold }
	)
	Kit.Button(statusPill, "CANCEL", function()
		PlayScreen.LeaveQueue()
	end, { Size = UDim2.fromOffset(86, 28), Position = UDim2.new(1, -94, 0.5, -14), TextSize = 13, ZIndex = 21 })

	local ctx = {
		Back = function()
			openPage(nil)
		end,
		Gui = gui,
	}
	screens.Play = PlayScreen.new(gui, ctx)
	screens.Loadout = LoadoutScreen.new(gui, ctx)
	screens.Shop = ShopScreen.new(gui, ctx)
	screens.Settings = SettingsScreen.new(gui, ctx)
	screens.Info = InfoScreen.new(gui, ctx)

	setSelected(1)
end

local function updateStatus()
	local lobby = State.Lobby
	if lobby.State == "Queue" then
		statusPill.Visible = true
		(statusPill:FindFirstChild("Text") :: TextLabel).Text =
			`Searching {lobby.Mode}  ·  {lobby.QueueCount or 1}/{lobby.QueueNeeded or 2}`
	else
		statusPill.Visible = false
	end
	if lobby.State == "Vote" or lobby.State == "Custom" then
		openPage("Play")
	end
end

---------------------------------------------------------------------------------------------------
-- Camera + visibility
---------------------------------------------------------------------------------------------------

local function inMenu(): boolean
	return not State.InMatch() and not State.POTGPlaying
end

local function onView()
	local visible = inMenu()
	gui.Enabled = visible
	if visible then
		Atmosphere.Apply("Menu")
		refreshAura()
		Anim.Play(LocalPlayer.Character, Animations.MenuIdle, 0.3)
	else
		clearAura()
		Anim.Stop(LocalPlayer.Character, Animations.MenuIdle)
		Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			Workspace.CurrentCamera.CameraSubject = humanoid
		end
	end
end

local function cameraStep()
	if not inMenu() then
		return
	end
	local stage = LocalPlayer:GetAttribute("MenuStage")
	if typeof(stage) ~= "Vector3" then
		return
	end
	if sceneOrigin ~= stage then
		buildScene(stage)
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 55
	local t = os.clock()
	local sway = Vector3.new(math.sin(t * 0.35) * 0.25, math.sin(t * 0.5) * 0.12, 0)
	-- Low, behind the character, looking down the street (the reference composition).
	local eye = stage + Vector3.new(0, 4.3, 10.5) + sway
	local focus = stage + Vector3.new(0, 7.5, -24)
	camera.CFrame = CFrame.lookAt(eye, focus)
end

function MenuController.Init()
	buildUI()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not gui.Enabled or openScreen ~= nil then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Up or key == Enum.KeyCode.W or key == Enum.KeyCode.DPadUp then
			setSelected((selected - 2) % #ITEMS + 1)
		elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S or key == Enum.KeyCode.DPadDown then
			setSelected(selected % #ITEMS + 1)
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			activate(selected)
		end
	end)

	State.DataChanged:Connect(function(data)
		coinsLabel.Text = `{data.Coins} coins`
		if inMenu() then
			refreshAura()
		end
	end)
	State.LobbyChanged:Connect(updateStatus)
	State.ViewChanged:Connect(onView)
	LocalPlayer.CharacterAdded:Connect(function()
		clearAura()
		task.wait(0.5)
		onView()
	end)
	RunService:BindToRenderStep("PowerBattlesMenuCamera", Enum.RenderPriority.Camera.Value + 3, cameraStep)
	onView()
end

return MenuController
