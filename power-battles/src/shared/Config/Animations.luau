-- Custom animation IDs. Upload your animations (R15) and paste the rbxassetid here.
-- Empty strings are skipped safely, so the game runs before the animations exist.

return {
	-- Movement
	Sprint = "",
	DashForward = "",
	DashBack = "",
	DashLeft = "",
	DashRight = "",
	DoubleJump = "",

	-- Sword (combo index = position in the list; the last swing of a combo is the finisher)
	Swings = { "", "", "", "", "" },
	SwordIdle = "",
	Parry = "",
	ParrySuccess = "",
	Stunned = "",

	-- Abilities (by Kind, overridable per ability Id)
	Cast = {
		Projectile = "",
		Beam = "",
		Nova = "",
		Cone = "",
		Meteor = "",
		Line = "",
		Blink = "",
		Vortex = "",
	},
	CastById = {
		-- Fireball = "rbxassetid://...",
	},

	-- Main menu pose
	MenuIdle = "",
}
