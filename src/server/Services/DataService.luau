--[[
	DataService: player profiles.

	* UpdateAsync with a session lock (jobId + timestamp) so two servers can
	  never both own a profile (prevents duplication exploits on teleports).
	* Autosave every 120s, save on leave, BindToClose flush.
	* Falls back to an in-memory profile when DataStores are unavailable
	  (Studio without API access), and tells the player it won't save.
	* Services mutate `profile.data` directly, then call Replicate(key).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Format = require(Shared.Util.Format)
local Progression = require(Shared.Config.Progression)

local STORE_NAME = "GrowYourPets_Profiles_v1"
local LOCK_EXPIRY = 600
local AUTOSAVE = 120

local DataService = {
	Name = "DataService",
	PlayerLoaded = Signal.new(),
	PlayerLeaving = Signal.new(),
	LevelUp = Signal.new(),
}

local S -- services
local store: DataStore? = nil
local profiles: { [Player]: { data: any, noSave: boolean, leaving: boolean } } = {}

local function defaultData()
	return {
		version = 1,
		coins = 300,
		mutagen = 0,
		gems = 0,
		level = 1,
		xp = 0,
		rebirths = 0,
		pets = {},
		equipped = {},
		alpha = nil,
		fruits = {},
		capsules = {},
		incubators = {},
		base = {
			droppers = { 1, 0, 0, 0, 0, 0 },
			belt = 1,
			extractor = 0,
			defenses = {},
			bestWave = 0,
			wave = 0,
		},
		heistTickets = 1,
		lastTicketRegen = os.time(),
		lastVipTickets = 0,
		heistCooldowns = {},
		dungeonCooldown = 0,
		daily = { streak = 0, lastClaim = 0 },
		quests = { day = 0, list = {}, claimed = {} },
		stats = {
			zombiesKilled = 0,
			bossesKilled = 0,
			wavesCleared = 0,
			eggsHatched = 0,
			fruitsCollected = 0,
			fruitsEaten = 0,
			heistsWon = 0,
			capsulesStolen = 0,
			playtime = 0,
		},
		codes = {},
		lastFruitDealer = 0,
		lastOnline = 0,
		purchases = {},
		purchaseOrder = {},
		extraVault = 0,
		firstJoin = os.time(),
		settings = { autoWave = true },
		tutorial = 0,
	}
end

-- Fill keys added in later versions without touching existing values.
local function reconcile(data, template)
	for key, value in template do
		if data[key] == nil then
			data[key] = if type(value) == "table" then table.clone(value) else value
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil and #value == 0 then
			reconcile(data[key], value)
		end
	end
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

function DataService:Init(services)
	S = services
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable, running in memory:", result)
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:Load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self.Load, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:Release(player)
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				self:Save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player in profiles do
				task.spawn(self.Save, self, player, false)
				task.wait(0.5)
			end
		end
	end)
end

function DataService:Load(player: Player)
	local data = nil
	local noSave = false
	if store then
		local ds = store :: DataStore
		for attempt = 1, 5 do
			local lockedBy = nil
			local ok, err = pcall(function()
				ds:UpdateAsync(keyFor(player), function(old)
					old = old or defaultData()
					local session = old.session
					if session and session.jobId ~= game.JobId and os.time() - session.time < LOCK_EXPIRY and attempt < 4 then
						lockedBy = session.jobId
						return nil
					end
					old.session = { jobId = game.JobId, time = os.time() }
					data = old
					return old
				end)
			end)
			if ok and data then
				break
			end
			if not ok then
				warn("[DataService] load failed:", err)
			elseif lockedBy then
				warn("[DataService] profile locked by", lockedBy, "retrying")
			end
			if not player.Parent then
				return
			end
			task.wait(if lockedBy then 6 else 2 ^ attempt)
		end
	end
	if not data then
		if store and not RunService:IsStudio() then
			player:Kick("Could not load your farm. Please rejoin in a moment!")
			return
		end
		data = defaultData()
		noSave = true
	end
	if not player.Parent then
		return
	end

	reconcile(data, defaultData())
	profiles[player] = { data = data, noSave = noSave, leaving = false }

	local isNew = next(data.pets) == nil
	if isNew then
		-- Starter pet so the loop begins instantly: you hatch a friend in
		-- the first minute and it already follows you.
		local uid = self:NewUid()
		data.pets[uid] = { uid = uid, species = "Pup", level = 1, xp = 0, variant = "Normal", mutations = {} }
		data.equipped = { uid }
		data.alpha = uid
	end

	self:CreateLeaderstats(player)
	-- Pass/VIP/policy info must be known before squads, plots and rewards
	-- react to PlayerLoaded (equip slots, luck, vault size depend on it).
	S.MonetizationService:LoadPlayer(player)
	if not player.Parent then
		profiles[player] = nil
		return
	end
	Net.Event("Init"):FireClient(player, self:ClientSnapshot(player))
	if noSave then
		S.AnnounceService:Notify(player, "Studio mode: progress will not save (enable API access to test saving).", "warn")
	end
	self.PlayerLoaded:Fire(player, data, isNew)
end

function DataService:Save(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or profile.noSave or not store then
		return
	end
	local data = profile.data
	data.lastOnline = os.time()
	local ds = store :: DataStore
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			ds:UpdateAsync(keyFor(player), function(old)
				if old and old.session and old.session.jobId ~= game.JobId then
					-- Someone else owns this profile now; never overwrite them.
					return nil
				end
				data.session = if release then nil else { jobId = game.JobId, time = os.time() }
				return data
			end)
		end)
		if ok then
			return
		end
		warn("[DataService] save failed:", err)
		task.wait(attempt)
	end
end

function DataService:Release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.leaving = true
	self.PlayerLeaving:Fire(player, profile.data)
	self:Save(player, true)
	profiles[player] = nil
end

function DataService:Get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

function DataService:IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService:NewUid(): string
	return HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 12)
