-- Client-side store: profile data, lobby state, match state, local cooldowns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Lib.Signal)
local Keybinds = require(Shared.Config.Keybinds)

local LocalPlayer = Players.LocalPlayer

local State = {
	Data = nil,
	Lobby = { State = "Menu" },
	Match = nil,
	Cooldowns = {}, -- [name] = { Start, Duration }
	POTGPlaying = false,
	ResultsShowing = false,

	DataChanged = Signal.new(),
	LobbyChanged = Signal.new(),
	MatchChanged = Signal.new(),
	CooldownChanged = Signal.new(),
	ViewChanged = Signal.new(), -- menu / match / potg / results visibility changes
}

function State.Settings()
	return State.Data and State.Data.Settings
		or {
			Keybinds = Keybinds.Defaults,
			MasterVolume = 1,
			MusicVolume = 0.6,
			SfxVolume = 1,
			Sensitivity = 1,
			FieldOfView = 70,
			VfxQuality = "High",
			DamageNumbers = true,
			AutoSkipPOTG = false,
			ScreenShake = true,
		}
end

function State.Binds()
	return State.Settings().Keybinds or Keybinds.Defaults
end

function State.InMatch(): boolean
	return LocalPlayer:GetAttribute("InMatch") == true
end

function State.StartCooldown(name: string, duration: number)
	State.Cooldowns[name] = { Start = os.clock(), Duration = duration }
	State.CooldownChanged:Fire(name)
end

function State.CooldownRemaining(name: string): number
	local cd = State.Cooldowns[name]
	if not cd then
		return 0
	end
	return math.max(0, cd.Start + cd.Duration - os.clock())
end

function State.ServerNow(): number
	return Workspace:GetServerTimeNow()
end

function State.Init()
	Net.Event("DataChanged").OnClientEvent:Connect(function(data)
		State.Data = data
		State.DataChanged:Fire(data)
	end)
	Net.Event("LobbyState").OnClientEvent:Connect(function(lobby)
		State.Lobby = lobby
		State.LobbyChanged:Fire(lobby)
	end)
	Net.Event("MatchState").OnClientEvent:Connect(function(match)
		State.Match = match
		State.MatchChanged:Fire(match)
	end)
	Net.Event("Cooldown").OnClientEvent:Connect(function(name, duration)
		State.StartCooldown(name, duration)
	end)
	LocalPlayer:GetAttributeChangedSignal("InMatch"):Connect(function()
		if not State.InMatch() then
			State.Match = nil
		end
		State.ViewChanged:Fire()
	end)
	task.spawn(function()
		local data = Net.Function("GetData"):InvokeServer()
		if data then
			State.Data = data
			State.DataChanged:Fire(data)
		end
	end)
end

return State
