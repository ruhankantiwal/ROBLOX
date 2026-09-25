--[[
	PetService: pet inventory, hatching, equipping, crafting, leveling and
	the lifecycle of pet entities in the world. The per-tick brain lives in
	PetAIService; this service owns data and spawning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Eggs = require(Shared.Config.Eggs)
local Rarity = require(Shared.Config.Rarity)
local Fruits = require(Shared.Config.Fruits)
local World = require(Shared.Config.World)
local Progression = require(Shared.Config.Progression)
local PetStats = require(Shared.Util.PetStats)
local Rng = require(Shared.Util.Rng)
local Protocol = require(Shared.Util.EntityProtocol)

local State = Protocol.State

local PetService = { Name = "PetService" }

local S
local squads: { [Player]: any } = {}
local lastHatch: { [Player]: number } = {}
local dirtyPets: { [Player]: { [string]: boolean } } = {}

local VALID_MODES = { Follow = true, Attack = true, Guard = true, Hunt = true }

function PetService:Init(services)
	S = services
end

function PetService:Start()
	S.DataService.PlayerLoaded:Connect(function(player)
		self:CreateSquad(player)
	end)
	S.DataService.PlayerLeaving:Connect(function(player)
		self:DestroySquad(player)
	end)

	Net.Event("EquipPet").OnServerEvent:Connect(function(player, uid)
		if type(uid) == "string" then
			self:Equip(player, uid)
		end
	end)
	Net.Event("UnequipPet").OnServerEvent:Connect(function(player, uid)
		if type(uid) == "string" then
			self:Unequip(player, uid)
		end
	end)
	Net.Event("EquipBest").OnServerEvent:Connect(function(player)
		self:EquipBest(player)
	end)
	Net.Event("SetAlpha").OnServerEvent:Connect(function(player, uid)
		if type(uid) == "string" then
			self:SetAlpha(player, uid)
		end
	end)
	Net.Event("LockPet").OnServerEvent:Connect(function(player, uid)
		local d = S.DataService:Get(player)
		if d and type(uid) == "string" and d.pets[uid] then
			d.pets[uid].locked = not d.pets[uid].locked
			S.DataService:ReplicatePet(player, uid)
		end
	end)
	Net.Event("SellPet").OnServerEvent:Connect(function(player, uids)
		if type(uids) == "table" then
			self:Sell(player, uids)
		end
	end)
	Net.Event("CraftPet").OnServerEvent:Connect(function(player, uid)
		if type(uid) == "string" then
			self:Craft(player, uid)
		end
	end)
	Net.Event("SquadCommand").OnServerEvent:Connect(function(player, mode, targetId)
		local squad = squads[player]
		if squad and type(mode) == "string" and VALID_MODES[mode] then
			squad.mode = mode
			squad.focusId = if mode == "Attack" and type(targetId) == "number" then targetId else nil
			squad.modeChangedAt = os.clock()
			for _, pet in squad.order do
				pet.target = nil
				pet.nextScan = 0
			end
		end
	end)
	Net.Function("HatchEgg").OnServerInvoke = function(player, eggId, count)
		if type(eggId) ~= "string" then
			return { ok = false, err = "Bad egg" }
		end
		return self:Hatch(player, eggId, if count == 3 then 3 else 1)
	end

	-- Flush pet XP progress to clients every few seconds (not every kill).
	task.spawn(function()
		while true do
			task.wait(3)
			for player, set in dirtyPets do
				for uid in set do
					S.DataService:ReplicatePet(player, uid)
				end
				dirtyPets[player] = nil
			end
		end
	end)
end

----------------------------------------------------------------------------
-- Squads & entities
----------------------------------------------------------------------------

function PetService:GetSquad(player: Player)
	return squads[player]
end

function PetService:Squads()
	return squads
end

function PetService:CreateSquad(player: Player)
	squads[player] = { pets = {}, order = {}, mode = "Follow", focusId = nil, player = player }
	self:RefreshEquipSlots(player)
	local d = S.DataService:Get(player)
	for _, uid in d.equipped do
		self:SpawnPet(player, uid)
	end
	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		local squad = squads[player]
		if root and squad then
			for i, pet in squad.order do
				pet.pos = root.Position + Vector3.new(math.cos(i) * 4, -3, math.sin(i) * 4)
				pet.target = nil
			end
		end
	end)
end

function PetService:DestroySquad(player: Player)
	local squad = squads[player]
	if not squad then
		return
	end
	for _, pet in squad.order do
		S.EntityService:Remove(pet)
	end
	squads[player] = nil
	lastHatch[player] = nil
	dirtyPets[player] = nil
end

function PetService:Appearance(pet, stats)
	return {
		source = "Pet",
		species = pet.species,
		variant = pet.variant,
		fruit = pet.fruit and pet.fruit.id,
		awakened = stats.special.awakened,
		mutations = pet.mutations,
		scale = stats.sizeMult,
	}
end

function PetService:SpawnPet(player: Player, uid: string)
	local squad = squads[player]
	local d = S.DataService:Get(player)
	local pet = d and d.pets[uid]
	if not squad or not pet or squad.pets[uid] then
		return
	end
	local stats = PetStats.Compute(pet)
	local root = S.EntityService:RootOf(player)
	local start = if root then root.Position - Vector3.new(0, 3, 0) else World.HubSpawn
	local body = Pets.Species[pet.species].body
	local length = (body.size and body.size.Z or 3)
	local entity = S.EntityService:Create("Pet", {
		ownerId = player.UserId,
		owner = player,
		uid = uid,
		name = Pets.Species[pet.species].displayName,
		rarity = Pets.Species[pet.species].rarity,
		level = pet.level,
		stats = stats,
		fruitId = pet.fruit and pet.fruit.id,
		maxHp = stats.hp,
		hp = stats.hp,
		pos = start + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4)),
		radius = length * 0.5 * stats.sizeMult,
		appearance = self:Appearance(pet, stats),
		cooldowns = {},
		nextAttack = 0,
		nextScan = 0,
		aura = 0,
	})
	squad.pets[uid] = entity
	self:RebuildOrder(player)
