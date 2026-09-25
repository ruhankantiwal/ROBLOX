--[[
	BlockyBuilder: turns a body description (from Config/Pets or
	Config/Zombies) plus fruit / mutation / variant data into a "rig":
	a flat list of block specs grouped into animatable limbs.

	Why blocks: zero meshes, zero textures, zero uploads. Every pet and
	zombie is 12-30 SmoothPlastic parts, which renders fast on low-end phones
	and reads instantly as "Roblox". The client turns a rig into anchored
	parts and animates groups (legs, head, tail, wings) procedurally.

	Coordinate convention: root sits on the ground under the body centre,
	facing -Z (Roblox LookVector). Everything is authored at scale 1 and
	scaled in finalize().

	Rig = {
		parts   = { { group, name, size, localCF, color, role, material } },
		groups  = { [groupName] = pivot CFrame in root space },
		height, length, radius, template,
		effects = { aura?, rainbow?, sparkles?, hearts?, glitch?, spotlight?, jitter? },
	}
	role is "main" | "accent" | "detail" | "head" | "eye" | "fx", used for
	rainbow cycling and hit flashes.
]]

local Config = script.Parent.Parent.Config
local Fruits = require(Config.Fruits)
local Mutations = require(Config.Mutations)

local BlockyBuilder = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(24, 24, 28)
local GOLD = Color3.fromRGB(255, 200, 50)

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

type Rig = {
	parts: { any },
	groups: { [string]: CFrame },
	anchors: { [string]: any },
	effects: { [string]: any },
	scale: number,
	height: number,
	length: number,
	radius: number,
	template: string,
}

local function newRig(template: string, scale: number): Rig
	return {
		parts = {},
		groups = {},
		anchors = {},
		effects = {},
		scale = scale,
		height = 0,
		length = 0,
		radius = 0,
		template = template,
	}
end

local function group(rig: Rig, name: string, pivot: CFrame)
	rig.groups[name] = pivot
end

-- Adds a part authored in ROOT space; stored relative to its group pivot.
local function add(rig: Rig, groupName: string, name: string, size: Vector3, cf: CFrame, color: Color3, role: string, material: Enum.Material?)
	local pivot = rig.groups[groupName]
	assert(pivot, "missing group " .. groupName)
	table.insert(rig.parts, {
		group = groupName,
		name = name,
		size = size,
		localCF = pivot:Inverse() * cf,
		color = color,
		role = role,
		material = material or SMOOTH,
	})
end

local function scaleCF(cf: CFrame, s: number): CFrame
	return CFrame.new(cf.Position * s) * cf.Rotation
end

local function finalize(rig: Rig)
	local s = rig.scale
	for name, pivot in rig.groups do
		rig.groups[name] = scaleCF(pivot, s)
	end
	local maxY, maxZ, maxX = 0, 0, 0
	for _, p in rig.parts do
		p.size *= s
		p.localCF = scaleCF(p.localCF, s)
		local world = rig.groups[p.group] * p.localCF
		maxY = math.max(maxY, world.Y + p.size.Y / 2)
		maxZ = math.max(maxZ, math.abs(world.Z) + p.size.Z / 2)
		maxX = math.max(maxX, math.abs(world.X) + p.size.X / 2)
	end
	rig.height = maxY
	rig.length = maxZ * 2
	rig.radius = math.max(maxX, maxZ) * 0.8
	return rig
end

----------------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------------

local function makePalette(body, variant: string?, fruitLook, mutationTint: Color3?)
	local c = body.colors
	local pal = {
		main = c.main,
		accent = c.accent,
		detail = c.detail,
		head = body.headColor or c.main,
		eye = body.eyeColor or BLACK,
	}
	if fruitLook then
		local t = fruitLook.tint or 0.5
		pal.main = pal.main:Lerp(fruitLook.palette.main, t)
		pal.accent = pal.accent:Lerp(fruitLook.palette.accent, t)
		pal.detail = pal.detail:Lerp(fruitLook.palette.detail, t)
		pal.head = pal.head:Lerp(fruitLook.palette.main, t)
	end
	if mutationTint then
		pal.main = pal.main:Lerp(mutationTint, 0.6)
		pal.head = pal.head:Lerp(mutationTint, 0.6)
	end
	if variant == "Golden" then
		pal.main = pal.main:Lerp(GOLD, 0.7)
		pal.accent = pal.accent:Lerp(GOLD, 0.5)
		pal.head = pal.head:Lerp(GOLD, 0.7)
	end
	return pal
end

----------------------------------------------------------------------------
-- Shared face / head features
----------------------------------------------------------------------------

