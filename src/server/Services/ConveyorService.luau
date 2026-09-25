--[[
	ConveyorService: the tycoon half of every base.

	Droppers drop Mutagen Goo onto the belt; the collector sells it. The
	server never moves items. It credits income once per second from a
	formula, and clients draw the goo sliding along the belt at the same
	rate (see client ConveyorVisuals). Zero physics, zero network per item.

	Income/s = sum(dropper value * (1 + level * 0.35)) / dropInterval
	           * beltSpeed * (2 with the 2x Conveyor pass) * coin mults

	The Brainrot Extractor rolls a Mutation Capsule on a timer and drops it
	into your vault, where other players can try to steal it.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Base = require(Shared.Config.Base)
local Progression = require(Shared.Config.Progression)
local StudStyle = require(Shared.Art.StudStyle)
local Format = require(Shared.Util.Format)

local C = StudStyle.Colors
local CONV = Base.Conveyor

local ConveyorService = { Name = "ConveyorService" }

local S
local active: { [Player]: any } = {}

local DROPPER_COLORS = {
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(120, 230, 120),
	Color3.fromRGB(255, 210, 80),
	Color3.fromRGB(255, 130, 60),
	Color3.fromRGB(220, 90, 255),
	Color3.fromRGB(255, 70, 120),
}

function ConveyorService:Init(services)
	S = services
end

function ConveyorService:Start() end

----------------------------------------------------------------------------
-- Economy
----------------------------------------------------------------------------

function ConveyorService:BeltSpeed(player: Player): number
	local d = S.DataService:Get(player)
	local speed = CONV.belts[d.base.belt].speed
	if S.MonetizationService:HasPass(player, "DoubleConveyor") then
		speed *= 2
	end
	return speed
end

-- Returns coins/s and mutagen/s before coin multipliers.
function ConveyorService:Rates(player: Player): (number, number)
	local d = S.DataService:Get(player)
	if not d then
		return 0, 0
	end
	local coins, mutagen = 0, 0
	for i, level in d.base.droppers do
		local def = CONV.droppers[i]
		if def and level > 0 then
			local mult = 1 + (level - 1) * CONV.dropperLevelMult
			coins += def.value * mult
			mutagen += def.mutagen * mult
		end
	end
	local speed = self:BeltSpeed(player)
	return coins / CONV.dropInterval * speed, mutagen / CONV.dropInterval * speed
end

function ConveyorService:Step(dt: number)
	local now = os.clock()
	for player, state in active do
		local coinsPerSec, mutagenPerSec = self:Rates(player)
		S.DataService:Add(player, "coins", coinsPerSec * dt)
		state.mutagenAcc += mutagenPerSec * dt
		if state.mutagenAcc >= 1 then
			local whole = math.floor(state.mutagenAcc)
			state.mutagenAcc -= whole
			S.DataService:Add(player, "mutagen", whole, true)
		end
		local d = S.DataService:Get(player)
		local ex = CONV.extractors[d.base.extractor]
		if ex and now >= state.nextCapsule then
			state.nextCapsule = now + ex.interval
			S.MutationService:AddCapsule(player, S.MutationService:RollMutation(ex.rarityBias), "extractor")
		end
	end
end

function ConveyorService:OnPlotAssigned(player: Player, plot)
	local d = S.DataService:Get(player)
	local state = { plot = plot, mutagenAcc = 0, nextCapsule = os.clock() + 30 }
	active[player] = state
	self:Rebuild(player)

	-- Offline earnings: a reason to come back tomorrow.
	if d.lastOnline and d.lastOnline > 0 then
		local cap = if S.MonetizationService:IsVIP(player) then Progression.OfflineCapSecondsVip else Progression.OfflineCapSeconds
		local away = math.min(os.time() - d.lastOnline, cap)
		if away > 60 then
			local rate = self:Rates(player)
			local earned = S.DataService:Add(player, "coins", rate * away * Progression.OfflineRate)
			if earned >= 1 then
				S.AnnounceService:Notify(player, ("💤 Your conveyor earned 💰%s while you were away (%s)"):format(Format.Short(earned), Format.Duration(away)), "reward")
			end
		end
	end
end

function ConveyorService:OnPlotReleased(plot)
	for player, state in active do
		if state.plot == plot then
			if state.model then
				state.model:Destroy()
			end
			active[player] = nil
		end
	end
	plot.info:SetAttribute("Droppers", nil)
end

----------------------------------------------------------------------------
-- Visuals + buy buttons
----------------------------------------------------------------------------

local function at(plot, pos: Vector3): Vector3
	return plot.cf:PointToWorldSpace(pos)
end

local function lcf(plot, pos: Vector3): CFrame
	return plot.cf * CFrame.new(pos)
end

function ConveyorService:Rebuild(player: Player)
	local state = active[player]
	local d = S.DataService:Get(player)
	if not state or not d then
		return
	end
	local plot = state.plot
	if state.model then
		state.model:Destroy()
	end
	local m = StudStyle.Model(plot.model, "Conveyor")
	state.model = m

	-- Belt
	local startP, finishP = CONV.start, CONV.finish
	local len = (finishP - startP).Magnitude
	local mid = (startP + finishP) / 2
	StudStyle.Block(m, Vector3.new(5, 1.2, len), lcf(plot, mid + Vector3.new(0, 0.6, 0)), C.Belt, { studs = false, material = Enum.Material.SmoothPlastic, name = "Belt" })
	for _, sx in { -1, 1 } do
		StudStyle.Block(m, Vector3.new(0.6, 1.8, len), lcf(plot, mid + Vector3.new(sx * 2.8, 0.9, 0)), Color3.fromRGB(250, 200, 40), { studs = false, material = Enum.Material.SmoothPlastic })
	end
	-- Collector
	local bin = StudStyle.OnGround(m, Vector3.new(7, 4, 6), at(plot, finishP + Vector3.new(0, 0, 3)), Color3.fromRGB(60, 160, 80))
	StudStyle.Neon(m, Vector3.new(6, 0.3, 5), lcf(plot, finishP + Vector3.new(0, 4.1, 3)), Color3.fromRGB(120, 255, 140))
	StudStyle.Label(bin, "💰 SELL", Color3.fromRGB(140, 255, 150), 80, 0.8)

	-- Belt upgrade button
	local beltLevel = d.base.belt
	local nextBelt = CONV.belts[beltLevel + 1]
	local beltPad = StudStyle.OnGround(m, Vector3.new(4, 0.8, 4), at(plot, startP + Vector3.new(0, 0, -6)), Color3.fromRGB(250, 200, 40), { name = "BeltButton" })
	StudStyle.Label(beltPad, ("⏩ Belt Lv%d"):format(beltLevel), Color3.fromRGB(255, 230, 120), 50, 0.6)
	if nextBelt then
		self:Button(player, beltPad, "Upgrade Belt", "💰" .. Format.Short(nextBelt.price), function()
			self:Buy(player, nextBelt.price, function()
				d.base.belt += 1
			end, "Belt upgraded!")
		end)
	end

	-- Droppers
	for i, def in CONV.droppers do
		local level = d.base.droppers[i] or 0
		local pos = def.offset
		if level > 0 then
			local color = DROPPER_COLORS[i]
			local tower = StudStyle.OnGround(m, Vector3.new(4, 6, 4), at(plot, pos), color, { name = "Dropper" .. i })
			StudStyle.Block(m, Vector3.new(4.5, 1, 4.5), lcf(plot, pos + Vector3.new(0, 6.5, 0)), C.DarkStone)
			local chuteDir = if pos.X < CONV.start.X then 1 else -1
			StudStyle.Block(m, Vector3.new(3.5, 1, 1.4), lcf(plot, pos + Vector3.new(chuteDir * 3.2, 4.6, 0)), C.DarkStone, { shadow = false })
			StudStyle.Label(tower, ("Dropper %d · Lv%d"):format(i, level), color, 60, 0.6)
			local cost = CONV.dropperUpgradeCost(i, level)
			self:Button(player, tower, ("Upgrade Dropper %d"):format(i), "💰" .. Format.Short(cost), function()
				self:Buy(player, cost, function()
					d.base.droppers[i] = level + 1
				end, ("Dropper %d is now Lv%d"):format(i, level + 1))
			end)
		else
			local prev = if i == 1 then 1 else d.base.droppers[i - 1] or 0
			if prev > 0 then
				local pad = StudStyle.OnGround(m, Vector3.new(4, 0.8, 4), at(plot, pos), Color3.fromRGB(90, 200, 90), { name = "DropperPad" .. i })
				StudStyle.Label(pad, ("➕ Dropper %d"):format(i), Color3.fromRGB(160, 255, 160), 50, 0.6)
				self:Button(player, pad, ("Buy Dropper %d"):format(i), "💰" .. Format.Short(def.price), function()
					self:Buy(player, def.price, function()
						d.base.droppers[i] = 1
					end, ("Dropper %d built!"):format(i))
				end)
			end
		end
	end

	-- Brainrot Extractor
	local exLevel = d.base.extractor
	local nextEx = CONV.extractors[exLevel + 1]
	local exPos = CONV.extractorOffset
	local machine
	if exLevel > 0 then
		machine = StudStyle.OnGround(m, Vector3.new(7, 7, 7), at(plot, exPos), Color3.fromRGB(150, 70, 220), { name = "Extractor" })
		StudStyle.Neon(m, Vector3.new(4, 3, 4), lcf(plot, exPos + Vector3.new(0, 8.5, 0)), Color3.fromRGB(255, 120, 220))
		StudStyle.Label(machine, ("🧠 Brainrot Extractor Lv%d"):format(exLevel), Color3.fromRGB(255, 160, 255), 70, 0.7)
	else
		machine = StudStyle.OnGround(m, Vector3.new(6, 0.8, 6), at(plot, exPos), Color3.fromRGB(150, 70, 220), { name = "ExtractorPad" })
		StudStyle.Label(machine, "🧠 Build Brainrot Extractor", Color3.fromRGB(255, 160, 255), 60, 0.6)
	end
	if nextEx then
		self:Button(player, machine, if exLevel == 0 then "Build Extractor" else "Upgrade Extractor", "💰" .. Format.Short(nextEx.price), function()
			self:Buy(player, nextEx.price, function()
				d.base.extractor += 1
			end, "🧠 Extractor upgraded: capsules roll faster and rarer!")
		end)
	end

	-- Client visuals read these
	local levels = {}
	for i = 1, #CONV.droppers do
		levels[i] = tostring(d.base.droppers[i] or 0)
	end
	plot.info:SetAttribute("Droppers", table.concat(levels, ","))
	plot.info:SetAttribute("BeltSpeed", self:BeltSpeed(player))
	local coinsPerSec = self:Rates(player)
	plot.info:SetAttribute("IncomePerSec", coinsPerSec * S.DataService:CoinMultiplier(player))
end

function ConveyorService:Button(player: Player, part: BasePart, action: string, cost: string, onBuy: () -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = cost
	p.HoldDuration = 0.2
	p.MaxActivationDistance = 11
	p.RequiresLineOfSight = false
	p:SetAttribute("OwnerUserId", player.UserId)
	CollectionService:AddTag(p, "OwnerOnlyPrompt")
	p.Parent = part
	p.Triggered:Connect(function(who)
		if who == player then
			onBuy()
		end
	end)
end

function ConveyorService:Buy(player: Player, price: number, apply: () -> (), message: string)
	if not S.DataService:Spend(player, "coins", price) then
		S.AnnounceService:Notify(player, ("Need 💰%s"):format(Format.Short(price)), "warn")
		return
	end
	apply()
	S.DataService:Replicate(player, "base")
	S.AnnounceService:Notify(player, message, "good")
	self:Rebuild(player)
end

-- Rebirth wipes the conveyor; called by RewardsService.
function ConveyorService:ResetForRebirth(player: Player)
	local d = S.DataService:Get(player)
	d.base.droppers = { 1, 0, 0, 0, 0, 0 }
	d.base.belt = 1
	S.DataService:Replicate(player, "base")
	self:Rebuild(player)
end

return ConveyorService
