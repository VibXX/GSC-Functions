-- Lobby + match flow.
--   Menu  -> PLAY -> pick a mode (1v1..5v5) -> queue -> map vote -> match
--   Menu  -> PLAY -> CUSTOM -> create/join a lobby, host sets rules -> map vote (or fixed map) -> match
--   Match -> best of N rounds -> (Play of the Game after each round) -> chests -> back to menu
--
-- Several matches can run per server at once; each gets its own arena slot far apart in Workspace.
-- Players in the menu stand on their own private "stage" far away from the arenas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local GameModes = require(Shared.Config.GameModes)
local Combat = require(Shared.Config.Combat)
local MapBuilder = require(script.Parent.Parent.Modules.MapBuilder)

local MatchService = {}
local S

local MENU_ORIGIN = Vector3.new(0, 800, 20000)
local MENU_SPACING = 400
local ARENA_SPACING = 2000

local playerMatch = {} -- [Player] = Match
local lobby = {} -- [Player] = { State = "Menu" | "Queue" | "Vote" | "Custom" | "Match", ... }
local queues = {} -- [modeId] = { Player }
local customs = {} -- [id] = custom lobby
local nextCustomId = 0
local menuSlots = {} -- [Player] = index
local arenaSlots = {} -- [index] = Match
local arenasFolder: Folder

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------

local function notify(player: Player, text: string)
	Net.Event("Notify"):FireClient(player, text)
end

local function sendLobby(player: Player)
	local state = lobby[player] or { State = "Menu" }
	local payload = { State = state.State, Mode = state.Mode, CustomId = state.CustomId }
	if state.State == "Queue" and state.Mode then
		local q = queues[state.Mode] or {}
		payload.QueueCount = #q
		payload.QueueNeeded = GameModes.ById[state.Mode].TeamSize * 2
	end
	Net.Event("LobbyState"):FireClient(player, payload)
end

local function setLobby(player: Player, state)
	lobby[player] = state
	sendLobby(player)
end

local function menuPosition(player: Player): Vector3
	local index = menuSlots[player]
	if not index then
		local used = {}
		for _, i in menuSlots do
			used[i] = true
		end
		index = 0
		while used[index] do
			index += 1
		end
		menuSlots[player] = index
	end
	return MENU_ORIGIN + Vector3.new(index * MENU_SPACING, 0, 0)
end

local function loadCharacter(player: Player): Model?
	if not player.Parent then
		return nil
	end
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("[MatchService] LoadCharacter failed: " .. tostring(err))
		return nil
	end
	local character = player.Character
	if character then
		character:WaitForChild("HumanoidRootPart", 10)
		character:WaitForChild("Humanoid", 10)
	end
	return character
end

-- Respawn a player on their menu stage, anchored, sword in hand.
local function spawnToMenu(player: Player)
	local character = loadCharacter(player)
	if not character or playerMatch[player] then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then
		return
	end
	character:PivotTo(CFrame.new(menuPosition(player) + Vector3.new(0, 3, 0)))
	root.Anchored = true
	player:SetAttribute("InMatch", false)
	player:SetAttribute("MenuStage", menuPosition(player))
	S.LoadoutService.Dress(player, true)
end

local function removeFromQueues(player: Player)
	for modeId, q in queues do
		local index = table.find(q, player)
		if index then
			table.remove(q, index)
			for _, other in q do
				sendLobby(other)
			end
		end
	end
end

local function activeMatchCount(): number
	local n = 0
	for _ in arenaSlots do
		n += 1
	end
	return n
end

local function reserveSlot(match): number?
	if activeMatchCount() >= GameModes.Rules.MaxConcurrentMatches then
		return nil
	end
	local index = 0
	while arenaSlots[index] do
		index += 1
	end
	arenaSlots[index] = match
	return index
end

---------------------------------------------------------------------------------------------------
-- Match
---------------------------------------------------------------------------------------------------

local Match = {}
Match.__index = Match

local matchCounter = 0

function Match.new(players: { Player }, settings, mapId: string, label: string)
	matchCounter += 1
	local self = setmetatable({}, Match)
	self.Id = matchCounter
	self.Label = label
	self.Settings = settings
	self.MapId = mapId
	self.MapInfo = GameModes.MapsById[mapId] or GameModes.Maps[1]
	self.Players = table.clone(players)
	self.Team = {}
	self.Wins = { 0, 0 }
	self.Round = 0
	self.State = "Starting"
	self.Alive = {}
	self.Stats = {}
	self.Active = false

	-- Shuffle then alternate teams.
	local shuffled = table.clone(players)
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	for i, player in shuffled do
		self.Team[player] = (i % 2 == 1) and 1 or 2
		self.Stats[player] = { Kills = 0, Deaths = 0, Damage = 0, Parries = 0, AbilitiesCast = 0 }
	end
	return self