local function addEyes(rig: Rig, headCF: CFrame, hs: Vector3, pal, derp: boolean?)
	local fz = headCF.Z - hs.Z / 2 - 0.03
	local ew, eh = hs.X * 0.17, hs.Y * 0.24
	for i, sx in { -1, 1 } do
		local ey = headCF.Y + hs.Y * 0.12 - (if derp and i == 2 then 0.12 else 0)
		add(rig, "Head", "Eye", Vector3.new(ew, eh, 0.08), CFrame.new(sx * hs.X * 0.24, ey, fz), pal.eye, "eye")
		add(rig, "Head", "Shine", Vector3.new(ew * 0.4, eh * 0.35, 0.05), CFrame.new(sx * hs.X * 0.24 - ew * 0.2, ey + eh * 0.25, fz - 0.04), WHITE, "eye")
	end
end

local function addSnout(rig: Rig, kind: string?, headCF: CFrame, hs: Vector3, pal)
	if not kind then
		return
	end
	local fz = headCF.Z - hs.Z / 2
	local y = headCF.Y - hs.Y * 0.2
	if kind == "Dog" then
		local d = hs.Z * 0.4
		add(rig, "Head", "Snout", Vector3.new(hs.X * 0.5, hs.Y * 0.4, d), CFrame.new(0, y, fz - d / 2), pal.accent, "accent")
		add(rig, "Head", "Nose", Vector3.new(hs.X * 0.22, hs.Y * 0.16, 0.1), CFrame.new(0, y + hs.Y * 0.12, fz - d - 0.04), BLACK, "eye")
	elseif kind == "Cat" then
		local d = hs.Z * 0.2
		add(rig, "Head", "Snout", Vector3.new(hs.X * 0.44, hs.Y * 0.28, d), CFrame.new(0, y, fz - d / 2), pal.accent, "accent")
		add(rig, "Head", "Nose", Vector3.new(hs.X * 0.14, hs.Y * 0.1, 0.08), CFrame.new(0, y + hs.Y * 0.1, fz - d - 0.03), Color3.fromRGB(255, 130, 160), "eye")
	elseif kind == "Pig" then
		local d = hs.Z * 0.22
		add(rig, "Head", "Snout", Vector3.new(hs.X * 0.5, hs.Y * 0.38, d), CFrame.new(0, y, fz - d / 2), pal.accent, "accent")
		for _, sx in { -1, 1 } do
			add(rig, "Head", "Nostril", Vector3.new(0.12, 0.16, 0.06), CFrame.new(sx * hs.X * 0.1, y, fz - d - 0.02), pal.detail, "detail")
		end
	elseif kind == "Muzzle" then
		local d = hs.Z * 0.3
		add(rig, "Head", "Snout", Vector3.new(hs.X * 0.7, hs.Y * 0.42, d), CFrame.new(0, y - hs.Y * 0.04, fz - d / 2), pal.accent, "accent")
		add(rig, "Head", "Nose", Vector3.new(hs.X * 0.3, hs.Y * 0.14, 0.08), CFrame.new(0, y + hs.Y * 0.1, fz - d - 0.03), BLACK, "eye")
	elseif kind == "Beak" then
		local d = hs.Z * 0.45
		add(rig, "Head", "Beak", Vector3.new(hs.X * 0.36, hs.Y * 0.26, d), CFrame.new(0, y + hs.Y * 0.05, fz - d / 2), pal.accent, "accent")
	end
end

local function addEars(rig: Rig, kind: string?, headCF: CFrame, hs: Vector3, pal)
	if not kind or kind == "None" then
		return
	end
	local top = headCF.Y + hs.Y / 2
	for _, sx in { -1, 1 } do
		if kind == "Pointy" then
			local s = Vector3.new(hs.X * 0.24, hs.Y * 0.42, 0.22)
			add(rig, "Head", "Ear", s, CFrame.new(sx * hs.X * 0.3, top + s.Y / 2 - 0.05, headCF.Z + 0.1) * CFrame.Angles(0, 0, -sx * 0.18), pal.main, "main")
			add(rig, "Head", "EarIn", Vector3.new(s.X * 0.5, s.Y * 0.6, 0.06), CFrame.new(sx * hs.X * 0.3, top + s.Y * 0.4, headCF.Z - 0.02) * CFrame.Angles(0, 0, -sx * 0.18), pal.accent, "accent")
		elseif kind == "Floppy" then
			local s = Vector3.new(0.28, hs.Y * 0.62, hs.Z * 0.4)
			add(rig, "Head", "Ear", s, CFrame.new(sx * (hs.X / 2 + 0.12), headCF.Y + hs.Y * 0.08, headCF.Z + 0.05) * CFrame.Angles(0, 0, sx * 0.15), pal.detail, "detail")
		elseif kind == "Long" then
			local s = Vector3.new(0.3, hs.Y * 1.05, 0.24)
			add(rig, "Head", "Ear", s, CFrame.new(sx * hs.X * 0.22, top + s.Y / 2 - 0.05, headCF.Z + 0.1) * CFrame.Angles(0, 0, -sx * 0.08), pal.main, "main")
			add(rig, "Head", "EarIn", Vector3.new(0.14, s.Y * 0.75, 0.06), CFrame.new(sx * hs.X * 0.22, top + s.Y / 2, headCF.Z - 0.02) * CFrame.Angles(0, 0, -sx * 0.08), pal.accent, "accent")
		elseif kind == "Round" then
			local s = Vector3.new(hs.X * 0.28, hs.Y * 0.28, 0.24)
			add(rig, "Head", "Ear", s, CFrame.new(sx * hs.X * 0.36, top + s.Y / 2 - 0.08, headCF.Z + 0.1), pal.detail, "detail")
		elseif kind == "Horns" then
			local s = Vector3.new(0.24, hs.Y * 0.46, 0.24)
			add(rig, "Head", "Horn", s, CFrame.new(sx * hs.X * 0.32, top + s.Y / 2 - 0.05, headCF.Z + 0.15) * CFrame.Angles(0.35, 0, -sx * 0.4), pal.detail, "detail")
		elseif kind == "Antlers" then
			local x = sx * hs.X * 0.28
			add(rig, "Head", "Antler", Vector3.new(0.2, 1.3, 0.2), CFrame.new(x, top + 0.6, headCF.Z + 0.15) * CFrame.Angles(0, 0, -sx * 0.25), pal.detail, "detail")
			add(rig, "Head", "Prong", Vector3.new(0.7, 0.18, 0.18), CFrame.new(x + sx * 0.45, top + 0.95, headCF.Z + 0.15) * CFrame.Angles(0, 0, sx * 0.45), pal.detail, "detail")
			add(rig, "Head", "Prong", Vector3.new(0.5, 0.16, 0.16), CFrame.new(x + sx * 0.35, top + 0.45, headCF.Z + 0.15) * CFrame.Angles(0, 0, sx * 0.3), pal.detail, "detail")
		end
	end
