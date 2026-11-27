-- SETTINGS: keybinds (click, then press a key), audio, camera, visuals, gameplay toggles.
-- Changes preview instantly; SAVE sends them to the server (validated + stored in player data).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Keybinds = require(Shared.Config.Keybinds)
local State = require(script.Parent.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local SettingsScreen = {}

-- Sounds should be parented to these SoundGroups (Music / SFX) so the sliders affect them.
local function soundGroup(name: string): SoundGroup
	local group = SoundService:FindFirstChild(name)
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Parent = SoundService
	end
	return group :: SoundGroup
end

function SettingsScreen.Apply(settings)
	soundGroup("Music").Volume = (settings.MasterVolume or 1) * (settings.MusicVolume or 0.6)
	soundGroup("SFX").Volume = (settings.MasterVolume or 1) * (settings.SfxVolume or 1)
end

local function deepCopy(t)
	local out = {}
	for k, v in t do
		out[k] = typeof(v) == "table" and deepCopy(v) or v
	end
	return out
end

function SettingsScreen.new(gui: ScreenGui, ctx)
	local draft
	local listening: string? = nil
	local bindButtons = {}

	local root, content = Kit.Page(gui, "Settings", function()
		listening = nil
		ctx.Back()
	end)

	local scroll = Kit.Scroll(content, { Size = UDim2.new(0.6, 0, 1, -60), Position = UDim2.new(0.2, 0, 0, 0) })
	Kit.List(scroll, nil, 4)
	Kit.Padding(scroll, 8)

	local footer = Kit.Frame(content, { BackgroundTransparency = 1, Size = UDim2.new(0.6, 0, 0, 44), Position = UDim2.new(0.2, 0, 1, -44) })
	Kit.List(footer, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)

	local render -- forward

	local function section(title: string)
		Kit.Label(scroll, title, 22, { Font = Kit.Fonts.Title, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 36) })
	end

	render = function()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		bindButtons = {}
		if not draft then
			return
		end

		section("Keybinds")
		for _, action in Keybinds.Actions do
			local row = Kit.Frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
			Kit.Label(row, Keybinds.Labels[action], 15, { Size = UDim2.new(0.6, 0, 1, 0) })
			bindButtons[action] = Kit.Button(row, Keybinds.Display(draft.Keybinds[action]), function()
				listening = action
				bindButtons[action].Text = "Press a key..."
			end, { Size = UDim2.fromOffset(150, 30), Position = UDim2.new(1, -150, 0.5, -15) })
		end
		Kit.Label(scroll, "Jump is Space. Gamepad: R2 attack, R1 ability, L1 parry, B dash, L3 sprint.", 13, { TextColor3 = C.Muted })

		section("Audio")
		Kit.Slider(scroll, "Master volume", 0, 1, draft.MasterVolume, 0.05, function(v)
			draft.MasterVolume = v
			SettingsScreen.Apply(draft)
		end)
		Kit.Slider(scroll, "Music", 0, 1, draft.MusicVolume, 0.05, function(v)
			draft.MusicVolume = v
			SettingsScreen.Apply(draft)
		end)
		Kit.Slider(scroll, "Sound effects", 0, 1, draft.SfxVolume, 0.05, function(v)
			draft.SfxVolume = v
			SettingsScreen.Apply(draft)
		end)

		section("Camera")
		Kit.Slider(scroll, "Mouse sensitivity", 0.1, 3, draft.Sensitivity, 0.05, function(v)
			draft.Sensitivity = v
			UserInputService.MouseDeltaSensitivity = v
		end)
		Kit.Slider(scroll, "Field of view", 60, 100, draft.FieldOfView, 1, function(v)
			draft.FieldOfView = v
		end)
		Kit.Toggle(scroll, "Screen shake", draft.ScreenShake, function(v)
			draft.ScreenShake = v
		end)

		section("Visuals")
		local qualities = { "Low", "Medium", "High" }
		Kit.Stepper(scroll, "Effects quality", qualities, table.find(qualities, draft.VfxQuality) or 3, function(v)
			return v
		end, function(v)
			draft.VfxQuality = v
		end)
		Kit.Toggle(scroll, "Damage numbers", draft.DamageNumbers, function(v)
			draft.DamageNumbers = v
		end)

		section("Gameplay")
		Kit.Toggle(scroll, "Auto-skip Play of the Game", draft.AutoSkipPOTG, function(v)
			draft.AutoSkipPOTG = v
		end)
	end

	Kit.Button(footer, "RESET DEFAULTS", function()
		draft.Keybinds = table.clone(Keybinds.Defaults)
		draft.MasterVolume, draft.MusicVolume, draft.SfxVolume = 1, 0.6, 1
		draft.Sensitivity, draft.FieldOfView = 1, 70
		draft.VfxQuality, draft.DamageNumbers, draft.AutoSkipPOTG, draft.ScreenShake = "High", true, false, true
		render()
	end, { Size = UDim2.fromOffset(170, 40) })
	Kit.Button(footer, "SAVE", function()
		local res = Net.Function("SaveSettings"):InvokeServer(draft)
		if res and res.ok then
			Kit.Toast("Settings saved", C.Good)
		else
			Kit.Toast("Couldn't save settings", C.Danger)
		end
	end, { Size = UDim2.fromOffset(140, 40), TextColor3 = C.GoldBright })

	UserInputService.InputBegan:Connect(function(input)
		if not listening or not root.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			listening = nil
			render()
			return
		end
		local bind = Keybinds.FromInput(input)
		if bind and Keybinds.IsValid(bind) then
			-- Swap if another action already uses this bind.
			for _, action in Keybinds.Actions do
				if draft.Keybinds[action] == bind and action ~= listening then
					draft.Keybinds[action] = draft.Keybinds[listening]
				end
			end
			draft.Keybinds[listening] = bind
			listening = nil
			render()
		end
	end)

	State.DataChanged:Connect(function(data)
		SettingsScreen.Apply(data.Settings)
	end)

	return {
		Show = function()
			draft = deepCopy(State.Settings())
			root.Visible = true
			render()
		end,
		Hide = function()
			root.Visible = false
			listening = nil
		end,
	}
end

return SettingsScreen
