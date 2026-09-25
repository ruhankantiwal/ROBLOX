--[[
	PlotService: the eight Farm Bases on Farm Row.

	Each plot has: a Barn Heart (core) the zombies want, a Graveyard Rift
	they pour out of, six Build Pads for Build & Kill defenses, a conveyor
	(ConveyorService), a capsule vault (MutationService), an incubator
	(EggHeistService), a Start Wave button and a Lock Base button.

	Prompt visibility: prompts tagged "OwnerOnlyPrompt" are shown only to
	the plot owner and "VisitorPrompt" only to everyone else (the client
	filters by the prompt's OwnerUserId attribute).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local Base = require(Shared.Config.Base)
local StudStyle = require(Shared.Art.StudStyle)
local Protocol = require(Shared.Util.EntityProtocol)
local Format = require(Shared.Util.Format)

local EV = Protocol.Event
local C = StudStyle.Colors

local PlotService = { Name = "PlotService" }

local S
local plots = {}
local byPlayer: { [Player]: any } = {}
local infoFolder: Folder

local function lcf(plot, pos: Vector3, yaw: number?): CFrame
	return plot.cf * CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)
end

local function at(plot, pos: Vector3): Vector3
	return plot.cf:PointToWorldSpace(pos)
end

function PlotService:Init(services)
	S = services
end

function PlotService:Start()
	infoFolder = Instance.new("Folder")
	infoFolder.Name = "PlotInfo"
	infoFolder.Parent = ReplicatedStorage

	local root = workspace:FindFirstChild("Plots") or Instance.new("Folder")
	root.Name = "Plots"
	root.Parent = workspace

	for i = 1, World.PlotCount do
		plots[i] = self:BuildPlot(i, root)
	end

	S.DataService.PlayerLoaded:Connect(function(player)
		self:Assign(player)
	end)
	S.DataService.PlayerLeaving:Connect(function(player)
		self:Release(player)
	end)
	Net.Event("LockBase").OnServerEvent:Connect(function(player)
		self:Lock(player)
	end)
end

----------------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------------

local function prompt(parent: Instance, action: string, object: string, tag: string, hold: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0.25
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	p.Parent = parent
	CollectionService:AddTag(p, tag)
	return p
end

function PlotService:BuildPlot(index: number, parentFolder: Instance)
	local plot = {
		index = index,
		cf = World.PlotCFrame(index),
		owner = nil,
		defenses = {},
		pads = {},
		lockedUntil = 0,
		lockCooldownUntil = 0,
		coreMax = Base.Core.maxHp,
		coreHp = Base.Core.maxHp,
	}
	plot.corePos = at(plot, Base.CoreOffset)
	plot.riftPos = at(plot, Base.RiftOffset)
	plot.spawnCF = lcf(plot, Base.SpawnOffset + Vector3.new(0, 4, 0), math.pi)

	local model = StudStyle.Model(parentFolder, "Plot_" .. index)
	plot.model = model
	local size = Base.PlotSize
	local half = size / 2

	-- Farm floor + field rows
	StudStyle.Block(model, Vector3.new(size, 0.2, size), lcf(plot, Vector3.new(0, 0.1, 0)), Color3.fromRGB(110, 190, 84))
	StudStyle.Block(model, Vector3.new(14, 0.3, 30), lcf(plot, Vector3.new(0, 0.15, 44)), C.Path, { name = "Path" })

	-- Fence with a gate gap at the front (+Z)
	local fence = StudStyle.Model(model, "Fence")
	local function rail(pos: Vector3, len: number, alongX: boolean)
		local s = if alongX then Vector3.new(len, 0.5, 0.5) else Vector3.new(0.5, 0.5, len)
		StudStyle.Block(fence, s, lcf(plot, pos + Vector3.new(0, 2.6, 0)), C.White, { shadow = false })
		StudStyle.Block(fence, s, lcf(plot, pos + Vector3.new(0, 1.4, 0)), C.White, { shadow = false })
	end
	rail(Vector3.new(0, 0, -half), size, true)
	rail(Vector3.new(-half, 0, 0), size, false)
	rail(Vector3.new(half, 0, 0), size, false)
	local gap = 16
	local seg = (size - gap) / 2
	rail(Vector3.new(-half + seg / 2, 0, half), seg, true)
	rail(Vector3.new(half - seg / 2, 0, half), seg, true)
	for k = 0, 10 do
		local t = -half + k * (size / 10)
		for _, p in { Vector3.new(t, 0, -half), Vector3.new(-half, 0, t), Vector3.new(half, 0, t) } do
			StudStyle.OnGround(fence, Vector3.new(0.9, 3.4, 0.9), at(plot, p), C.White, { shadow = false })
		end
	end

	-- Graveyard Rift (zombie spawn)
	local rift = StudStyle.Model(model, "Rift")
	for _, sx in { -1, 1 } do
		StudStyle.OnGround(rift, Vector3.new(3, 12, 3), at(plot, Base.RiftOffset + Vector3.new(sx * 8, 0, 0)), C.DarkStone)
	end
	StudStyle.Block(rift, Vector3.new(20, 2, 3.4), lcf(plot, Base.RiftOffset + Vector3.new(0, 13, 0)), C.DarkStone)
	StudStyle.Neon(rift, Vector3.new(13, 11, 0.6), lcf(plot, Base.RiftOffset + Vector3.new(0, 5.8, 0)), Color3.fromRGB(150, 60, 220))
	for k, x in { -16, 14, 22 } do
		StudStyle.OnGround(rift, Vector3.new(2.4, 3.2, 0.8), at(plot, Base.RiftOffset + Vector3.new(x, 0, 6 + k)), C.Stone, { shadow = false })
	end

	-- Barn Heart (core)
	local core = StudStyle.Model(model, "BarnHeart")
	local cpos = Base.CoreOffset
	StudStyle.OnGround(core, Vector3.new(12, 7, 9), at(plot, cpos), C.Red)
	StudStyle.Block(core, Vector3.new(12.4, 0.6, 9.4), lcf(plot, cpos + Vector3.new(0, 7.1, 0)), C.White)
	for _, sx in { -1, 1 } do
		StudStyle.Block(core, Vector3.new(7.2, 0.8, 9.8), lcf(plot, cpos + Vector3.new(sx * 3.1, 9, 0)) * CFrame.Angles(0, 0, sx * -0.55), C.DarkWood)
	end
	StudStyle.Block(core, Vector3.new(3.4, 4.6, 0.4), lcf(plot, cpos + Vector3.new(0, 2.3, 4.6)), C.White, { collide = false })
	local gem = StudStyle.Neon(core, Vector3.new(2.4, 2.4, 2.4), lcf(plot, cpos + Vector3.new(0, 14, 0)) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 60, 90))
	gem.Name = "HeartGem"
	plot.coreBar = self:MakeBar(gem, "Barn Heart")

	-- Build pads
	for i, offset in Base.BuildPads do
		local pad = StudStyle.Block(model, Vector3.new(7, 0.6, 7), lcf(plot, offset + Vector3.new(0, 0.3, 0)), Color3.fromRGB(150, 110, 70), { name = "BuildPad" .. i })
		local pr = prompt(pad, "Build", "", "OwnerOnlyPrompt")
		pr.Triggered:Connect(function(player)
			self:OnPadTriggered(player, plot, i)
		end)
		plot.pads[i] = { part = pad, prompt = pr, offset = offset }
	end

	-- Buttons: Start Wave / Lock Base
	local waveBtn = StudStyle.OnGround(model, Vector3.new(5, 1, 5), at(plot, Base.WaveButtonOffset), Color3.fromRGB(70, 200, 90), { name = "WaveButton" })
	StudStyle.Label(waveBtn, "🧟 START WAVE", Color3.fromRGB(140, 255, 140), 60, 0.7)
	prompt(waveBtn, "Start Wave", "Barn Heart", "OwnerOnlyPrompt").Triggered:Connect(function(player)
		if self:GetPlot(player) == plot then
			S.ZombieService:StartWave(player)
		end
	end)
	local lockBtn = StudStyle.OnGround(model, Vector3.new(5, 1, 5), at(plot, Base.LockButtonOffset), Color3.fromRGB(220, 70, 70), { name = "LockButton" })
	StudStyle.Label(lockBtn, "🔒 LOCK BASE", Color3.fromRGB(255, 150, 150), 60, 0.7)
	prompt(lockBtn, "Lock Base", "Stops thieves", "OwnerOnlyPrompt").Triggered:Connect(function(player)
		if self:GetPlot(player) == plot then
			self:Lock(player)
		end
	end)

	-- Laser gate shown while locked
	local laser = StudStyle.Neon(model, Vector3.new(16, 6, 0.3), lcf(plot, Vector3.new(0, 3, half)), Color3.fromRGB(255, 40, 40))
	laser.Name = "LockLaser"
	laser.Transparency = 1
	plot.laser = laser

	-- Sign
	StudStyle.OnGround(model, Vector3.new(1, 7, 1), at(plot, Vector3.new(-12, 0, half + 2)), C.DarkWood)
	local board = StudStyle.Block(model, Vector3.new(14, 4, 0.8), lcf(plot, Vector3.new(-12, 8, half + 2)), C.Wood, { name = "Sign" })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.PixelsPerStud = 30
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = "Empty Farm"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = text
	text.Parent = gui
	gui.Parent = board
	plot.signText = text

	-- Replicated info for client-side visuals (conveyor items, lock timer)
	local info = Instance.new("Folder")
	info.Name = "Plot_" .. index
	info:SetAttribute("Index", index)
	info:SetAttribute("OwnerUserId", 0)
	info.Parent = infoFolder
	plot.info = info

	return plot
end

function PlotService:MakeBar(adornee: BasePart, title: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 42)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.MaxDistance = 150
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = title
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	local back = Instance.new("Frame")
	back.Position = UDim2.fromScale(0, 0.55)
	back.Size = UDim2.fromScale(1, 0.4)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 70, 100)
	fill.BorderSizePixel = 0
	corner:Clone().Parent = fill
	fill.Parent = back
	back.Parent = gui
	gui.Parent = adornee
	return fill
end

----------------------------------------------------------------------------
-- Ownership
----------------------------------------------------------------------------

function PlotService:Assign(player: Player)
	local plot = nil
	for _, p in plots do
		if not p.owner then
			plot = p
			break
		end
	end
	if not plot then
		S.AnnounceService:Notify(player, "All farms are taken on this server!", "error")
		return
	end
	plot.owner = player
	byPlayer[player] = plot
	plot.signText.Text = player.DisplayName .. "'s Farm"
	plot.info:SetAttribute("OwnerUserId", player.UserId)
	plot.info:SetAttribute("OwnerName", player.DisplayName)
	for _, prompt in plot.model:GetDescendants() do
		if prompt:IsA("ProximityPrompt") then
			prompt:SetAttribute("OwnerUserId", player.UserId)
		end
	end
	player:SetAttribute("PlotIndex", plot.index)

	local d = S.DataService:Get(player)
	for i = 1, #Base.BuildPads do
		local tier = d.base.defenses[tostring(i)] or 0
		self:SetDefense(plot, i, tier)
	end
	self:SetCoreHp(plot, plot.coreMax)

	local function toPlot(character: Model)
		task.defer(function()
			if character.Parent and byPlayer[player] == plot then
				character:PivotTo(plot.spawnCF)
			end
		end)
	end
	plot.charConn = player.CharacterAdded:Connect(toPlot)
	if player.Character then
		toPlot(player.Character)
	end

	S.ConveyorService:OnPlotAssigned(player, plot)
	S.MutationService:OnPlotAssigned(player, plot)
	S.EggHeistService:OnPlotAssigned(player, plot)
end

function PlotService:Release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	S.ZombieService:EndWave(player, "left")
	byPlayer[player] = nil
	if plot.charConn then
		plot.charConn:Disconnect()
		plot.charConn = nil
	end
	for i in plot.defenses do
		self:ClearDefenseModel(plot, i)
	end
	plot.defenses = {}
	plot.owner = nil
	plot.lockedUntil = 0
	plot.laser.Transparency = 1
	plot.signText.Text = "Empty Farm"
	plot.info:SetAttribute("OwnerUserId", 0)
	plot.info:SetAttribute("OwnerName", nil)
	S.ConveyorService:OnPlotReleased(plot)
	S.MutationService:OnPlotReleased(plot)
	S.EggHeistService:OnPlotReleased(plot)
end

function PlotService:GetPlot(player: Player)
	return byPlayer[player]
end

function PlotService:Plots()
	return plots
end

function PlotService:IsOnPlot(player: Player, margin: number?): boolean
	local plot = byPlayer[player]
	local root = S.EntityService:RootOf(player)
	if not plot or not root then
		return false
	end
	local localPos = plot.cf:PointToObjectSpace(root.Position)
	local half = Base.PlotSize / 2 + (margin or 0)
	return math.abs(localPos.X) < half and math.abs(localPos.Z) < half
end

function PlotService:PlotAt(pos: Vector3)
	for _, plot in plots do
		local l = plot.cf:PointToObjectSpace(pos)
		if math.abs(l.X) < Base.PlotSize / 2 and math.abs(l.Z) < Base.PlotSize / 2 then
			return plot
		end
	end
	return nil
end

----------------------------------------------------------------------------
-- Core
----------------------------------------------------------------------------

function PlotService:SetCoreHp(plot, hp: number)
	plot.coreHp = math.clamp(hp, 0, plot.coreMax)
	plot.coreBar.Size = UDim2.fromScale(plot.coreHp / plot.coreMax, 1)
end

function PlotService:DamageCore(plot, amount: number)
	self:SetCoreHp(plot, plot.coreHp - amount)
	S.EntityService:Event(plot.corePos, { EV.Beam, "CoreHit", plot.corePos.X, plot.corePos.Y + 14, plot.corePos.Z, plot.corePos.X, plot.corePos.Y + 14, plot.corePos.Z })
end

----------------------------------------------------------------------------
-- Build & Kill defenses
----------------------------------------------------------------------------

function PlotService:OnPadTriggered(player: Player, plot, padIndex: number)
	if plot.owner ~= player then
		return
	end
	local d = S.DataService:Get(player)
	local key = tostring(padIndex)
	local tier = d.base.defenses[key] or 0
	local nextDef = Base.Defenses[tier + 1]
	if not nextDef then
		S.AnnounceService:Notify(player, "This defense is fully upgraded!", "info")
		return
	end
	if not S.DataService:Spend(player, "coins", nextDef.price) then
		S.AnnounceService:Notify(player, ("Need 💰%s for %s."):format(Format.Short(nextDef.price), nextDef.name), "warn")
		return
	end
	d.base.defenses[key] = tier + 1
	S.DataService:Replicate(player, "base")
	self:SetDefense(plot, padIndex, tier + 1)
	S.AnnounceService:Notify(player, ("Built %s!"):format(nextDef.name), "good")
end

function PlotService:ClearDefenseModel(plot, padIndex: number)
	local d = plot.defenses[padIndex]
	if d and d.model then
		d.model:Destroy()
	end
end

function PlotService:SetDefense(plot, padIndex: number, tier: number)
	self:ClearDefenseModel(plot, padIndex)
	plot.defenses[padIndex] = nil
	local pad = plot.pads[padIndex]
	local nextDef = Base.Defenses[tier + 1]
	pad.prompt.ActionText = if nextDef then (if tier == 0 then "Build " else "Upgrade: ") .. nextDef.name else "Maxed"
	pad.prompt.ObjectText = if nextDef then "💰" .. Format.Short(nextDef.price) else ""
	pad.prompt.Enabled = nextDef ~= nil
	if tier <= 0 then
		return
	end
	local def = Base.Defenses[tier]
	local pos = at(plot, pad.offset)
	local defense = {
		pad = padIndex,
		tier = tier,
		def = def,
		hp = def.hp,
		maxHp = def.hp,
		pos = pos,
		radius = def.radius,
		broken = false,
		nextFire = 0,
	}
	defense.model = self:BuildDefenseModel(plot, pad.offset, def)
	plot.defenses[padIndex] = defense
end

function PlotService:BuildDefenseModel(plot, offset: Vector3, def)
	local m = StudStyle.Model(plot.model, "Defense_" .. def.id)
	local base = offset + Vector3.new(0, 0.6, 0)
	if def.id == "HayWall" then
		for k = 0, 1 do
			StudStyle.OnGround(m, Vector3.new(7, 2.4, 3), at(plot, base + Vector3.new(0, k * 2.4, 0)), C.Hay)
		end
	elseif def.id == "SpikeWall" then
		StudStyle.OnGround(m, Vector3.new(7.5, 5, 2), at(plot, base), C.Wood)
		for k = -1, 1 do
			StudStyle.Block(m, Vector3.new(0.6, 0.6, 3.2), lcf(plot, base + Vector3.new(k * 2.4, 3, -2)) * CFrame.Angles(0.5, 0, 0), C.Stone, { shadow = false })
		end
	else
		local color = if def.id == "BlazeCannon" then C.Red else Color3.fromRGB(80, 170, 255)
		StudStyle.OnGround(m, Vector3.new(4, 2.5, 4), at(plot, base), C.DarkStone)
		StudStyle.OnGround(m, Vector3.new(3, 2.4, 3), at(plot, base + Vector3.new(0, 2.5, 0)), color)
		StudStyle.Block(m, Vector3.new(1, 1, 3.6), lcf(plot, base + Vector3.new(0, 3.7, -2.4)), C.DarkStone, { shadow = false })
		StudStyle.Neon(m, Vector3.new(0.7, 0.7, 0.3), lcf(plot, base + Vector3.new(0, 3.7, -4.3)), if def.id == "BlazeCannon" then C.Lava else C.Crystal)
	end
	return m
end

function PlotService:SetDefenseBroken(d, broken: boolean)
	d.broken = broken
	for _, p in d.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = if broken then 0.6 else 0
			p.CanCollide = not broken
		end
	end
end

function PlotService:DamageDefense(plot, d, amount: number, attacker)
	if d.broken then
		return
	end
	d.hp -= amount
	if d.def.thorns and attacker then
		S.CombatService:Damage(nil, attacker, d.def.thorns * (1 + (plot.owner and S.DataService:Get(plot.owner).base.wave or 0) * 0.15), { fx = "Thorns", canCrit = false })
	end
	if d.hp <= 0 then
		self:SetDefenseBroken(d, true)
		S.EntityService:Event(d.pos, { EV.Beam, "DefenseBroken", d.pos.X, d.pos.Y + 2, d.pos.Z, d.pos.X, d.pos.Y + 6, d.pos.Z })
	end
end

function PlotService:RepairDefenses(plot)
	for _, d in plot.defenses do
		d.hp = d.maxHp
		if d.broken then
			self:SetDefenseBroken(d, false)
		end
	end
end

-- First intact defense a zombie walking from `from` to `to` would bump.
function PlotService:BlockingDefense(plot, from: Vector3, to: Vector3, radius: number)
	local seg = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local len2 = seg:Dot(seg)
	local best, bestT = nil, math.huge
	for _, d in plot.defenses do
		if not d.broken then
			local rel = Vector3.new(d.pos.X - from.X, 0, d.pos.Z - from.Z)
			local near = rel.Magnitude < d.radius + radius + 1.5
			local t = if len2 > 0 then math.clamp(rel:Dot(seg) / len2, 0, 1) else 0
			local closest = seg * t
			local off = (rel - closest).Magnitude
			if near or (d.def.block and off < d.radius + radius and t > 0 and t < 1) then
				local score = if near then -1 else t
				if score < bestT then
					best, bestT = d, score
				end
			end
		end
	end
	return best
end

-- Turrets fire at the plot's wave zombies.
function PlotService:StepDefenses(_dt: number)
	local now = os.clock()
	for _, plot in plots do
		local owner = plot.owner
		if owner and S.ZombieService:GetWave(owner) then
			for _, d in plot.defenses do
				local def = d.def
				if def.range and not d.broken and now >= d.nextFire then
					local targets = S.ZombieService:Query(d.pos, def.range, owner.UserId)
					local best, bestD = nil, math.huge
					for _, z in targets do
						local dist = (z.pos - d.pos).Magnitude
						if dist < bestD then
							best, bestD = z, dist
						end
					end
					if best then
						d.nextFire = now + 1 / def.fireRate
						local wave = S.DataService:Get(owner).base.wave
						local damage = def.damage * (1 + wave * 0.12)
						local muzzle = d.pos + Vector3.new(0, 4.5, 0)
						S.EntityService:Event(d.pos, { EV.Beam, def.id, muzzle.X, muzzle.Y, muzzle.Z, best.pos.X, best.pos.Y + 2, best.pos.Z })
						if def.splash then
							S.CombatService:Burst(nil, best.pos, def.splash, damage, if def.burn then { status = "Burn", dps = 0.4, duration = 3 } else nil, "FireBurst", owner.UserId)
						else
							S.CombatService:Damage(nil, best, damage, { fx = "Turret" })
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------------
-- Base lock (anti-steal)
----------------------------------------------------------------------------

function PlotService:IsLocked(plot): boolean
	return os.time() < plot.lockedUntil
end

function PlotService:Lock(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	local now = os.time()
	if now < plot.lockCooldownUntil then
		S.AnnounceService:Notify(player, ("Lock recharging: %s"):format(Format.Duration(plot.lockCooldownUntil - now)), "warn")
		return
	end
	local duration = if S.MonetizationService:IsVIP(player) then Base.Lock.durationVip else Base.Lock.duration
	plot.lockedUntil = now + duration
	plot.lockCooldownUntil = plot.lockedUntil + Base.Lock.cooldown
	plot.info:SetAttribute("LockedUntil", plot.lockedUntil)
	plot.laser.Transparency = 0.35
	S.AnnounceService:Notify(player, ("🔒 Base locked for %ds"):format(duration), "good")
	task.delay(duration, function()
		if plot.owner == player and os.time() >= plot.lockedUntil then
			plot.laser.Transparency = 1
		end
	end)
end

return PlotService