end

local function addTail(rig: Rig, kind: string?, root: Vector3, pal, isBird: boolean?)
	if not kind or kind == "None" then
		return
	end
	group(rig, "Tail", CFrame.new(root))
	if kind == "Short" then
		add(rig, "Tail", "Tail", Vector3.new(0.4, 0.4, 0.45), CFrame.new(root + Vector3.new(0, 0.1, 0.2)), pal.main, "main")
	elseif kind == "Long" then
		local cf = CFrame.new(root) * CFrame.Angles(0.55, 0, 0) * CFrame.new(0, 0, 0.8)
		add(rig, "Tail", "Tail", Vector3.new(0.3, 0.3, 1.6), cf, pal.main, "main")
		add(rig, "Tail", "TailTip", Vector3.new(0.34, 0.34, 0.4), cf * CFrame.new(0, 0, 0.8), pal.detail, "detail")
		rig.anchors.tailTip = { group = "Tail", cf = cf * CFrame.new(0, 0, 0.9) }
	elseif kind == "Curly" then
		add(rig, "Tail", "Tail", Vector3.new(0.25, 0.25, 0.5), CFrame.new(root + Vector3.new(0, 0.15, 0.25)), pal.main, "main")
		add(rig, "Tail", "Curl", Vector3.new(0.25, 0.4, 0.25), CFrame.new(root + Vector3.new(0.1, 0.4, 0.5)), pal.main, "main")
	elseif kind == "Fluffy" then
		local cf = CFrame.new(root) * CFrame.Angles(0.7, 0, 0) * CFrame.new(0, 0, 0.65)
		add(rig, "Tail", "Tail", Vector3.new(0.8, 0.8, 1.3), cf, pal.main, "main")
		add(rig, "Tail", "TailTip", Vector3.new(0.84, 0.84, 0.4), cf * CFrame.new(0, 0, 0.72), pal.accent, "accent")
		rig.anchors.tailTip = { group = "Tail", cf = cf * CFrame.new(0, 0, 0.9) }
	elseif kind == "Fan" then
		local w = if isBird then 1.2 else 1
		add(rig, "Tail", "Tail", Vector3.new(w, 0.9, 0.22), CFrame.new(root + Vector3.new(0, 0.25, 0.15)) * CFrame.Angles(-0.4, 0, 0), pal.detail, "detail")
	end
end

local function addWings(rig: Rig, y: number, w: number, l: number, pal, span: number, dragon: boolean?)
	for _, side in { { "WingL", -1 }, { "WingR", 1 } } do
		local name, sx = side[1], side[2]
		local pivot = CFrame.new(sx * w / 2, y, -l * 0.05)
		group(rig, name, pivot)
		local depth = l * (if dragon then 0.85 else 0.6)
		add(rig, name, "Wing", Vector3.new(span, 0.15, depth), pivot * CFrame.new(sx * span / 2, 0, 0), if dragon then pal.main else pal.detail, if dragon then "main" else "detail")
		if dragon then
			add(rig, name, "WingBone", Vector3.new(span, 0.28, 0.28), pivot * CFrame.new(sx * span / 2, 0.08, -depth / 2), pal.detail, "detail")
			add(rig, name, "WingClaw", Vector3.new(0.3, 0.3, 0.5), pivot * CFrame.new(sx * span, 0.08, -depth / 2 - 0.2), pal.accent, "accent")
		end
	end
	rig.effects.wings = true
