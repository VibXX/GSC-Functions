-- Play of the Game playback. Builds local "ghost" clones of the players involved, moves them along
-- the recorded root CFrames, replays the logged combat events through FxController, and follows
-- the featured player with a cinematic camera. Skippable (keybind or button).
--
-- Note: the replay plays on the map as it is now (already damaged). Replaying the destruction
-- itself would require recording each debris piece; see docs/GAME_DESIGN.md for the v2 plan.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Keybinds = require(Shared.Config.Keybinds)
local Swords = require(Shared.Config.Swords)
local Anim = require(Shared.Lib.Anim)
local VFX = require(Shared.Lib.VFX)
local State = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local FxController = require(script.Parent.FxController)

local LocalPlayer = Players.LocalPlayer
local C = Kit.Colors

local POTGController = {}

-- Default R15 Animate-script animations, used to make ghosts look alive.
local RUN_ANIM = "rbxassetid://507767714"
local IDLE_ANIM = "rbxassetid://507766666"

local gui: ScreenGui
local nameLabel: TextLabel
local titleLabel: TextLabel
local playing = nil -- current session

local function makeGhost(character: Model): Model?
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, ghost = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or not ghost then
		return nil
	end
	for _, d in ghost:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ForceField") then
			d:Destroy()
		elseif d.Name == "RagdollSocket" or d.Name == "RagdollA0" or d.Name == "RagdollA1" then
			d:Destroy()
		elseif d:IsA("Motor6D") then
			d.Enabled = true
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = false
		end
	end
	local root = ghost:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then
		ghost:Destroy()
		return nil
	end
	root.Anchored = true
	local humanoid = ghost:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.PlatformStand = true
		humanoid.Health = humanoid.MaxHealth
	end
	ghost:SetAttribute("Ragdolled", nil)
	ghost.Parent = VFX.Container()
	return ghost
end

local function setRealCharactersHidden(hidden: boolean)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = hidden and 1 or 0
				end
			end
		end
	end
end

local function stop()
	local session = playing
	if not session then
		return
	end
	playing = nil
	session.Conn:Disconnect()
	for _, ghost in session.Ghosts do
		ghost:Destroy()
	end
	FxController.ClearAll()
	setRealCharactersHidden(false)
	gui.Enabled = false
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	State.POTGPlaying = false
	State.ViewChanged:Fire()
	Net.Event("SkipPOTG"):FireServer()
end

local function playerById(id: number?): Player?
	return id and Players:GetPlayerByUserId(id) or nil
end

