--[[
	MonetizationService: game passes, developer products, VIP subscription,
	server-wide boosts, and paid random item compliance.

	Compliance: anything flagged `randomItem` in Config/Monetization is
	hidden from, and refused for, players whose PolicyService info says
	ArePaidRandomItemsRestricted. Odds for those items are sent to the client
	with the shop info so they are visible before purchase.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Monetization = require(Shared.Config.Monetization)
local Fruits = require(Shared.Config.Fruits)
local Eggs = require(Shared.Config.Eggs)

local MonetizationService = { Name = "MonetizationService" }

local S
local owned: { [Player]: { [string]: boolean } } = {}
local vip: { [Player]: boolean } = {}
local randomRestricted: { [Player]: boolean } = {}
local serverLuckUntil = 0

local IS_STUDIO = RunService:IsStudio()

local function productByKey(key: string)
	return Monetization.Products[key]
end

local function findProductById(id: number)
	for key, p in Monetization.Products do
		if p.id == id and id ~= 0 then
			return key, p
		end
	end
	return nil, nil
end

local function findPassById(id: number)
	for key, p in Monetization.GamePasses do
		if p.id == id and id ~= 0 then
			return key, p
		end
	end
	return nil, nil
end

function MonetizationService:Init(services)
	S = services
end

function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = function(info)
		return self:ProcessReceipt(info)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = findPassById(passId)
		if key then
			self:GrantPass(player, key)
		end
	end)

	Players.UserSubscriptionStatusChanged:Connect(function(player, subscriptionId)
		if subscriptionId == Monetization.Subscription.id then
			self:RefreshVip(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		vip[player] = nil
		randomRestricted[player] = nil
	end)

	Net.Event("Purchase").OnServerEvent:Connect(function(player, kind, key)
		if type(kind) ~= "string" or type(key) ~= "string" then
			return
		end
		self:RequestPurchase(player, kind, key)
	end)

	Net.Function("GetShopInfo").OnServerInvoke = function(player)
		return self:ShopInfo(player)
	end
end

function MonetizationService:LoadPlayer(player: Player)
	owned[player] = owned[player] or {}
	-- Policy first: it decides what the shop is allowed to show.
	local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	if ok and policy then
		randomRestricted[player] = policy.ArePaidRandomItemsRestricted == true
	else
		-- Fail closed in live servers; allow testing in Studio.
		randomRestricted[player] = not IS_STUDIO
	end

	for key, pass in Monetization.GamePasses do
		if pass.id ~= 0 then
			local okOwn, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
			if okOwn and has then
				owned[player][key] = true
			end
		end
	end
	for key in owned[player] do
		player:SetAttribute("Pass_" .. key, true)
	end
	player:SetAttribute("RandomRestricted", randomRestricted[player])
	self:RefreshVip(player)
end

function MonetizationService:RefreshVip(player: Player)
	local isVip = owned[player] ~= nil and owned[player].VIP == true
	local subId = Monetization.Subscription.id
	if subId ~= "" then
		local ok, status = pcall(MarketplaceService.GetUserSubscriptionStatusAsync, MarketplaceService, player, subId)
		if ok and status and status.IsSubscribed then
			isVip = true
		end
	end
	local was = vip[player]
	vip[player] = isVip
	player:SetAttribute("VIP", isVip)
	if was ~= nil and was ~= isVip then
		S.PetService:RefreshEquipSlots(player)
	end
end

----------------------------------------------------------------------------
-- Queries used by other services
----------------------------------------------------------------------------

function MonetizationService:HasPass(player: Player, key: string): boolean
	local pass = Monetization.GamePasses[key]
	if pass and pass.randomItem and randomRestricted[player] then
		return false
	end
	local o = owned[player]
	return o ~= nil and o[key] == true
end

function MonetizationService:IsVIP(player: Player): boolean
	return vip[player] == true
end

function MonetizationService:CanBuyRandomItems(player: Player): boolean
	return randomRestricted[player] == false
end

function MonetizationService:CoinMult(player: Player): number
	return if self:IsVIP(player) then Monetization.VipCoinMult else 1
end

function MonetizationService:ServerLuckActive(): boolean
	return os.time() < serverLuckUntil
end

-- Luck used for eggs. Paid luck is ignored for restricted players.
function MonetizationService:Luck(player: Player): number
	if randomRestricted[player] then
		return 1
	end
	local luck = 1
	if self:HasPass(player, "LuckyHatch") then
		luck *= Monetization.GamePasses.LuckyHatch.luck
	end
	if self:ServerLuckActive() then
		luck *= 2
	end
	return luck
end

----------------------------------------------------------------------------
-- Purchasing
----------------------------------------------------------------------------

function MonetizationService:RequestPurchase(player: Player, kind: string, key: string)
	if kind == "pass" then
		local pass = Monetization.GamePasses[key]
		if not pass then
			return
		end
		if pass.randomItem and not self:CanBuyRandomItems(player) then
			S.AnnounceService:Notify(player, "This item isn't available in your region.", "warn")
			return
		end
		if self:HasPass(player, key) then
			S.AnnounceService:Notify(player, "You already own " .. pass.name .. "!", "info")
			return
		end
		if pass.id == 0 then
			if IS_STUDIO then
				self:GrantPass(player, key)
				S.AnnounceService:Notify(player, "[Studio] Granted " .. pass.name .. " for testing.", "good")
			else
				S.AnnounceService:Notify(player, "Coming soon!", "info")
			end
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	elseif kind == "product" then
		local product = productByKey(key)
		if not product then
			return
		end
		if product.randomItem and not self:CanBuyRandomItems(player) then
			S.AnnounceService:Notify(player, "This item isn't available in your region.", "warn")
			return
		end
		if product.id == 0 then
			if IS_STUDIO then
				self:GrantProduct(player, key, product)
				S.AnnounceService:Notify(player, "[Studio] Granted " .. product.name .. " for testing.", "good")
			else
				S.AnnounceService:Notify(player, "Coming soon!", "info")
			end
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.id)
	elseif kind == "subscription" then
		local subId = Monetization.Subscription.id
		if subId == "" then
			-- Subscription not configured yet: sell the lifetime VIP pass.
			self:RequestPurchase(player, "pass", "VIP")
			return
		end
		MarketplaceService:PromptSubscriptionPurchase(player, subId)
	end
end

function MonetizationService:GrantPass(player: Player, key: string)
	owned[player] = owned[player] or {}
	owned[player][key] = true
	if key == "VIP" then
		self:RefreshVip(player)
	end
	if key == "ExtraEquip" or key == "VIP" then
		S.PetService:RefreshEquipSlots(player)
	end
	if key == "MountBoost" then
		S.MountService:RefreshSpeed(player)
	end
	player:SetAttribute("Pass_" .. key, true)
	S.AnnounceService:Notify(player, "Unlocked " .. Monetization.GamePasses[key].name .. "!", "reward")
end

function MonetizationService:ProcessReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = S.DataService:Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receiptId = tostring(info.PurchaseId)
	if data.purchases[receiptId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key, product = findProductById(info.ProductId)
	if not key or not product then
		warn("[Monetization] unknown product", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(self.GrantProduct, self, player, key, product)
	if not ok then
		warn("[Monetization] grant failed:", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Idempotency record (keep the last 100 receipts).
	data.purchases[receiptId] = true
	table.insert(data.purchaseOrder, receiptId)
	while #data.purchaseOrder > 100 do
		data.purchases[table.remove(data.purchaseOrder, 1)] = nil
	end
	task.spawn(S.DataService.Save, S.DataService, player, false)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService:GrantProduct(player: Player, key: string, product)
	local grant = product.grant
	local data = S.DataService:Get(player)
	if grant.heistTickets then
		data.heistTickets += grant.heistTickets
		S.DataService:Replicate(player, "heistTickets")
	end
	if grant.gems then
		S.DataService:Add(player, "gems", grant.gems, true)
	end
	if grant.fruitRoll then
		S.FruitService:Roll(player, "robux")
	end
	if grant.serverLuck then
		serverLuckUntil = math.max(serverLuckUntil, os.time()) + grant.serverLuck
		workspace:SetAttribute("ServerLuckUntil", serverLuckUntil)
		S.AnnounceService:Announce(("🌟 %s activated SERVER LUCK x2 for everyone!"):format(player.DisplayName), "reward")
	end
	if grant.nuke then
		S.ZombieService:Nuke(player)
		S.AnnounceService:Announce(("☢️ %s NUKED THE HORDE!"):format(player.DisplayName), "warn", true)
	end
	S.AnnounceService:Notify(player, "Thanks! " .. product.name .. " delivered.", "reward")
end

-- Everything the shop UI needs, including odds for random items.
function MonetizationService:ShopInfo(player: Player)
	local canRandom = self:CanBuyRandomItems(player)
	local passes = {}
	for _, key in Monetization.PassOrder do
		local p = Monetization.GamePasses[key]
		if (p.id ~= 0 or IS_STUDIO) and (canRandom or not p.randomItem) then
			table.insert(passes, {
				key = key,
				name = p.name,
				icon = p.icon,
				desc = p.desc,
				price = p.price,
				owned = self:HasPass(player, key),
				randomItem = p.randomItem,
			})
		end
	end
	local products = {}
	for _, key in Monetization.ProductOrder do
		local p = Monetization.Products[key]
		if (p.id ~= 0 or IS_STUDIO) and (canRandom or not p.randomItem) then
			local odds = nil
			if p.oddsFrom == "FruitRobux" then
				odds = {}
				local total = 0
				for _, id in Fruits.Order do
					total += Fruits.List[id].robuxWeight
				end
				for _, id in Fruits.Order do
					table.insert(odds, { name = Fruits.List[id].displayName, chance = Fruits.List[id].robuxWeight / total * 100 })
				end
			elseif p.oddsFrom and Eggs.List[p.oddsFrom] then
				odds = {}
				for _, entry in Eggs.List[p.oddsFrom].odds do
					table.insert(odds, { name = entry.pet, chance = entry.chance })
				end
			end
			table.insert(products, {
				key = key,
				name = p.name,
				icon = p.icon,
				price = p.price,
				randomItem = p.randomItem,
				odds = odds,
			})
		end
	end
	return {
		passes = passes,
		products = products,
		vip = self:IsVIP(player),
		subscription = {
			name = Monetization.Subscription.name,
			priceUsd = Monetization.Subscription.priceUsd,
			perks = Monetization.Subscription.perks,
			configured = Monetization.Subscription.id ~= "",
		},
		canBuyRandom = canRandom,
		serverLuckUntil = serverLuckUntil,
		studio = IS_STUDIO,
	}
end

return MonetizationService
