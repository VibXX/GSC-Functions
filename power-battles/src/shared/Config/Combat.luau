-- Movement + combat tuning. All timings in seconds, distances in studs.

return {
	MaxHealth = 150,

	WalkSpeed = 16,
	SprintSpeed = 26,
	JumpPower = 50,
	DoubleJumpPower = 58,
	AirJumps = 1,

	Dash = {
		Distance = 24,
		Duration = 0.18,
		IFrames = 0.28, -- can't be hit during this window
		Cooldown = 1.4,
	},

	Parry = {
		Window = 0.25, -- active parry frames
		LatencyGrace = 0.1, -- extra server-side window to account for ping
		Cooldown = 1.0, -- refunded on a successful parry
		StunAttacker = 1.0, -- melee attackers that get parried are stunned
		FacingDot = -0.2, -- must roughly face the attacker (dot product threshold)
	},

	ComboResetTime = 1.0,
	HitboxHeight = 6,

	Ragdoll = {
		ImmunityAfter = 0.6, -- can't be re-ragdolled immediately after standing up
		MaxDuration = 2.5,
	},

	KillY = -120, -- relative to arena origin
	LastHitCreditTime = 8, -- fall deaths credit the last attacker within this window

	ShiftLockOffset = Vector3.new(1.75, 0.6, 0),
	SprintFovBoost = 8,

	-- Sword weld offset relative to the R15 RightGripAttachment. Blade points along the handle's +Y.
	SwordGripOffset = CFrame.new(),
	MenuGripOffset = CFrame.Angles(math.rad(-70), 0, 0), -- blade hangs down, like a resting pose
}
