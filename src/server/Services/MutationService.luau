--[[
	MutationService: Mutation Capsules and the Brainrot economy.

	  * Vault: each base shows its capsules on pedestals. Visitors can hold
	    "Steal" on a pedestal when the base is unlocked; they then have to
	    carry the capsule home while the owner's pets hunt them (CarryService).
	  * Brainrot Belt: a conveyor in the hub carrying random capsules with
	    price tags. First player to buy one gets it.
	  * Mutation Lab: apply a capsule to a pet for Mutagen (UI -> ApplyMutation).
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)
local World = require(Shared.Config.World)
local Pets = require(Shared.Config.Pets)
local StudStyle = require(Shared.Art.StudStyle)
local Props = require(Shared.Art.Props)
local PetStats = require(Shared.Util.PetStats)
local Rng = require(Shared.Util.Rng)
local Format = require(Shared.Util.Format)

local BELT_SPAWN_EVERY = 6
local BELT_TRAVEL = 32
local BELT_MAX = 7
local STEAL_PROTECTION_SECONDS = 20 * 60 -- new players can't be robbed

local MutationService = { Name = "MutationService" }

local S
local vaults: { [Player]: any } = {}
local beltItems = {}
local nextBeltSpawn = 0
local beltFolder: Folder

function MutationService:Init(services)
	S = services
end

function MutationService:Start()
	beltFolder = Instance.new("Folder")
	beltFolder.Name = "BrainrotBelt"
	beltFolder.Parent = workspace

	Net.Event("ApplyMutation").OnServerEvent:Connect(function(player, capsuleId, petUid)
		if type(capsuleId) == "string" and type(petUid) == "string" then
			self:Apply(player, capsuleId, petUid)
		end
	end)
end

----------------------------------------------------------------------------
-- Rolling & granting
----------------------------------------------------------------------------

-- bias 0..2: higher biases favour rarer mutations.
function MutationService:RollMutation(bias: number): string
	local entries = {}
	for _, id in Mutations.Order do
		local m = Mutations.List[id]
		local rank = Rarity.Rank(m.rarity)
		table.insert(entries, { id = id, w = m.weight * (1 + bias * (rank - 1) * 0.5) })
	end
	return Rng.Pick(entries, function(e)
		return e.w
	end).id
end

function MutationService:VaultSize(player: Player): number
	local d = S.DataService:Get(player)
	return Mutations.VaultSize + (if S.MonetizationService:IsVIP(player) then Mutations.VipVaultBonus else 0) + (d and d.extraVault or 0)
end

function MutationService:AddCapsule(player: Player, mutationId: string, source: string): boolean
	local d = S.DataService:Get(player)
	if not d or not Mutations.List[mutationId] then
		return false
	end
	if #d.capsules >= self:VaultSize(player) then
		if source ~= "stolen" then
			S.AnnounceService:Notify(player, "Capsule vault full! Apply or sell capsules in the Mutation Lab.", "warn")
			return false
		end
	end
	table.insert(d.capsules, { id = S.DataService:NewUid(), mutation = mutationId })
	S.DataService:Replicate(player, "capsules")
	self:RefreshVault(player)
	local m = Mutations.List[mutationId]
	S.AnnounceService:Notify(player, ("%s New capsule: %s (%s)"):format(m.emoji, m.displayName, m.rarity), "reward")
	return true
end

----------------------------------------------------------------------------
-- Applying (Mutation Lab)
----------------------------------------------------------------------------

function MutationService:Apply(player: Player, capsuleId: string, petUid: string)
	local d = S.DataService:Get(player)
	local pet = d and d.pets[petUid]
	if not pet then
		return
	end
	local index = nil
	for i, c in d.capsules do
		if c.id == capsuleId then
			index = i
			break
		end
	end
	if not index then
		return
	end
	local mutationId = d.capsules[index].mutation
	local m = Mutations.List[mutationId]
	if table.find(pet.mutations, mutationId) then
		S.AnnounceService:Notify(player, "This pet already has " .. m.displayName .. ".", "warn")
		return
	end
	local cost = Mutations.ApplyCost[m.rarity]
	if not S.DataService:Spend(player, "mutagen", cost) then
		S.AnnounceService:Notify(player, ("Need %d Mutagen 🧪"):format(cost), "warn")
		return
	end
	table.remove(d.capsules, index)
	local slots = PetStats.MutationSlots(pet)
	if #pet.mutations >= slots then
		table.remove(pet.mutations, 1)
	end
	table.insert(pet.mutations, mutationId)
	S.DataService:Replicate(player, "capsules")
	self:RefreshVault(player)
	S.PetService:RefreshPet(player, petUid)
	Net.Event("MutationCinematic"):FireClient(player, { kind = "Mutation", uid = petUid, id = mutationId })
	if Rarity.Rank(m.rarity) >= 5 then
		S.AnnounceService:Announce(("%s gave their %s %s %s!"):format(player.DisplayName, Pets.Species[pet.species].displayName, m.emoji, m.displayName), "reward")
	end
end

----------------------------------------------------------------------------
-- Vault pedestals + stealing
----------------------------------------------------------------------------

local VAULT_ORIGIN = Vector3.new(44, 0, -24)
local VAULT_STEP = 9

function MutationService:OnPlotAssigned(player: Player, plot)
	vaults[player] = { plot = plot }
	self:RefreshVault(player)
end

function MutationService:OnPlotReleased(plot)
	for player, vault in vaults do
		if vault.plot == plot then
			if vault.model then
				vault.model:Destroy()
			end
			vaults[player] = nil
		end
	end
end

function MutationService:RefreshVault(player: Player)
	local vault = vaults[player]
	local d = S.DataService:Get(player)
	if not vault or not d then
		return
	end
	local plot = vault.plot
	if vault.model then
		vault.model:Destroy()
	end
	local m = StudStyle.Model(plot.model, "Vault")
	vault.model = m
	local size = self:VaultSize(player)
	for i = 1, size do
		local row = (i - 1) % 6
		local col = math.floor((i - 1) / 6)
		local offset = VAULT_ORIGIN + Vector3.new(-col * 8, 0, row * VAULT_STEP)
		local pos = plot.cf:PointToWorldSpace(offset)
		local pedestal = StudStyle.OnGround(m, Vector3.new(4, 2, 4), pos, Color3.fromRGB(70, 70, 86), { name = "Pedestal" .. i })
		local capsule = d.capsules[i]
		if capsule then
			local mut = Mutations.List[capsule.mutation]
			Props.Capsule(m, CFrame.new(pos + Vector3.new(0, 3.8, 0)), mut, 1)
			StudStyle.Label(pedestal, ("%s %s"):format(mut.emoji, mut.displayName), Rarity.Color(mut.rarity), 55, 0.65)
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Steal"
			prompt.ObjectText = mut.displayName
			prompt.HoldDuration = 1.6
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("OwnerUserId", player.UserId)
			CollectionService:AddTag(prompt, "VisitorPrompt")
			prompt.Parent = pedestal
			local capsuleId = capsule.id
			prompt.Triggered:Connect(function(thief)
				self:TrySteal(thief, player, capsuleId)
			end)
		end
	end
end

function MutationService:TrySteal(thief: Player, victim: Player, capsuleId: string)
	if thief == victim or not victim.Parent then
		return
	end
	local victimData = S.DataService:Get(victim)
	local thiefData = S.DataService:Get(thief)
	local vault = vaults[victim]
	if not victimData or not thiefData or not vault then
		return
	end
	if S.PlotService:IsLocked(vault.plot) then
		S.AnnounceService:Notify(thief, "🔒 This base is locked!", "warn")
		return
	end
	if os.time() - victimData.firstJoin < STEAL_PROTECTION_SECONDS then
		S.AnnounceService:Notify(thief, "🛡️ New farmers are protected. Find another target!", "warn")
		return
	end
	if S.CarryService:IsCarrying(thief) then
		return
	end
	local index = nil
	for i, c in victimData.capsules do
		if c.id == capsuleId then
			index = i
			break
		end
	end
	if not index then
		return
	end
	local capsule = table.remove(victimData.capsules, index)
	S.DataService:Replicate(victim, "capsules")
	self:RefreshVault(victim)
	local mut = Mutations.List[capsule.mutation]

	S.AnnounceService:Notify(victim, ("🚨 %s is stealing your %s! Your army is on it!"):format(thief.DisplayName, mut.displayName), "error")
	S.CarryService:StartCarry(thief, {
		kind = "Capsule",
		label = ("%s STOLEN %s"):format(mut.emoji, mut.displayName:upper()),
		victim = victim,
		speedMult = 0.8,
		timeout = 120,
		visual = function(parent: Instance, cf: CFrame)
			return Props.Capsule(parent, cf, mut, 0.9)
		end,
		deliverCheck = function()
			return S.PlotService:IsOnPlot(thief, -10)
		end,
		onDeliver = function()
			self:AddCapsule(thief, capsule.mutation, "stolen")
			S.DataService:IncrementStat(thief, "capsulesStolen")
			S.AnnounceService:Announce(("🦹 %s stole %s's %s %s!"):format(thief.DisplayName, victim.DisplayName, mut.emoji, mut.displayName), "warn")
		end,
		onDrop = function(reason: string)
			if victim.Parent and S.DataService:Get(victim) then
				table.insert(victimData.capsules, capsule)
				S.DataService:Replicate(victim, "capsules")
				self:RefreshVault(victim)
				if reason == "caught" then
					S.AnnounceService:Notify(victim, ("🛡️ Your army caught %s and got your capsule back!"):format(thief.DisplayName), "good")
				end
			end
		end,
	})
end

----------------------------------------------------------------------------
-- Hub Brainrot Belt
----------------------------------------------------------------------------

function MutationService:Step(_dt: number)
	local now = os.clock()
	if now >= nextBeltSpawn and #beltItems < BELT_MAX then
		nextBeltSpawn = now + BELT_SPAWN_EVERY
		self:SpawnBeltItem()
	end
end

function MutationService:SpawnBeltItem()
	local bias = if S.MonetizationService:ServerLuckActive() then 1.5 else 0.3
	local mutationId = self:RollMutation(bias)
	local mut = Mutations.List[mutationId]
	local price = Mutations.BeltPrice[mut.rarity]
	local from = World.BrainrotBelt.from + Vector3.new(0, 3.4, 0)
	local to = World.BrainrotBelt.to + Vector3.new(0, 3.4, 0)

	local model = Props.Capsule(beltFolder, CFrame.new(from), mut, 1.1)
	local anchor = model.PrimaryPart :: BasePart
	StudStyle.Label(anchor, ("%s %s\n💰%s"):format(mut.emoji, mut.displayName, Format.Short(price)), Rarity.Color(mut.rarity), 90, 0.9)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy"
	prompt.ObjectText = ("%s · 💰%s"):format(mut.displayName, Format.Short(price))
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	local item = { model = model, mutation = mutationId, price = price, sold = false }
	table.insert(beltItems, item)

	-- Move the whole capsule along the belt with one tween per part.
	local info = TweenInfo.new(BELT_TRAVEL, Enum.EasingStyle.Linear)
	local offset = to - from
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			TweenService:Create(p, info, { CFrame = p.CFrame + offset }):Play()
		end
	end

	prompt.Triggered:Connect(function(player)
		if item.sold then
			return
		end
		local d = S.DataService:Get(player)
		if not d then
			return
		end
		if #d.capsules >= self:VaultSize(player) then
			S.AnnounceService:Notify(player, "Capsule vault full!", "warn")
			return
		end
		if not S.DataService:Spend(player, "coins", price) then
			S.AnnounceService:Notify(player, ("Need 💰%s"):format(Format.Short(price)), "warn")
			return
		end
		item.sold = true
		self:AddCapsule(player, mutationId, "belt")
		if Rarity.Rank(mut.rarity) >= 5 then
			S.AnnounceService:Announce(("%s grabbed a %s %s off the Brainrot Belt!"):format(player.DisplayName, mut.emoji, mut.displayName), "reward")
		end
		self:RemoveBeltItem(item)
	end)

	task.delay(BELT_TRAVEL, function()
		self:RemoveBeltItem(item)
	end)
end

function MutationService:RemoveBeltItem(item)
	local i = table.find(beltItems, item)
	if i then
		table.remove(beltItems, i)
	end
	if item.model.Parent then
		item.model:Destroy()
	end
end


return MutationService
