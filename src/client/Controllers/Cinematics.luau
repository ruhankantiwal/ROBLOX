--[[
	Cinematics: the clip-worthy moments.

	  Hatch      egg shakes harder and harder, white flash, pet spins in
	             with a rarity banner (1 or 3 eggs side by side)
	  Mutation   the camera orbits your pet in slow motion while it
	             transforms: flash in the fruit colour, rings, giant title
	  Clip Mode  hides every UI element so recording for TikTok/Shorts is
	             one tap

	All built from ViewportFrames + BlockyBuilder, no assets.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Eggs = require(Shared.Config.Eggs)
local Fruits = require(Shared.Config.Fruits)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)
local BlockyBuilder = require(Shared.Art.BlockyBuilder)
local Props = require(Shared.Art.Props)
local PetStats = require(Shared.Util.PetStats)

local Kit = require(script.Parent.Parent.UI.Kit)
local FX = require(script.Parent.FX)
local EntityRenderer = require(script.Parent.EntityRenderer)
local ClientState = require(script.Parent.Parent.ClientState)

local LOCAL = Players.LocalPlayer

local Cinematics = { busy = false }

local gui: ScreenGui

function Cinematics.Start()
	gui = Kit.new("ScreenGui", {
		Name = "Cinematics",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Parent = LOCAL:WaitForChild("PlayerGui"),
	})
	Net.Event("HatchResult").OnClientEvent:Connect(function(result)
		Cinematics.Hatch(result)
	end)
	Net.Event("MutationCinematic").OnClientEvent:Connect(function(info)
		Cinematics.Mutation(info)
	end)
end

----------------------------------------------------------------------------
-- Viewport helpers
----------------------------------------------------------------------------

local function viewport(parent: Instance, size: UDim2, position: UDim2): (ViewportFrame, WorldModel, Camera)
	local vp = Kit.new("ViewportFrame", {
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1, -0.6),
		Parent = parent,
	})
	local world = Kit.new("WorldModel", { Parent = vp })
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = vp
	vp.CurrentCamera = camera
	return vp, world, camera
end

-- Static pose of a pet rig inside a WorldModel. Returns its height.
function Cinematics.PetModel(parent: Instance, pet, cf: CFrame): (Model, number)
	local stats = PetStats.Compute(pet)
	local rig = BlockyBuilder.Build(Pets.Species[pet.species].body, {
		scale = stats.sizeMult,
		variant = pet.variant,
		fruit = pet.fruit and pet.fruit.id,
		awakened = stats.special.awakened,
		mutations = pet.mutations,
	})
	local model = Instance.new("Model")
	for _, spec in rig.parts do
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = spec.size
		p.Color = spec.color
		p.Material = spec.material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = cf * rig.groups[spec.group] * spec.localCF
		p.Parent = model
	end
	model.Parent = parent
	return model, rig.height
end

local function overlay(): Frame
	local dim = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.35 }):Play()
	return dim
end

local function flashScreen(color: Color3, duration: number?)
	local f = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		ZIndex = 20,
		Parent = gui,
	})
	TweenService:Create(f, TweenInfo.new(duration or 0.5), { BackgroundTransparency = 1 }):Play()
	task.delay((duration or 0.5) + 0.1, function()
		f:Destroy()
	end)
end

local function banner(parent: Instance, text: string, color: Color3, y: number, size: number): TextLabel
	local label = Kit.label(text, size, color, {
		Size = UDim2.new(1, 0, 0, size + 10),
		Position = UDim2.fromScale(0.5, y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 10,
		Parent = parent,
	})
	Kit.pop(label)
	return label
end

----------------------------------------------------------------------------
-- Hatch
----------------------------------------------------------------------------

function Cinematics.Hatch(result)
	if not result or not result.ok or not result.results then
		return
	end
	local d = ClientState.data
	local dim = overlay()
	local n = #result.results
	local skip = false
	local tap = Kit.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 30,
		Parent = dim,
	})
	tap.Activated:Connect(function()
		skip = true
	end)

	local slots = {}
	for i, r in result.results do
		local x = if n == 1 then 0.5 else 0.2 + (i - 1) * 0.3
		local vp, world, camera = viewport(dim, UDim2.fromScale(0.34, 0.5), UDim2.fromScale(x, 0.45))
		local eggDef = Eggs.List[result.egg] or Eggs.List.DragonEgg
		local egg = Props.Egg(world, CFrame.new(), eggDef, 1)
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.2, -9), Vector3.new(0, 1.7, 0))
		slots[i] = { vp = vp, world = world, camera = camera, egg = egg, result = r }
	end

	-- Shake: harder and faster
	local start = os.clock()
	while os.clock() - start < 1.3 and not skip do
		local t = os.clock() - start
		for _, s in slots do
			local amp = 0.05 + t * 0.35
			s.egg:PivotTo(CFrame.Angles(0, 0, math.sin(t * (12 + t * 30)) * amp))
		end
		RunService.RenderStepped:Wait()
	end
	flashScreen(Color3.new(1, 1, 1), 0.45)

	local best = 0
	for _, s in slots do
		s.egg:Destroy()
		local r = s.result
		local pet = (r.uid and d and d.pets[r.uid]) or { species = r.species, level = 1, variant = r.variant, mutations = {} }
		local _, height = Cinematics.PetModel(s.world, pet, CFrame.new())
		s.height = height
		local def = Pets.Species[r.species]
		local rarityColor = Rarity.Color(def.rarity)
		local rank = Rarity.Rank(def.rarity)
		best = math.max(best, rank)
		local title = def.emoji .. " " .. def.displayName
		if r.variant and r.variant ~= "Normal" then
			title = Pets.Variants[r.variant].label .. " " .. title
		end
		local holder = Kit.new("Frame", {
			Size = UDim2.new(0.3, 0, 0, 90),
			Position = UDim2.new(s.vp.Position.X.Scale, 0, 0.78, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Parent = dim,
		})
		banner(holder, title, Color3.new(1, 1, 1), 0.3, 30)
		banner(holder, def.rarity:upper(), rarityColor, 0.8, 26)
	end
	if best >= 5 then
		flashScreen(Color3.fromRGB(255, 220, 80), 0.9)
		FX.Shake(1.2, 0.6)
	end

	local spinStart = os.clock()
	while os.clock() - spinStart < (if skip then 0.6 else 2.2) do
		local t = os.clock() - spinStart
		for _, s in slots do
			local h = s.height or 3
			local dist = h * 2.2 + 5
			s.camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(t * 1.4) * dist, h * 0.75, -math.cos(t * 1.4) * dist), Vector3.new(0, h * 0.45, 0))
		end
		RunService.RenderStepped:Wait()
	end
	TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	for _, s in slots do
		s.vp:Destroy()
	end
	task.wait(0.25)
	dim:Destroy()
