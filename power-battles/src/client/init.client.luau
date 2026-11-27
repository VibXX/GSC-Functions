-- Power Battles client bootstrap.

local ORDER = {
	"FxController",
	"MovementController",
	"ShiftLockController",
	"CombatController",
	"HudController",
	"MenuController",
	"POTGController",
	"ChestController",
}

local State = require(script.ClientState)
State.Init()

for _, name in ORDER do
	local controller = require(script.Controllers[name])
	if controller.Init then
		controller.Init()
	end
end
