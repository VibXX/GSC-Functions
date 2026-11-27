-- Chest opening: shows after the match results (or right away for shop purchases).
-- Click the chest -> it shakes, bursts open -> coins, then each card drop is revealed in rarity order.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Chests = require(Shared.Config.Chests)
local Rarities = require(Shared.Config.Rarities)
local Catalog = require(Shared.Lib.Catalog)
local State = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)

local LocalPlayer = Players.LocalPlayer
local C = Kit.Colors

local ChestController = {}

local queue = {}
local showing = false
local gui: ScreenGui

local function tween(obj, time, props, style)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function canShow(): boolean
	return not State.InMatch() and not State.POTGPlaying
end

local function dropCard(parent: Instance, drop, order: number)
	local rarity = Rarities.Info[drop.Rarity]
	local theme = Catalog.Theme(drop.Kind, drop.Id)
	local card = Kit.Frame(
		parent,
		{ Size = UDim2.fromOffset(170, 230), BackgroundColor3 = C.Panel, LayoutOrder = order, BackgroundTransparency = 1 }
	)
	Kit.Corner(card, 10)
	local stroke = Kit.Stroke(card, rarity.Color, 3, 1)
	local glow = Kit.Frame(card, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rarity.Color, BackgroundTransparency = 1 })
	Kit.Corner(glow, 10)
	Kit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.6, 1), Parent = glow })

	local items = {}
	local function add(inst)
		table.insert(items, inst)
		return inst
	end
	local swatch = add(Kit.Frame(card, {
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.new(0.5, -30, 0, 22),
		BackgroundColor3 = theme.Primary,
		BackgroundTransparency = 1,
	}))
	Kit.Corner(swatch, 30)
	Kit.new("UIGradient", { Color = ColorSequence.new(theme.Secondary or theme.Primary, theme.Primary), Rotation = 45, Parent = swatch })
	add(Kit.Label(card, string.upper(drop.Rarity), 12, {
		Font = Kit.Fonts.Bold,
		TextColor3 = rarity.Color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 92),
		TextTransparency = 1,
	}))
	add(Kit.Label(card, drop.Name, 18, {
		Font = Kit.Fonts.Serif,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(6, 112),
		Size = UDim2.new(1, -12, 0, 44),
		TextTransparency = 1,
	}))
	add(
		Kit.Label(
			card,
			drop.Kind == "Sword" and "Sword" or "Ability",
			12,
			{ TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 154), TextTransparency = 1 }
		)
	)
	local headline = drop.Unlocked and "NEW!" or `+{drop.Cards} cards`
	add(Kit.Label(card, headline, 20, {
		Font = Kit.Fonts.Heavy,
		TextColor3 = drop.Unlocked and C.GoldBright or C.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 176),
		TextTransparency = 1,
	}))
	local progress = drop.CardsNeeded and `Lv {drop.Level} · {drop.TotalCards}/{drop.CardsNeeded}` or `Lv {drop.Level} · MAX`
	add(Kit.Label(card, progress, 12, {
		TextColor3 = (drop.CardsNeeded and drop.TotalCards >= drop.CardsNeeded) and C.GoldBright or C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 204),
		TextTransparency = 1,
	}))

	-- Reveal
	card.Size = UDim2.fromOffset(120, 160)
	tween(card, 0.35, { Size = UDim2.fromOffset(170, 230), BackgroundTransparency = 0 }, Enum.EasingStyle.Back)
	tween(stroke, 0.35, { Transparency = 0 })
	tween(glow, 0.2, { BackgroundTransparency = 0 })
	for _, inst in items do
		if inst:IsA("TextLabel") then
			tween(inst, 0.35, { TextTransparency = 0 })
		else
			tween(inst, 0.35, { BackgroundTransparency = 0 })
		end
	end
end

