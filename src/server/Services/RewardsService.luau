--[[
	RewardsService: retention loops.
	  * 7-day login streak (resets if you miss a day)
	  * 3 daily quests, picked deterministically per player per day
	  * free Heist Ticket regeneration (+VIP daily tickets)
	  * codes, rebirth ("Evolve Farm"), deterministic Gem shop
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Progression = require(Shared.Config.Progression)
local Monetization = require(Shared.Config.Monetization)
local Format = require(Shared.Util.Format)

local DAY = 86400

local RewardsService = { Name = "RewardsService" }

local S

local function dayNumber(t: number): number
	return math.floor(t / DAY)
end

function RewardsService:Init(services)
	S = services
end

function RewardsService:Start()
	S.DataService.PlayerLoaded:Connect(function(player)
		self:RollQuests(player)
		self:RegenTickets(player)
	end)
	Net.Event("ClaimDaily").OnServerEvent:Connect(function(player)
		self:ClaimDaily(player)
	end)
	Net.Event("ClaimQuest").OnServerEvent:Connect(function(player, index)
		if type(index) == "number" then
			self:ClaimQuest(player, index)
		end
	end)
	Net.Event("RedeemCode").OnServerEvent:Connect(function(player, code)
		if type(code) == "string" and #code <= 32 then
			self:Redeem(player, code)
		end
	end)
	Net.Event("Rebirth").OnServerEvent:Connect(function(player)
		self:Rebirth(player)
	end)
	Net.Event("GemPurchase").OnServerEvent:Connect(function(player, key)
		if type(key) == "string" then
			self:GemPurchase(player, key)
		end
	end)
end

function RewardsService:Step(dt: number)
	for _, player in Players:GetPlayers() do
		local d = S.DataService:Get(player)
		if d then
			d.stats.playtime += dt
			-- quest tracker progress lives in stats; sync it a few times a minute
			S.DataService:Replicate(player, "stats")
			self:RegenTickets(player)
			if dayNumber(os.time()) ~= d.quests.day then
				self:RollQuests(player)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Grants
----------------------------------------------------------------------------

function RewardsService:Grant(player: Player, reward)
	local d = S.DataService:Get(player)
	if reward.coins then
		S.DataService:Add(player, "coins", reward.coins, true)
	end
	if reward.mutagen then
		S.DataService:Add(player, "mutagen", reward.mutagen, true)
	end
	if reward.gems then
		S.DataService:Add(player, "gems", reward.gems, true)
	end
	if reward.heistTickets then
		d.heistTickets += reward.heistTickets
		S.DataService:Replicate(player, "heistTickets")
	end
	if reward.fruit then
		if reward.fruit == "Random" then
			S.FruitService:GrantRandom(player, "reward")
		else
			S.FruitService:Grant(player, reward.fruit, "reward", true)
		end
	end
	if reward.capsule then
		local bias = if reward.capsule == "Rare" then 1 else 0
		S.MutationService:AddCapsule(player, S.MutationService:RollMutation(bias), "reward")
	end
end

----------------------------------------------------------------------------
-- Daily streak
----------------------------------------------------------------------------

function RewardsService:ClaimDaily(player: Player)
	local d = S.DataService:Get(player)
	if not d then
		return
	end
	local today = dayNumber(os.time())
	local last = dayNumber(d.daily.lastClaim)
	if d.daily.lastClaim > 0 and today == last then
		S.AnnounceService:Notify(player, "Come back tomorrow for your next reward!", "info")
		return
	end
	if d.daily.lastClaim > 0 and today - last > 1 then
		d.daily.streak = 0
	end
	d.daily.streak += 1
	d.daily.lastClaim = os.time()
	local index = (d.daily.streak - 1) % #Progression.DailyRewards + 1
	self:Grant(player, Progression.DailyRewards[index])
	S.DataService:Replicate(player, "daily")
	S.AnnounceService:Notify(player, ("🎁 Day %d reward claimed!"):format(d.daily.streak), "reward")
end

----------------------------------------------------------------------------
-- Daily quests
----------------------------------------------------------------------------

function RewardsService:RollQuests(player: Player)
	local d = S.DataService:Get(player)
	if not d then
		return
	end
	local today = dayNumber(os.time())
	if d.quests.day == today and #d.quests.list > 0 then
		return
	end
	local rng = Random.new(today * 31 + player.UserId)
	local pool = table.clone(Progression.QuestPool)
	local list = {}
	for _ = 1, 3 do
		local q = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(list, { id = q.id, stat = q.stat, goal = q.goal, text = q.text:format(q.goal), reward = q.reward, base = d.stats[q.stat] or 0 })
	end
	d.quests = { day = today, list = list, claimed = {} }
	S.DataService:Replicate(player, "quests")
end

function RewardsService:ClaimQuest(player: Player, index: number)
	local d = S.DataService:Get(player)
	local q = d and d.quests.list[index]
	if not q or d.quests.claimed[tostring(index)] then
		return
	end
	local progress = (d.stats[q.stat] or 0) - q.base
	if progress < q.goal then
		S.AnnounceService:Notify(player, ("Quest progress: %d/%d"):format(progress, q.goal), "info")
		return
	end
	d.quests.claimed[tostring(index)] = true
	self:Grant(player, q.reward)
	S.DataService:Replicate(player, "quests")
	S.AnnounceService:Notify(player, "✅ Quest complete!", "reward")
end

----------------------------------------------------------------------------
-- Heist tickets
----------------------------------------------------------------------------

function RewardsService:RegenTickets(player: Player)
	local d = S.DataService:Get(player)
	if not d then
		return
	end
	local now = os.time()
	local every = Progression.FreeTicketEvery
	local gained = math.floor((now - d.lastTicketRegen) / every)
	if gained > 0 then
		d.lastTicketRegen += gained * every
		local room = math.max(0, Progression.FreeTicketCap - d.heistTickets)
		local add = math.min(gained, room)
		if add > 0 then
			d.heistTickets += add
			S.DataService:Replicate(player, "heistTickets")
			S.AnnounceService:Notify(player, "🎟️ Free Heist Ticket ready!", "reward")
		end
	end
	if S.MonetizationService:IsVIP(player) and dayNumber(now) ~= dayNumber(d.lastVipTickets) then
		d.lastVipTickets = now
		d.heistTickets += Monetization.VipDailyTickets
		S.DataService:Replicate(player, "heistTickets")
		S.AnnounceService:Notify(player, ("👑 VIP: +%d Heist Tickets today!"):format(Monetization.VipDailyTickets), "reward")
	end
end

----------------------------------------------------------------------------
-- Codes
----------------------------------------------------------------------------

function RewardsService:Redeem(player: Player, raw: string)
	local d = S.DataService:Get(player)
	local code = raw:upper():gsub("%s", "")
	local reward = Progression.Codes[code]
	if not d or not reward then
		S.AnnounceService:Notify(player, "Invalid code.", "error")
		return
	end
	if d.codes[code] then
		S.AnnounceService:Notify(player, "Code already redeemed.", "warn")
		return
	end
	d.codes[code] = true
	self:Grant(player, reward)
	S.AnnounceService:Notify(player, ("Code %s redeemed!"):format(code), "reward")
end

----------------------------------------------------------------------------
-- Rebirth: reset coins + conveyor, keep pets/fruits, gain permanent bonus
----------------------------------------------------------------------------

function RewardsService:Rebirth(player: Player)
	local d = S.DataService:Get(player)
	if not d then
		return
	end
	local cost = Progression.RebirthCost(d.rebirths)
	if d.coins < cost then
		S.AnnounceService:Notify(player, ("Evolve Farm needs 💰%s"):format(Format.Short(cost)), "warn")
		return
	end
	d.coins = 0
	d.rebirths += 1
	S.DataService:Replicate(player, "coins")
	S.DataService:Replicate(player, "rebirths")
	S.ConveyorService:ResetForRebirth(player)
	S.PetService:RefreshEquipSlots(player)
	S.AnnounceService:Announce(("🧬 %s EVOLVED their farm! (Rebirth %d)"):format(player.DisplayName, d.rebirths), "reward")
end

----------------------------------------------------------------------------
-- Gem shop (deterministic items only)
----------------------------------------------------------------------------

function RewardsService:GemPurchase(player: Player, key: string)
	local item = Monetization.GemShop[key]
	local d = S.DataService:Get(player)
	if not item or not d then
		return
	end
	if key == "ExtraVaultSlot" and d.extraVault >= item.max then
		S.AnnounceService:Notify(player, "Vault is at max size.", "warn")
		return
	end
	if not S.DataService:Spend(player, "gems", item.gems) then
		S.AnnounceService:Notify(player, ("Need %d 💎"):format(item.gems), "warn")
		Net.Event("OpenPanel"):FireClient(player, "Shop", "Gems")
		return
	end
	if key == "SkipIncubation" then
		if not S.EggHeistService:SkipIncubation(player) then
			S.DataService:Add(player, "gems", item.gems, true)
			S.AnnounceService:Notify(player, "No eggs are incubating.", "info")
			return
		end
	elseif key == "RepairCore" then
		local plot = S.PlotService:GetPlot(player)
		if plot then
			S.PlotService:SetCoreHp(plot, plot.coreMax)
		end
	elseif key == "ExtraVaultSlot" then
		d.extraVault += 1
		S.MutationService:RefreshVault(player)
	end
	S.AnnounceService:Notify(player, item.name .. " ✔", "good")
end

return RewardsService