end

----------------------------------------------------------------------------
-- Templates
----------------------------------------------------------------------------

local function buildQuad(rig: Rig, b, pal)
	local size: Vector3 = b.size or Vector3.new(2.2, 1.8, 3)
	local w, h, l = size.X, size.Y, size.Z
	local hs: Vector3 = b.headSize or Vector3.new(1.7, 1.5, 1.5)
	local legLen = b.legLen or 1.2
	local legT = math.min(w, l) * 0.28
	local bodyY = legLen + h / 2
	local extras = b.extras or {}

	group(rig, "Root", CFrame.new())
	group(rig, "Body", CFrame.new(0, bodyY, 0))
	local wool = table.find(extras, "Wool") ~= nil
	add(rig, "Body", "Torso", if wool then size + Vector3.new(0.4, 0.3, 0.3) else size, CFrame.new(0, bodyY, 0), pal.main, "main")
	add(rig, "Body", "Chest", Vector3.new(w * 0.6, h * 0.5, 0.1), CFrame.new(0, bodyY - h * 0.1, -l / 2 - 0.05), pal.accent, "accent")

	local lx, lz = w / 2 - legT / 2, l / 2 - legT / 2
	for _, leg in { { "LegFL", -lx, -lz }, { "LegFR", lx, -lz }, { "LegBL", -lx, lz }, { "LegBR", lx, lz } } do
		group(rig, leg[1], CFrame.new(leg[2], legLen, leg[3]))
		add(rig, leg[1], leg[1], Vector3.new(legT, legLen, legT), CFrame.new(leg[2], legLen / 2, leg[3]), if wool then pal.accent else pal.main, "main")
		add(rig, leg[1], "Paw", Vector3.new(legT + 0.06, 0.24, legT + 0.06), CFrame.new(leg[2], 0.12, leg[3]), pal.accent, "accent")
	end

	local neckY = bodyY + h * 0.3
	group(rig, "Head", CFrame.new(0, neckY, -l / 2 + 0.1))
	local headCF = CFrame.new(0, neckY + hs.Y * 0.35, -l / 2 - hs.Z * 0.2)
	add(rig, "Head", "Head", hs, headCF, pal.head, "head")
	addEyes(rig, headCF, hs, pal)
	addSnout(rig, b.snout, headCF, hs, pal)
	addEars(rig, b.ears, headCF, hs, pal)
	rig.anchors.head = { group = "Head", cf = headCF, size = hs }
	rig.anchors.back = { group = "Body", y = bodyY + h / 2, w = w, l = l, bodyY = bodyY }
	rig.anchors.front = { group = "Body", cf = CFrame.new(0, bodyY, -l / 2) }

	addTail(rig, b.tail, Vector3.new(0, bodyY + h * 0.25, l / 2), pal)
	if table.find(extras, "Wings") then
		addWings(rig, bodyY + h * 0.4, w, l, pal, w * 1.1)
	end
	return rig
end

local function buildBird(rig: Rig, b, pal)
	local size: Vector3 = b.size or Vector3.new(1.6, 1.5, 1.8)
	local w, h, l = size.X, size.Y, size.Z
	local hs: Vector3 = b.headSize or Vector3.new(1.3, 1.2, 1.2)
	local legLen = b.legLen or 0.7
	local bodyY = legLen + h / 2
	local extras = b.extras or {}

	group(rig, "Root", CFrame.new())
	group(rig, "Body", CFrame.new(0, bodyY, 0))
	add(rig, "Body", "Torso", size, CFrame.new(0, bodyY, 0), pal.main, "main")
	add(rig, "Body", "Chest", Vector3.new(w * 0.7, h * 0.6, 0.1), CFrame.new(0, bodyY - h * 0.08, -l / 2 - 0.05), pal.detail, "detail")

	for _, leg in { { "LegFL", -w * 0.22 }, { "LegFR", w * 0.22 } } do
		group(rig, leg[1], CFrame.new(leg[2], legLen, 0))
		add(rig, leg[1], leg[1], Vector3.new(0.2, legLen, 0.2), CFrame.new(leg[2], legLen / 2, 0), pal.accent, "accent")
		add(rig, leg[1], "Foot", Vector3.new(0.4, 0.12, 0.5), CFrame.new(leg[2], 0.06, -0.1), pal.accent, "accent")
	end

	local neckY = bodyY + h * 0.4
	group(rig, "Head", CFrame.new(0, neckY, -l * 0.2))
	local headCF = CFrame.new(0, neckY + hs.Y * 0.45, -l * 0.22)
	add(rig, "Head", "Head", hs, headCF, pal.head, "head")
	addEyes(rig, headCF, hs, pal)
	addSnout(rig, "Beak", headCF, hs, pal)
	addEars(rig, b.ears, headCF, hs, pal)
	rig.anchors.head = { group = "Head", cf = headCF, size = hs }
	rig.anchors.back = { group = "Body", y = bodyY + h / 2, w = w, l = l, bodyY = bodyY }
	rig.anchors.front = { group = "Body", cf = CFrame.new(0, bodyY, -l / 2) }

	addTail(rig, b.tail or "Fan", Vector3.new(0, bodyY, l / 2), pal, true)

	if table.find(extras, "Wings") then
		addWings(rig, bodyY + h * 0.2, w, l, pal, w * 1.3)
	else
		for _, side in { { "WingL", -1 }, { "WingR", 1 } } do
			local pivot = CFrame.new(side[2] * w / 2, bodyY + h * 0.3, 0)
			group(rig, side[1], pivot)
			add(rig, side[1], "Wing", Vector3.new(0.2, h * 0.7, l * 0.7), pivot * CFrame.new(side[2] * 0.1, -h * 0.3, 0), pal.detail, "detail")
		end
		rig.effects.wings = true
	end
	rig.effects.hop = true
	return rig
