--[[
	EggHeistService: "Steal an Egg".

	1. Walk to a heist site (Chicken Coop in the Meadow, Dragon's Nest at
	   the far end of the Long Valley) and start a run (the Nest costs a
	   Heist Ticket).
	2. Guardians patrol (visible only to you); the boss guards the egg.
	3. Defeat the boss with your army, hold "Steal Egg".
	4. RUN home down the valley carrying it. Guardians chase you; one hit
	   and the egg flies back to the nest. Your Alpha mount is the escape.
	5. Deliver to your base incubator. It hatches after a timer into a
	   rare/mythical pet (odds shown in the UI).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local Eggs = require(Shared.Config.Eggs)
local Base = require(Shared.Config.Base)
local StudStyle = require(Shared.Art.StudStyle)
local Props = require(Shared.Art.Props)
local Format = require(Shared.Util.Format)

local RUN_TIMEOUT = 8 * 60
local ABANDON_DIST = 700
local INCUBATOR_SLOTS = 3

local EggHeistService = { Name = "EggHeistService" }

local S
local runs: { [Player]: any } = {}
local incubators: { [Player]: any } = {}
local folder: Folder

function EggHeistService:Init(services)
	S = services
end

function EggHeistService:Start()
	folder = Instance.new("Folder")
	folder.Name = "Heists"
	folder.Parent = workspace
	for id, def in World.Heists do
		self:BuildSite(id, def)
	end
	S.DataService.PlayerLeaving:Connect(function(player)
		self:EndRun(player, false, "left")
	end)
end

----------------------------------------------------------------------------
-- Sites
----------------------------------------------------------------------------

function EggHeistService:SitePositions(def)
	local center = World.Resolve(def.center)
	return center, center + Vector3.new(0, 0, -56), center + Vector3.new(0, 0, 22)
end

function EggHeistService:BuildSite(id: string, def)
	local _, gatePos, pedestalPos = self:SitePositions(def)
	local egg = Eggs.List[def.egg]

	local gate = StudStyle.OnGround(folder, Vector3.new(8, 1, 8), gatePos, Color3.fromRGB(255, 200, 60), { name = id .. "_Start" })
	StudStyle.Label(gate, ("🥚 %s\n%s"):format(def.name, if def.ticket then "Costs 1 🎟️" else "Free · 10 min cooldown"), Color3.fromRGB(255, 220, 120), 120, 1.2)
	local startPrompt = Instance.new("ProximityPrompt")
	startPrompt.ActionText = "Start Heist"
	startPrompt.ObjectText = def.name
	startPrompt.HoldDuration = 0.5
	startPrompt.MaxActivationDistance = 12
	startPrompt.RequiresLineOfSight = false
	startPrompt.Parent = gate
	startPrompt.Triggered:Connect(function(player)
		self:StartRun(player, id)
	end)

	local pedestal = StudStyle.OnGround(folder, Vector3.new(6, 3, 6), pedestalPos, Color3.fromRGB(60, 50, 70), { name = id .. "_Pedestal" })
	Props.Egg(folder, CFrame.new(pedestalPos + Vector3.new(0, 3, 0)), egg, 1.2)
	StudStyle.Label(pedestal, ("%s"):format(egg.displayName), egg.color, 90, 1)
	local stealPrompt = Instance.new("ProximityPrompt")
	stealPrompt.ActionText = "Steal Egg"
	stealPrompt.ObjectText = egg.displayName
	stealPrompt.HoldDuration = 2
	stealPrompt.MaxActivationDistance = 10
	stealPrompt.RequiresLineOfSight = false
	stealPrompt.Parent = pedestal
	stealPrompt.Triggered:Connect(function(player)
		self:StealEgg(player, id)
	end)
	CollectionService:AddTag(pedestal, "HeistPedestal")
end

----------------------------------------------------------------------------
-- Runs
----------------------------------------------------------------------------

function EggHeistService:StartRun(player: Player, heistId: string)
	local def = World.Heists[heistId]
	local d = S.DataService:Get(player)
	if not def or not d then
		return
	end
	if runs[player] then
		S.AnnounceService:Notify(player, "You're already on a heist!", "warn")
		return
	end
	local cooldown = d.heistCooldowns[heistId] or 0
	if os.time() < cooldown then
		S.AnnounceService:Notify(player, ("The guards are on alert. Try again in %s."):format(Format.Duration(cooldown - os.time())), "warn")
		return
	end
	local squad = S.PetService:GetSquad(player)
	if not squad or #squad.order == 0 then
		S.AnnounceService:Notify(player, "Equip at least one pet before a heist!", "warn")
		return
	end
	if #d.incubators >= self:IncubatorSlots(player) then
		S.AnnounceService:Notify(player, "Your incubator is full! Hatch your eggs first.", "warn")
		return
	end
	if def.ticket then
		if d.heistTickets < 1 then
			S.AnnounceService:Notify(player, "You need a 🎟️ Heist Ticket! (free ticket every 4h, or grab some in the Shop)", "warn")
			Net.Event("OpenPanel"):FireClient(player, "Shop", "HeistTicket1")
			return
		end
		d.heistTickets -= 1
		S.DataService:Replicate(player, "heistTickets")
	end

	local center, _, pedestalPos = self:SitePositions(def)
	local run = {
		kind = "Heist",
		player = player,
		heistId = heistId,
		def = def,
		alive = {},
		bossDead = false,
		carrier = nil,
		startedAt = os.clock(),
		center = center,
	}
	local ring = {}
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		table.insert(ring, center + Vector3.new(math.cos(a) * 32, 0, math.sin(a) * 32))
	end
	for i, guardType in def.guards do
		local start = ring[(i - 1) % #ring + 1]
		local guard = S.ZombieService:Spawn(guardType, def.level, start, {
			encounter = run,
			visibleTo = player.UserId,
			leash = def.pursuitLeash,
		})
		guard.patrol = { points = ring, i = (i % #ring) + 1 }
	end
	run.boss = S.ZombieService:Spawn(def.boss, def.level + 2, pedestalPos + Vector3.new(0, 0, -10), {
		encounter = run,
		visibleTo = player.UserId,
		leash = 45,
	})
	run.onKilled = function(z)
		if z == run.boss then
			run.bossDead = true
			S.AnnounceService:Notify(player, "🥚 The egg is unguarded! Hold STEAL EGG, then RUN HOME!", "reward")
			self:SendState(player)
		end
	end
	runs[player] = run
	self:SendState(player)
	S.AnnounceService:Notify(player, ("🥷 Heist started: defeat the %s!"):format(run.boss.name), "warn")
end

function EggHeistService:StealEgg(player: Player, heistId: string)
	local run = runs[player]
	if not run or run.heistId ~= heistId then
		S.AnnounceService:Notify(player, "Start the heist at the entrance first!", "warn")
		return
	end
	if not run.bossDead then
		S.AnnounceService:Notify(player, ("Defeat the %s first!"):format(run.boss.name), "warn")
		return
	end
	if S.CarryService:IsCarrying(player) then
		return
	end
	local egg = Eggs.List[run.def.egg]
	local started = S.CarryService:StartCarry(player, {
		kind = "Egg",
		label = "🥚 STOLEN " .. egg.displayName:upper(),
		speedMult = 0.85,
		timeout = 300,
		visual = function(parent: Instance, cf: CFrame)
			return Props.Egg(parent, cf * CFrame.new(0, -1, 0), egg, 0.6)
		end,
		deliverCheck = function()
			local inc = incubators[player]
			local root = S.EntityService:RootOf(player)
			return inc ~= nil and root ~= nil and (root.Position - inc.pos).Magnitude < 18
		end,
		onDeliver = function()
			self:Incubate(player, run.def.egg)
			self:EndRun(player, true, "delivered")
		end,
		onDrop = function(reason: string)
			run.carrier = nil
			if reason ~= "left" then
				S.AnnounceService:Notify(player, "The egg flew back to the nest! Go get it again.", "warn")
			end
			self:SendState(player)
		end,
	})
	if started then
		run.carrier = player
		self:SendState(player)
	end
end

function EggHeistService:Step(_dt: number)
	local now = os.clock()
	for player, run in runs do
		local root = S.EntityService:RootOf(player)
		if now - run.startedAt > RUN_TIMEOUT then
			self:EndRun(player, false, "timeout")
		elseif root and not run.carrier and (root.Position - run.center).Magnitude > ABANDON_DIST then
			self:EndRun(player, false, "abandoned")
		end
	end
	for player, inc in incubators do
		self:UpdateIncubatorLabel(player, inc)
	end
end

function EggHeistService:EndRun(player: Player, won: boolean, reason: string)
	local run = runs[player]
	if not run then
		return
	end
	runs[player] = nil
	if S.CarryService:IsCarrying(player) and reason ~= "delivered" then
		S.CarryService:Drop(player, "left")
	end
	S.ZombieService:DespawnEncounter(run)
	local d = S.DataService:Get(player)
	if d then
		if run.def.cooldown > 0 then
			d.heistCooldowns[run.heistId] = os.time() + run.def.cooldown
		end
		if won then
			S.DataService:IncrementStat(player, "heistsWon")
			S.DataService:AddXP(player, run.def.level * 30)
			local egg = Eggs.List[run.def.egg]
			S.AnnounceService:Announce(("🥚 %s stole a %s and made it home!"):format(player.DisplayName, egg.displayName), "reward", run.heistId == "DragonNest")
		elseif reason == "timeout" then
			S.AnnounceService:Notify(player, "⏰ Heist failed: the guards reset.", "error")
		end
	end
	if player.Parent then
		Net.Event("HeistState"):FireClient(player, nil)
	end
end

function EggHeistService:SendState(player: Player)
	local run = runs[player]
	if not run then
		Net.Event("HeistState"):FireClient(player, nil)
		return
	end
	Net.Event("HeistState"):FireClient(player, {
		name = run.def.name,
		egg = run.def.egg,
		bossName = run.boss and run.boss.name,
		bossDead = run.bossDead,
		carrying = run.carrier ~= nil,
		timeLeft = RUN_TIMEOUT - (os.clock() - run.startedAt),
		home = if incubators[player] then incubators[player].pos else nil,
	})
end

----------------------------------------------------------------------------
-- Incubator (lives on your plot)
----------------------------------------------------------------------------

function EggHeistService:IncubatorSlots(player: Player): number
	return INCUBATOR_SLOTS + (if S.MonetizationService:IsVIP(player) then 1 else 0)
end

function EggHeistService:OnPlotAssigned(player: Player, plot)
	local pos = plot.cf:PointToWorldSpace(Base.IncubatorOffset)
	incubators[player] = { plot = plot, pos = pos }
	self:RebuildIncubator(player)
end

function EggHeistService:OnPlotReleased(plot)
	for player, inc in incubators do
		if inc.plot == plot then
			if inc.model then
				inc.model:Destroy()
			end
			incubators[player] = nil
		end
	end
end

function EggHeistService:RebuildIncubator(player: Player)
	local inc = incubators[player]
	local d = S.DataService:Get(player)
	if not inc or not d then
		return
	end
	if inc.model then
		inc.model:Destroy()
	end
	local m = StudStyle.Model(inc.plot.model, "Incubator")
	inc.model = m
	local base = StudStyle.OnGround(m, Vector3.new(12, 1.5, 7), inc.pos, Color3.fromRGB(140, 96, 60), { name = "Nest" })
	for i = 1, self:IncubatorSlots(player) do
		local slotPos = inc.pos + inc.plot.cf:VectorToWorldSpace(Vector3.new((i - 2.5) * 3, 1.5, 0))
		StudStyle.Block(m, Vector3.new(2.6, 0.5, 2.6), CFrame.new(slotPos + Vector3.new(0, 0.25, 0)), Color3.fromRGB(230, 200, 130), { shadow = false })
		local entry = d.incubators[i]
		if entry then
			Props.Egg(m, CFrame.new(slotPos + Vector3.new(0, 0.5, 0)), Eggs.List[entry.egg], 0.55)
		end
	end
	inc.label = StudStyle.Label(base, "🥚 Incubator (steal eggs in heists!)", Color3.fromRGB(255, 230, 150), 90, 1)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hatch"
	prompt.ObjectText = "Incubator"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerUserId", player.UserId)
	CollectionService:AddTag(prompt, "OwnerOnlyPrompt")
	prompt.Parent = base
	prompt.Triggered:Connect(function(who)
		if who == player then
			self:HatchReady(player)
		end
	end)
	self:UpdateIncubatorLabel(player, inc)
end

function EggHeistService:UpdateIncubatorLabel(player: Player, inc)
	local d = S.DataService:Get(player)
	if not d or not inc.label then
		return
	end
	local text = inc.label:FindFirstChild("Text") :: TextLabel?
	if not text then
		return
	end
	if #d.incubators == 0 then
		text.Text = "🥚 Incubator (steal eggs in heists!)"
		return
	end
	local lines = {}
	for _, entry in d.incubators do
		local left = entry.readyAt - os.time()
		table.insert(lines, Eggs.List[entry.egg].displayName .. ": " .. (if left <= 0 then "READY!" else Format.Duration(left)))
	end
	text.Text = table.concat(lines, "\n")
end

function EggHeistService:Incubate(player: Player, eggId: string)
	local d = S.DataService:Get(player)
	local egg = Eggs.List[eggId]
	table.insert(d.incubators, { egg = eggId, readyAt = os.time() + egg.incubateSeconds })
	S.DataService:Replicate(player, "incubators")
	self:RebuildIncubator(player)
end

function EggHeistService:SkipIncubation(player: Player): boolean
	local d = S.DataService:Get(player)
	for _, entry in d.incubators do
		if entry.readyAt > os.time() then
			entry.readyAt = os.time()
			S.DataService:Replicate(player, "incubators")
			self:RebuildIncubator(player)
			return true
		end
	end
	return false
end

function EggHeistService:HatchReady(player: Player)
	local d = S.DataService:Get(player)
	if not d then
		return
	end
	local results = {}
	local remaining = {}
	local hatchedEgg = nil
	local now = os.time()
	for _, entry in d.incubators do
		if entry.readyAt <= now then
			hatchedEgg = hatchedEgg or entry.egg
			local species, variant = S.PetService:RollEgg(player, entry.egg)
			local uid = S.PetService:GrantPet(player, species, variant, { ignoreCap = true })
			table.insert(results, { uid = uid, species = species, variant = variant })
		else
			table.insert(remaining, entry)
		end
	end
	if #results == 0 then
		S.AnnounceService:Notify(player, "Nothing is ready to hatch yet.", "info")
		return
	end
	d.incubators = remaining
	S.DataService:Replicate(player, "incubators")
	S.DataService:IncrementStat(player, "eggsHatched", #results)
	self:RebuildIncubator(player)
	Net.Event("HatchResult"):FireClient(player, { ok = true, results = results, egg = hatchedEgg })
end

return EggHeistService
