local GameModes = {}

GameModes.Modes = {
	{ Id = "1v1", Name = "1v1", TeamSize = 1, Description = "Pure duel. No excuses." },
	{ Id = "2v2", Name = "2v2", TeamSize = 2, Description = "Partner up." },
	{ Id = "3v3", Name = "3v3", TeamSize = 3, Description = "Small squad brawl." },
	{ Id = "4v4", Name = "4v4", TeamSize = 4, Description = "Team warfare." },
	{ Id = "5v5", Name = "5v5", TeamSize = 5, Description = "Total chaos. Bring the whole map down." },
}

GameModes.ById = {}
for _, mode in GameModes.Modes do
	GameModes.ById[mode.Id] = mode
end

-- Default rules for matchmade games.
GameModes.Rules = {
	RoundsToWin = 2, -- best of 3
	RoundTime = 150, -- seconds before the round times out
	CountdownTime = 3,
	RoundEndDelay = 3,
	POTGLength = 8, -- seconds of footage in Play of the Game
	MapVoteTime = 12,
	MatchEndDelay = 7, -- time on the results / chest screen before returning to menu
	MaxConcurrentMatches = 4, -- per server
}

-- Options the host of a custom game can change.
GameModes.Custom = {
	MaxLobbies = 6,
	TeamSize = { Min = 1, Max = 5, Default = 1 },
	RoundsToWin = { Min = 1, Max = 5, Default = 2 },
	RoundTimeOptions = { 60, 90, 150, 240 },
	Toggles = {
		Abilities = { Default = true, Label = "Abilities" },
		Destruction = { Default = true, Label = "Map Destruction" },
		CardLevels = { Default = true, Label = "Card Level Buffs" },
		POTG = { Default = true, Label = "Play of the Game" },
	},
}

function GameModes.DefaultCustomSettings()
	local settings = {
		TeamSize = GameModes.Custom.TeamSize.Default,
		RoundsToWin = GameModes.Custom.RoundsToWin.Default,
		RoundTime = GameModes.Rules.RoundTime,
		Map = "Vote",
	}
	for key, toggle in GameModes.Custom.Toggles do
		settings[key] = toggle.Default
	end
	return settings
end

function GameModes.DefaultMatchSettings(teamSize: number)
	local settings = GameModes.DefaultCustomSettings()
	settings.TeamSize = teamSize
	settings.RoundsToWin = GameModes.Rules.RoundsToWin
	return settings
end

-- Map pool. If ServerStorage.Maps.<Id> exists it's used as the map; otherwise MapBuilder
-- procedurally generates a destructible arena using Style.
GameModes.Maps = {
	{
		Id = "ProvingGrounds",
		Name = "Proving Grounds",
		Description = "Concrete training yard. Plenty to break.",
		Style = "Concrete",
		Seed = 11,
	},
	{ Id = "AshenTown", Name = "Ashen Town", Description = "A dead brick town at dusk.", Style = "Brick", Seed = 27 },
	{ Id = "FrostHollow", Name = "Frost Hollow", Description = "Frozen ruins in a snowy basin.", Style = "Frost", Seed = 43 },
	{
		Id = "GothicQuarter",
		Name = "Gothic Quarter",
		Description = "Narrow streets between tall stone houses.",
		Style = "Gothic",
		Seed = 58,
	},
}

GameModes.MapsById = {}
for _, map in GameModes.Maps do
	GameModes.MapsById[map.Id] = map
end

return GameModes
