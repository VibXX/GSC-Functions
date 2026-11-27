-- LOADOUT: browse all 25 swords / 25 abilities, see card progress, equip and level up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rarities = require(Shared.Config.Rarities)
local Swords = require(Shared.Config.Swords)
local Abilities = require(Shared.Config.Abilities)
local Catalog = require(Shared.Lib.Catalog)
local CardLevels = require(Shared.Lib.CardLevels)
local State = require(script.Parent.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local LoadoutScreen = {}

local function passiveText(passive): string
	if not passive then
		return "No passive."
	end
	local t = passive.Type
	if t == "DoT" then
		return `{passive.Label}: {passive.Damage} damage every {passive.Interval}s for {passive.Ticks * passive.Interval}s.`
	elseif t == "Slow" then
		return `Slows targets by {math.floor((1 - passive.Mult) * 100)}% for {passive.Duration}s.`
	elseif t == "Lifesteal" then
		return `Heals you for {math.floor(passive.Percent * 100)}% of damage dealt.`
	elseif t == "Chain" then
		return `Lightning arcs to a nearby enemy for {math.floor(passive.Percent * 100)}% damage.`
	elseif t == "FinisherBoost" then
		return `Combo finisher deals +{math.floor(passive.Bonus * 100)}% more damage.`
	elseif t == "Haste" then
		return `Swings {math.floor((1 - passive.Mult) * 100)}% faster.`
	elseif t == "Vulnerable" then
		return `Targets take +{math.floor((passive.Mult - 1) * 100)}% damage for {passive.Duration}s.`
	elseif t == "Knockback" then
		return "Combo finisher launches the target."
	end
	return ""
end

local function statusText(status): string?
	if not status then
		return nil
	end
	if status.Type == "Slow" then
		return `Slows {math.floor((1 - status.Mult) * 100)}% for {status.Duration}s`
	elseif status.Type == "Root" then
		return `Roots for {status.Duration}s`
	elseif status.Type == "DoT" then
		return `{status.Label} {status.Damage}/s for {status.Ticks}s`
	end
	return nil
end

function LoadoutScreen.new(gui: ScreenGui, ctx)
	local root, content = Kit.Page(gui, "Loadout", ctx.Back)
	local kind = "Sword"
	local selectedId: string? = nil

	local tabs = Kit.Frame(content, { BackgroundTransparency = 1, Size = UDim2.new(0.62, 0, 0, 40) })
	Kit.List(tabs, Enum.FillDirection.Horizontal, 10)
	local gridHolder = Kit.Scroll(content, { Size = UDim2.new(0.62, -12, 1, -52), Position = UDim2.fromOffset(0, 52) })
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 120),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gridHolder,
	})

	local detail = Kit.Frame(content, {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		Size = UDim2.new(0.38, -12, 1, 0),
		Position = UDim2.new(0.62, 12, 0, 0),
	})
	Kit.Corner(detail, 8)
	Kit.Stroke(detail, C.Line)
	Kit.Padding(detail, 18)

	local render -- forward

	local tabButtons = {}
	for _, k in { "Sword", "Ability" } do
		tabButtons[k] = Kit.Button(tabs, k == "Sword" and "SWORDS" or "ABILITIES", function()
			kind = k
			selectedId = nil
			render()
		end, { Size = UDim2.fromOffset(150, 38) })
	end

	local function renderDetail()
		for _, child in detail:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = State.Data
		if not data then
			return
		end
		local id = selectedId or data.Equipped[kind]
		local def = Catalog.Get(kind, id)
		if not def then
			return
		end
		local rarity = Rarities.Info[def.Rarity]
		local info = CardLevels.UpgradeInfo(data, kind, id)
		local list = Kit.Frame(detail, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -100) })
		Kit.List(list, nil, 6)
		Kit.Label(list, def.Name, 34, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 42) })
		Kit.Label(
			list,
			string.upper(def.Rarity) .. (kind == "Sword" and ` · {def.Archetype}` or ` · {def.Kind}`),
			14,
			{ TextColor3 = rarity.Color, Font = Kit.Fonts.Bold }
		)
		Kit.Label(list, def.Description, 15, { TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 44) })

		local level = info.Owned and info.Level or 1
		local lines = {}
		if kind == "Sword" then
			local s = Swords.GetStats(id, level)
			table.insert(lines, `Damage  {string.format("%.1f", s.Damage)}  (finisher x{s.FinisherMultiplier})`)
			table.insert(lines, `Swing speed  {string.format("%.2f", s.SwingCooldown)}s  ·  Combo {s.ComboLength}`)
			table.insert(lines, `Reach  {s.Range} studs  ·  Move speed x{s.MoveSpeedMultiplier}`)
			table.insert(lines, "Passive: " .. passiveText(def.Passive))
		else
			local s = Abilities.GetStats(id, level)
			table.insert(lines, `Damage  {string.format("%.1f", s.Damage)}{s.Count and s.Count > 1 and ` x{s.Count}` or ""}`)
			table.insert(lines, `Cooldown  {string.format("%.1f", s.Cooldown)}s`)
			table.insert(lines, `Ragdoll  {s.Ragdoll}s  ·  Destruction radius {s.Destruction}`)
			local status = statusText(s.Status)
			if status then
				table.insert(lines, status)
			end
		end
		for _, line in lines do
			Kit.Label(list, line, 15)
		end

		-- Card progress
		if info.Owned then
			Kit.Label(
				list,
				info.IsMax and `Level {info.Level} (MAX)` or `Level {info.Level}  ·  {info.Cards}/{info.CardsNeeded} cards`,
				16,
				{ Font = Kit.Fonts.Bold, TextColor3 = C.Gold }
			)
			if not info.IsMax then
				local bar = Kit.Frame(list, { Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = C.PanelLight })
				Kit.Corner(bar, 4)
				local fill = Kit.Frame(
					bar,
					{ Size = UDim2.fromScale(math.clamp(info.Cards / info.CardsNeeded, 0, 1), 1), BackgroundColor3 = rarity.Color }
				)
				Kit.Corner(fill, 4)
			end
		else
			Kit.Label(list, "LOCKED - find its card in a chest to unlock it.", 15, { TextColor3 = C.Danger })
		end

		local buttons = Kit.Frame(detail, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 90), Position = UDim2.new(0, 0, 1, -90) })
		Kit.List(buttons, nil, 8)
		if info.Owned then
			local equipped = data.Equipped[kind] == id
			Kit.Button(buttons, equipped and "EQUIPPED" or "EQUIP", function()
				if not equipped then
					local res = Net.Function("EquipItem"):InvokeServer(kind, id)
					if res and not res.ok then
						Kit.Toast(res.err, C.Danger)
					end
				end
			end, { Size = UDim2.new(1, 0, 0, 40), TextColor3 = equipped and C.Muted or C.Text })
			if not info.IsMax then
				Kit.Button(buttons, `UPGRADE  ·  {info.CoinsNeeded} coins`, function()
					local res = Net.Function("UpgradeItem"):InvokeServer(kind, id)
					if res and res.ok then
						Kit.Toast(`{def.Name} is now level {res.level}!`, C.GoldBright)
					elseif res then
						Kit.Toast(res.err, C.Danger)
					end
				end, { Size = UDim2.new(1, 0, 0, 40), TextColor3 = info.CanUpgrade and C.GoldBright or C.Muted })
			end
		end
	end

	render = function()
		for k, button in tabButtons do
			button.TextColor3 = k == kind and C.GoldBright or C.Muted
		end
		for _, child in gridHolder:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = State.Data
		if not data then
			return
		end
		for order, def in Catalog.Sorted(kind) do
			local rarity = Rarities.Info[def.Rarity]
			local owned = CardLevels.Owns(data, kind, def.Id)
			local info = CardLevels.UpgradeInfo(data, kind, def.Id)
			local card = Kit.Button(gridHolder, "", function()
				selectedId = def.Id
				renderDetail()
			end, { LayoutOrder = order, BackgroundColor3 = owned and C.PanelLight or C.Panel, Accent = rarity.Color })
			-- Rarity bar
			local bar = Kit.Frame(
				card,
				{ Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = rarity.Color, BackgroundTransparency = owned and 0 or 0.6 }
			)
			Kit.Corner(bar, 3)
			-- Theme swatch (sword edge colour / ability primary)
			local theme = Catalog.Theme(kind, def.Id)
			local swatch = Kit.Frame(card, {
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(0.5, -17, 0, 16),
				BackgroundColor3 = theme.Primary,
				BackgroundTransparency = owned and 0 or 0.7,
			})
			Kit.Corner(swatch, 17)
			Kit.new(
				"UIGradient",
				{ Color = ColorSequence.new(theme.Secondary or theme.Primary, theme.Primary), Rotation = 45, Parent = swatch }
			)
			Kit.Label(card, def.Name, 14, {
				Font = Kit.Fonts.Bold,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -8, 0, 34),
				Position = UDim2.fromOffset(4, 54),
				TextColor3 = owned and C.Text or C.Muted,
			})
			local footer
			if not owned then
				footer = "LOCKED"
			elseif info.IsMax then
				footer = `Lv {info.Level} · MAX`
			else
				footer = `Lv {info.Level} · {info.Cards}/{info.CardsNeeded}`
			end
			Kit.Label(card, footer, 12, {
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 16),
				Position = UDim2.new(0, 0, 1, -22),
				TextColor3 = info.CanUpgrade and C.GoldBright or C.Muted,
			})
			if data.Equipped[kind] == def.Id then
				Kit.Highlight(card, C.GoldBright)
			end
		end
		renderDetail()
	end

	State.DataChanged:Connect(function()
		if root.Visible then
			render()
		end
	end)

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

return LoadoutScreen