local function play(payload)
	if playing then
		stop()
	end
	if #payload.Frames < 2 then
		Net.Event("SkipPOTG"):FireServer()
		return
	end
	State.POTGPlaying = true
	State.ViewChanged:Fire()
	FxController.ClearAll()

	-- Ghosts for everyone who appears in the clip.
	local ghosts = {}
	local seen = {}
	for _, frame in payload.Frames do
		for key in frame.P do
			seen[key] = true
		end
	end
	for key in seen do
		local player = playerById(tonumber(key))
		if player and player.Character then
			local ghost = makeGhost(player.Character)
			if ghost then
				ghosts[key] = ghost
				Anim.Play(ghost, IDLE_ANIM, 0)
			end
		end
	end
	setRealCharactersHidden(true)

	local function resolve(player: Player?): Model?
		return player and ghosts[tostring(player.UserId)] or nil
	end

	nameLabel.Text = payload.FeaturedName
	titleLabel.Text = payload.Title
	gui.Enabled = true

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local featuredKey = tostring(payload.Featured)
	local frames, events = payload.Frames, payload.Events
	local nextEvent = 1
	local lastPositions = {}
	local start = os.clock()

	local session = { Ghosts = ghosts }
	session.Conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - start
		if t >= payload.Duration then
			stop()
			return
		end
		-- Interpolate root CFrames.
		local i = 1
		while i < #frames and frames[i + 1].T <= t do
			i += 1
		end
		local a, b = frames[i], frames[math.min(i + 1, #frames)]
		local alpha = b.T > a.T and math.clamp((t - a.T) / (b.T - a.T), 0, 1) or 0
		for key, ghost in ghosts do
			local root = ghost:FindFirstChild("HumanoidRootPart") :: BasePart
			local cfA, cfB = a.P[key], b.P[key]
			if root and (cfA or cfB) then
				local cf = (cfA and cfB) and cfA:Lerp(cfB, alpha) or (cfA or cfB)
				root.CFrame = cf
				local last = lastPositions[key]
				local speed = last and ((cf.Position - last) * Vector3.new(1, 0, 1)).Magnitude / math.max(dt, 1e-3) or 0
				lastPositions[key] = cf.Position
				if speed > 4 then
					Anim.Play(ghost, RUN_ANIM, 0.15)
				else
					Anim.Stop(ghost, RUN_ANIM, 0.2)
				end
			end
		end
		-- Fire events up to now.
		while nextEvent <= #events and events[nextEvent].T <= t do
			local e = events[nextEvent]
			nextEvent += 1
			local actor = playerById(e.Actor)
			if e.Type == "Swing" and actor then
				FxController.SwordSwing({
					Player = actor,
					Combo = e.Combo,
					Finisher = e.Finisher,
					Sword = e.Sword or "InitiatesBlade",
					Range = e.Range or Swords.GetStats(e.Sword or "InitiatesBlade", 1, true).Range,
				}, resolve)
			elseif e.Type == "Ability" and e.Fx then
				local fx = table.clone(e.Fx)
				fx.ReplayElapsed = 0
				FxController.AbilityStart(fx, resolve, true)
			elseif e.Type == "Impact" and e.Fx then
				FxController.AbilityImpact(e.Fx, true)
			elseif e.Type == "Damage" then
				local victim = playerById(e.Target)
				local ghost = resolve(victim)
				local root = ghost and ghost:FindFirstChild("HumanoidRootPart") :: BasePart
				FxController.Hit({
					Type = "Hit",
					Victim = victim,
					Attacker = actor,
					Amount = e.Amount or 0,
					Source = e.Source,
					Position = root and root.Position,
				}, resolve)
			elseif e.Type == "Parry" then
				FxController.Parry({ Victim = actor, Attacker = playerById(e.Target), Success = true }, resolve)
			elseif e.Type == "Dash" then
				FxController.Dash(resolve(actor))
			elseif e.Type == "DoubleJump" then
				FxController.DoubleJump(resolve(actor))
			elseif e.Type == "Kill" then
				local victimGhost = resolve(playerById(e.Target))
				if victimGhost then
					VFX.Flash(victimGhost, Color3.fromRGB(255, 60, 60), 0.6)
					task.delay(0.6, function()
						if victimGhost.Parent then
							for _, d in victimGhost:GetDescendants() do
								if d:IsA("BasePart") then
									VFX.Tween(d, 0.5, { Transparency = 1 })
								end
							end
						end
					end)
				end
			end
		end
		-- Over-the-shoulder camera on the featured player.
		local featured = ghosts[featuredKey]
		local froot = featured and featured:FindFirstChild("HumanoidRootPart") :: BasePart
		if froot then
			local desired = froot.CFrame * CFrame.new(3, 4, 11)
			local focus = froot.Position + froot.CFrame.LookVector * 20 + Vector3.new(0, 2, 0)
			local target = CFrame.lookAt(desired.Position, focus)
			camera.CFrame = camera.CFrame:Lerp(target, math.clamp(dt * 6, 0, 1))
		end
	end)
	playing = session
	-- Snap camera on first frame.
	local featured = ghosts[featuredKey]
	local froot = featured and featured:FindFirstChild("HumanoidRootPart") :: BasePart
	if froot then
		camera.CFrame = CFrame.lookAt((froot.CFrame * CFrame.new(3, 4, 11)).Position, froot.Position)
	end
end

local function build()
	gui = Kit.new("ScreenGui", {
		Name = "POTG",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
		DisplayOrder = 30,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
	})
	-- Letterbox bars
	Kit.Frame(gui, { Size = UDim2.new(1, 0, 0.09, 0), BackgroundColor3 = Color3.new(0, 0, 0) })
	Kit.Frame(gui, { Size = UDim2.new(1, 0, 0.09, 0), Position = UDim2.fromScale(0, 0.91), BackgroundColor3 = Color3.new(0, 0, 0) })
	local card = Kit.Frame(gui, { BackgroundTransparency = 1, Size = UDim2.fromOffset(600, 140), Position = UDim2.new(0, 40, 0.11, 0) })
	Kit.Label(card, "Play of the Game", 46, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 52), TextStrokeTransparency = 0.5 })
	nameLabel = Kit.Label(card, "", 32, {
		Font = Kit.Fonts.Serif,
		TextColor3 = C.GoldBright,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 40),
		TextStrokeTransparency = 0.5,
	})
	titleLabel = Kit.Label(
		card,
		"",
		16,
		{ Font = Kit.Fonts.Bold, TextColor3 = C.Muted, Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 22) }
	)
	local skip = Kit.Button(gui, "SKIP", function()
		stop()
	end, { Size = UDim2.fromOffset(150, 36), Position = UDim2.new(1, -190, 0.91, 8) })
	State.DataChanged:Connect(function()
		skip.Text = `SKIP  [{Keybinds.Display(State.Binds().SkipPOTG)}]`
	end)
end

function POTGController.Init()
	build()
	Net.Event("POTG").OnClientEvent:Connect(function(payload)
		if State.Settings().AutoSkipPOTG then
			Net.Event("SkipPOTG"):FireServer()
			return
		end
		local wait = (payload.StartsAt or 0) - State.ServerNow()
		if wait > 0 then
			task.wait(math.min(wait, 1))
		end
		play(payload)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if playing and not processed and Keybinds.Matches(input, "SkipPOTG", State.Binds()) then
			stop()
		end
	end)
	-- Match ended / left: make sure nothing is stuck.
	State.ViewChanged:Connect(function()
		if playing and not State.InMatch() then
			stop()
		end
	end)
end

return POTGController
