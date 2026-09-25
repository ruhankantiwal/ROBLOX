--[[
	FX: every visual effect in the game, built from neon blocks and tweens.
	Budgets scale with the player's graphics quality so phones stay smooth.

	The two money shots for TikTok/Shorts live here:
	  * DeathExplosion: zombies burst into physics blocks (ragdoll pop)
	  * the ability rings/cones/lightning that come off mutated pets
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local FX = {}

local folder: Folder
local debrisCount = 0
local textPool: { BillboardGui } = {}
local activeTexts = 0
local shake = { amount = 0, untilT = 0 }

FX.ElementColors = {
	Hit = Color3.fromRGB(255, 255, 255),
	Fire = Color3.fromRGB(255, 110, 30),
	Ice = Color3.fromRGB(150, 230, 255),
	Lightning = Color3.fromRGB(255, 240, 60),
	Volt = Color3.fromRGB(255, 240, 60),
	Dragon = Color3.fromRGB(255, 60, 60),
	Brainrot = Color3.fromRGB(255, 80, 220),
	Heal = Color3.fromRGB(90, 255, 120),
	Taunt = Color3.fromRGB(255, 170, 60),
	Spit = Color3.fromRGB(160, 255, 80),
	Turret = Color3.fromRGB(110, 200, 255),
	Nuke = Color3.fromRGB(255, 255, 180),
}

-- 0.3 (potato) .. 1 (high)
function FX.Quality(): number
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	local q = if ok and level > 0 then level / 10 else 0.6
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		q = math.min(q, 0.5)
	end
	return math.clamp(q, 0.3, 1)
end

function FX.Start()
	folder = Instance.new("Folder")
	folder.Name = "ClientFX"
	folder.Parent = workspace

	RunService:BindToRenderStep("BeastShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now < shake.untilT then
			local camera = workspace.CurrentCamera
			local a = shake.amount * ((shake.untilT - now) / 0.4)
			camera.CFrame *= CFrame.new(math.random() * a - a / 2, math.random() * a - a / 2, 0)
		end
	end)
end

function FX.Shake(amount: number, duration: number?)
	shake.amount = math.max(shake.amount * (if os.clock() < shake.untilT then 1 else 0), amount)
	shake.untilT = os.clock() + (duration or 0.4)
end

local function block(size: Vector3, cf: CFrame, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon == false then Enum.Material.SmoothPlastic else Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function fadeAndKill(p: BasePart, duration: number, goal: { [string]: any }?)
	local props: { [string]: any } = { Transparency = 1 }
	local extra: { [string]: any } = goal or {}
	for k, v in extra do
		props[k] = v
	end
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
	Debris:AddItem(p, duration + 0.05)
end

----------------------------------------------------------------------------
-- Primitives
----------------------------------------------------------------------------

-- Expanding flat ring on the ground.
function FX.Ring(pos: Vector3, radius: number, color: Color3, duration: number?)
	local d = duration or 0.45
	local ring = block(Vector3.new(0.4, 2, 2), CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), color)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.2
	fadeAndKill(ring, d, { Size = Vector3.new(0.4, radius * 2, radius * 2) })
end

-- Blocks flying outward (tween only, no physics).
function FX.Burst(pos: Vector3, color: Color3, count: number?, speed: number?)
	local n = math.floor((count or 8) * FX.Quality())
	for _ = 1, n do
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
		local s = 0.3 + math.random() * 0.5
		local p = block(Vector3.new(s, s, s), CFrame.new(pos), color)
		fadeAndKill(p, 0.45, {
			CFrame = CFrame.new(pos + dir * (speed or 6)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Size = Vector3.new(0.05, 0.05, 0.05),
		})
	end
end

function FX.Cone(pos: Vector3, dir: Vector3, range: number, angleDeg: number, color: Color3)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	flat = flat.Unit
	local width = 2 * range * math.tan(math.rad(angleDeg / 2))
	local cf = CFrame.lookAt(pos + Vector3.new(0, 1.5, 0), pos + Vector3.new(0, 1.5, 0) + flat) * CFrame.new(0, 0, -range / 2)
	local wedge = block(Vector3.new(1, 3, 2), cf, color)
	wedge.Transparency = 0.3
	fadeAndKill(wedge, 0.4, { Size = Vector3.new(width, 3.5, range) })
	for k = 1, math.floor(6 * FX.Quality()) do
		local off = (math.random() - 0.5) * width * 0.8
		local target = cf * CFrame.new(off, 0, -range / 2)
		local p = block(Vector3.new(0.8, 0.8, 0.8), CFrame.new(pos + Vector3.new(0, 1.5, 0)), color)
		fadeAndKill(p, 0.35 + k * 0.02, { CFrame = target })
	end
end

function FX.Projectile(from: Vector3, to: Vector3, color: Color3, size: number?)
	local s = size or 0.8
	local p = block(Vector3.new(s, s, s), CFrame.new(from), color)
	local t = math.clamp((to - from).Magnitude / 90, 0.08, 0.35)
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) }):Play()
	task.delay(t, function()
		FX.Burst(to, color, 4, 3)
		p:Destroy()
	end)