end

-- What the client needs to draw every panel.
function DataService:ClientSnapshot(player: Player)
	local d = self:Get(player)
	return {
		coins = d.coins,
		mutagen = d.mutagen,
		gems = d.gems,
		level = d.level,
		xp = d.xp,
		rebirths = d.rebirths,
		pets = d.pets,
		equipped = d.equipped,
		alpha = d.alpha,
		fruits = d.fruits,
		capsules = d.capsules,
		incubators = d.incubators,
		base = d.base,
		heistTickets = d.heistTickets,
		daily = d.daily,
		quests = d.quests,
		stats = d.stats,
		settings = d.settings,
		lastFruitDealer = d.lastFruitDealer,
		serverTime = os.time(),
	}
end

function DataService:Replicate(player: Player, key: string)
	local d = self:Get(player)
	if d then
		Net.Event("DataChanged"):FireClient(player, key, d[key])
	end
	if key == "coins" or key == "level" then
		self:UpdateLeaderstats(player)
	end
end

function DataService:ReplicatePet(player: Player, uid: string)
	local d = self:Get(player)
	if d then
		Net.Event("DataChanged"):FireClient(player, "pet", uid, d.pets[uid])
	end
end

----------------------------------------------------------------------------
-- Currency / XP helpers
----------------------------------------------------------------------------

function DataService:CoinMultiplier(player: Player): number
	local d = self:Get(player)
	if not d then
		return 1
	end
	local mult = 1 + d.rebirths * Progression.Rebirth.coinBonusPerRebirth
	mult *= S.MonetizationService:CoinMult(player)
	return mult
end

-- Adds currency. Coins get rebirth/VIP multipliers unless raw = true.
function DataService:Add(player: Player, currency: string, amount: number, raw: boolean?): number
	local d = self:Get(player)
	if not d or amount == 0 then
		return 0
	end
	if currency == "coins" and amount > 0 and not raw then
		amount *= self:CoinMultiplier(player)
	end
	d[currency] = (d[currency] or 0) + amount
	self:Replicate(player, currency)
	return amount
end

function DataService:Spend(player: Player, currency: string, amount: number): boolean
	local d = self:Get(player)
	if not d or amount < 0 or (d[currency] or 0) < amount then
		return false
	end
	d[currency] -= amount
	self:Replicate(player, currency)
	return true
end

function DataService:AddXP(player: Player, amount: number)
	local d = self:Get(player)
	if not d then
		return
	end
	d.xp += amount
	local leveled = false
	while d.xp >= Progression.PlayerXpToNext(d.level) do
		d.xp -= Progression.PlayerXpToNext(d.level)
		d.level += 1
		leveled = true
	end
	self:Replicate(player, "xp")
	if leveled then
		self:Replicate(player, "level")
		S.AnnounceService:Notify(player, ("LEVEL UP! You are now Lv %d"):format(d.level), "levelup")
		self.LevelUp:Fire(player, d.level)
	end
end

function DataService:IncrementStat(player: Player, stat: string, n: number?)
	local d = self:Get(player)
	if not d then
		return
	end
	d.stats[stat] = (d.stats[stat] or 0) + (n or 1)
end

----------------------------------------------------------------------------
-- Leaderstats (abbreviated strings so big numbers stay readable)
----------------------------------------------------------------------------

function DataService:CreateLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Parent = folder
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Parent = folder
	folder.Parent = player
	self:UpdateLeaderstats(player)
end

function DataService:UpdateLeaderstats(player: Player)
	local d = self:Get(player)
	local folder = player:FindFirstChild("leaderstats")
	if not d or not folder then
		return
	end
	local coins = folder:FindFirstChild("Coins") :: StringValue?
	local level = folder:FindFirstChild("Level") :: IntValue?
	if coins then
		coins.Value = Format.Short(d.coins)
	end
	if level then
		level.Value = d.level
	end
end

return DataService