end

function PetService:DespawnPet(player: Player, uid: string)
	local squad = squads[player]
	local entity = squad and squad.pets[uid]
	if not entity then
		return
	end
	if entity.mounted then
		S.MountService:Dismount(player)
	end
	S.EntityService:Remove(entity)
	squad.pets[uid] = nil
	self:RebuildOrder(player)
end

-- Alpha first, then by power: the formation reads strongest-in-front.
function PetService:RebuildOrder(player: Player)
	local squad = squads[player]
	local d = S.DataService:Get(player)
	if not squad or not d then
		return
	end
	local order = {}
	for _, e in squad.pets do
		e.isAlpha = e.uid == d.alpha
		table.insert(order, e)
	end
	table.sort(order, function(a, b)
		if a.isAlpha ~= b.isAlpha then
			return a.isAlpha
		end
		return a.stats.powerScore > b.stats.powerScore
	end)
	squad.order = order
end

-- Recompute stats + visuals after level/fruit/mutation/variant changes.
function PetService:RefreshPet(player: Player, uid: string)
	local d = S.DataService:Get(player)
	local pet = d and d.pets[uid]
	if not pet then
		return
	end
	S.DataService:ReplicatePet(player, uid)
	local squad = squads[player]
	local entity = squad and squad.pets[uid]
	if not entity then
		return
	end
	local stats = PetStats.Compute(pet)
	local ratio = if entity.maxHp > 0 then entity.hp / entity.maxHp else 1
	entity.stats = stats
	entity.level = pet.level
	entity.fruitId = pet.fruit and pet.fruit.id
	entity.hp = stats.hp * math.max(ratio, 0.01)
	entity.radius = (Pets.Species[pet.species].body.size and Pets.Species[pet.species].body.size.Z or 3) * 0.5 * stats.sizeMult
	S.EntityService:SetAppearance(entity, self:Appearance(pet, stats), stats.hp)
	self:RebuildOrder(player)
end

function PetService:OnFainted(entity, _killer)
	entity.fainted = true
	entity.dead = false -- pets faint, they never die
	entity.hp = 0
	entity.state = State.Fainted
	entity.target = nil
	entity.respawnAt = os.clock() + Pets.FaintSeconds
	if entity.mounted and entity.owner then
		S.MountService:Dismount(entity.owner)
	end
end

----------------------------------------------------------------------------
-- Equip management
----------------------------------------------------------------------------