end

function Match:TeamOf(player: Player): number?
	return self.Team[player]
end

function Match:EnemiesOf(player: Player): { Player }
	local team = self.Team[player]
	local out = {}
	for _, other in self.Players do
		if self.Team[other] ~= team then
			table.insert(out, other)
		end
	end
	return out
end

function Match:AddStat(player: Player, key: string, amount: number)
	local stats = self.Stats[player]
	if stats then
		stats[key] = (stats[key] or 0) + amount
	end
end

function Match:TeamCount(team: number): number
	local n = 0
	for _, player in self.Players do
		if self.Team[player] == team then
			n += 1
		end
	end
	return n
end

function Match:Broadcast(extra)
	local teams = {}
	local names = {}
	for _, player in self.Players do
		teams[tostring(player.UserId)] = self.Team[player]
		names[tostring(player.UserId)] = player.DisplayName
	end
	local payload = {
		State = self.State,
		Round = self.Round,
		Wins = self.Wins,
		RoundsToWin = self.Settings.RoundsToWin,
		Teams = teams,
		Names = names,
		Label = self.Label,
		MapId = self.MapInfo.Id,
		MapName = self.MapInfo.Name,
		Style = self.MapInfo.Style,
		Abilities = self.Settings.Abilities,
		Origin = self.Origin,
	}
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	Net.FireList("MatchState", self.Players, payload)
end

function Match:LoadMap()
	if self.Map then
		self.Map:Destroy()
	end
	if self.DebrisFolder then
		self.DebrisFolder:Destroy()
	end
	self.Map = MapBuilder.Load(self.MapId, self.Origin)
	self.Map.Parent = self.Folder
	local debris = Instance.new("Folder")
	debris.Name = "Debris"
	debris.Parent = self.Folder
	self.DebrisFolder = debris
end

