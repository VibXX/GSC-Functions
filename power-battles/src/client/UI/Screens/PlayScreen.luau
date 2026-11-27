-- PLAY: choose 1v1-5v5 (matchmaking + map vote) or a Custom Game (host picks the rules).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local GameModes = require(Shared.Config.GameModes)
local State = require(script.Parent.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local PlayScreen = {}

function PlayScreen.LeaveQueue()
	Net.Function("LeaveQueue"):InvokeServer()
end

local function result(res)
	if res and not res.ok and res.err then
		Kit.Toast(res.err, C.Danger)
	end
	return res and res.ok
end

function PlayScreen.new(gui: ScreenGui, ctx)
	local root, content = Kit.Page(gui, "Play", function()
		local lobby = State.Lobby.State
		if lobby == "Custom" then
			Net.Function("LeaveCustom"):InvokeServer()
		end
		ctx.Back()
	end)

	-------------------------------------------------------------------------------- Modes
	local modes = Kit.Frame(content, { BackgroundTransparency = 1, Size = UDim2.new(0.55, -12, 1, 0) })
	Kit.Label(modes, "MATCHMAKING", 14, { TextColor3 = C.Muted, Font = Kit.Fonts.Bold, Size = UDim2.new(1, 0, 0, 22) })
	local modeList = Kit.Frame(modes, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -30), Position = UDim2.fromOffset(0, 30) })
	Kit.List(modeList, nil, 10)
	for i, mode in GameModes.Modes do
		local card = Kit.Button(modeList, "", function()
			result(Net.Function("JoinQueue"):InvokeServer(mode.Id))
		end, { Size = UDim2.new(1, 0, 0, 64), LayoutOrder = i })
		Kit.Label(card, mode.Name, 30, { Font = Kit.Fonts.Title, Size = UDim2.new(0, 110, 1, 0), Position = UDim2.fromOffset(18, 0) })
		Kit.Label(
			card,
			mode.Description,
			15,
			{ TextColor3 = C.Muted, Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(140, 0) }
		)
	end

	-------------------------------------------------------------------------------- Custom
	local custom = Kit.Frame(content, {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		Size = UDim2.new(0.45, -12, 1, 0),
		Position = UDim2.new(0.55, 12, 0, 0),
	})
	Kit.Corner(custom, 8)
	Kit.Stroke(custom, C.Line)
	Kit.Padding(custom, 16)
	Kit.Label(custom, "CUSTOM GAMES", 14, { TextColor3 = C.Muted, Font = Kit.Fonts.Bold, Size = UDim2.new(1, 0, 0, 22) })

	-- Browser (not in a lobby)
	local browser = Kit.Frame(custom, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -30), Position = UDim2.fromOffset(0, 30) })
	local lobbyList = Kit.Scroll(browser, { Size = UDim2.new(1, 0, 1, -56) })
	Kit.List(lobbyList, nil, 6)
	local function refreshList()
		for _, child in lobbyList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local list = Net.Function("ListCustom"):InvokeServer() or {}
		if #list == 0 then
			Kit.Label(lobbyList, "No custom games yet. Create one!", 15, { TextColor3 = C.Muted })
		end
		for _, entry in list do
			local row = Kit.Button(lobbyList, "", function()
				result(Net.Function("JoinCustom"):InvokeServer(entry.Id))
			end, { Size = UDim2.new(1, -6, 0, 46) })
			Kit.Label(row, entry.Name, 16, { Font = Kit.Fonts.Bold, Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(12, 0) })
			Kit.Label(row, `{entry.Settings.TeamSize}v{entry.Settings.TeamSize}  ·  {entry.Count}/{entry.Max}`, 14, {
				TextColor3 = C.Muted,
				Size = UDim2.new(0.4, -12, 1, 0),
				Position = UDim2.new(0.6, 0, 0, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
			})
		end
	end
	local browserButtons =
		Kit.Frame(browser, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44) })
	Kit.List(browserButtons, Enum.FillDirection.Horizontal, 10)
	Kit.Button(browserButtons, "CREATE GAME", function()
		result(Net.Function("CreateCustom"):InvokeServer())
	end, { Size = UDim2.new(0.5, -5, 1, 0) })
	Kit.Button(browserButtons, "REFRESH", refreshList, { Size = UDim2.new(0.5, -5, 1, 0) })

	-- Lobby (inside a custom game)
	local lobbyView = Kit.Frame(
		custom,
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -30), Position = UDim2.fromOffset(0, 30), Visible = false }
	)
	local lobbyTitle = Kit.Label(lobbyView, "", 22, { Font = Kit.Fonts.Serif })
	local playersLabel =
		Kit.Label(lobbyView, "", 14, { TextColor3 = C.Muted, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 40) })
	local settingsHolder =
		Kit.Frame(lobbyView, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -130) })
	local lobbyButtons =
		Kit.Frame(lobbyView, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44) })
	Kit.List(lobbyButtons, Enum.FillDirection.Horizontal, 10)
	local startButton = Kit.Button(lobbyButtons, "START", function()
		result(Net.Function("StartCustom"):InvokeServer())
	end, { Size = UDim2.new(0.5, -5, 1, 0) })
	Kit.Button(lobbyButtons, "LEAVE", function()
		Net.Function("LeaveCustom"):InvokeServer()
	end, { Size = UDim2.new(0.5, -5, 1, 0) })

	local currentSettings = nil
	local isHost = false
	local function push(key, value)
		if not isHost or not currentSettings then
			return
		end
		local copy = table.clone(currentSettings)
		copy[key] = value
		result(Net.Function("UpdateCustom"):InvokeServer(copy))
	end

	local function renderSettings(settings)
		for _, child in settingsHolder:GetChildren() do
			child:Destroy()
		end
		Kit.List(settingsHolder, nil, 2)
		local cfg = GameModes.Custom
		local sizes = {}
		for n = cfg.TeamSize.Min, cfg.TeamSize.Max do
			table.insert(sizes, n)
		end
		local rounds = {}
		for n = cfg.RoundsToWin.Min, cfg.RoundsToWin.Max do
			table.insert(rounds, n)
		end
		local maps = { "Vote" }
		for _, map in GameModes.Maps do
			table.insert(maps, map.Id)
		end
		local function opt(label, options, value, fmt, key)
			local row = Kit.Stepper(settingsHolder, label, options, table.find(options, value) or 1, fmt, function(v)
				push(key, v)
			end)
			for _, d in row:GetDescendants() do
				if d:IsA("TextButton") then
					d.Visible = isHost
				end
			end
		end
		opt("Team size", sizes, settings.TeamSize, function(v)
			return `{v}v{v}`
		end, "TeamSize")
		opt("Rounds to win", rounds, settings.RoundsToWin, function(v)
			return `First to {v}`
		end, "RoundsToWin")
		opt("Round time", cfg.RoundTimeOptions, settings.RoundTime, function(v)
			return `{v}s`
		end, "RoundTime")
		opt("Map", maps, settings.Map, function(v)
			return v == "Vote" and "Players vote" or GameModes.MapsById[v].Name
		end, "Map")
		for key, toggle in cfg.Toggles do
			opt(toggle.Label, { true, false }, settings[key], function(v)
				return v and "On" or "Off"
			end, key)
		end
	end

	Net.Event("CustomUpdate").OnClientEvent:Connect(function(update)
		currentSettings = update.Lobby.Settings
		isHost = update.IsHost
		lobbyTitle.Text = update.Lobby.Name
		playersLabel.Text = `Players ({#update.Players}/{update.Lobby.Max}): {table.concat(update.Players, ", ")}`
		startButton.Visible = isHost
		renderSettings(currentSettings)
	end)

	-------------------------------------------------------------------------------- Map vote overlay
	local vote = Kit.Frame(
		root,
		{ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Bg, BackgroundTransparency = 0.05, Visible = false, ZIndex = 30 }
	)
	local voteTitle = Kit.Label(vote, "Vote for a map", 48, {
		Font = Kit.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromScale(0, 0.12),
		ZIndex = 31,
	})
	local voteTimer = Kit.Label(vote, "", 18, {
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0.12, 66),
		ZIndex = 31,
	})
	local cards = Kit.Frame(
		vote,
		{ BackgroundTransparency = 1, Size = UDim2.new(0.8, 0, 0, 220), Position = UDim2.new(0.1, 0, 0.32, 0), ZIndex = 31 }
	)
	Kit.List(cards, Enum.FillDirection.Horizontal, 18, Enum.HorizontalAlignment.Center)
	local voteEndsAt = 0
	local myVote = nil

	Net.Event("MapVote").OnClientEvent:Connect(function(payload)
		voteEndsAt = payload.EndsAt
		voteTitle.Text = (payload.Label and payload.Label ~= "Custom") and `{payload.Label}  ·  Vote for a map` or "Vote for a map"
		for _, child in cards:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for _, option in payload.Options do
			local selected = myVote == option.Id
			local card = Kit.Button(cards, "", function()
				myVote = option.Id
				Net.Function("VoteMap"):InvokeServer(option.Id)
			end, { Size = UDim2.new(1 / #payload.Options, -12, 1, 0), ZIndex = 32, Accent = C.GoldBright })
			if selected then
				Kit.Highlight(card, C.GoldBright)
			end
			Kit.Label(card, option.Name, 28, {
				Font = Kit.Fonts.Title,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.fromOffset(0, 30),
				ZIndex = 33,
			})
			Kit.Label(card, option.Description, 14, {
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -24, 0, 60),
				Position = UDim2.fromOffset(12, 80),
				ZIndex = 33,
			})
			Kit.Label(card, `{payload.Counts[option.Id] or 0} votes`, 18, {
				Font = Kit.Fonts.Bold,
				TextColor3 = C.Gold,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 1, -44),
				ZIndex = 33,
			})
		end
	end)

	RunService.RenderStepped:Connect(function()
		if vote.Visible then
			voteTimer.Text = `Starting in {math.max(0, math.ceil(voteEndsAt - State.ServerNow()))}s`
		end
	end)

	local function syncLobby()
		local s = State.Lobby.State
		vote.Visible = s == "Vote"
		if s ~= "Vote" then
			myVote = nil
		end
		lobbyView.Visible = s == "Custom"
		browser.Visible = s ~= "Custom"
		if s == "Menu" and root.Visible then
			refreshList()
		end
	end
	State.LobbyChanged:Connect(syncLobby)

	return {
		Show = function()
			root.Visible = true
			syncLobby()
			if State.Lobby.State ~= "Custom" then
				task.spawn(refreshList)
			end
		end,
		Hide = function()
			root.Visible = false
		end,
	}
end

return PlayScreen