end

-- Jagged lightning through a list of points.
function FX.Lightning(points: { Vector3 }, color: Color3)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local segments = 3
		local prev = a
		for s = 1, segments do
			local t = s / segments
			local nextP = a:Lerp(b, t) + (if s < segments then Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 else Vector3.zero)
			local len = (nextP - prev).Magnitude
			local seg = block(Vector3.new(0.3, 0.3, len), CFrame.lookAt((prev + nextP) / 2, nextP), color)
			fadeAndKill(seg, 0.25)
			prev = nextP
		end
	end
end

function FX.Beam(from: Vector3, to: Vector3, color: Color3, width: number?)
	local len = (to - from).Magnitude
	if len < 0.1 then
		return
	end
	local w = width or 0.5
	local seg = block(Vector3.new(w, w, len), CFrame.lookAt((from + to) / 2, to), color)
	fadeAndKill(seg, 0.2)
end

----------------------------------------------------------------------------
-- Floating text / damage numbers (pooled BillboardGuis)
----------------------------------------------------------------------------

local function getText(): BillboardGui
	local gui = table.remove(textPool)
	if gui then
		return gui
	end
	gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.Name = "T"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	return gui
end

function FX.Text(pos: Vector3, text: string, color: Color3, big: boolean?)
	local cap = math.floor(40 * FX.Quality())
	if activeTexts >= cap then
		return
	end
	activeTexts += 1
	local anchor = block(Vector3.new(0.1, 0.1, 0.1), CFrame.new(pos + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2), color)
	anchor.Transparency = 1
	local gui = getText()
	local label = gui:FindFirstChild("T") :: TextLabel
	gui.Size = if big then UDim2.fromOffset(300, 70) else UDim2.fromOffset(200, 42)
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = anchor.CFrame + Vector3.new(0, if big then 6 else 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.6), { TextTransparency = 1 }):Play()
	task.delay(0.95, function()
		activeTexts -= 1
		gui.Parent = nil
		gui.Adornee = nil
		table.insert(textPool, gui)
		anchor:Destroy()
	end)
end

function FX.Damage(pos: Vector3, amount: number, crit: boolean, color: Color3?)
	local text = if amount >= 1e6 then string.format("%.1fM", amount / 1e6) elseif amount >= 1e3 then string.format("%.1fK", amount / 1e3) else tostring(amount)
	FX.Text(pos, if crit then text .. "!" else text, if crit then Color3.fromRGB(255, 70, 70) else (color or Color3.new(1, 1, 1)), crit)
end

----------------------------------------------------------------------------
-- Zombie death: the ragdoll pop
----------------------------------------------------------------------------

local DEATH_STYLES = {
	Fire = { color = Color3.fromRGB(40, 30, 30), burst = Color3.fromRGB(255, 120, 30), power = 1 },
	Ice = { color = Color3.fromRGB(180, 235, 255), burst = Color3.fromRGB(200, 245, 255), power = 0.8 },
	Volt = { burst = Color3.fromRGB(255, 240, 60), power = 1.2 },
	Lightning = { burst = Color3.fromRGB(255, 240, 60), power = 1.2 },
	Dragon = { color = Color3.fromRGB(50, 30, 30), burst = Color3.fromRGB(255, 70, 40), power = 1.4 },
	Nuke = { burst = Color3.fromRGB(255, 255, 200), power = 2.4 },
	Meme_GravityFlip = { burst = Color3.fromRGB(255, 80, 220), power = 1.6, up = 3 },
	Meme_ConfettiNuke = { burst = Color3.fromRGB(255, 220, 60), power = 1.8, confetti = true },
	Meme_BruhFreeze = { color = Color3.fromRGB(180, 235, 255), burst = Color3.fromRGB(255, 255, 255), power = 1 },
	Poof = { poof = true },
}

