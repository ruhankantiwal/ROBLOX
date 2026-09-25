--[[
	WorldBuilder: builds The Long Valley from studded blocks at server start.

	Layout (walking away from spawn along +Z):
	  Barnyard Plaza (hub)  eggs, Fruit Dealer, Brainrot Belt, rebirth
	  Farm Row              8 player bases (PlotService)
	  Meadow Fields         camps, Hay Tower parkour, Chicken Coop heist
	  Whispering Woods  10  pine forest, Treetop Trail, Hollow Stump dungeon
	  Crystal Canyon    25  narrow canyon, Crystal Spire parkour
	  Volcano Ridge     40  lava, the volcano rim secret
	  Dragon's Nest     50  the Dragon Egg heist

	Performance budget: ~4-5k parts total, all Plastic/SmoothPlastic/Neon,
	flat rows merged into single parts, props without shadows, and
	StreamingEnabled so phones only load what is near them.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Eggs = require(Shared.Config.Eggs)
local Fruits = require(Shared.Config.Fruits)
local Pets = require(Shared.Config.Pets)
local StudStyle = require(Shared.Art.StudStyle)
local Props = require(Shared.Art.Props)
local BlockyBuilder = require(Shared.Art.BlockyBuilder)
local Format = require(Shared.Util.Format)

local C = StudStyle.Colors
local T = World.Tile

local WorldBuilder = { Name = "WorldBuilder" }

local S
local rng = Random.new(World.Seed)
local worldFolder: Folder

function WorldBuilder:Init(services)
	S = services
end

function WorldBuilder:Start()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = workspace
	if not workspace:FindFirstChild("Plots") then
		local plots = Instance.new("Folder")
		plots.Name = "Plots"
		plots.Parent = workspace
	end

	self:Atmosphere()
	self:Ground()
	self:Road()
	self:Hub()
	self:ZoneGates()
	self:Decorate()
	self:Landmarks()
	self:HeistStructures()
	self:Dungeon()
	self:FruitSpawns()
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local function folder(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = worldFolder
	return f
end

local function ground(x: number, z: number): Vector3
	return Vector3.new(x, World.GroundHeight(x, z), z)
end

local function fruitAnchor(parent: Instance, pos: Vector3, hidden: boolean)
	local a = Instance.new("Part")
	a.Name = "FruitSpawn"
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.new(1, 1, 1)
	a.Position = pos + Vector3.new(0, 0.5, 0)
	a:SetAttribute("Hidden", hidden)
	a.Parent = parent
	CollectionService:AddTag(a, "FruitSpawn")
end

-- Turns a BlockyBuilder rig into static parts (statues, mascots).
function WorldBuilder:Statue(parent: Instance, body, cf: CFrame, opts, tint: Color3?): Model
	local rig = BlockyBuilder.Build(body, opts)
	local model = StudStyle.Model(parent, "Statue")
	for _, spec in rig.parts do
		local color = if tint and spec.role ~= "eye" then spec.color:Lerp(tint, 0.75) else spec.color
		StudStyle.Block(model, spec.size, cf * rig.groups[spec.group] * spec.localCF, color, {
			material = if spec.material == Enum.Material.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			studs = false,
			shadow = true,
		})
	end
	return model
end

local function prompt(parent: Instance, action: string, object: string, tag: string?, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0.2
	p.MaxActivationDistance = distance or 12
	p.RequiresLineOfSight = false
	p.Parent = parent
	if tag then
		CollectionService:AddTag(p, tag)
	end
	return p
end

----------------------------------------------------------------------------
-- Sky
----------------------------------------------------------------------------

function WorldBuilder:Atmosphere()
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(200, 225, 255)
	atmosphere.Decay = Color3.fromRGB(120, 150, 200)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting
end

----------------------------------------------------------------------------
-- Ground + cliffs
----------------------------------------------------------------------------

function WorldBuilder:Ground()
	local groundFolder = folder("Ground")
	local cliffFolder = folder("Cliffs")
	local iz0 = math.floor(World.StartZ / T)
	local iz1 = math.floor(World.Length / T)
	for iz = iz0, iz1 do
		local zc = (iz + 0.5) * T
		local zone = World.ZoneAt(zc)
		local pal = zone.palette
		local rowColor = if iz % 2 == 0 then pal.ground else pal.groundAlt
		local cx = World.CenterX(zc)
		local hw = World.HalfWidth(zc)
		local ixStart = math.floor((cx - hw) / T) - 2
		local ixEnd = math.floor((cx + hw) / T) + 2

		-- Floor: merge runs of equal height into one part.
		local runStart, runHeight = nil, nil
		local function flush(ixEndExclusive: number)
			if runStart then
				local x0 = runStart * T
				local x1 = ixEndExclusive * T
				local top = runHeight
				local bottom = -12
				StudStyle.Block(groundFolder, Vector3.new(x1 - x0, top - bottom, T), CFrame.new((x0 + x1) / 2, (top + bottom) / 2, zc), rowColor, { shadow = false })
			end
			runStart = nil
		end
		for ix = ixStart, ixEnd do
			local tx = (ix + 0.5) * T
			local d = math.abs(tx - cx)
			if d <= hw then
				local h = World.GroundHeight(tx, zc)
				if runStart and h ~= runHeight then
					flush(ix)
				end
				if not runStart then
					runStart, runHeight = ix, h
				end
			else
				flush(ix)
				-- Cliff column: inner step + taller outer wall, grassy tops.
				local h = World.CliffHeight(ix, iz)
				local outer = (ix < ixStart + 2) or (ix > ixEnd - 2)
				if outer then
					h += 14
				end
				StudStyle.Block(cliffFolder, Vector3.new(T, h + 12, T), CFrame.new(tx, (h - 12) / 2, zc), pal.cliff)
				StudStyle.Block(cliffFolder, Vector3.new(T, 2, T), CFrame.new(tx, h + 1, zc), pal.cliffTop, { shadow = false })
			end
		end
		flush(ixEnd + 1)
	end

	-- End caps so nobody walks off the ends of the valley.
	for _, z in { World.StartZ - T / 2, World.Length + T / 2 } do
		local zone = World.ZoneAt(z)
		local cx = World.CenterX(z)
		StudStyle.Block(cliffFolder, Vector3.new(World.HalfWidth(z) * 2 + T * 4, 110, T), CFrame.new(cx, 43, z), zone.palette.cliff)
	end
end

-- The Long Valley Road: a dirt path down the centre so players on phones
-- always know which way is "further".
function WorldBuilder:Road()
	local road = folder("Road")
	local step = T / 2
	for z = World.StartZ + step / 2, World.Length - step / 2, step do
		local x = World.CenterX(z)
		local h = World.GroundHeight(x, z)
		StudStyle.Block(road, Vector3.new(14, 0.4, step + 0.2), CFrame.new(x, h + 0.2, z) * CFrame.Angles(0, math.atan(math.cos((z - 880) / 260) * 80 / 260 * math.clamp((z - 880) / 300, 0, 1)), 0), C.Path, { shadow = false })
	end
end

----------------------------------------------------------------------------
-- Barnyard Plaza (hub)
----------------------------------------------------------------------------

function WorldBuilder:Hub()
	local hub = folder("Hub")

	-- Plaza floor
	StudStyle.Block(hub, Vector3.new(170, 0.2, 230), CFrame.new(0, 0.1, 140), Color3.fromRGB(220, 200, 150), { shadow = false })

	-- Welcome arch
	for _, sx in { -1, 1 } do
		StudStyle.OnGround(hub, Vector3.new(6, 26, 6), Vector3.new(sx * 30, 0, 18), C.Wood)
	end
	local beam = StudStyle.Block(hub, Vector3.new(68, 8, 4), CFrame.new(0, 28, 18), C.Red)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 230, 90)
		label.Text = "GROW YOUR PETS\nANIMAL FARM"
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(60, 20, 20)
		stroke.Parent = label
		label.Parent = gui
		gui.Parent = beam
	end

	-- Fountain with a golden Griffin
	local fountain = StudStyle.Model(hub, "Fountain")
	StudStyle.OnGround(fountain, Vector3.new(30, 2, 30), Vector3.new(0, 0, 100), C.Stone)
	StudStyle.OnGround(fountain, Vector3.new(26, 0.6, 26), Vector3.new(0, 2, 100), C.Water, { material = Enum.Material.SmoothPlastic, studs = false })
	StudStyle.OnGround(fountain, Vector3.new(8, 8, 8), Vector3.new(0, 2, 100), C.Stone)
	self:Statue(fountain, Pets.Species.Griffin.body, CFrame.new(0, 10, 100) * CFrame.Angles(0, math.pi, 0), { scale = 2.2 }, C.Gold)

	-- Mascot: giant Farm Pup by the arch
	self:Statue(hub, Pets.Species.Pup.body, CFrame.new(-48, 0.4, 40) * CFrame.Angles(0, math.pi * 0.85, 0), { scale = 3.2 })

	-- Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = World.HubSpawn + Vector3.new(0, 0.5, 0)
	spawn.Color = Color3.fromRGB(90, 200, 90)
	spawn.Material = Enum.Material.Plastic
	spawn.TopSurface = Enum.SurfaceType.Studs
	spawn.Duration = 3
	spawn.Neutral = true
	spawn.Parent = hub

	-- Egg stands (prompt opens the egg panel with odds on the client)
	for eggId, pos in World.EggStands do
		local egg = Eggs.List[eggId]
		local stand = StudStyle.OnGround(hub, Vector3.new(9, 3, 9), pos, Color3.fromRGB(250, 240, 210), { name = eggId .. "_Stand" })
		StudStyle.OnGround(hub, Vector3.new(10, 0.6, 10), pos, egg.spotColor, { shadow = false })
		Props.Egg(hub, CFrame.new(pos + Vector3.new(0, 3, 0)), egg, 1.9)
		local label = if egg.levelReq then ("%s\n💰%s · Lv%d"):format(egg.displayName, Format.Short(egg.price), egg.levelReq) else ("%s\n💰%s"):format(egg.displayName, Format.Short(egg.price))
		StudStyle.Label(stand, label, Color3.new(1, 1, 1), 90, 1.2).StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
		local p = prompt(stand, "Hatch", egg.displayName, "EggPrompt", 14)
		p:SetAttribute("EggId", eggId)
	end

	-- Fruit Dealer stall
	local dealer = StudStyle.Model(hub, "FruitDealer")
	local dp = World.FruitDealer
	local counter = StudStyle.OnGround(dealer, Vector3.new(16, 4, 5), dp, C.Wood)
	for _, sx in { -1, 1 } do
		StudStyle.OnGround(dealer, Vector3.new(1, 11, 1), dp + Vector3.new(sx * 8, 0, -4), C.DarkWood)
		StudStyle.OnGround(dealer, Vector3.new(1, 11, 1), dp + Vector3.new(sx * 8, 0, 3), C.DarkWood)
	end
	for k = 0, 5 do
		StudStyle.Block(dealer, Vector3.new(2.8, 0.6, 9), CFrame.new(dp + Vector3.new(-7 + k * 2.8, 11.3, -0.5)), if k % 2 == 0 then C.Red else C.White, { shadow = false })
	end
	for i, fruitId in Fruits.Order do
		Props.Fruit(dealer, CFrame.new(dp + Vector3.new(-6 + (i - 1) * 3, 5.2, 0)), Fruits.List[fruitId], 0.9)
	end
	StudStyle.Label(counter, "🍉 FRUIT DEALER", Color3.fromRGB(255, 200, 120), 90, 1).StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	prompt(counter, "Browse", "Fruit Dealer", "DealerPrompt")

	-- Rebirth statue
	local rp = World.RebirthStatue
	local pedestal = StudStyle.OnGround(hub, Vector3.new(10, 4, 10), rp, C.Gold)
	for k = 0, 7 do
		local a = k * 0.8
		StudStyle.Neon(hub, Vector3.new(1.2, 1.2, 1.2), CFrame.new(rp + Vector3.new(math.cos(a) * 2.5, 5 + k * 1.3, math.sin(a) * 2.5)), if k % 2 == 0 then Color3.fromRGB(120, 255, 200) else Color3.fromRGB(255, 120, 220))
	end
	StudStyle.Label(pedestal, "🧬 EVOLVE FARM (Rebirth)", Color3.fromRGB(150, 255, 220), 90, 1).StudsOffsetWorldSpace = Vector3.new(0, 16, 0)
	prompt(pedestal, "Evolve", "Rebirth", "RebirthPrompt")

	-- Mutation Lab kiosk
	local lab = StudStyle.OnGround(hub, Vector3.new(10, 8, 8), Vector3.new(118, 0, 60), Color3.fromRGB(150, 70, 220))
	StudStyle.Neon(hub, Vector3.new(6, 3, 0.4), CFrame.new(118, 5, 55.8), Color3.fromRGB(120, 255, 180))
	StudStyle.Label(lab, "🧪 MUTATION LAB", Color3.fromRGB(210, 160, 255), 90, 1)
	prompt(lab, "Open", "Mutation Lab", "LabPrompt")

	-- Brainrot Belt
	local belt = StudStyle.Model(hub, "BrainrotBelt")
	local from, to = World.BrainrotBelt.from, World.BrainrotBelt.to
	local mid = (from + to) / 2
	local len = (to - from).Magnitude
	StudStyle.Block(belt, Vector3.new(len, 1.6, 6), CFrame.new(mid + Vector3.new(0, 0.8, 0)), C.Belt, { studs = false, material = Enum.Material.SmoothPlastic })
	for _, sz in { -1, 1 } do
		StudStyle.Block(belt, Vector3.new(len, 2.4, 0.6), CFrame.new(mid + Vector3.new(0, 1.2, sz * 3.3)), Color3.fromRGB(250, 200, 40), { studs = false, material = Enum.Material.SmoothPlastic })
	end
	local machine = StudStyle.OnGround(belt, Vector3.new(10, 12, 10), from + Vector3.new(-6, 0, 0), Color3.fromRGB(150, 70, 220))
	StudStyle.Neon(belt, Vector3.new(5, 4, 5), CFrame.new(from + Vector3.new(-6, 14, 0)), Color3.fromRGB(255, 120, 220))
	StudStyle.Label(machine, "🧠 BRAINROT BELT\nBuy capsules as they roll by!", Color3.fromRGB(255, 170, 240), 120, 1.3).StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	StudStyle.OnGround(belt, Vector3.new(8, 6, 8), to + Vector3.new(6, 0, 0), C.DarkStone)

	-- Lamps and hay bales
	for k = -3, 3 do
		for _, sx in { -1, 1 } do
			local p = Vector3.new(sx * 80, 0, 140 + k * 30)
			StudStyle.OnGround(hub, Vector3.new(1, 9, 1), p, C.DarkStone, { shadow = false })
			StudStyle.Neon(hub, Vector3.new(1.8, 1.8, 1.8), CFrame.new(p + Vector3.new(0, 9.9, 0)), Color3.fromRGB(255, 230, 150))
		end
	end
	for _ = 1, 8 do
		local p = Vector3.new(rng:NextNumber(-150, 150), 0, rng:NextNumber(20, 270))
		if math.abs(p.X) > 90 then
			StudStyle.OnGround(hub, Vector3.new(4, 3, 3), p, C.Hay, nil, rng:NextNumber(0, 3))
		end
	end
end

----------------------------------------------------------------------------
-- Zone gates
----------------------------------------------------------------------------

function WorldBuilder:ZoneGates()
	local gates = folder("ZoneGates")
	for _, zone in World.Zones do
		if zone.levelReq > 1 then
			local z = zone.zStart
			local cx = World.CenterX(z)
			local hw = World.HalfWidth(z)
			local barrier = StudStyle.Block(gates, Vector3.new(hw * 2 + 8, 60, 2), CFrame.new(cx, 30, z), zone.palette.accent, {
				material = Enum.Material.Neon,
				studs = false,
				shadow = false,
				name = "ZoneGate",
			})
			barrier.Transparency = 0.75
			barrier:SetAttribute("LevelReq", zone.levelReq)
			barrier:SetAttribute("ZoneName", zone.name)
			CollectionService:AddTag(barrier, "ZoneGate")
			for _, sx in { -1, 1 } do
				StudStyle.OnGround(gates, Vector3.new(8, 34, 8), Vector3.new(cx + sx * 20, 0, z), zone.palette.cliff)
			end
			local sign = StudStyle.Block(gates, Vector3.new(48, 9, 3), CFrame.new(cx, 38, z), zone.palette.cliffTop)
			StudStyle.Label(sign, ("%s\n🔒 Lv %d"):format(zone.name, zone.levelReq), Color3.new(1, 1, 1), 250, 2).StudsOffsetWorldSpace = Vector3.new(0, 0, -3)
		end
	end
end

----------------------------------------------------------------------------
-- Trees, rocks, flowers
----------------------------------------------------------------------------

local function blockedForDecor(x: number, z: number): boolean
	if z < 830 then
		return true -- hub + Farm Row stay clean
	end
	if math.abs(x - World.CenterX(z)) < 22 then
		return true -- road
	end
	if not World.IsInsideValley(x, z, 18) then
		return true
	end
	for _, heist in World.Heists do
		local c = World.Resolve(heist.center)
		if (Vector3.new(x, 0, z) - Vector3.new(c.X, 0, c.Z)).Magnitude < 85 then
			return true
		end
	end
	for _, zone in World.Zones do
		if math.abs(z - zone.zStart) < 30 then
			return true
		end
	end
	return false
end

function WorldBuilder:Tree(parent: Instance, pos: Vector3, style: string, zone)
	local s = rng:NextNumber(0.8, 1.4)
	if style == "Round" then
		StudStyle.OnGround(parent, Vector3.new(1.6, 6, 1.6) * s, pos, C.Wood, { shadow = false })
		StudStyle.OnGround(parent, Vector3.new(7, 5, 7) * s, pos + Vector3.new(0, 5.5 * s, 0), C.Leaf)
		StudStyle.OnGround(parent, Vector3.new(4.6, 2.4, 4.6) * s, pos + Vector3.new(0, 10.5 * s, 0), Color3.fromRGB(90, 190, 90), { shadow = false })
	elseif style == "Pine" then
		StudStyle.OnGround(parent, Vector3.new(1.4, 5, 1.4) * s, pos, C.DarkWood, { shadow = false })
		for k, w in { 8, 6, 3.6 } do
			StudStyle.OnGround(parent, Vector3.new(w, 3.2, w) * s, pos + Vector3.new(0, (3 + (k - 1) * 3) * s, 0), C.DarkLeaf, { shadow = k == 1 })
		end
	elseif style == "Crystal" then
		for k = 1, 3 do
			local h = rng:NextNumber(5, 12) * s
			local off = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
			StudStyle.Block(parent, Vector3.new(2, h, 2), CFrame.new(pos + off + Vector3.new(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)), if k == 1 then C.Crystal else zone.palette.accent, {
				material = if k == 1 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				studs = false,
				shadow = false,
			})
		end
	elseif style == "Dead" then
		StudStyle.OnGround(parent, Vector3.new(1.4, 9, 1.4) * s, pos, Color3.fromRGB(60, 50, 46), { shadow = false })
		for _, sx in { -1, 1 } do
			StudStyle.Block(parent, Vector3.new(4, 0.8, 0.8) * s, CFrame.new(pos + Vector3.new(sx * 1.6 * s, 6.5 * s, 0)) * CFrame.Angles(0, 0, sx * 0.5), Color3.fromRGB(60, 50, 46), { shadow = false })
		end
	end
end

function WorldBuilder:Decorate()
	local decor = folder("Decor")
	for _, zone in World.Zones do
		local placed = 0
		local attempts = 0
		while placed < zone.trees and attempts < zone.trees * 6 do
			attempts += 1
			local z = rng:NextNumber(zone.zStart, zone.zEnd)
			local hw = World.HalfWidth(z)
			local x = World.CenterX(z) + rng:NextNumber(-hw, hw)
			if not blockedForDecor(x, z) then
				placed += 1
				local style = zone.treeStyle or "Round"
				self:Tree(decor, ground(x, z), style, zone)
			end
		end
		-- Rocks + flowers
		for _ = 1, math.floor((zone.zEnd - zone.zStart) / 40) do
			local z = rng:NextNumber(zone.zStart, zone.zEnd)
			local hw = World.HalfWidth(z)
			local x = World.CenterX(z) + rng:NextNumber(-hw, hw)
			if not blockedForDecor(x, z) then
				local size = Vector3.new(rng:NextNumber(3, 7), rng:NextNumber(2, 5), rng:NextNumber(3, 7))
				StudStyle.OnGround(decor, size, ground(x, z), zone.palette.cliff, { shadow = false }, rng:NextNumber(0, 3))
			end
		end
		if zone.id == "Meadow" then
			for _ = 1, 60 do
				local z = rng:NextNumber(zone.zStart, zone.zEnd)
				local hw = World.HalfWidth(z)
				local x = World.CenterX(z) + rng:NextNumber(-hw, hw)
				if not blockedForDecor(x, z) then
					local colors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 230, 80), Color3.fromRGB(180, 120, 255), Color3.new(1, 1, 1) }
					StudStyle.OnGround(decor, Vector3.new(0.8, 0.8, 0.8), ground(x, z), colors[rng:NextInteger(1, #colors)], { collide = false, shadow = false, studs = false, material = Enum.Material.SmoothPlastic })
				end
			end
		end
	end
end

----------------------------------------------------------------------------
-- Landmarks + parkour (hidden fruit spots on top)
----------------------------------------------------------------------------

function WorldBuilder:Landmarks()
	local marks = folder("Landmarks")

	-- Farm Row windmill
	local wm = Vector3.new(0, 0, 820)
	StudStyle.OnGround(marks, Vector3.new(10, 26, 10), wm + Vector3.new(60, 0, 0), C.White)
	StudStyle.Block(marks, Vector3.new(12, 3, 12), CFrame.new(wm + Vector3.new(60, 27.5, 0)), C.Red)
	for k = 0, 3 do
		StudStyle.Block(marks, Vector3.new(2, 18, 0.6), CFrame.new(wm + Vector3.new(60, 22, -5.4)) * CFrame.Angles(0, 0, k * math.pi / 2) * CFrame.new(0, 9, 0), C.Wood, { shadow = false })
	end

	-- Meadow: Hay Tower parkour (spiral)
	do
		local base = World.Resolve(Vector3.new(-120, 0, 1010))
		for k = 0, 15 do
			local a = k * 0.75
			local p = base + Vector3.new(math.cos(a) * 11, k * 4.5, math.sin(a) * 11)
			StudStyle.Block(marks, Vector3.new(6, 2, 6), CFrame.new(p + Vector3.new(0, 1, 0)), C.Hay)
		end
		local topY = base.Y + 16 * 4.5
		StudStyle.Block(marks, Vector3.new(10, 2, 10), CFrame.new(base + Vector3.new(0, topY - base.Y + 1, 0)), C.Red)
		StudStyle.OnGround(marks, Vector3.new(4, topY - base.Y, 4), base, C.Wood)
		fruitAnchor(marks, base + Vector3.new(0, topY - base.Y + 2, 0), true)
		-- ponds
		for k = 1, 3 do
			local pp = World.Resolve(Vector3.new(rng:NextNumber(-150, 150), 0, 880 + k * 120))
			if not blockedForDecor(pp.X, pp.Z) then
				StudStyle.Block(marks, Vector3.new(24, 0.3, 16), CFrame.new(pp + Vector3.new(0, 0.2, 0)), C.Water, { material = Enum.Material.SmoothPlastic, studs = false, collide = false })
			end
		end
	end

	-- Woods: Treetop Trail (floating platforms between giant pines)
	do
		local start = World.Resolve(Vector3.new(110, 0, 1420))
		for k = 0, 9 do
			local p = start + Vector3.new(math.sin(k) * 14, 6 + k * 3.2, k * 13)
			StudStyle.Block(marks, Vector3.new(7, 1.4, 7), CFrame.new(p), C.Wood)
			if k % 3 == 0 then
				StudStyle.OnGround(marks, Vector3.new(2, p.Y - start.Y, 2), Vector3.new(p.X, start.Y, p.Z + 4), C.DarkWood, { shadow = false })
			end
		end
		fruitAnchor(marks, start + Vector3.new(math.sin(9) * 14, 6 + 9 * 3.2 + 0.7, 9 * 13), true)
	end

	-- Canyon: Crystal Spire (neon stepping stones)
	do
		local base = World.Resolve(Vector3.new(-70, 0, 2150))
		for k = 0, 13 do
			local a = k * 1.1
			local p = base + Vector3.new(math.cos(a) * 9, 4 + k * 4, math.sin(a) * 9)
			StudStyle.Block(marks, Vector3.new(4.5, 1.2, 4.5), CFrame.new(p) * CFrame.Angles(0, a, 0), C.Crystal, { material = Enum.Material.Neon, studs = false })
		end
		StudStyle.OnGround(marks, Vector3.new(6, 60, 6), base, Color3.fromRGB(150, 90, 200))
		fruitAnchor(marks, base + Vector3.new(0, 61, 0), true)
	end

	-- Volcano Ridge: the volcano (stepped cone) with a lava crater secret
	do
		local base = World.Resolve(Vector3.new(90, 0, 2650))
		for k = 0, 6 do
			local w = 70 - k * 9
			StudStyle.Block(marks, Vector3.new(w, 6, w), CFrame.new(base + Vector3.new(0, 3 + k * 6, 0)), if k % 2 == 0 then Color3.fromRGB(70, 60, 62) else Color3.fromRGB(86, 70, 70))
		end
		StudStyle.Block(marks, Vector3.new(10, 1, 10), CFrame.new(base + Vector3.new(0, 42.6, 0)), C.Lava, { material = Enum.Material.Neon, studs = false })
		fruitAnchor(marks, base + Vector3.new(12, 42, 0), true)
		for k = 1, 5 do
			local lp = World.Resolve(Vector3.new(rng:NextNumber(-120, 120), 0, 2450 + k * 85))
			if not blockedForDecor(lp.X, lp.Z) then
				StudStyle.Block(marks, Vector3.new(rng:NextNumber(10, 22), 0.3, rng:NextNumber(8, 16)), CFrame.new(lp + Vector3.new(0, 0.2, 0)), C.Lava, { material = Enum.Material.Neon, studs = false, collide = false })
			end
		end
	end
end

----------------------------------------------------------------------------
-- Heist structures (interactive parts come from EggHeistService)
----------------------------------------------------------------------------

function WorldBuilder:HeistStructures()
	local heists = folder("HeistSites")

	-- Chicken Coop
	do
		local c = World.Resolve(World.Heists.ChickenCoop.center)
		local coop = c + Vector3.new(0, 0, 36)
		StudStyle.OnGround(heists, Vector3.new(26, 10, 14), coop, C.Red)
		for _, sx in { -1, 1 } do
			StudStyle.Block(heists, Vector3.new(15, 1, 16), CFrame.new(coop + Vector3.new(sx * 6.5, 12.5, 0)) * CFrame.Angles(0, 0, sx * -0.5), C.White)
		end
		for k = 0, 23 do
			local a = k / 24 * math.pi * 2
			if not (a > math.pi * 1.35 and a < math.pi * 1.65) then -- gap facing the valley start
				StudStyle.OnGround(heists, Vector3.new(1, 4, 1), c + Vector3.new(math.cos(a) * 46, 0, math.sin(a) * 46), C.White, { shadow = false })
				StudStyle.Block(heists, Vector3.new(12.2, 0.6, 0.6), CFrame.new(c + Vector3.new(math.cos(a + 0.13) * 46, 3, math.sin(a + 0.13) * 46)) * CFrame.Angles(0, -a - 0.13 - math.pi / 2, 0), C.White, { shadow = false })
			end
		end
		for _ = 1, 6 do
			StudStyle.OnGround(heists, Vector3.new(4, 3, 3), c + Vector3.new(rng:NextNumber(-35, 35), 0, rng:NextNumber(-20, 20)), C.Hay, { shadow = false }, rng:NextNumber(0, 3))
			end
	end

	-- Dragon's Nest
	do
		local c = World.Resolve(World.Heists.DragonNest.center)
		for k = 0, 17 do
			local a = k / 18 * math.pi * 2
			if not (a > math.pi * 1.4 and a < math.pi * 1.6) then
				local h = rng:NextNumber(14, 30)
				StudStyle.Block(heists, Vector3.new(7, h, 7), CFrame.new(c + Vector3.new(math.cos(a) * 60, h / 2, math.sin(a) * 60)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), a, rng:NextNumber(-0.2, 0.2)), Color3.fromRGB(40, 26, 50))
			end
		end
		local nest = c + Vector3.new(0, 0, 22)
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			StudStyle.Block(heists, Vector3.new(7, 3, 3), CFrame.new(nest + Vector3.new(math.cos(a) * 9, 1.5, math.sin(a) * 9)) * CFrame.Angles(0, -a, 0.2), Color3.fromRGB(120, 80, 50), { shadow = false })
		end
		for _ = 1, 5 do
			StudStyle.Block(heists, Vector3.new(rng:NextNumber(10, 18), 0.3, rng:NextNumber(8, 14)), CFrame.new(c + Vector3.new(rng:NextNumber(-45, 45), 0.2, rng:NextNumber(-40, 0))), C.Lava, { material = Enum.Material.Neon, studs = false, collide = false })
			StudStyle.OnGround(heists, Vector3.new(3, 1.5, 3), c + Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(10, 45)), C.Gold, { shadow = false })
			end
	end
end

----------------------------------------------------------------------------
-- The Hollow Stump dungeon (entrance in the Woods, arena far below)
----------------------------------------------------------------------------

function WorldBuilder:Dungeon()
	local dun = folder("Dungeon")
	local def = World.Dungeon
	local entrance = World.Resolve(def.entrance)
	local stump = StudStyle.Block(dun, Vector3.new(10, 18, 18), CFrame.new(entrance + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2), C.Wood, {
		shape = Enum.PartType.Cylinder,
		studs = false,
		material = Enum.Material.SmoothPlastic,
	})
	StudStyle.Block(dun, Vector3.new(0.6, 12, 12), CFrame.new(entrance + Vector3.new(0, 10.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(20, 14, 10), {
		shape = Enum.PartType.Cylinder,
		studs = false,
		material = Enum.Material.SmoothPlastic,
		collide = false,
	})
	StudStyle.Label(stump, "🪵 THE HOLLOW STUMP\nSecret dungeon", Color3.fromRGB(255, 200, 120), 120, 1.2).StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	prompt(stump, "Enter", "The Hollow", nil, 16).Triggered:Connect(function(player)
		S.ZombieService:StartDungeon(player)
	end)

	local center = Vector3.new(World.CenterX(def.arena.Z) + def.arena.X, def.arena.Y, def.arena.Z)
	StudStyle.Block(dun, Vector3.new(120, 4, 120), CFrame.new(center - Vector3.new(0, 2, 0)), Color3.fromRGB(70, 56, 44))
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local size = if side.X ~= 0 then Vector3.new(4, 26, 124) else Vector3.new(124, 26, 4)
		StudStyle.Block(dun, size, CFrame.new(center + side * 62 + Vector3.new(0, 13, 0)), Color3.fromRGB(50, 40, 34))
		StudStyle.Neon(dun, Vector3.new(1.5, 2.5, 1.5), CFrame.new(center + side * 58 + Vector3.new(0, 8, 0)), Color3.fromRGB(255, 150, 40))
	end
	StudStyle.Block(dun, Vector3.new(124, 2, 124), CFrame.new(center + Vector3.new(0, 27, 0)), Color3.fromRGB(40, 32, 28), { shadow = false })
	for _ = 1, 6 do
		StudStyle.OnGround(dun, Vector3.new(3, 10, 3), center + Vector3.new(rng:NextNumber(-45, 45), 0, rng:NextNumber(-45, 45)), Color3.fromRGB(96, 70, 50))
	end
end

----------------------------------------------------------------------------
-- Fruit spawn anchors (open ground + hidden spots added by Landmarks)
----------------------------------------------------------------------------

function WorldBuilder:FruitSpawns()
	local spawns = folder("FruitSpawns")
	for _, zone in World.Zones do
		if zone.id ~= "Hub" then
			local count = if zone.id == "FarmRow" then 2 else 5
			local made = 0
			local tries = 0
			while made < count and tries < 60 do
				tries += 1
				local z = rng:NextNumber(zone.zStart + 30, zone.zEnd - 30)
				if zone.id == "FarmRow" then
					-- between the road and the bases, never inside a plot
					local side = if rng:NextNumber() < 0.5 then -1 else 1
					fruitAnchor(spawns, ground(World.CenterX(z) + side * rng:NextNumber(28, 80), z), false)
					made += 1
				else
					local hw = World.HalfWidth(z) - 30
					local x = World.CenterX(z) + rng:NextNumber(-hw, hw)
					if not blockedForDecor(x, z) then
						fruitAnchor(spawns, ground(x, z), false)
						made += 1
					end
				end
			end
		end
	end
end

return WorldBuilder
