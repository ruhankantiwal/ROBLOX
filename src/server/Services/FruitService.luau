--[[
	FruitService: Beast Fruits in the world, the Fruit Dealer, fruit
	storage, and feeding a fruit to a pet (the core mutation moment).

	World spawns: every few minutes a fruit appears at one of the tagged
	"FruitSpawn" anchors WorldBuilder placed (some hidden on parkour tops
	and in secret spots). Everyone gets a vague "a fruit spawned!" banner;
	Fruit Notifier owners get the exact fruit, location and a beam.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Fruits = require(Shared.Config.Fruits)
local Rarity = require(Shared.Config.Rarity)
local Pets = require(Shared.Config.Pets)
local World = require(Shared.Config.World)
local Props = require(Shared.Art.Props)
local StudStyle = require(Shared.Art.StudStyle)
local Rng = require(Shared.Util.Rng)
local Format = require(Shared.Util.Format)

local FruitService = { Name = "FruitService" }

local S
local worldFruits: { [string]: any } = {}
local nextSpawn = 0
local folder: Folder
local counter = 0

function FruitService:Init(services)
	S = services
end

function FruitService:Start()
	folder = Instance.new("Folder")
	folder.Name = "WorldFruits"
	folder.Parent = workspace
	nextSpawn = os.clock() + 45 -- first fruit soon after server start

	Net.Function("FeedFruit").OnServerInvoke = function(player, petUid, fruitId)
		if type(petUid) ~= "string" or type(fruitId) ~= "string" then
			return false
		end
		return self:Feed(player, petUid, fruitId)
	end
	Net.Function("RollFruit").OnServerInvoke = function(player, mode)
		if mode == "coins" then
			return self:DealerRoll(player)
		elseif mode == "robux" then
			S.MonetizationService:RequestPurchase(player, "product", "FruitRoll")
			return { ok = true, prompted = true }
		end
		return { ok = false }
	end

	S.DataService.PlayerLoaded:Connect(function(player)
		-- Late joiners with the notifier see fruits already out there.
		if S.MonetizationService:HasPass(player, "FruitNotifier") then
			for id, wf in worldFruits do
				Net.Event("FruitSpawned"):FireClient(player, id, wf.fruitId, wf.position, wf.hidden)
			end
		end
	end)
end

function FruitService:Storage(player: Player): number
	return Fruits.BaseStorage + (if S.MonetizationService:HasPass(player, "FruitStorage") then 10 else 0)
end

function FruitService:CountFruits(player: Player): number
	local d = S.DataService:Get(player)
	local n = 0
	for _, c in d.fruits do
		n += c
	end
	return n
end

function FruitService:PickFruit(weightKey: string): string
	local entries = {}
	for _, id in Fruits.Order do
		table.insert(entries, { id = id, w = Fruits.List[id][weightKey] })
	end
	return Rng.Pick(entries, function(e)
		return e.w
	end).id
end

-- Returns true if the fruit went into storage.
function FruitService:Grant(player: Player, fruitId: string, source: string, force: boolean?): boolean
	local d = S.DataService:Get(player)
	if not d then
		return false
	end
	if not force and self:CountFruits(player) >= self:Storage(player) then
		S.AnnounceService:Notify(player, "🧺 Fruit storage full! Feed a fruit to a pet first.", "warn")
		return false
	end
	d.fruits[fruitId] = (d.fruits[fruitId] or 0) + 1
	S.DataService:Replicate(player, "fruits")
	S.DataService:IncrementStat(player, "fruitsCollected")
	local fruit = Fruits.List[fruitId]
	S.AnnounceService:Notify(player, ("%s You got a %s!"):format(fruit.emoji, fruit.displayName), "reward")
	if Rarity.Rank(fruit.rarity) >= 5 then
		S.AnnounceService:Announce(("%s found a %s %s! (%s)"):format(player.DisplayName, fruit.emoji, fruit.displayName, source), "reward", fruit.rarity == "Mythical")
	end
	return true
end

function FruitService:GrantRandom(player: Player, source: string)
	return self:Grant(player, self:PickFruit("spawnWeight"), source, true)
end

-- Robux roll (called by MonetizationService after a receipt).
function FruitService:Roll(player: Player, mode: string)
	local fruitId = self:PickFruit(if mode == "robux" then "robuxWeight" else "spawnWeight")
	self:Grant(player, fruitId, "roll", true)
	Net.Event("MutationCinematic"):FireClient(player, { kind = "FruitRoll", id = fruitId })
	return fruitId
end

-- Coin roll at the Fruit Dealer: free currency, hourly cooldown.
function FruitService:DealerRoll(player: Player)
	local d = S.DataService:Get(player)
	if not d then
		return { ok = false }
	end
	local root = S.EntityService:RootOf(player)
	if not root or (root.Position - World.FruitDealer).Magnitude > 30 then
		return { ok = false, err = "Visit the Fruit Dealer in the hub." }
	end
	local wait = d.lastFruitDealer + Fruits.DealerCooldown - os.time()
	if wait > 0 then
		return { ok = false, err = ("Dealer restocks in %s"):format(Format.Duration(wait)) }
	end
	if self:CountFruits(player) >= self:Storage(player) then
		return { ok = false, err = "Fruit storage full!" }
	end
	if not S.DataService:Spend(player, "coins", Fruits.DealerCost) then
		return { ok = false, err = ("Need 💰%s"):format(Format.Short(Fruits.DealerCost)) }
	end
	d.lastFruitDealer = os.time()
	S.DataService:Replicate(player, "lastFruitDealer")
	local fruitId = self:PickFruit("spawnWeight")
	self:Grant(player, fruitId, "dealer", true)
	return { ok = true, fruit = fruitId }
end

----------------------------------------------------------------------------
-- Feeding: the mutation moment
----------------------------------------------------------------------------

function FruitService:Feed(player: Player, petUid: string, fruitId: string): boolean
	local d = S.DataService:Get(player)
	local pet = d and d.pets[petUid]
	local fruit = Fruits.List[fruitId]
	if not pet or not fruit or (d.fruits[fruitId] or 0) < 1 then
		return false
	end
	d.fruits[fruitId] -= 1
	if d.fruits[fruitId] <= 0 then
		d.fruits[fruitId] = nil
	end
	pet.fruit = { id = fruitId, mastery = 0 }
	S.DataService:Replicate(player, "fruits")
	S.DataService:IncrementStat(player, "fruitsEaten")
	S.PetService:RefreshPet(player, petUid)
	Net.Event("MutationCinematic"):FireClient(player, { kind = "Fruit", uid = petUid, id = fruitId })
	if Rarity.Rank(fruit.rarity) >= 5 then
		S.AnnounceService:Announce(("%s's %s ate a %s %s and MUTATED!"):format(player.DisplayName, Pets.Species[pet.species].displayName, fruit.emoji, fruit.displayName), "reward")
	end
	return true
end

----------------------------------------------------------------------------
-- World spawns
----------------------------------------------------------------------------

function FruitService:Step(_dt: number)
	local now = os.clock()
	for id, wf in worldFruits do
		if now - wf.spawnedAt > Fruits.Despawn then
			self:RemoveWorldFruit(id)
		end
	end
	local count = 0
	for _ in worldFruits do
		count += 1
	end
	if now >= nextSpawn then
		nextSpawn = now + Fruits.SpawnInterval
		if count < Fruits.MaxWorldFruits then
			self:SpawnWorldFruit()
		end
	end
end

function FruitService:SpawnWorldFruit()
	local anchors = CollectionService:GetTagged("FruitSpawn")
	local free = {}
	for _, a in anchors do
		if a:IsA("BasePart") and not a:GetAttribute("Occupied") then
			table.insert(free, a)
		end
	end
	if #free == 0 then
		return
	end
	local anchor = free[math.random(1, #free)] :: BasePart
	local fruitId = self:PickFruit("spawnWeight")
	local fruit = Fruits.List[fruitId]
	counter += 1
	local id = "wf" .. counter
	local pos = anchor.Position + Vector3.new(0, 2, 0)
	local hidden = anchor:GetAttribute("Hidden") == true

	local model = Props.Fruit(folder, CFrame.new(pos), fruit, 1.2)
	local primary = model.PrimaryPart :: BasePart
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(fruit.color)
	sparkle.LightEmission = 0.6
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.Size = NumberSequence.new(0.4, 0)
	sparkle.Parent = primary
	if not hidden then
		StudStyle.Label(primary, fruit.emoji .. " " .. fruit.displayName, fruit.color, 70, 0.8)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = fruit.displayName
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = primary
	prompt.Triggered:Connect(function(player)
		if worldFruits[id] and self:Grant(player, fruitId, "wild") then
			self:RemoveWorldFruit(id)
		end
	end)

	anchor:SetAttribute("Occupied", true)
	worldFruits[id] = { fruitId = fruitId, model = model, anchor = anchor, spawnedAt = os.clock(), position = pos, hidden = hidden }

	local zone = World.ZoneAt(pos.Z)
	for _, player in Players:GetPlayers() do
		if S.MonetizationService:HasPass(player, "FruitNotifier") then
			Net.Event("FruitSpawned"):FireClient(player, id, fruitId, pos, hidden)
		else
			S.AnnounceService:Notify(player, ("🍉 A Beast Fruit spawned somewhere in %s!"):format(zone.name), "info")
		end
	end
end

function FruitService:RemoveWorldFruit(id: string)
	local wf = worldFruits[id]
	if not wf then
		return
	end
	worldFruits[id] = nil
	wf.anchor:SetAttribute("Occupied", nil)
	wf.model:Destroy()
	Net.Event("FruitDespawned"):FireAllClients(id)
end

return FruitService
