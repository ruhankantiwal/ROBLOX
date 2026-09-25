--[[
	Props: blocky eggs, Beast Fruits and Mutation Capsules. Used by the
	server (shop stands, world fruits, vaults, carried loot) and the client
	(hatch and fruit cinematics), so they look identical everywhere.
]]

local Config = script.Parent.Parent.Config
local Rarity = require(Config.Rarity)

local Props = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A chunky voxel egg: four stacked slabs, narrow top and bottom, plus
-- spots. `egg` is an entry from Config/Eggs. Returns the model and its
-- PrimaryPart (the widest slab).
function Props.Egg(parent: Instance, cf: CFrame, egg, scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Egg"
	local color = egg.color
	local mat = if egg.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local layers = {
		{ w = 1.6, h = 0.5, y = 0.25 },
		{ w = 2.2, h = 1.0, y = 1.0 },
		{ w = 2.0, h = 0.9, y = 1.95 },
		{ w = 1.4, h = 0.6, y = 2.7 },
		{ w = 0.8, h = 0.3, y = 3.15 },
	}
	local primary
	for i, l in layers do
		local p = part(model, "Layer" .. i, Vector3.new(l.w, l.h, l.w) * s, cf * CFrame.new(0, l.y * s, 0), color, if i == 2 then mat else Enum.Material.SmoothPlastic)
		if i == 2 then
			primary = p
		end
	end
	for i, o in { Vector3.new(1.11, 1.1, 0.3), Vector3.new(-0.4, 1.9, 1.01), Vector3.new(0.5, 2.1, -1.01), Vector3.new(-1.11, 0.8, -0.2) } do
		local size = if math.abs(o.X) > 1 then Vector3.new(0.05, 0.45, 0.45) else Vector3.new(0.45, 0.45, 0.05)
		part(model, "Spot" .. i, size * s, cf * CFrame.new(o * s), egg.spotColor)
	end
	model.PrimaryPart = primary
	model.Parent = parent
	return model
end

-- A voxel fruit with a leaf and a stem, tinted by the fruit's colour.
function Props.Fruit(parent: Instance, cf: CFrame, fruit, scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Fruit"
	local body = part(model, "Body", Vector3.new(1.6, 1.5, 1.6) * s, cf, fruit.color)
	part(model, "Top", Vector3.new(1.1, 0.35, 1.1) * s, cf * CFrame.new(0, 0.9 * s, 0), fruit.color:Lerp(Color3.new(1, 1, 1), 0.2))
	part(model, "Bottom", Vector3.new(1.1, 0.3, 1.1) * s, cf * CFrame.new(0, -0.85 * s, 0), fruit.color:Lerp(Color3.new(0, 0, 0), 0.25))
	part(model, "Swirl", Vector3.new(1.62, 0.25, 1.62) * s, cf * CFrame.new(0, 0.2 * s, 0), fruit.color:Lerp(Color3.new(1, 1, 1), 0.45), Enum.Material.Neon)
	part(model, "Stem", Vector3.new(0.2, 0.5, 0.2) * s, cf * CFrame.new(0, 1.3 * s, 0), Color3.fromRGB(96, 64, 38))
	part(model, "Leaf", Vector3.new(0.7, 0.12, 0.4) * s, cf * CFrame.new(0.4 * s, 1.35 * s, 0) * CFrame.Angles(0, 0, 0.4), Color3.fromRGB(80, 190, 80))
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- A Mutation Capsule: a two-tone pill with a glowing band in the
-- mutation's rarity colour.
function Props.Capsule(parent: Instance, cf: CFrame, mutation, scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Capsule"
	local color = Rarity.Color(mutation.rarity)
	local body = part(model, "Top", Vector3.new(1.3, 1.1, 1.3) * s, cf * CFrame.new(0, 0.6 * s, 0), Color3.fromRGB(245, 245, 250))
	part(model, "Bottom", Vector3.new(1.3, 1.1, 1.3) * s, cf * CFrame.new(0, -0.6 * s, 0), color)
	part(model, "Band", Vector3.new(1.36, 0.2, 1.36) * s, cf, color, Enum.Material.Neon)
	part(model, "CapTop", Vector3.new(0.9, 0.25, 0.9) * s, cf * CFrame.new(0, 1.25 * s, 0), Color3.fromRGB(245, 245, 250))
	part(model, "CapBottom", Vector3.new(0.9, 0.25, 0.9) * s, cf * CFrame.new(0, -1.25 * s, 0), color)
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

return Props