end

local function buildZombie(rig: Rig, b, pal)
	group(rig, "Root", CFrame.new())
	group(rig, "Body", CFrame.new(0, 3, 0))
	add(rig, "Body", "Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), pal.accent, "accent")
	add(rig, "Body", "Rip", Vector3.new(0.6, 0.5, 0.06), CFrame.new(0.4, 2.6, -0.52), pal.main, "main")

	for _, leg in { { "LegFL", -0.5 }, { "LegFR", 0.5 } } do
		group(rig, leg[1], CFrame.new(leg[2], 2, 0))
		add(rig, leg[1], leg[1], Vector3.new(0.95, 2, 0.95), CFrame.new(leg[2], 1, 0), pal.detail, "detail")
	end
	for _, arm in { { "ArmL", -1.45 }, { "ArmR", 1.45 } } do
		group(rig, arm[1], CFrame.new(arm[2], 3.7, 0))
		add(rig, arm[1], arm[1], Vector3.new(0.9, 0.9, 2), CFrame.new(arm[2], 3.6, -0.6), pal.main, "main")
		add(rig, arm[1], "Sleeve", Vector3.new(0.95, 0.95, 0.7), CFrame.new(arm[2], 3.6, 0.1), pal.accent, "accent")
	end

	group(rig, "Head", CFrame.new(0, 4, 0))
	local hs = Vector3.new(1.6, 1.6, 1.6)
	local headCF = CFrame.new(0, 4.8, 0)
	add(rig, "Head", "Head", hs, headCF, pal.main, "head")
	pal.eye = if b.neonDetail then pal.detail else Color3.fromRGB(200, 30, 30)
	addEyes(rig, headCF, hs, pal, true)
	add(rig, "Head", "Mouth", Vector3.new(0.7, 0.16, 0.06), CFrame.new(0.1, 4.45, -0.83), BLACK, "eye")
	rig.anchors.head = { group = "Head", cf = headCF, size = hs }
	rig.anchors.back = { group = "Body", y = 4, w = 2, l = 1, bodyY = 3 }
	rig.effects.biped = true
	return rig
end

----------------------------------------------------------------------------
-- Accessories: fruit mutations, brainrot mutations, boss hats
----------------------------------------------------------------------------

local ACCESSORIES = {}

function ACCESSORIES.StrawHat(rig: Rig, pal)
	local head = rig.anchors.head
	local top = head.cf.Y + head.size.Y / 2
	add(rig, "Head", "Brim", Vector3.new(head.size.X * 1.9, 0.14, head.size.Z * 1.9), CFrame.new(0, top + 0.07, head.cf.Z), Color3.fromRGB(232, 200, 110), "detail")
	add(rig, "Head", "HatTop", Vector3.new(head.size.X * 0.9, 0.5, head.size.Z * 0.9), CFrame.new(0, top + 0.35, head.cf.Z), Color3.fromRGB(232, 200, 110), "detail")
	add(rig, "Head", "Band", Vector3.new(head.size.X * 0.92, 0.14, head.size.Z * 0.92), CFrame.new(0, top + 0.18, head.cf.Z), Color3.fromRGB(200, 40, 40), "detail")
end

function ACCESSORIES.Crown(rig: Rig, pal)
	local head = rig.anchors.head
	local top = head.cf.Y + head.size.Y / 2
	add(rig, "Head", "Crown", Vector3.new(head.size.X * 0.8, 0.3, head.size.Z * 0.8), CFrame.new(0, top + 0.15, head.cf.Z), GOLD, "fx")
	for _, o in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		add(rig, "Head", "CrownPoint", Vector3.new(0.18, 0.3, 0.18), CFrame.new(o.X * head.size.X * 0.32, top + 0.45, head.cf.Z + o.Z * head.size.Z * 0.32), GOLD, "fx")
	end
end

function ACCESSORIES.Beard(rig: Rig, pal)
	local head = rig.anchors.head
	add(rig, "Head", "Beard", Vector3.new(0.4, 0.6, 0.3), CFrame.new(0, head.cf.Y - head.size.Y / 2 - 0.2, head.cf.Z - head.size.Z * 0.3), pal.accent, "accent")
end

function ACCESSORIES.Crest(rig: Rig, pal)
	local head = rig.anchors.head
	local top = head.cf.Y + head.size.Y / 2
	add(rig, "Head", "Crest", Vector3.new(0.18, 0.7, head.size.Z * 0.8), CFrame.new(0, top + 0.3, head.cf.Z + 0.1), pal.detail, "detail", if rig.effects.neonDetail then NEON else nil)
end

function ACCESSORIES.Horn(rig: Rig, pal)
	local head = rig.anchors.head
	local cf = CFrame.new(0, head.cf.Y + head.size.Y * 0.35, head.cf.Z - head.size.Z * 0.35) * CFrame.Angles(-0.6, 0, 0)
	add(rig, "Head", "Horn", Vector3.new(0.3, 1.1, 0.3), cf * CFrame.new(0, 0.5, 0), pal.detail, "detail")
end

function ACCESSORIES.Tusks(rig: Rig, pal)
	local head = rig.anchors.head
	for _, sx in { -1, 1 } do
		add(rig, "Head", "Tusk", Vector3.new(0.16, 0.5, 0.16), CFrame.new(sx * head.size.X * 0.25, head.cf.Y - head.size.Y * 0.25, head.cf.Z - head.size.Z * 0.62) * CFrame.Angles(0.3, 0, sx * 0.3), pal.detail, "detail")
	end
end

function ACCESSORIES.Mane(rig: Rig, pal)
	local back = rig.anchors.back
	add(rig, "Body", "Mane", Vector3.new(back.w + 0.3, 1, 0.9), CFrame.new(0, back.y - 0.2, -back.l / 2 + 0.4), pal.detail, "detail")
end

function ACCESSORIES.Stripes(rig: Rig, pal)
	local back = rig.anchors.back
	for i = -1, 1 do
		add(rig, "Body", "Stripe", Vector3.new(back.w + 0.04, 0.9, 0.22), CFrame.new(0, back.y - 0.35, i * back.l * 0.25), pal.detail, "detail")
	end
end

function ACCESSORIES.Spots(rig: Rig, pal)
	local back = rig.anchors.back
	local spots = { Vector3.new(-1, 0.1, -0.2), Vector3.new(1, -0.2, 0.25), Vector3.new(-1, -0.25, 0.3) }
	for _, o in spots do
		add(rig, "Body", "Spot", Vector3.new(0.06, 0.7, 0.9), CFrame.new(o.X * (back.w / 2 + 0.02), back.bodyY + o.Y, o.Z * back.l), pal.detail, "detail")
	end
	add(rig, "Body", "SpotTop", Vector3.new(0.9, 0.06, 1), CFrame.new(0.2, back.y + 0.02, 0.2), pal.detail, "detail")
end

function ACCESSORIES.Shades(rig: Rig, pal)
	local head = rig.anchors.head
	local fz = head.cf.Z - head.size.Z / 2 - 0.1
	local y = head.cf.Y + head.size.Y * 0.12
	add(rig, "Head", "Shades", Vector3.new(head.size.X * 0.92, head.size.Y * 0.24, 0.12), CFrame.new(0, y, fz), BLACK, "fx")
	add(rig, "Head", "ShadesGlint", Vector3.new(0.2, 0.06, 0.05), CFrame.new(-head.size.X * 0.25, y + 0.06, fz - 0.07), WHITE, "fx")
end

function ACCESSORIES.Wool(_rig: Rig, _pal)
	-- handled in buildQuad (fluffier torso)
end

function ACCESSORIES.Wings(_rig: Rig, _pal)
	-- handled by the template
end

-- Fruit "look" parts ------------------------------------------------------

function ACCESSORIES.FlameMane(rig: Rig, pal)
	local head = rig.anchors.head
	local back = rig.anchors.back
	local top = head.cf.Y + head.size.Y / 2
	local orange, yellow = Color3.fromRGB(255, 110, 20), Color3.fromRGB(255, 220, 60)
	add(rig, "Head", "Flame", Vector3.new(0.5, 0.9, 0.5), CFrame.new(0, top + 0.4, head.cf.Z + 0.1) * CFrame.Angles(0, 0.78, 0), orange, "fx", NEON)
	add(rig, "Head", "Flame", Vector3.new(0.3, 0.6, 0.3), CFrame.new(0, top + 0.75, head.cf.Z + 0.1) * CFrame.Angles(0, 0.3, 0), yellow, "fx", NEON)
	for i = 0, 1 do
		add(rig, "Body", "BackFlame", Vector3.new(0.4, 0.6, 0.4), CFrame.new(0, back.y + 0.25, -back.l * 0.15 + i * back.l * 0.35) * CFrame.Angles(0, 0.78, 0), orange, "fx", NEON)
	end
end

function ACCESSORIES.EmberTail(rig: Rig, pal)
	local tip = rig.anchors.tailTip
	if tip then
		add(rig, "Tail", "Ember", Vector3.new(0.5, 0.5, 0.5), tip.cf, Color3.fromRGB(255, 140, 20), "fx", NEON)
	end
end

function ACCESSORIES.IceSpikes(rig: Rig, pal)
	local back = rig.anchors.back
	for i = 0, 3 do
		local z = -back.l * 0.35 + i * back.l * 0.24
		local s = 0.55 - i * 0.06
		add(rig, "Body", "IceSpike", Vector3.new(s, s, s), CFrame.new(0, back.y + 0.1, z) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(200, 245, 255), "fx", NEON)
	end
	local head = rig.anchors.head
	add(rig, "Head", "IceCrown", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, head.cf.Y + head.size.Y / 2 + 0.1, head.cf.Z) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(150, 230, 255), "fx", NEON)
