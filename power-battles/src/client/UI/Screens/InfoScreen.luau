-- INFORMATION: quick how-to-play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Keybinds = require(Shared.Config.Keybinds)
local Combat = require(Shared.Config.Combat)
local Chests = require(Shared.Config.Chests)
local State = require(script.Parent.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local InfoScreen = {}

local function sections()
	local b = State.Binds()
	local key = function(action)
		return Keybinds.Display(b[action])
	end
	return {
		{
			"The Goal",
			"Teams of 1 to 5 fight to the death on a map you can tear apart - only the floor survives. Wipe out the other team to win the round. First team to win 2 rounds (best of 3) takes the match.",
		},
		{
			"Controls",
			`Attack: {key("Attack")} (hold to keep swinging)   ·   Ability: {key("Ability")} (fires where you aim)   ·   Parry: {key(
				"Parry"
			)}   ·   Dash: {key("Dash")}   ·   Sprint: hold {key("Sprint")}   ·   Double jump: Space in the air. Shift lock is always on in matches. Rebind in Settings.`,
		},
		{
			"Sword Combat",
			`Your sword is your main weapon. Swings chain into a combo; the last hit is a heavy finisher. Rarer swords hit harder and carry passives like burn, lifesteal or chain lightning.`,
		},
		{
			"Parry",
			`Press parry just before a hit lands ({math.floor(Combat.Parry.Window * 1000)} ms window) while facing the attacker. A sword parry stuns the attacker for {Combat.Parry.StunAttacker}s and refunds your parry. Projectiles that hit a parry are deflected. Miss it and you're on a {Combat.Parry.Cooldown}s cooldown.`,
		},
		{
			"Dash",
			`Dashing makes you untouchable for {math.floor(Combat.Dash.IFrames * 1000)} ms (i-frames). Use it to slip through abilities and swings. {Combat.Dash.Cooldown}s cooldown.`,
		},
		{
			"Abilities",
			"Every ability goes where your crosshair points and ragdolls whoever it hits. They also blow holes in the map, so use them to open new routes or drop a tower on someone.",
		},
		{
			"Chests & Cards",
			`Every match ends with a chest: a Victory Chest for winning ({Chests.Types.Victory.Drops} card drops, better odds) or a Defeat Chest for losing ({Chests.Types.Defeat.Drops} drop). The first card of an item unlocks it. Extra cards plus coins level it up for a small buff. Bad luck protection guarantees a Legendary within {Chests.Pity.Legendary} chests and a Mythic within {Chests.Pity.Mythic}.`,
		},
		{
			"Rarities",
			"Common · Uncommon · Rare · Epic · Legendary · Mythic. There are 25 swords and 25 abilities. The rarer, the stronger and flashier.",
		},
		{ "Play of the Game", `After each round the best moment is replayed for everyone. Press {key("SkipPOTG")} to skip.` },
	}
end

function InfoScreen.new(gui: ScreenGui, ctx)
	local root, content = Kit.Page(gui, "Information", ctx.Back)
	local scroll = Kit.Scroll(content, { Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromScale(0.2, 0) })
	Kit.List(scroll, nil, 6)

	local function render()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for _, s in sections() do
			Kit.Label(scroll, s[1], 26, { Font = Kit.Fonts.Title, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 34) })
			local body =
				Kit.Label(scroll, s[2], 16, { TextColor3 = C.Text, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
			body.LineHeight = 1.15
		end
	end

	return {
		Show = function()
			root.Visible = true
			render()
		end,
		Hide = function()
			root.Visible = false
		end,
	}
end

return InfoScreen
