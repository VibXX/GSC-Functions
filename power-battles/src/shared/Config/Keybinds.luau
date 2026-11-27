-- Rebindable actions. Binds are stored as strings: an Enum.KeyCode name ("Q") or an
-- Enum.UserInputType mouse name ("MouseButton1"). Jump stays on the Humanoid's default (Space / A).

local Keybinds = {}

Keybinds.Actions = { "Attack", "Ability", "Parry", "Dash", "Sprint", "SkipPOTG" }

Keybinds.Labels = {
	Attack = "Sword Attack",
	Ability = "Use Ability",
	Parry = "Parry",
	Dash = "Dash",
	Sprint = "Sprint (hold)",
	SkipPOTG = "Skip Play of the Game",
}

Keybinds.Defaults = {
	Attack = "MouseButton1",
	Ability = "E",
	Parry = "F",
	Dash = "Q",
	Sprint = "LeftShift",
	SkipPOTG = "X",
}

-- Fixed gamepad layout.
Keybinds.Gamepad = {
	Attack = Enum.KeyCode.ButtonR2,
	Ability = Enum.KeyCode.ButtonR1,
	Parry = Enum.KeyCode.ButtonL1,
	Dash = Enum.KeyCode.ButtonB,
	Sprint = Enum.KeyCode.ButtonL3,
	SkipPOTG = Enum.KeyCode.ButtonY,
}

local MOUSE = { MouseButton1 = true, MouseButton2 = true, MouseButton3 = true }
local BLOCKED = { Escape = true, Space = true, Unknown = true, W = true, A = true, S = true, D = true, Slash = true, Backquote = true }

function Keybinds.IsValid(bind: any): boolean
	if typeof(bind) ~= "string" or #bind > 32 then
		return false
	end
	if MOUSE[bind] then
		return true
	end
	if BLOCKED[bind] then
		return false
	end
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[bind]
	end)
	return ok and code ~= nil
end

function Keybinds.FromInput(input: InputObject): string?
	if MOUSE[input.UserInputType.Name] then
		return input.UserInputType.Name
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		return input.KeyCode.Name
	end
	return nil
end

function Keybinds.Matches(input: InputObject, action: string, binds: { [string]: string }?): boolean
	local bind = (binds and binds[action]) or Keybinds.Defaults[action]
	if Keybinds.Gamepad[action] and input.KeyCode == Keybinds.Gamepad[action] then
		return true
	end
	if MOUSE[bind] then
		return input.UserInputType.Name == bind
	end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == bind
end

function Keybinds.Display(bind: string): string
	if bind == "MouseButton1" then
		return "LMB"
	elseif bind == "MouseButton2" then
		return "RMB"
	elseif bind == "MouseButton3" then
		return "MMB"
	end
	return bind
end

return Keybinds