end

function ACCESSORIES.BoltSpikes(rig: Rig, pal)
	local back = rig.anchors.back
	for i = 0, 2 do
		local z = -back.l * 0.3 + i * back.l * 0.3
		add(rig, "Body", "Bolt", Vector3.new(0.22, 0.8, 0.3), CFrame.new(0, back.y + 0.35, z) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.45 else -0.45), Color3.fromRGB(255, 240, 60), "fx", NEON)
	end
end

function ACCESSORIES.DragonWings(rig: Rig, pal)
	-- remove any regular wings, then add big membrane wings
	local keep = {}
	for _, p in rig.parts do
		if p.group ~= "WingL" and p.group ~= "WingR" then
			table.insert(keep, p)
		end
	end
	rig.parts = keep
	local back = rig.anchors.back
	addWings(rig, back.y - 0.1, back.w, back.l, pal, back.w * 1.6 + 0.8, true)
end

function ACCESSORIES.DragonHorns(rig: Rig, pal)
	local head = rig.anchors.head
	local top = head.cf.Y + head.size.Y / 2
	for _, sx in { -1, 1 } do
		local base = CFrame.new(sx * head.size.X * 0.3, top, head.cf.Z + 0.2) * CFrame.Angles(0.7, 0, -sx * 0.25)
		add(rig, "Head", "DHorn", Vector3.new(0.26, 0.7, 0.26), base * CFrame.new(0, 0.35, 0), pal.detail, "detail")
		add(rig, "Head", "DHornTip", Vector3.new(0.18, 0.4, 0.18), base * CFrame.new(0, 0.85, 0.12) * CFrame.Angles(0.4, 0, 0), pal.accent, "accent")
	end
