-- In-match HUD: round score + timer, health, ability / dash / parry cooldowns, crosshair, kill feed,
-- countdown + round banners, overhead health bars, spectate-on-death, and the end-of-match scoreboard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Abilities = require(Shared.Config.Abilities)
local Rarities = require(Shared.Config.Rarities)
local Keybinds = require(Shared.Config.Keybinds)
local State = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local Atmosphere = require(script.Parent.Parent.Atmosphere)

local LocalPlayer = Players.LocalPlayer
local C = Kit.Colors

local HudController = {}

local gui: ScreenGui
local refs = {}
local overheads = {} -- [Player] = BillboardGui
local spectateTarget: Player? = nil

local function teamColor(team: number?): Color3
	return team == 1 and C.Team1 or C.Team2
end

local function myTeam(): number?
	local match = State.Match
	return match and match.Teams and match.Teams[tostring(LocalPlayer.UserId)]
end

local function banner(text: string, sub: string?, color: Color3?, duration: number?)
	local frame = refs.Banner
	frame.Title.Text = text
	frame.Title.TextColor3 = color or C.Text
	frame.Sub.Text = sub or ""
	frame.Visible = true
	frame.Title.TextTransparency = 1
	frame.Sub.TextTransparency = 1
	TweenService:Create(frame.Title, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	TweenService:Create(frame.Sub, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	local token = os.clock()
	frame:SetAttribute("Token", token)
	task.delay(duration or 1.6, function()
		if frame:GetAttribute("Token") == token then
			TweenService:Create(frame.Title, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			TweenService:Create(frame.Sub, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
	end)
end
HudController.Banner = banner

local function cooldownSlot(parent: Instance, name: string, label: string, size: number, order: number)
	local slot = Kit.Frame(
		parent,
		{ Name = name, Size = UDim2.fromOffset(size, size), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15, LayoutOrder = order }
	)
	Kit.Corner(slot, 8)
	local stroke = Kit.Stroke(slot, C.Line, 2)
	local title = Kit.Label(slot, label, 13, {
		Name = "Title",
		Size = UDim2.new(1, -8, 0, 30),
		Position = UDim2.fromOffset(4, 4),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Bold,
		TextScaled = true,
	})
	local key = Kit.Label(slot, "", 12, {
		Name = "Key",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})
	local shade = Kit.Frame(slot, {
		Name = "Shade",
		Size = UDim2.fromScale(1, 0),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		ZIndex = 2,
	})
	Kit.Corner(shade, 8)
	local timer = Kit.Label(
		slot,
		"",
		18,
		{ Name = "Timer", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Kit.Fonts.Heavy, ZIndex = 3 }
	)
	return { Frame = slot, Stroke = stroke, Title = title, Key = key, Shade = shade, Timer = timer }
end

local function build()
	gui = Kit.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
		DisplayOrder = 5,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
	})

	-- Crosshair
	local cross = Kit.Frame(gui, {
		Name = "Crosshair",
		Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Text,
	})
	Kit.Corner(cross, 3)
	Kit.Stroke(cross, Color3.new(0, 0, 0), 1, 0.4)
	refs.Crosshair = cross

	-- Top: score + timer
	local top = Kit.Frame(gui, {
		Size = UDim2.fromOffset(360, 64),
		Position = UDim2.new(0.5, -180, 0, 14),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
	})
	Kit.Corner(top, 8)
	Kit.Stroke(top, C.Line, 1, 0.2)
	refs.ScoreLeft = Kit.Label(top, "0", 34, {
		Size = UDim2.new(0, 70, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Font = Kit.Fonts.Heavy,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Team1,
	})
	refs.ScoreRight = Kit.Label(top, "0", 34, {
		Size = UDim2.new(0, 70, 1, 0),
		Position = UDim2.new(1, -80, 0, 0),
		Font = Kit.Fonts.Heavy,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Team2,
	})
	refs.Timer = Kit.Label(top, "2:30", 26, {
		Size = UDim2.new(1, -160, 0, 34),
		Position = UDim2.fromOffset(80, 4),
		Font = Kit.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	refs.RoundLabel = Kit.Label(top, "ROUND 1", 13, {
		Size = UDim2.new(1, -160, 0, 18),
		Position = UDim2.fromOffset(80, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
		Font = Kit.Fonts.Bold,
	})

	-- Bottom: health bar
	local healthBack = Kit.Frame(gui, {
		Size = UDim2.fromOffset(420, 18),
		Position = UDim2.new(0.5, -210, 1, -48),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.2,
	})
	Kit.Corner(healthBack, 4)
	Kit.Stroke(healthBack, C.Line, 1)
	refs.HealthFill = Kit.Frame(healthBack, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Good })
	Kit.Corner(refs.HealthFill, 4)
	refs.HealthText = Kit.Label(
		healthBack,
		"150",
		13,
		{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Kit.Fonts.Bold, ZIndex = 2 }
	)

	-- Bottom right: ability + dash + parry
	local slots = Kit.Frame(gui, { BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 92), Position = UDim2.new(1, -316, 1, -110) })
	Kit.List(slots, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	refs.Dash = cooldownSlot(slots, "Dash", "DASH", 64, 1)
	refs.Parry = cooldownSlot(slots, "Parry", "PARRY", 64, 2)
	refs.Ability = cooldownSlot(slots, "Ability", "ABILITY", 90, 3)

	-- Kill feed
	local feed = Kit.Frame(gui, { BackgroundTransparency = 1, Size = UDim2.fromOffset(340, 200), Position = UDim2.new(1, -356, 0, 16) })
	Kit.List(feed, nil, 4, Enum.HorizontalAlignment.Right)
	refs.Feed = feed

	-- Centre banner
	local bannerFrame = Kit.Frame(gui, {
		Name = "Banner",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 140),
		Position = UDim2.new(0, 0, 0.28, 0),
		Visible = false,
	})
	Kit.Label(bannerFrame, "", 72, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 90),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Title,
		TextStrokeTransparency = 0.4,
	})
	Kit.Label(bannerFrame, "", 20, {
		Name = "Sub",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 92),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Serif,
		TextColor3 = C.Muted,
	})
	refs.Banner = bannerFrame

	-- Spectating label
	refs.Spectate = Kit.Label(gui, "", 16, {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 1, -84),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
		Visible = false,
	})

	-- Results / scoreboard
	local results = Kit.Frame(gui, {
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Bg,
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 10,
	})
	refs.ResultTitle = Kit.Label(results, "VICTORY", 96, {
		Size = UDim2.new(1, 0, 0, 110),
		Position = UDim2.fromOffset(0, 40),
		Font = Kit.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 11,
	})
	local board = Kit.Frame(results, {
		Size = UDim2.fromOffset(640, 360),
		Position = UDim2.new(0.5, -320, 0, 170),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		ZIndex = 11,
	})
	Kit.Corner(board, 8)
	Kit.Padding(board, 14)
	Kit.List(board, nil, 4)
	refs.Board = board
	refs.Results = results
