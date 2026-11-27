-- Play of the Game. During each round the server records every fighter's root CFrame at 10 Hz plus
-- a log of combat events (swings, casts, hits, kills, parries). When the round ends it scores every
-- sliding window, picks the best player + moment, and sends that slice to the clients, who replay
-- it with ghost copies of the characters. Players can skip; the round continues when everyone has
-- skipped or the clip ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local GameModes = require(Shared.Config.GameModes)

local POTGService = {}
local S

local SAMPLE_RATE = 0.1
local MIN_SCORE = 40

local SCORE = {
	Kill = 100,
	Damage = 1.2, -- per point of damage
	Parry = 45,
	MultiKill = { [2] = 80, [3] = 220, [4] = 400, [5] = 650 },
}

local TITLES = {
	[1] = "ELIMINATION",
	[2] = "DOUBLE ELIMINATION",
	[3] = "TRIPLE ELIMINATION",
	[4] = "QUAD ELIMINATION",
	[5] = "TEAM WIPE",
}

function POTGService.BeginRound(match)
	match.Recording = { Start = os.clock(), Frames = {}, Events = {} }
	task.spawn(function()
		local recording = match.Recording
		while match.Recording == recording and match.Active do
			local frame = { T = os.clock() - recording.Start, P = {} }
			for _, player in match.Players do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
				if root then
					frame.P[tostring(player.UserId)] = root.CFrame
				end
			end
			table.insert(recording.Frames, frame)
			task.wait(SAMPLE_RATE)
		end
	end)
end

function POTGService.Log(match, event)
	if not match or not match.Recording then
		return
	end
	event.T = os.clock() - match.Recording.Start
	table.insert(match.Recording.Events, event)
end

local function scoreWindow(events, actor: number, startT: number, endT: number)
	local score, kills, damage = 0, 0, 0
	for _, event in events do
		if event.T >= startT and event.T <= endT and event.Actor == actor then
			if event.Type == "Kill" then
				kills += 1
			elseif event.Type == "Damage" then
				damage += event.Amount or 0
			elseif event.Type == "Parry" then
				score += SCORE.Parry
			end
		end
	end
	score += kills * SCORE.Kill + damage * SCORE.Damage + (SCORE.MultiKill[math.min(kills, 5)] or 0)
	return score, kills
end

-- Finds the best (actor, window). Candidate windows end shortly after each kill / big hit.
function POTGService.Pick(match)
	local recording = match.Recording
	if not recording then
		return nil
	end
	local length = match.Settings.POTGLength or GameModes.Rules.POTGLength
	local best
	for _, event in recording.Events do
		if (event.Type == "Kill" or event.Type == "Damage") and event.Actor then
			local endT = event.T + 1.5
			local startT = math.max(0, endT - length)
			local score, kills = scoreWindow(recording.Events, event.Actor, startT, endT)
			if not best or score > best.Score then
				best = { Actor = event.Actor, Start = startT, Finish = endT, Score = score, Kills = kills }
			end
		end
	end
	if not best or best.Score < MIN_SCORE then
		return nil
	end
	return best
end

-- Builds the replay payload and waits until it has finished playing or every player skipped.
function POTGService.Present(match)
	local pick = POTGService.Pick(match)
	if not pick then
		return
	end
	local recording = match.Recording
	match.Recording = nil -- stop sampling

	local frames, events = {}, {}
	for _, frame in recording.Frames do
		if frame.T >= pick.Start and frame.T <= pick.Finish then
			table.insert(frames, { T = frame.T - pick.Start, P = frame.P })
		end
	end
	for _, event in recording.Events do
		if event.T >= pick.Start and event.T <= pick.Finish then
			local copy = table.clone(event)
			copy.T -= pick.Start
			table.insert(events, copy)
		end
	end

	local featured
	for _, player in match.Players do
		if player.UserId == pick.Actor then
			featured = player
		end
	end
	local duration = pick.Finish - pick.Start
	local payload = {
		Featured = pick.Actor,
		FeaturedName = featured and featured.DisplayName or "Unknown",
		Title = TITLES[math.min(pick.Kills, 5)] or "HIGHLIGHT",
		Duration = duration,
		Frames = frames,
		Events = events,
		StartsAt = Workspace:GetServerTimeNow() + 0.5,
	}

	match.POTGSkips = {}
	Net.FireList("POTG", match.Players, payload)
	local deadline = os.clock() + duration + 2
	while os.clock() < deadline and match.Active do
		local everyoneSkipped = true
		for _, player in match.Players do
			if player.Parent and not match.POTGSkips[player] then
				everyoneSkipped = false
				break
			end
		end
		if everyoneSkipped then
			break
		end
		task.wait(0.1)
	end
	match.POTGSkips = nil
end

function POTGService.Init(services)
	S = services
end

function POTGService.Start()
	Net.Event("SkipPOTG").OnServerEvent:Connect(function(player)
		local match = S.MatchService.GetMatch(player)
		if match and match.POTGSkips then
			match.POTGSkips[player] = true
		end
	end)
end

return POTGService