local function show(result)
	showing = true
	gui.Enabled = true
	local root = gui:FindFirstChild("Root")
	if root then
		root:Destroy()
	end
	local chestInfo = Chests.Types[result.Chest]
	root = Kit.Frame(gui, { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Bg, BackgroundTransparency = 0.08 })
	Kit.Label(root, chestInfo.Name, 64, {
		Font = Kit.Fonts.Title,
		TextColor3 = chestInfo.Color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.fromScale(0, 0.1),
	})
	local hint = Kit.Label(
		root,
		"Click the chest to open it",
		16,
		{ TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0.1, 84) }
	)

	-- Chest drawing: body + lid + lock.
	local chest = Kit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(220, 170),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = root,
	})
	local body = Kit.Frame(
		chest,
		{ Size = UDim2.new(1, 0, 0.62, 0), Position = UDim2.fromScale(0, 0.38), BackgroundColor3 = Color3.fromRGB(70, 44, 26) }
	)
	Kit.Corner(body, 6)
	Kit.Stroke(body, chestInfo.Color, 3)
	local lid = Kit.Frame(chest, { Size = UDim2.new(1, 0, 0.4, 0), BackgroundColor3 = Color3.fromRGB(86, 54, 32), ZIndex = 2 })
	Kit.Corner(lid, 14)
	Kit.Stroke(lid, chestInfo.Color, 3)
	local lock = Kit.Frame(
		chest,
		{ Size = UDim2.fromOffset(30, 36), Position = UDim2.new(0.5, -15, 0.3, 0), BackgroundColor3 = chestInfo.Color, ZIndex = 3 }
	)
	Kit.Corner(lock, 4)
	local flash =
		Kit.Frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 20 })

	local row = Kit.Frame(
		root,
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 240), Position = UDim2.new(0, 0, 0.42, 0), Visible = false }
	)
	Kit.List(row, Enum.FillDirection.Horizontal, 18, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local coins = Kit.Label(root, "", 28, {
		Font = Kit.Fonts.Serif,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.32, 0),
		Size = UDim2.new(1, 0, 0, 36),
		Visible = false,
	})
	local continueButton = Kit.Button(root, "CONTINUE", function()
		gui.Enabled = false
		showing = false
		root:Destroy()
		ChestController.Next()
	end, { Size = UDim2.fromOffset(200, 44), Position = UDim2.new(0.5, -100, 0.85, 0), Visible = false })

	local opened = false
	chest.Activated:Connect(function()
		if opened then
			return
		end
		opened = true
		hint.Text = ""
		for i = 1, 6 do
			chest.Rotation = (i % 2 == 0) and 6 or -6
			task.wait(0.06 + i * 0.01)
		end
		chest.Rotation = 0
		tween(lid, 0.25, { Position = UDim2.new(0, 0, -0.5, 0), Rotation = -18 }, Enum.EasingStyle.Back)
		flash.BackgroundTransparency = 0.1
		tween(flash, 0.5, { BackgroundTransparency = 1 })
		task.wait(0.35)
		tween(chest, 0.3, { Position = UDim2.new(0.5, 0, 0.82, 0), Size = UDim2.fromOffset(110, 85) })
		coins.Visible = true
		coins.Text = `+{result.Coins} coins`
		row.Visible = true
		for i, drop in result.Drops do
			dropCard(row, drop, i)
			task.wait(Rarities.Info[drop.Rarity].Index >= 4 and 0.9 or 0.5)
		end
		chest.Visible = false
		continueButton.Visible = true
	end)
end

function ChestController.Next()
	if showing or #queue == 0 or not canShow() then
		return
	end
	show(table.remove(queue, 1))
end

function ChestController.Init()
	gui = Kit.new("ScreenGui", {
		Name = "Chests",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
		DisplayOrder = 40,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
	})
	Net.Event("ChestResult").OnClientEvent:Connect(function(result)
		table.insert(queue, result)
		ChestController.Next()
	end)
	State.ViewChanged:Connect(function()
		task.wait(0.6) -- let the menu fade in first
		ChestController.Next()
	end)
end

return ChestController
