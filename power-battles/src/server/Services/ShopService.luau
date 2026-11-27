-- Developer products + game passes. Receipts are idempotent (PurchaseHistory) and saved immediately.

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Shop = require(Shared.Config.Shop)

local ShopService = {}
local S

local productById = {}
local randomRestricted = {} -- [Player] = bool
local ownedPasses = {} -- [Player] = { [Key] = true }

local function checkPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	-- Fail closed: if we can't check, treat random paid items as restricted.
	randomRestricted[player] = not ok or info.ArePaidRandomItemsRestricted
end

local function checkPasses(player: Player)
	ownedPasses[player] = {}
	for _, pass in Shop.GamePasses do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and owns then
				ownedPasses[player][pass.Key] = true
			end
		end
	end
	player:SetAttribute("VIP", ownedPasses[player].VIP == true)
end

function ShopService.CoinBonus(player: Player): number
	local bonus = 0
	local owned = ownedPasses[player]
	if owned then
		for _, pass in Shop.GamePasses do
			if owned[pass.Key] and pass.CoinBonus then
				bonus += pass.CoinBonus
			end
		end
	end
	return bonus
end

local function grant(player: Player, product)
	local grants = product.Grants
	if grants.Coins then
		S.DataService.Update(player, function(data)
			data.Coins += grants.Coins
		end)
	end
	if grants.Chest then
		S.ChestService.Grant(player, grants.Chest, "Purchase")
	end
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = productById[receipt.ProductId]
	if not player or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = S.DataService.WaitForData(player, 15)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if data.PurchaseHistory[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local ok, err = pcall(grant, player, product)
	if not ok then
		warn("[ShopService] grant failed: " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	data.PurchaseHistory[receipt.PurchaseId] = os.time()
	S.DataService.SaveNow(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.Init(services)
	S = services
	for _, product in Shop.Products do
		if product.Id ~= 0 then
			productById[product.Id] = product
		end
	end
end

function ShopService.Start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			checkPasses(player)
		end
	end)

	local function onPlayer(player: Player)
		task.spawn(checkPolicy, player)
		task.spawn(checkPasses, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		randomRestricted[player] = nil
		ownedPasses[player] = nil
	end)

	Net.Function("GetShop").OnServerInvoke = function(player)
		local items = {}
		for _, product in Shop.Products do
			if not (product.Random and randomRestricted[player] ~= false) then
				table.insert(items, { Key = product.Key, Configured = product.Id ~= 0 })
			end
		end
		for _, pass in Shop.GamePasses do
			table.insert(
				items,
				{ Key = pass.Key, Configured = pass.Id ~= 0, Owned = ownedPasses[player] and ownedPasses[player][pass.Key] == true }
			)
		end
		return items
	end

	Net.Function("Purchase").OnServerInvoke = function(player, key)
		local item = typeof(key) == "string" and Shop.ByKey[key]
		if not item then
			return { ok = false, err = "Unknown item" }
		end
		if item.Id == 0 then
			return { ok = false, err = "This item isn't set up yet." }
		end
		if item.Random and randomRestricted[player] ~= false then
			return { ok = false, err = "Not available in your region." }
		end
		if item.Type == "GamePass" then
			MarketplaceService:PromptGamePassPurchase(player, item.Id)
		else
			MarketplaceService:PromptProductPurchase(player, item.Id)
		end
		return { ok = true }
	end
end

return ShopService