end

function ACCESSORIES.SpikeTail(rig: Rig, pal)
	local tip = rig.anchors.tailTip
	if tip then
		add(rig, "Tail", "TailSpike", Vector3.new(0.6, 0.6, 0.12), tip.cf * CFrame.Angles(0, 0, math.rad(45)), pal.accent, "accent")
	end
	local back = rig.anchors.back
	for i = 0, 2 do
		add(rig, "Body", "BackSpike", Vector3.new(0.12, 0.45, 0.45), CFrame.new(0, back.y + 0.12, -back.l * 0.25 + i * back.l * 0.25) * CFrame.Angles(math.rad(45), 0, 0), pal.accent, "accent")
	end
end

function ACCESSORIES.GlitchHalo(rig: Rig, pal)
	local head = rig.anchors.head
	local pivot = CFrame.new(0, head.cf.Y + head.size.Y / 2 + 0.9, head.cf.Z)
	group(rig, "Halo", pivot)
	local colors = { Color3.fromRGB(255, 60, 220), Color3.fromRGB(60, 255, 240), Color3.fromRGB(255, 240, 60), Color3.fromRGB(120, 255, 90) }
	for i, color in colors do
		local a = (i - 1) / #colors * math.pi * 2
		add(rig, "Halo", "Glitch", Vector3.new(0.32, 0.32, 0.32), pivot * CFrame.new(math.cos(a) * 0.9, 0, math.sin(a) * 0.9), color, "fx", NEON)
	end
	rig.effects.halo = true
end

-- Brainrot mutation accessories -----------------------------------------

function ACCESSORIES.Jaw(rig: Rig, pal)
	local head = rig.anchors.head
	add(rig, "Head", "Jaw", Vector3.new(head.size.X * 0.95, head.size.Y * 0.32, head.size.Z * 0.9), CFrame.new(0, head.cf.Y - head.size.Y * 0.55, head.cf.Z - 0.1), pal.head, "head")
end