function PetService:EquipSlots(player: Player): number
	local d = S.DataService:Get(player)
	if not d then
		return Pets.BaseEquipSlots
	end
	local slots = Pets.BaseEquipSlots
	if S.MonetizationService:HasPass(player, "ExtraEquip") then
		slots += 1
	end
	if S.MonetizationService:IsVIP(player) then
		slots += 1
	end
	for rebirth in Progression.Rebirth.equipSlotAt do
		if d.rebirths >= rebirth then
			slots += 1
		end
	end
	return math.min(slots, Pets.MaxEquipSlots)
end

function PetService:InventoryMax(player: Player): number
	return Pets.BaseInventory + (if S.MonetizationService:IsVIP(player) then 40 else 0)
end

function PetService:RefreshEquipSlots(player: Player)
	local d = S.DataService:Get(player)
	if not d then
		return
	end
	local slots = self:EquipSlots(player)
	player:SetAttribute("EquipSlots", slots)
	while #d.equipped > slots do
		local uid = table.remove(d.equipped)
		self:DespawnPet(player, uid)
	end
	S.DataService:Replicate(player, "equipped")
end

function PetService:Equip(player: Player, uid: string)
	local d = S.DataService:Get(player)
	if not d or not d.pets[uid] or table.find(d.equipped, uid) then
		return
	end
	if #d.equipped >= self:EquipSlots(player) then
		S.AnnounceService:Notify(player, "Army is full! Unequip a pet or get more slots.", "warn")
		return
	end
	table.insert(d.equipped, uid)
	if not d.alpha or not table.find(d.equipped, d.alpha) then
		d.alpha = uid
		S.DataService:Replicate(player, "alpha")
	end
	S.DataService:Replicate(player, "equipped")
	self:SpawnPet(player, uid)
end

function PetService:Unequip(player: Player, uid: string)
	local d = S.DataService:Get(player)
	local i = d and table.find(d.equipped, uid)
	if not i then
		return
	end
	table.remove(d.equipped, i)
	if d.alpha == uid then
		d.alpha = d.equipped[1]
		S.DataService:Replicate(player, "alpha")
	end
	S.DataService:Replicate(player, "equipped")
	self:DespawnPet(player, uid)
end

