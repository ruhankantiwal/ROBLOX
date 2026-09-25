--[[
	StudStyle: the only way world geometry gets made.

	Art rules this enforces (mobile-first, classic Roblox look):
	  * Materials: Plastic (studded tops) for ground and buildings,
	    SmoothPlastic for small props, Neon only for glowing accents.
	    No SurfaceAppearance, no PBR MaterialVariants, no custom textures.
	  * Studs come from the engine's built-in SurfaceType.Studs, so the
	    "stud texture pack" costs no texture memory at all.
	  * Small props never cast shadows; big terrain blocks do.
	  * Decorative parts are CanQuery/CanTouch false so raycasts and touch
	    events stay cheap.
]]

local StudStyle = {}

StudStyle.Colors = {
	Wood = Color3.fromRGB(124, 84, 52),
	DarkWood = Color3.fromRGB(86, 58, 38),
	Hay = Color3.fromRGB(232, 200, 110),
	Stone = Color3.fromRGB(150, 150, 156),
	DarkStone = Color3.fromRGB(90, 90, 98),
	Red = Color3.fromRGB(206, 58, 50),
	White = Color3.fromRGB(245, 245, 240),
	Leaf = Color3.fromRGB(64, 160, 70),
	DarkLeaf = Color3.fromRGB(40, 110, 56),
	Gold = Color3.fromRGB(255, 200, 50),
	Lava = Color3.fromRGB(255, 100, 20),
	Water = Color3.fromRGB(70, 150, 230),
	Crystal = Color3.fromRGB(110, 230, 255),
	Path = Color3.fromRGB(214, 190, 140),
	Belt = Color3.fromRGB(46, 46, 52),
}

export type BlockOptions = {
	material: Enum.Material?,
	studs: boolean?,
	collide: boolean?,
	query: boolean?,
	shadow: boolean?,
	transparency: number?,
	name: string?,
	shape: Enum.PartType?,
}

function StudStyle.Block(parent: Instance, size: Vector3, cf: CFrame, color: Color3, opts: BlockOptions?): Part
	local o: BlockOptions = opts or {}
	local p = Instance.new("Part")
	p.Name = o.name or "Block"
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = o.material or Enum.Material.Plastic
	if o.shape then
		p.Shape = o.shape
	end
	local studs = if o.studs == nil then p.Material == Enum.Material.Plastic else o.studs
	if studs then
		p.TopSurface = Enum.SurfaceType.Studs
		p.BottomSurface = Enum.SurfaceType.Inlet
	else
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
	end
	p.CanCollide = if o.collide == nil then true else o.collide
	p.CanQuery = if o.query == nil then p.CanCollide else o.query
	p.CanTouch = false
	-- Small props never cast shadows (big win on low-end GPUs).
	p.CastShadow = if o.shadow == nil then (size.X * size.Y * size.Z > 200) else o.shadow
	if o.transparency then
		p.Transparency = o.transparency
	end
	p.Parent = parent
	return p
end

-- Convenience: a block whose bottom sits at `groundPos`.
function StudStyle.OnGround(parent: Instance, size: Vector3, groundPos: Vector3, color: Color3, opts: BlockOptions?, yaw: number?): Part
	local cf = CFrame.new(groundPos + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, yaw or 0, 0)
	return StudStyle.Block(parent, size, cf, color, opts)
end

function StudStyle.Neon(parent: Instance, size: Vector3, cf: CFrame, color: Color3, collide: boolean?): Part
	return StudStyle.Block(parent, size, cf, color, {
		material = Enum.Material.Neon,
		studs = false,
		collide = collide or false,
		shadow = false,
	})
end

-- A floating label that only renders within `distance` studs.
function StudStyle.Label(adornee: BasePart, text: string, color: Color3?, distance: number?, sizeScale: number?): BillboardGui
	local s = sizeScale or 1
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(260 * s, 60 * s)
	gui.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y / 2 + 2.5 * s, 0)
	gui.MaxDistance = distance or 120
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
	return gui
end

function StudStyle.Model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

return StudStyle