function ACCESSORIES.Cup(rig: Rig, pal)
	local head = rig.anchors.head
	local top = head.cf.Y + head.size.Y / 2
	add(rig, "Head", "Cup", Vector3.new(0.55, 0.65, 0.55), CFrame.new(head.size.X * 0.2, top + 0.32, head.cf.Z), WHITE, "fx")
	add(rig, "Head", "Coffee", Vector3.new(0.47, 0.06, 0.47), CFrame.new(head.size.X * 0.2, top + 0.66, head.cf.Z), Color3.fromRGB(110, 70, 40), "fx")
	add(rig, "Head", "Sleeve", Vector3.new(0.6, 0.22, 0.6), CFrame.new(head.size.X * 0.2, top + 0.3, head.cf.Z), Color3.fromRGB(0, 120, 80), "fx")
end

function ACCESSORIES.Grass(rig: Rig, pal)
	local head = rig.anchors.head
	local top = head.cf.Y + head.size.Y / 2
	for i = -1, 1 do
		add(rig, "Head", "Grass", Vector3.new(0.14, 0.45 + (1 - math.abs(i)) * 0.2, 0.14), CFrame.new(i * 0.2, top + 0.25, head.cf.Z) * CFrame.Angles(0, 0, i * 0.3), Color3.fromRGB(90, 200, 70), "fx")
	end
end

function ACCESSORIES.Hands67(rig: Rig, pal)
	local front = rig.anchors.front
	local back = rig.anchors.back
	if not front then
		return
	end
	for _, side in { { "HandL", -1 }, { "HandR", 1 } } do
		local pivot = CFrame.new(side[2] * back.w * 0.55, back.bodyY + 0.2, -back.l / 2 - 0.2)
		group(rig, side[1], pivot)
		add(rig, side[1], "Hand", Vector3.new(0.5, 0.5, 0.3), pivot * CFrame.new(0, 0.3, 0), pal.accent, "accent")
	end
	rig.effects.hands67 = true
end

function ACCESSORIES.Hearts(rig: Rig)
	rig.effects.hearts = true
end

function ACCESSORIES.Spotlight(rig: Rig)
	rig.effects.spotlight = true
end

function ACCESSORIES.Glitch(rig: Rig)
	rig.effects.glitch = true
end

function ACCESSORIES.AuraGold(rig: Rig)
	rig.effects.aura = rig.effects.aura or "Gold"
	rig.effects.auraGold = true
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------

local TEMPLATES = {
	Quad = buildQuad,
	Bird = buildBird,
	Zombie = buildZombie,
}

--[[
	BlockyBuilder.Build(body, opts)
	opts = {
		scale: number?,            extra scale (rarity/fruit/mutation size)
		variant: string?,          "Normal" | "Shiny" | "Golden" | "Rainbow"
		fruit: string?,            fruit id -> look
		awakened: boolean?,
		mutations: { string }?,
	}
]]
function BlockyBuilder.Build(body, opts: { [string]: any }?)
	local o = opts or {}
	local fruit = o.fruit and Fruits.List[o.fruit]
	local fruitLook = fruit and fruit.look
	local mutationTint: Color3? = nil
	local mutationAccessories = {}
	-- Size multipliers from rarity/fruit/mutations arrive pre-multiplied in
	-- opts.scale (PetStats.sizeMult), so they are not re-applied here.
	for _, id in o.mutations or {} do
		local m = Mutations.List[id]
		if m then
			mutationTint = m.tint or mutationTint
			if m.accessory then
				table.insert(mutationAccessories, m.accessory)
			end
			if m.special and m.special.jitter then
				mutationAccessories[#mutationAccessories + 1] = "__jitter"
			end
		end
	end

	local scale = (body.scale or 1) * (o.scale or 1)
	local template = body.template or "Quad"
	local rig = newRig(template, scale)
	rig.effects.neonDetail = body.neonDetail
	local pal = makePalette(body, o.variant, fruitLook, mutationTint)

	TEMPLATES[template](rig, body, pal)

	for _, extra in body.extras or {} do
		local fn = ACCESSORIES[extra]
		if fn then
			fn(rig, pal)
		end
	end
	if fruitLook then
		for _, partId in fruitLook.parts or {} do
			local fn = ACCESSORIES[partId]
			if fn then
				fn(rig, pal)
			end
		end
		rig.effects.aura = fruitLook.aura
		rig.effects.rainbow = fruitLook.rainbow
		rig.effects.fruit = o.fruit
		if o.awakened then
			rig.effects.awakened = true
		end
	end
	for _, acc in mutationAccessories do
		if acc == "__jitter" then
			rig.effects.jitter = true
		else
			local fn = ACCESSORIES[acc]
			if fn then
				fn(rig, pal)
			end
		end
	end

	if o.variant == "Rainbow" then
		rig.effects.rainbow = true
	elseif o.variant == "Shiny" then
		rig.effects.sparkles = true
	elseif o.variant == "Golden" then
		rig.effects.golden = true
	end

	return finalize(rig)
end

return BlockyBuilder