end

local function feedEntry(info)
	local row = Kit.Frame(refs.Feed, { Size = UDim2.fromOffset(340, 26), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.3 })
	Kit.Corner(row, 4)
	local def = Abilities.ById[info.Source]
	local how = def and def.Name or (info.Source == "Fall" and "the void" or "blade")
	local text
	if info.Killer then
		text =
			`<font color="#{teamColor(info.KillerTeam):ToHex()}">{info.Killer}</font>  [{how}]  <font color="#{teamColor(info.VictimTeam):ToHex()}">{info.Victim}</font>`
	else
		text = `<font color="#{teamColor(info.VictimTeam):ToHex()}">{info.Victim}</font> fell`
	end
	Kit.Label(row, text, 14, {
		RichText = true,
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(6, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Kit.Fonts.Bold,
	})
	task.delay(5, function()
		row:Destroy()
	end)
end

local function overheadFor(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local existing = overheads[player]
	if existing and existing.Adornee == head then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local bill = Kit.new("BillboardGui", {
		Size = UDim2.fromOffset(120, 34),
		StudsOffset = Vector3.new(0, 2.6, 0),
		AlwaysOnTop = true,
		Adornee = head,
		MaxDistance = 250,
		Parent = gui,
	})
	Kit.Label(bill, player.DisplayName, 13, {
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Bold,
		TextStrokeTransparency = 0.4,
	})
	local back = Kit.Frame(bill, {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.fromOffset(0, 20),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
	})
	Kit.Frame(back, { Name = "Fill", Size = UDim2.fromScale(1, 1) })
	overheads[player] = bill
	return bill
end

local function updateOverheads()
	local match = State.Match
	for player, bill in overheads do
		if not player.Parent or not match then
			bill:Destroy()
			overheads[player] = nil
		end
	end
	if not match then
		return
	end
	for _, player in Players:GetPlayers() do
		local team = match.Teams[tostring(player.UserId)]
		if player ~= LocalPlayer and team then
			local bill = overheadFor(player)
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if bill and humanoid then
				local fill = bill:FindFirstChild("Fill", true) :: Frame
				fill.Size = UDim2.fromScale(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 1)
				fill.BackgroundColor3 = teamColor(team)
				bill.Enabled = humanoid.Health > 0
				(bill:FindFirstChild("Name") :: TextLabel).TextColor3 = teamColor(team)
			end
		end
	end
end

local function updateSlot(slot, name: string, maxDuration: number?)
	local remaining = State.CooldownRemaining(name)
	local cd = State.Cooldowns[name]
	local total = cd and cd.Duration or 1
	if remaining > 0 and total > 0 then
		slot.Shade.Size = UDim2.fromScale(1, remaining / total)
		slot.Timer.Text = remaining >= 1 and tostring(math.ceil(remaining)) or string.format("%.1f", remaining)
	else
		slot.Shade.Size = UDim2.fromScale(1, 0)
		slot.Timer.Text = ""
	end
end

local function updateSpectate()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = Workspace.CurrentCamera
	local match = State.Match
	if humanoid and humanoid.Health <= 0 and match and match.State == "Fighting" then
		local target = spectateTarget
		local targetHumanoid = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if not targetHumanoid or targetHumanoid.Health <= 0 then
			target = nil
			-- Prefer living teammates, then anyone.
			for pass = 1, 2 do
				for _, player in Players:GetPlayers() do
					local team = match.Teams[tostring(player.UserId)]
					local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if player ~= LocalPlayer and team and h and h.Health > 0 and (pass == 2 or team == myTeam()) then
						target = player
						break
					end
				end
				if target then
					break
				end
			end
			spectateTarget = target
		end
		if target and target.Character then
			camera.CameraSubject = target.Character:FindFirstChildOfClass("Humanoid")
			refs.Spectate.Text = "Spectating " .. target.DisplayName
			refs.Spectate.Visible = true
		end
	else
		if spectateTarget then
			spectateTarget = nil
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		refs.Spectate.Visible = false
	end
end

local function update()
	local match = State.Match
	gui.Enabled = State.InMatch() and match ~= nil and not State.POTGPlaying
	if not gui.Enabled then
		return
	end
	-- Score: my team always on the left.
	local mine = myTeam() or 1
	local wins = match.Wins or { 0, 0 }
	refs.ScoreLeft.Text = tostring(wins[mine])
	refs.ScoreRight.Text = tostring(wins[3 - mine])
	refs.ScoreLeft.TextColor3 = teamColor(mine)
	refs.ScoreRight.TextColor3 = teamColor(3 - mine)
	refs.RoundLabel.Text = `ROUND {match.Round}  ·  FIRST TO {match.RoundsToWin}`
	if match.EndsAt and (match.State == "Fighting" or match.State == "Countdown") then
		local left = math.max(0, match.EndsAt - State.ServerNow())
		refs.Timer.Text = match.State == "Countdown" and tostring(math.ceil(left))
			or string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
	else
		refs.Timer.Text = "-"
	end

	local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local pct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		refs.HealthFill.Size = UDim2.fromScale(pct, 1)
		refs.HealthFill.BackgroundColor3 = pct > 0.5 and C.Good or (pct > 0.25 and C.GoldBright or C.Danger)
		refs.HealthText.Text = tostring(math.ceil(humanoid.Health))
	end

	local binds = State.Binds()
	refs.Dash.Key.Text = Keybinds.Display(binds.Dash)
	refs.Parry.Key.Text = Keybinds.Display(binds.Parry)
	refs.Ability.Key.Text = Keybinds.Display(binds.Ability)
	local abilityId = State.Data and State.Data.Equipped.Ability
	local def = abilityId and Abilities.ById[abilityId]
	if def then
		refs.Ability.Title.Text = string.upper(def.Name)
		refs.Ability.Stroke.Color = Rarities.Info[def.Rarity].Color
	end
	refs.Ability.Frame.Visible = match.Abilities ~= false
	updateSlot(refs.Dash, "Dash")
	updateSlot(refs.Parry, "Parry")
	updateSlot(refs.Ability, "Ability")
	refs.Crosshair.Visible = not refs.Spectate.Visible
	updateOverheads()
	updateSpectate()
end

local lastState
local function onMatchChanged(match)
	if not match then
		return
	end
	if match.Style then
		Atmosphere.Apply(match.Style)
	end
	refs.Results.Visible = false
	State.ResultsShowing = false
	if match.State == "Countdown" and lastState ~= "Countdown" then
		banner(`ROUND {match.Round}`, match.MapName, C.Text, 1.4)
		task.delay(1.6, function()
			if State.Match and State.Match.State == "Countdown" then
				banner("READY", nil, C.GoldBright, 1)
			end
		end)
	elseif match.State == "Fighting" and lastState ~= "Fighting" then
		banner("FIGHT", nil, C.GoldBright, 0.9)
	end
	lastState = match.State
end

local function showResults(result)
	State.ResultsShowing = true
	refs.Results.Visible = true
	refs.ResultTitle.Text = result.Draw and "DRAW" or (result.Won and "VICTORY" or "DEFEAT")
	refs.ResultTitle.TextColor3 = result.Draw and C.Text or (result.Won and C.GoldBright or C.Danger)
	for _, child in refs.Board:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local header = Kit.Frame(refs.Board, { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, ZIndex = 12 })
	local cols = { { "PLAYER", 0, 0.4 }, { "K", 0.4, 0.12 }, { "D", 0.52, 0.12 }, { "DMG", 0.64, 0.18 }, { "PARRIES", 0.82, 0.18 } }
	for _, col in cols do
		Kit.Label(header, col[1], 13, {
			Size = UDim2.new(col[3], 0, 1, 0),
			Position = UDim2.new(col[2], 0, 0, 0),
			TextColor3 = C.Muted,
			Font = Kit.Fonts.Bold,
			ZIndex = 12,
		})
	end
	table.sort(result.Scoreboard, function(a, b)
		if a.Team ~= b.Team then
			return a.Team < b.Team
		end
		return a.Kills > b.Kills
	end)
	for _, entry in result.Scoreboard do
		local row = Kit.Frame(
			refs.Board,
			{ Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.4, ZIndex = 12 }
		)
		Kit.Corner(row, 4)
		local values = { entry.Name, entry.Kills, entry.Deaths, entry.Damage, entry.Parries }
		for i, col in cols do
			Kit.Label(row, tostring(values[i]), 14, {
				Size = UDim2.new(col[3], 0, 1, 0),
				Position = UDim2.new(col[2], i == 1 and 8 or 0, 0, 0),
				TextColor3 = i == 1 and teamColor(entry.Team) or C.Text,
				Font = i == 1 and Kit.Fonts.Bold or Kit.Fonts.Body,
				ZIndex = 12,
			})
		end
	end
end

function HudController.Init()
	build()
	State.MatchChanged:Connect(onMatchChanged)
	Net.Event("KillFeed").OnClientEvent:Connect(feedEntry)
	Net.Event("RoundResult").OnClientEvent:Connect(function(result)
		local mine = myTeam()
		if result.Winner == 0 then
			banner("DRAW", `Round {result.Round}`, C.Text, 2.5)
		elseif result.Winner == mine then
			banner("ROUND WON", `Round {result.Round}`, C.GoldBright, 2.5)
		else
			banner("ROUND LOST", `Round {result.Round}`, C.Danger, 2.5)
		end
	end)
	Net.Event("MatchResult").OnClientEvent:Connect(showResults)
	Net.Event("Notify").OnClientEvent:Connect(function(text)
		Kit.Toast(text)
	end)
	State.ViewChanged:Connect(function()
		if not State.InMatch() then
			refs.Results.Visible = false
			State.ResultsShowing = false
			lastState = nil
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return HudController
