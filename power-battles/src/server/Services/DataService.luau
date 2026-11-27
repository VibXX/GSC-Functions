-- Player save data: DataStore with session locking, autosave, and an in-memory fallback in Studio
-- when API access is off.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Progression = require(Shared.Config.Progression)
local Keybinds = require(Shared.Config.Keybinds)

local DataService = {}

local STORE_NAME = "PowerBattles_PlayerData_v1"
local AUTOSAVE_INTERVAL = 120
local LOCK_EXPIRY = 180
local LOAD_RETRIES = 6

local store: DataStore? = nil
local useMemory = false
local memoryStore = {}

local profiles = {} -- [Player] = { Data, Loaded }
local loadedCallbacks = {}

local function template()
	return {
		Version = 1,
		Coins = Progression.StartingCoins,
		Swords = { [Progression.StarterSword] = { Level = 1, Cards = 0 } },
		Abilities = { [Progression.StarterAbility] = { Level = 1, Cards = 0 } },
		Equipped = { Sword = Progression.StarterSword, Ability = Progression.StarterAbility },
		Pity = { Legendary = 0, Mythic = 0 },
		Stats = { Wins = 0, Losses = 0, Kills = 0, Deaths = 0, Parries = 0, MatchesPlayed = 0 },
		Settings = {
			Keybinds = table.clone(Keybinds.Defaults),
			MasterVolume = 1,
			MusicVolume = 0.6,
			SfxVolume = 1,
			Sensitivity = 1,
			FieldOfView = 70,
			VfxQuality = "High",
			DamageNumbers = true,
			AutoSkipPOTG = false,
			ScreenShake = true,
		},
		PurchaseHistory = {},
	}
end

-- Fill any keys missing from saved data (new fields added in updates).
local function reconcile(data, defaults)
	for key, value in defaults do
		if data[key] == nil then
			data[key] = typeof(value) == "table" and table.clone(value) or value
		elseif
			typeof(value) == "table"
			and typeof(data[key]) == "table"
			and key ~= "Swords"
			and key ~= "Abilities"
			and key ~= "PurchaseHistory"
		then
			reconcile(data[key], value)
		end
	end
	return data
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function isStudioApiError(err: any): boolean
	local message = tostring(err)
	return string.find(message, "StudioAccessToApisNotAllowed") ~= nil
		or string.find(message, "Studio access to APIs") ~= nil
		or string.find(message, "must publish this place") ~= nil
end

local function switchToMemory(reason: any)
	if not useMemory then
		warn("[DataService] Using in-memory data (nothing will save). Reason: " .. tostring(reason))
	end
	useMemory = true
end

local function loadAsync(player: Player)
	if useMemory then
		return memoryStore[player.UserId] or template()
	end
	local key = keyFor(player)
	for attempt = 1, LOAD_RETRIES do
		local lockedElsewhere = false
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(saved)
				saved = saved or template()
				local lock = saved.SessionLock
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < LOCK_EXPIRY and attempt < LOAD_RETRIES then
					lockedElsewhere = true
					return nil -- cancel write, try again shortly
				end
				saved.SessionLock = { JobId = game.JobId, Time = os.time() }
				return saved
			end)
		end)
		if ok and result and not lockedElsewhere then
			return result
		elseif not ok then
			if RunService:IsStudio() and isStudioApiError(result) then
				switchToMemory(result)
				return template()
			end
			warn(`[DataService] load attempt {attempt} failed for {player.Name}: {result}`)
		end
		task.wait(lockedElsewhere and 5 or 2)
	end
	return nil
end

local function saveAsync(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not profile.Loaded then
		return
	end
	local data = profile.Data
	if useMemory then
		memoryStore[player.UserId] = data
		return
	end
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(saved)
			if saved and saved.SessionLock and saved.SessionLock.JobId ~= game.JobId then
				return nil -- another server owns this save now; never overwrite it
			end
			data.SessionLock = (not release) and { JobId = game.JobId, Time = os.time() } or nil
			return data
		end)
	end)
	if not ok then
		warn(`[DataService] save failed for {player.Name}: {err}`)
	end
end

-- Public copy for the client (no lock / purchase internals).
local function publicCopy(data)
	local copy = table.clone(data)
	copy.SessionLock = nil
	copy.PurchaseHistory = nil
	return copy
end

function DataService.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Loaded and profile.Data or nil
end

function DataService.WaitForData(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local data = DataService.Get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

function DataService.Push(player: Player)
	local data = DataService.Get(player)
	if data then
		Net.Event("DataChanged"):FireClient(player, publicCopy(data))
	end
end

-- Mutate a player's data. fn(data) may return a value which is passed back.
function DataService.Update(player: Player, fn)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local result = fn(data)
	DataService.Push(player)
	return result
end

function DataService.SaveNow(player: Player)
	saveAsync(player, false)
end

function DataService.OnLoaded(callback: (Player, any) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		if profile.Loaded then
			task.spawn(callback, player, profile.Data)
		end
	end
end

local function onPlayerAdded(player: Player)
	profiles[player] = { Loaded = false }
	local data = loadAsync(player)
	if not player.Parent then
		return
	end
	if not data then
		player:Kick("Couldn't load your data. Please rejoin in a minute.")
		return
	end
	reconcile(data, template())
	profiles[player] = { Data = data, Loaded = true }
	DataService.Push(player)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, data)
	end
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		switchToMemory(result)
	end

	Net.Function("GetData").OnServerInvoke = function(player)
		local data = DataService.WaitForData(player, 30)
		return data and publicCopy(data) or nil
	end

	Net.Function("SaveSettings").OnServerInvoke = function(player, settings)
		if typeof(settings) ~= "table" then
			return { ok = false }
		end
		return DataService.Update(player, function(data)
			local s = data.Settings
			local function num(key, min, max)
				if typeof(settings[key]) == "number" and settings[key] == settings[key] then
					s[key] = math.clamp(settings[key], min, max)
				end
			end
			local function bool(key)
				if typeof(settings[key]) == "boolean" then
					s[key] = settings[key]
				end
			end
			num("MasterVolume", 0, 1)
			num("MusicVolume", 0, 1)
			num("SfxVolume", 0, 1)
			num("Sensitivity", 0.1, 3)
			num("FieldOfView", 60, 100)
			bool("DamageNumbers")
			bool("AutoSkipPOTG")
			bool("ScreenShake")
			if settings.VfxQuality == "Low" or settings.VfxQuality == "Medium" or settings.VfxQuality == "High" then
				s.VfxQuality = settings.VfxQuality
			end
			if typeof(settings.Keybinds) == "table" then
				for _, action in Keybinds.Actions do
					local bind = settings.Keybinds[action]
					if Keybinds.IsValid(bind) then
						s.Keybinds[action] = bind
					end
				end
			end
			return { ok = true }
		end) or { ok = false }
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		saveAsync(player, true)
		profiles[player] = nil
	end)

	game:BindToClose(function()
		for player in profiles do
			task.spawn(saveAsync, player, true)
		end
		task.wait(RunService:IsStudio() and 1 or 5)
	end)

	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player in profiles do
			task.spawn(saveAsync, player, false)
		end
	end
end

return DataService