function FX.DeathExplosion(parts: { BasePart }, center: Vector3, fx: string)
	local style = DEATH_STYLES[fx] or { burst = Color3.fromRGB(150, 255, 120), power = 1 }
	if style.poof then
		for _, p in parts do
			fadeAndKill(p, 0.3, { Size = p.Size * 0.2 })
		end
		FX.Burst(center, Color3.fromRGB(200, 200, 220), 6)
		return
	end
	local budget = math.floor(260 * FX.Quality())
	local power = style.power or 1
	for _, p in parts do
		if style.color then
			p.Color = p.Color:Lerp(style.color, 0.7)
		end
		if debrisCount < budget then
			debrisCount += 1
			p.Anchored = false
			p.CanCollide = true
			p.Parent = folder
			local out = (p.Position - center)
			out = if out.Magnitude > 0.01 then out.Unit else Vector3.new(0, 1, 0)
			p.AssemblyLinearVelocity = (out * 28 + Vector3.new(0, 30 * (style.up or 1), 0) + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 16) * power
			p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 22
			task.delay(1.8, function()
				fadeAndKill(p, 0.5)
				task.delay(0.5, function()
					debrisCount -= 1
				end)
			end)
		else
			fadeAndKill(p, 0.3)
		end
	end
	FX.Burst(center + Vector3.new(0, 2, 0), style.burst, 10, 8 * power)
	if style.confetti then
		local colors = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 230, 60), Color3.fromRGB(120, 255, 120) }
		for i = 1, math.floor(18 * FX.Quality()) do
			FX.Burst(center + Vector3.new(0, 3, 0), colors[i % #colors + 1], 1, 14)
		end
	end
end

----------------------------------------------------------------------------
-- Ability dispatcher (fx names come from Config/Fruits and services)
----------------------------------------------------------------------------

function FX.Ability(fx: string, pos: Vector3, radius: number, dir: Vector3, ownerIsLocal: boolean)
	local q = FX.Quality()
	if fx == "FireBurst" or fx == "FireRing" then
		FX.Ring(pos, radius, FX.ElementColors.Fire)
		FX.Burst(pos + Vector3.new(0, 1, 0), Color3.fromRGB(255, 200, 60), 14, radius * 0.6)
	elseif fx == "IceRing" then
		FX.Ring(pos, radius, FX.ElementColors.Ice, 0.6)
		FX.Burst(pos + Vector3.new(0, 1, 0), Color3.new(1, 1, 1), 12, radius * 0.5)
	elseif fx == "IceCone" then
		FX.Cone(pos, dir, radius, 55, FX.ElementColors.Ice)
	elseif fx == "DragonBreath" then
		FX.Cone(pos, dir, radius, 50, FX.ElementColors.Fire)
		FX.Cone(pos, dir, radius * 0.7, 30, Color3.fromRGB(255, 230, 80))
	elseif fx == "VoltRing" then
		FX.Ring(pos, radius, FX.ElementColors.Volt, 0.3)
		for _ = 1, math.floor(5 * q) do
			local a = math.random() * math.pi * 2
			local r = math.random() * radius
			local ground = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			FX.Lightning({ ground + Vector3.new(0, 18, 0), ground }, FX.ElementColors.Volt)
		end
	elseif fx == "SkyDive" then
		FX.Ring(pos, radius, FX.ElementColors.Dragon, 0.6)
		FX.Ring(pos, radius * 0.6, Color3.fromRGB(255, 200, 60), 0.4)
		FX.Burst(pos, Color3.fromRGB(120, 90, 70), 16, radius * 0.5)
	elseif fx == "Dash" then
		FX.Beam(pos + Vector3.new(0, 2, 0), pos + dir + Vector3.new(0, 2, 0), Color3.fromRGB(255, 255, 255), 1.2)
	elseif fx == "Glitch" or fx:sub(1, 5) == "Meme_" then
		local colors = { Color3.fromRGB(255, 60, 220), Color3.fromRGB(60, 255, 240), Color3.fromRGB(255, 240, 60) }
		for i, c in colors do
			task.delay(i * 0.06, function()
				FX.Ring(pos, radius * (0.6 + i * 0.15), c, 0.35)
			end)
		end
		if fx == "Meme_ConfettiNuke" or fx == "Meme_GigaMode" then
			FX.Burst(pos + Vector3.new(0, 3, 0), colors[math.random(1, 3)], 20, radius)
		end
	elseif fx == "Aura" then
		FX.Ring(pos, radius, Color3.fromRGB(255, 215, 0), 0.7)
		FX.Ring(pos, radius * 0.5, Color3.new(1, 1, 1), 0.5)
		FX.Burst(pos + Vector3.new(0, 2, 0), Color3.fromRGB(255, 215, 0), 18, radius * 0.7)
	elseif fx == "Heal" then
		FX.Ring(pos, radius * 0.4, FX.ElementColors.Heal, 0.5)
	elseif fx == "Taunt" then
		FX.Ring(pos, radius, FX.ElementColors.Taunt, 0.35)
	elseif fx == "Nuke" then
		FX.Ring(pos, radius, FX.ElementColors.Nuke, 1.2)
		FX.Ring(pos, radius * 0.5, Color3.fromRGB(255, 160, 40), 0.9)
		FX.Shake(2.5, 1)
	elseif fx:sub(1, 6) == "Mount_" then
		local element = fx:sub(7)
		FX.Cone(pos, dir, radius, 70, FX.ElementColors[element] or Color3.new(1, 1, 1))
	else
		FX.Ring(pos, radius, Color3.new(1, 1, 1), 0.3)
	end
	if ownerIsLocal and radius >= 14 then
		FX.Shake(0.6 + radius / 40, 0.35)
	end
end

function FX.LocalPlayerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

return FX