function Match:SpawnPoint(player: Player, index: number): CFrame
	local spawns = self.Map:FindFirstChild("Spawns")
	local folder = spawns and spawns:FindFirstChild("Team" .. self.Team[player])
	local points = folder and folder:GetChildren() or {}
	if #points == 0 then
		local x = self.Team[player] == 1 and -100 or 100
		return CFrame.lookAt(self.Origin + Vector3.new(x, 4, index * 8), self.Origin + Vector3.new(0, 4, index * 8))
	end
	local point = points[((index - 1) % #points) + 1] :: BasePart
	return point.CFrame + Vector3.new(0, 3, 0)
end

function Match:OnDied(player: Player)
	if not self.Alive[player] then
		return
	end
	self.Alive[player] = false
	self:AddStat(player, "Deaths", 1)
	local killer, source = S.CombatService.GetLastAttacker(player)
	if killer and self.Team[killer] and self.Team[killer] ~= self.Team[player] then
		self:AddStat(killer, "Kills", 1)
		S.POTGService.Log(self, { Type = "Kill", Actor = killer.UserId, Target = player.UserId })
	end
	Net.FireList("KillFeed", self.Players, {
		Killer = killer and killer.DisplayName,
		KillerTeam = killer and self.Team[killer],
		Victim = player.DisplayName,
		VictimTeam = self.Team[player],
		Source = source and (source.Id or source.Type) or "Fall",
	})
end

function Match:SpawnAll()
	local teamIndex = { 0, 0 }
	local pending = 0
	for _, player in self.Players do
		local team = self.Team[player]
		teamIndex[team] += 1
		local index = teamIndex[team]
		pending += 1
		task.spawn(function()
			local character = loadCharacter(player)
			if character and self.Active and table.find(self.Players, player) then
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if root and humanoid then
					character:PivotTo(self:SpawnPoint(player, index))
					root.Anchored = true
					S.LoadoutService.Dress(player, false)
					self.Alive[player] = true
					humanoid.Died:Connect(function()
						self:OnDied(player)
					end)
				end
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + 15
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

function Match:SetAnchored(anchored: boolean)
	for _, player in self.Players do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			root.Anchored = anchored
		end
	end
end

function Match:AliveOnTeam(team: number): number
	local n = 0
	for _, player in self.Players do
		if self.Team[player] == team and self.Alive[player] then
			n += 1
		end
	end
	return n
end

-- Plays one round. Returns winning team (1/2) or 0 for a draw.
function Match:PlayRound(): number
	self.State = "Loading"
	self.Alive = {}
	self:LoadMap()
	self:SpawnAll()
	if not self.Active then
		return 0
	end

	self.State = "Countdown"
	self:Broadcast({ EndsAt = Workspace:GetServerTimeNow() + GameModes.Rules.CountdownTime })
	S.POTGService.BeginRound(self)
	task.wait(GameModes.Rules.CountdownTime)
	self:SetAnchored(false)

	self.State = "Fighting"
	local roundEnds = Workspace:GetServerTimeNow() + self.Settings.RoundTime
	self:Broadcast({ EndsAt = roundEnds })

	local killY = self.Origin.Y + Combat.KillY
	while self.Active do
		task.wait(0.1)
		for _, player in self.Players do
			if self.Alive[player] then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not root or not humanoid then
					self.Alive[player] = false
				elseif root.Position.Y < killY then
					humanoid.Health = 0
				end
			end
		end
		local alive1, alive2 = self:AliveOnTeam(1), self:AliveOnTeam(2)
		if alive1 == 0 and alive2 == 0 then
			return 0
		elseif alive1 == 0 then
			return 2
		elseif alive2 == 0 then
			return 1
		end
		if Workspace:GetServerTimeNow() >= roundEnds then
			-- Time out: team with more total health % wins.
			local health = { 0, 0 }
			for _, player in self.Players do
				local humanoid = self.Alive[player] and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					health[self.Team[player]] += humanoid.Health / humanoid.MaxHealth
				end
			end
			if math.abs(health[1] - health[2]) < 0.01 then
				return 0
			end
			return health[1] > health[2] and 1 or 2
		end
	end
	return 0
end

function Match:Run()
	self.Active = true
	self.Folder = Instance.new("Folder")
	self.Folder.Name = "Match" .. self.Id
	self.Folder.Parent = arenasFolder
	self.Origin = Vector3.new(self.Slot * ARENA_SPACING, 0, 0)

	for _, player in self.Players do
		playerMatch[player] = self
		setLobby(player, { State = "Match" })
		player:SetAttribute("InMatch", true)
		player:SetAttribute("Team", self.Team[player])
	end

	local toWin = self.Settings.RoundsToWin
	while self.Active and self.Wins[1] < toWin and self.Wins[2] < toWin do
		self.Round += 1
		local winner = self:PlayRound()
		if not self.Active then
			break
		end
		if winner > 0 then
			self.Wins[winner] += 1
		end
		-- Forfeit if a whole team left.
		for team = 1, 2 do
			if self:TeamCount(team) == 0 then
				self.Wins[3 - team] = toWin
			end
		end
		self.State = "RoundEnd"
		self:Broadcast()
		Net.FireList("RoundResult", self.Players, { Winner = winner, Wins = self.Wins, Round = self.Round })
		task.wait(GameModes.Rules.RoundEndDelay)
		if self.Settings.POTG then
			self.State = "POTG"
			self:Broadcast()
			S.POTGService.Present(self)
		end
		self.Recording = nil
	end
	self:Finish()
end

function Match:Finish()
	self.State = "MatchEnd"
	local winnerTeam = 0
	if self.Wins[1] > self.Wins[2] then
		winnerTeam = 1
	elseif self.Wins[2] > self.Wins[1] then
		winnerTeam = 2
	end
	self:Broadcast({ WinnerTeam = winnerTeam })

	local scoreboard = {}
	for _, player in self.Players do
		local stats = self.Stats[player]
		table.insert(scoreboard, {
			Name = player.DisplayName,
			Team = self.Team[player],
			Kills = stats.Kills,
			Deaths = stats.Deaths,
			Damage = math.floor(stats.Damage),
			Parries = stats.Parries,
		})
	end
	for _, player in self.Players do
		local won = self.Team[player] == winnerTeam
		local stats = self.Stats[player]
		S.DataService.Update(player, function(data)
			data.Stats.MatchesPlayed += 1
			data.Stats.Kills += stats.Kills
			data.Stats.Deaths += stats.Deaths
			data.Stats.Parries += stats.Parries
			if won then
				data.Stats.Wins += 1
			else
				data.Stats.Losses += 1
			end
		end)
		Net.Event("MatchResult"):FireClient(player, {
			Won = won,
			Draw = winnerTeam == 0,
			WinnerTeam = winnerTeam,
			Wins = self.Wins,
			Scoreboard = scoreboard,
		})
		task.spawn(S.ChestService.Grant, player, won and "Victory" or "Defeat", "Match")
	end

	task.wait(GameModes.Rules.MatchEndDelay)
	self:Cleanup()
end

function Match:Cleanup()
	self.Active = false
	self.Recording = nil
	for _, player in self.Players do
		playerMatch[player] = nil
		player:SetAttribute("InMatch", false)
		player:SetAttribute("Team", nil)
		setLobby(player, { State = "Menu" })
		task.spawn(spawnToMenu, player)
	end
	if self.Folder then
		self.Folder:Destroy()
	end
	arenaSlots[self.Slot] = nil
	MatchService.TryStartQueues()
end

function Match:RemovePlayer(player: Player)
	local index = table.find(self.Players, player)
	if index then
		table.remove(self.Players, index)
	end
	self.Alive[player] = nil
	playerMatch[player] = nil
	if #self.Players == 0 and self.Active then
		self.Active = false
		if self.Folder then
			self.Folder:Destroy()
		end
		arenaSlots[self.Slot] = nil
	end
end

local function launchMatch(players: { Player }, settings, mapId: string, label: string)
	local match = Match.new(players, settings, mapId, label)
	local slot = reserveSlot(match)
	while not slot do
		for _, player in players do
			notify(player, "Waiting for a free arena...")
		end
		task.wait(2)
		slot = reserveSlot(match)
	end
	match.Slot = slot
	-- Players may have left while waiting.
	for i = #match.Players, 1, -1 do
		if not match.Players[i].Parent then
			table.remove(match.Players, i)
		end
	end
	if match:TeamCount(1) == 0 or match:TeamCount(2) == 0 then
		arenaSlots[slot] = nil
		for _, player in match.Players do
			setLobby(player, { State = "Menu" })
			notify(player, "Match cancelled - not enough players.")
		end
		return
	end
	match:Run()
end

---------------------------------------------------------------------------------------------------
-- Map vote
---------------------------------------------------------------------------------------------------

local function pickMapOptions(count: number): { string }
	local pool = {}
	for _, map in GameModes.Maps do
		table.insert(pool, map.Id)
	end
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(count, #pool) do
		table.insert(out, pool[i])
	end
	return out
end

local function voteCounts(session)
	local counts = {}
	for _, mapId in session.Votes do
		counts[mapId] = (counts[mapId] or 0) + 1
	end
	return counts
end

local function sendVote(session)
	local options = {}
	for _, id in session.Options do
		local info = GameModes.MapsById[id]
		table.insert(options, { Id = id, Name = info.Name, Description = info.Description, Style = info.Style })
	end
	Net.FireList(
		"MapVote",
		session.Players,
		{ Options = options, EndsAt = session.EndsAt, Counts = voteCounts(session), Label = session.Label }
	)
end

-- requeueMode: for matchmade games, players go back to the front of this queue if someone leaves.
local function startVote(players: { Player }, settings, label: string, requeueMode: string?)
	if settings.Map and settings.Map ~= "Vote" and GameModes.MapsById[settings.Map] then
		for _, player in players do
			setLobby(player, { State = "Match" })
		end
		task.spawn(launchMatch, players, settings, settings.Map, label)
		return
	end
	local session = {
		Players = table.clone(players),
		Options = pickMapOptions(3),
		Votes = {},
		EndsAt = Workspace:GetServerTimeNow() + GameModes.Rules.MapVoteTime,
		Settings = settings,
		Label = label,
	}
	for _, player in players do
		setLobby(player, { State = "Vote", Vote = session })
	end
	sendVote(session)

	task.delay(GameModes.Rules.MapVoteTime, function()
		local present = {}
		for _, player in session.Players do
			if player.Parent and lobby[player] and lobby[player].Vote == session then
				table.insert(present, player)
			end
		end
		local needed = requeueMode and GameModes.ById[requeueMode].TeamSize * 2 or 2
		if #present < needed then
			for _, player in present do
				if requeueMode then
					local q = queues[requeueMode]
					table.insert(q, 1, player)
					setLobby(player, { State = "Queue", Mode = requeueMode })
					notify(player, "A player left - back in queue.")
				else
					setLobby(player, { State = "Menu" })
					notify(player, "Not enough players to start.")
				end
			end
			if requeueMode then
				MatchService.TryStartQueues()
			end
			return
		end
		-- Tally (random tiebreak).
		local counts = voteCounts(session)
		local best, bestCount = {}, -1
		for _, id in session.Options do
			local c = counts[id] or 0
			if c > bestCount then
				best, bestCount = { id }, c
			elseif c == bestCount then
				table.insert(best, id)
			end
		end
		local mapId = best[math.random(1, #best)]
		for _, player in present do
			setLobby(player, { State = "Match" })
		end
		launchMatch(present, settings, mapId, label)
	end)
end

---------------------------------------------------------------------------------------------------
-- Matchmaking queues
---------------------------------------------------------------------------------------------------

function MatchService.TryStartQueues()
	for _, mode in GameModes.Modes do
		local q = queues[mode.Id]
		local needed = mode.TeamSize * 2
		while #q >= needed and activeMatchCount() < GameModes.Rules.MaxConcurrentMatches do
			local players = {}
			for _ = 1, needed do
				table.insert(players, table.remove(q, 1))
			end
			startVote(players, GameModes.DefaultMatchSettings(mode.TeamSize), mode.Name, mode.Id)
		end
		for _, player in q do
			sendLobby(player)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Custom games
---------------------------------------------------------------------------------------------------

local function customSummary(custom)
	return {
		Id = custom.Id,
		Name = custom.Name,
		Host = custom.Host.DisplayName,
		Count = #custom.Players,
		Max = custom.Settings.TeamSize * 2,
		Settings = custom.Settings,
	}
end

local function sendCustom(custom)
	local names = {}
	for _, player in custom.Players do
		table.insert(names, player.DisplayName)
	end
	for _, player in custom.Players do
		Net.Event("CustomUpdate"):FireClient(player, {
			Lobby = customSummary(custom),
			Players = names,
			IsHost = player == custom.Host,
		})
	end
end

local function leaveCustom(player: Player)
	local state = lobby[player]
	local custom = state and state.CustomId and customs[state.CustomId]
	if not custom then
		return
	end
	local index = table.find(custom.Players, player)
	if index then
		table.remove(custom.Players, index)
	end
	if #custom.Players == 0 then
		customs[custom.Id] = nil
	else
		if custom.Host == player then
			custom.Host = custom.Players[1]
			notify(custom.Host, "You are now the host.")
		end
		sendCustom(custom)
	end
end

local function validateCustomSettings(input, playerCount: number)
	local defaults = GameModes.DefaultCustomSettings()
	local out = {}
	local c = GameModes.Custom
	local teamSize = tonumber(input.TeamSize) or defaults.TeamSize
	out.TeamSize = math.clamp(math.floor(teamSize), c.TeamSize.Min, c.TeamSize.Max)
	if out.TeamSize * 2 < playerCount then
		return nil, "Too many players for that team size."
	end
	out.RoundsToWin = math.clamp(math.floor(tonumber(input.RoundsToWin) or defaults.RoundsToWin), c.RoundsToWin.Min, c.RoundsToWin.Max)
	out.RoundTime = table.find(c.RoundTimeOptions, input.RoundTime) and input.RoundTime or defaults.RoundTime
	out.Map = (input.Map == "Vote" or GameModes.MapsById[input.Map]) and input.Map or "Vote"
	for key, toggle in c.Toggles do
		if typeof(input[key]) == "boolean" then
			out[key] = input[key]
		else
			out[key] = toggle.Default
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- Public API used by other services
---------------------------------------------------------------------------------------------------

function MatchService.GetMatch(player: Player)
	return playerMatch[player]
end

function MatchService.CanFight(player: Player): boolean
	local match = playerMatch[player]
	return match ~= nil and match.State == "Fighting" and match.Alive[player] == true
end

function MatchService.AreEnemies(a: Player, b: Player): boolean
	local match = playerMatch[a]
	return match ~= nil and match == playerMatch[b] and match.Team[a] ~= match.Team[b]
end

---------------------------------------------------------------------------------------------------

function MatchService.Init(services)
	S = services
	for _, mode in GameModes.Modes do
		queues[mode.Id] = {}
	end
	arenasFolder = Instance.new("Folder")
	arenasFolder.Name = "Arenas"
	arenasFolder.Parent = Workspace
end

function MatchService.Start()
	local function inMenu(player: Player): boolean
		local state = lobby[player]
		return state ~= nil and state.State == "Menu"
	end

	Net.Function("JoinQueue").OnServerInvoke = function(player, modeId)
		if typeof(modeId) ~= "string" or not GameModes.ById[modeId] then
			return { ok = false, err = "Unknown mode" }
		end
		if not inMenu(player) then
			return { ok = false, err = "You're already busy." }
		end
		table.insert(queues[modeId], player)
		setLobby(player, { State = "Queue", Mode = modeId })
		MatchService.TryStartQueues()
		return { ok = true }
	end

	Net.Function("LeaveQueue").OnServerInvoke = function(player)
		local state = lobby[player]
		if state and state.State == "Queue" then
			removeFromQueues(player)
			setLobby(player, { State = "Menu" })
		end
		return { ok = true }
	end

	Net.Function("VoteMap").OnServerInvoke = function(player, mapId)
		local state = lobby[player]
		local session = state and state.Vote
		if not session or typeof(mapId) ~= "string" or not table.find(session.Options, mapId) then
			return { ok = false }
		end
		session.Votes[player] = mapId
		sendVote(session)
		return { ok = true }
	end

	Net.Function("ListCustom").OnServerInvoke = function()
		local list = {}
		for _, custom in customs do
			table.insert(list, customSummary(custom))
		end
		table.sort(list, function(a, b)
			return a.Id < b.Id
		end)
		return list
	end

	Net.Function("CreateCustom").OnServerInvoke = function(player)
		if not inMenu(player) then
			return { ok = false, err = "You're already busy." }
		end
		local count = 0
		for _ in customs do
			count += 1
		end
		if count >= GameModes.Custom.MaxLobbies then
			return { ok = false, err = "Too many custom games on this server." }
		end
		nextCustomId += 1
		local custom = {
			Id = nextCustomId,
			Name = player.DisplayName .. "'s Game",
			Host = player,
			Players = { player },
			Settings = GameModes.DefaultCustomSettings(),
		}
		customs[custom.Id] = custom
		setLobby(player, { State = "Custom", CustomId = custom.Id })
		sendCustom(custom)
		return { ok = true, id = custom.Id }
	end

	Net.Function("JoinCustom").OnServerInvoke = function(player, id)
		local custom = customs[id]
		if not custom then
			return { ok = false, err = "That game no longer exists." }
		end
		if not inMenu(player) then
			return { ok = false, err = "You're already busy." }
		end
		if #custom.Players >= custom.Settings.TeamSize * 2 then
			return { ok = false, err = "That game is full." }
		end
		table.insert(custom.Players, player)
		setLobby(player, { State = "Custom", CustomId = custom.Id })
		sendCustom(custom)
		return { ok = true }
	end

	Net.Function("LeaveCustom").OnServerInvoke = function(player)
		leaveCustom(player)
		setLobby(player, { State = "Menu" })
		return { ok = true }
	end

	Net.Function("UpdateCustom").OnServerInvoke = function(player, settings)
		local state = lobby[player]
		local custom = state and state.CustomId and customs[state.CustomId]
		if not custom or custom.Host ~= player or typeof(settings) ~= "table" then
			return { ok = false, err = "Only the host can change settings." }
		end
		local validated, err = validateCustomSettings(settings, #custom.Players)
		if not validated then
			return { ok = false, err = err }
		end
		custom.Settings = validated
		sendCustom(custom)
		return { ok = true }
	end

	Net.Function("StartCustom").OnServerInvoke = function(player)
		local state = lobby[player]
		local custom = state and state.CustomId and customs[state.CustomId]
		if not custom or custom.Host ~= player then
			return { ok = false, err = "Only the host can start." }
		end
		if #custom.Players < 2 then
			return { ok = false, err = "Need at least 2 players." }
		end
		customs[custom.Id] = nil
		startVote(custom.Players, custom.Settings, "Custom")
		return { ok = true }
	end

	S.DataService.OnLoaded(function(player)
		setLobby(player, { State = "Menu" })
		spawnToMenu(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeFromQueues(player)
		leaveCustom(player)
		local match = playerMatch[player]
		if match then
			match:RemovePlayer(player)
		end
		lobby[player] = nil
		menuSlots[player] = nil
	end)
end

return MatchService