end

----------------------------------------------------------------------------
-- Mutation / Fruit feeding
----------------------------------------------------------------------------

function Cinematics.Mutation(info)
	local color, title, subtitle
	if info.kind == "Fruit" or info.kind == "FruitRoll" then
		local fruit = Fruits.List[info.id]
		color = fruit.color
		title = if info.kind == "Fruit" then ("%s %s MUTATION!"):format(fruit.emoji, fruit.element:upper()) else ("%s %s!"):format(fruit.emoji, fruit.displayName:upper())
		subtitle = fruit.tagline
	else
		local m = Mutations.List[info.id]
		color = Rarity.Color(m.rarity)
		title = ("%s %s"):format(m.emoji, m.displayName:upper())
		subtitle = m.joke
	end

	local dim = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local ent = info.uid and EntityRenderer.PetByUid(info.uid)
	local camera = workspace.CurrentCamera

	if ent and info.kind ~= "FruitRoll" then
		-- In-world orbit around the real pet
		local oldType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		local start = os.clock()
		local flashed = false
		while os.clock() - start < 2.8 do
			local t = os.clock() - start
			local current = EntityRenderer.PetByUid(info.uid) or ent
			local h = if current.rig then current.rig.height else 3
			local center = current.pos + Vector3.new(0, h * 0.5, 0)
			local dist = h * 2 + 8 - t * 1.2
			camera.CFrame = CFrame.lookAt(center + Vector3.new(math.sin(t * 1.1) * dist, h * 0.5 + 2, math.cos(t * 1.1) * dist), center)
			if t > 0.7 and not flashed then
				flashed = true
				flashScreen(color, 0.7)
				FX.Ring(current.pos, 14, color, 0.8)
				FX.Ring(current.pos, 8, Color3.new(1, 1, 1), 0.5)
				FX.Burst(center, color, 24, 12)
				FX.Shake(1, 0.5)
				banner(dim, title, color, 0.18, 44)
				banner(dim, subtitle, Color3.new(1, 1, 1), 0.27, 22)
			end
			RunService.RenderStepped:Wait()
		end
		camera.CameraType = if oldType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else oldType
	else
		-- Viewport fallback (pet not deployed, or a fruit roll)
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.35 }):Play()
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		local vp, world, cam = viewport(dim, UDim2.fromScale(0.4, 0.55), UDim2.fromScale(0.5, 0.52))
		local height = 3
		if info.kind == "FruitRoll" then
			Props.Fruit(world, CFrame.new(0, 1.5, 0), Fruits.List[info.id], 1.6)
		else
			local pet = ClientState.data and ClientState.data.pets[info.uid]
			if pet then
				local _, h = Cinematics.PetModel(world, pet, CFrame.new())
				height = h
			end
		end
		flashScreen(color, 0.7)
		banner(dim, title, color, 0.16, 44)
		banner(dim, subtitle, Color3.new(1, 1, 1), 0.86, 22)
		local start = os.clock()
		while os.clock() - start < 2.6 do
			local t = os.clock() - start
			local dist = height * 2.2 + 5
			cam.CFrame = CFrame.lookAt(Vector3.new(math.sin(t) * dist, height * 0.8, math.cos(t) * dist), Vector3.new(0, height * 0.45, 0))
			RunService.RenderStepped:Wait()
		end
		vp:Destroy()
	end
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	for _, child in dim:GetChildren() do
		if child:IsA("TextLabel") then
			TweenService:Create(child, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
	end
	task.wait(0.35)
	dim:Destroy()
end

----------------------------------------------------------------------------
-- Clip mode
----------------------------------------------------------------------------

local clipMode = false
function Cinematics.ToggleClipMode(): boolean
	clipMode = not clipMode
	for _, screen in LOCAL.PlayerGui:GetChildren() do
		if screen:IsA("ScreenGui") and screen ~= gui and screen.Name ~= "ClipModeButton" then
			screen.Enabled = not clipMode
		end
	end
	return clipMode
end

return Cinematics