function PetService:EquipBest(player: Player)
	local d = S.DataService:Get(player)
	if not d then
		return
	end
	local list = {}
	for uid, pet in d.pets do
		table.insert(list, { uid = uid, score = PetStats.Compute(pet).powerScore })
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	for _, uid in table.clone(d.equipped) do
		self:Unequip(player, uid)
	end
	for i = 1, math.min(#list, self:EquipSlots(player)) do
		self:Equip(player, list[i].uid)
	end
	d.alpha = d.equipped[1]
	S.DataService:Replicate(player, "alpha")
	self:RebuildOrder(player)
end

function PetService:SetAlpha(player: Player, uid: string)
	local d = S.DataService:Get(player)
	if not d or not table.find(d.equipped, uid) then
		return
	end
	if S.MountService:IsMounted(player) then
		S.MountService:Dismount(player)
	end
	d.alpha = uid
	S.DataService:Replicate(player, "alpha")
	self:RebuildOrder(player)
end

----------------------------------------------------------------------------
-- Granting, hatching, selling, crafting
----------------------------------------------------------------------------

function PetService:CountPets(player: Player): number
	local d = S.DataService:Get(player)
	local n = 0
	for _ in d.pets do
		n += 1
	end
	return n
end

function PetService:GrantPet(player: Player, species: string, variant: string?, opts: { [string]: any }?): string?
	local d = S.DataService:Get(player)
	if not d or not Pets.Species[species] then
		return nil
	end
	local o = opts or {}
	if not o.ignoreCap and self:CountPets(player) >= self:InventoryMax(player) then
		S.AnnounceService:Notify(player, "Pet inventory full! Sell or craft some pets.", "warn")
		return nil
	end
	local uid = S.DataService:NewUid()
	d.pets[uid] = {
		uid = uid,
		species = species,
		level = o.level or 1,
		xp = 0,
		variant = variant or "Normal",
		mutations = o.mutations or {},
		fruit = o.fruit,
	}
	S.DataService:ReplicatePet(player, uid)
	if #d.equipped < self:EquipSlots(player) then
		self:Equip(player, uid)
	end
	if not o.silent then
		self:AnnounceHatch(player, species, variant or "Normal")
	end
	return uid
end

function PetService:AnnounceHatch(player: Player, species: string, variant: string)
	local def = Pets.Species[species]
	local info = Rarity.Info[def.rarity]
	local isShiny = variant == "Shiny"
	if info.announce == "none" and not isShiny then
		return
	end
	local variantInfo = Pets.Variants[variant]
	local prefix = if variantInfo and variantInfo.label ~= "" then variantInfo.label .. " " else ""
	local text = ("%s hatched a %s%s %s! (%s)"):format(player.DisplayName, prefix, def.emoji, def.displayName, def.rarity)
	S.AnnounceService:Announce(text, if def.rarity == "Secret" then "secret" else "reward", info.announce == "global")
end

function PetService:Hatch(player: Player, eggId: string, count: number)
	local d = S.DataService:Get(player)
	local egg = Eggs.List[eggId]
	if not d or not egg or egg.source ~= "Shop" then
		return { ok = false, err = "That egg can't be hatched here." }
	end
	local now = os.clock()
	if lastHatch[player] and now - lastHatch[player] < Eggs.HatchCooldown then
		return { ok = false, err = "cooldown" }
	end
	if egg.levelReq and d.level < egg.levelReq then
		return { ok = false, err = ("Reach Lv %d to hatch this egg."):format(egg.levelReq) }
	end
	if count == 3 and not S.MonetizationService:HasPass(player, "TripleHatch") then
		count = 1
	end
	local root = S.EntityService:RootOf(player)
	local standPos = World.EggStands[eggId]
	if not root or not standPos or (root.Position - standPos).Magnitude > Eggs.HatchRange + 8 then
		return { ok = false, err = "Walk up to the egg to hatch it." }
	end
	if self:CountPets(player) + count > self:InventoryMax(player) then
		return { ok = false, err = "Pet inventory full! Sell or craft some pets." }
	end
	if not S.DataService:Spend(player, "coins", egg.price * count) then
		return { ok = false, err = "Not enough coins!" }
	end
	lastHatch[player] = now

	local odds = Rng.LuckAdjustedOdds(egg.odds, S.MonetizationService:Luck(player), Eggs.LuckMaxChance)
	local results = {}
	for _ = 1, count do
		local pick = Rng.Pick(odds, function(e)
			return e.chance
		end)
		local variant = if math.random() < Pets.Variants.Shiny.hatchChance then "Shiny" else "Normal"
		local uid = self:GrantPet(player, pick.pet, variant, { ignoreCap = true })
		table.insert(results, { uid = uid, species = pick.pet, variant = variant })
	end
	S.DataService:IncrementStat(player, "eggsHatched", count)
	S.DataService:AddXP(player, 5 * count)
	return { ok = true, results = results, egg = eggId }
end

-- Rolls a heist egg's table (no cost; used by the incubator).
function PetService:RollEgg(player: Player, eggId: string)
	local egg = Eggs.List[eggId]
	local odds = Rng.LuckAdjustedOdds(egg.odds, S.MonetizationService:Luck(player), Eggs.LuckMaxChance)
	local pick = Rng.Pick(odds, function(e)
		return e.chance
	end)
	local variant = if math.random() < Pets.Variants.Shiny.hatchChance * 2 then "Shiny" else "Normal"
	return pick.pet, variant
end

function PetService:Sell(player: Player, uids: { any })
	local d = S.DataService:Get(player)
	local total = 0
	for _, uid in uids do
		local pet = type(uid) == "string" and d.pets[uid]
		if pet and not pet.locked and not table.find(d.equipped, uid) then
			local def = Pets.Species[pet.species]
			total += Rarity.Info[def.rarity].sellValue * (Pets.Variants[pet.variant] or Pets.Variants.Normal).mult
			d.pets[uid] = nil
			S.DataService:ReplicatePet(player, uid)
		end
	end
	if total > 0 then
		S.DataService:Add(player, "coins", math.floor(total), true)
		S.AnnounceService:Notify(player, ("Sold for 💰%d"):format(math.floor(total)), "good")
	end
end

-- Five of the same species+variant -> one of the next variant.
function PetService:Craft(player: Player, uid: string)
	local d = S.DataService:Get(player)
	local base = d and d.pets[uid]
	if not base then
		return
	end
	local nextVariant = if base.variant == "Normal" then "Golden" elseif base.variant == "Golden" then "Rainbow" else nil
	if not nextVariant then
		S.AnnounceService:Notify(player, "This pet can't be crafted further.", "warn")
		return
	end
	local need = Pets.Variants[nextVariant].craftCount
	local picks = { uid }
	for otherUid, pet in d.pets do
		if #picks >= need then
			break
		end
		if otherUid ~= uid and pet.species == base.species and pet.variant == base.variant and not pet.locked and not table.find(d.equipped, otherUid) then
			table.insert(picks, otherUid)
		end
	end
	if #picks < need then
		S.AnnounceService:Notify(player, ("Need %d unequipped, unlocked %s %s to craft."):format(need, base.variant, Pets.Species[base.species].displayName), "warn")
		return
	end
	local level = 1
	for _, pickUid in picks do
		level = math.max(level, d.pets[pickUid].level)
	end
	local fruit, mutations = base.fruit, base.mutations
	for _, pickUid in picks do
		self:Unequip(player, pickUid)
		d.pets[pickUid] = nil
		S.DataService:ReplicatePet(player, pickUid)
	end
	self:GrantPet(player, base.species, nextVariant, { level = level, fruit = fruit, mutations = mutations, ignoreCap = true, silent = true })
	S.AnnounceService:Notify(player, ("Crafted a %s %s!"):format(nextVariant, Pets.Species[base.species].displayName), "reward")
end

----------------------------------------------------------------------------
-- Growth: XP, fruit mastery
----------------------------------------------------------------------------

function PetService:AddPetXP(player: Player, entity, amount: number)
	local d = S.DataService:Get(player)
	local pet = d and d.pets[entity.uid]
	if not pet then
		return
	end
	local maxLevel = Rarity.Info[Pets.Species[pet.species].rarity].maxLevel
	if pet.level >= maxLevel then
		return
	end
	pet.xp += amount
	local leveled = false
	while pet.level < maxLevel and pet.xp >= Progression.PetXpToNext(pet.level) do
		pet.xp -= Progression.PetXpToNext(pet.level)
		pet.level += 1
		leveled = true
	end
	if leveled then
		S.CombatService:Text(entity, ("LEVEL %d!"):format(pet.level), "#7CFF6B")
		self:RefreshPet(player, entity.uid)
	else
		dirtyPets[player] = dirtyPets[player] or {}
		dirtyPets[player][entity.uid] = true
	end
end

function PetService:AddMastery(player: Player, entity, amount: number)
	local d = S.DataService:Get(player)
	local pet = d and d.pets[entity.uid]
	if not pet or not pet.fruit then
		return
	end
	local fruit = Fruits.List[pet.fruit.id]
	local before = pet.fruit.mastery or 0
	local after = before + amount
	pet.fruit.mastery = after
	local milestone = false
	for _, ability in fruit.abilities do
		if before < ability.mastery and after >= ability.mastery then
			milestone = true
			S.AnnounceService:Notify(player, ("%s learned %s!"):format(entity.name, ability.name), "reward")
		end
	end
	if fruit.awaken and before < fruit.awaken.mastery and after >= fruit.awaken.mastery then
		milestone = true
		S.AnnounceService:Announce(("%s's %s AWAKENED its %s!"):format(player.DisplayName, entity.name, fruit.displayName), "reward")
	end
	if milestone then
		self:RefreshPet(player, entity.uid)
	else
		dirtyPets[player] = dirtyPets[player] or {}
		dirtyPets[player][entity.uid] = true
	end
end

-- Kill credit: the killer gets full XP and mastery, squadmates share half.
function PetService:AwardKill(player: Player, killer, xp: number, isBoss: boolean)
	local squad = squads[player]
	if not squad then
		return
	end
	for _, pet in squad.order do
		if pet == killer then
			self:AddPetXP(player, pet, xp)
			self:AddMastery(player, pet, if isBoss then 10 else 1)
			local sp = pet.stats.special
			if sp.auraPerKill then
				pet.aura = math.min((pet.aura or 0) + sp.auraPerKill, sp.auraMax or 50)
			end
		elseif not pet.fainted then
			self:AddPetXP(player, pet, xp * 0.5)
		end
	end
end

return PetService
