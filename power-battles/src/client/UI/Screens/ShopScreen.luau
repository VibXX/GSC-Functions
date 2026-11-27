-- SHOP: coin packs, Victory Chest Key (odds shown, hidden where paid random items are restricted), VIP.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Shop = require(Shared.Config.Shop)
local Rarities = require(Shared.Config.Rarities)
local ChestRoller = require(Shared.Lib.ChestRoller)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local ShopScreen = {}

function ShopScreen.new(gui: ScreenGui, ctx)
	local root, content = Kit.Page(gui, "Shop", ctx.Back)
	local scroll = Kit.Scroll(content)
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(300, 250),
		CellPadding = UDim2.fromOffset(16, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	local function render()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local available = Net.Function("GetShop"):InvokeServer() or {}
		for order, entry in available do
			local item = Shop.ByKey[entry.Key]
			local card = Kit.Frame(scroll, { BackgroundColor3 = C.Panel, LayoutOrder = order })
			Kit.Corner(card, 8)
			Kit.Stroke(card, item.Random and C.GoldBright or C.Line)
			Kit.Padding(card, 14)
			Kit.Label(card, item.Name, 26, { Font = Kit.Fonts.Title, Size = UDim2.new(1, 0, 0, 34) })
			Kit.Label(
				card,
				item.Description,
				14,
				{ TextColor3 = C.Muted, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 36) }
			)
			if item.Random and item.Grants.Chest then
				-- Odds disclosure (required for paid random items).
				local odds = ChestRoller.GetOdds(item.Grants.Chest)
				local lines = {}
				for _, rarity in Rarities.Order do
					local color = Rarities.Info[rarity].Color:ToHex()
					table.insert(lines, `<font color="#{color}">{rarity}</font> {string.format("%.2f", odds[rarity])}%`)
				end
				Kit.Label(
					card,
					table.concat(lines, "   "),
					12,
					{ RichText = true, Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 70) }
				)
			end
			local label
			if entry.Owned then
				label = "OWNED"
			elseif not entry.Configured then
				label = "COMING SOON"
			else
				label = `R$ {item.PriceHint}`
			end
			Kit.Button(card, label, function()
				if entry.Owned or not entry.Configured then
					return
				end
				local res = Net.Function("Purchase"):InvokeServer(item.Key)
				if res and not res.ok then
					Kit.Toast(res.err, C.Danger)
				end
			end, {
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.new(0, 0, 1, -40),
				TextColor3 = entry.Configured and C.GoldBright or C.Muted,
			})
		end
	end

	return {
		Show = function()
			root.Visible = true
			task.spawn(render)
		end,
		Hide = function()
			root.Visible = false
		end,
	}
end

return ShopScreen
