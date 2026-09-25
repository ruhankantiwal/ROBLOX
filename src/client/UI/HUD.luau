--[[
	HUD layout (mobile-first, keeps clear of Roblox's own chat, leaderboard,
	thumbstick and jump button):

	  ┌──────────── [💰 coins] [🧪 mutagen] [💎 gems] [Lv 12 ▓▓▓░] ─────────┐
	  │  🐾          [WAVE 7 · 12 left · ❤ Barn Heart ▓▓▓▓░]           📜 │
	  │  🍉          [👹 Farmer Zed ▓▓▓▓▓▓░░]  (toasts under here)     quest│
	  │  🧪                                                          tracker│
	  │  🛒                                                              │
	  │  🎁                                                       [🧟 WAVE]│
	  │  ⚙️                                                       [🐎 RIDE]│
	  │           [👣 Follow][⚔️ Attack][🛡️ Guard][🏹 Hunt]       [⚔️ HIT] │
	  │           [🐶 ▓▓][🐱 ▓▓][🐷 ▓▓] ← squad cards        (jump btn)│
	  └──────────────────────────────────────────────────────────────────┘
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Fruits = require(Shared.Config.Fruits)
local Rarity = require(Shared.Config.Rarity)
local Progression = require(Shared.Config.Progression)
local World = require(Shared.Config.World)
local Protocol = require(Shared.Util.EntityProtocol)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Kit)
local Panels = require(script.Parent.Panels)
local ClientState = require(script.Parent.Parent.ClientState)
local EntityRenderer = require(script.Parent.Parent.Controllers.EntityRenderer)
local Cinematics = require(script.Parent.Parent.Controllers.Cinematics)

local LOCAL = Players.LocalPlayer
local K = Kit.Colors

local HUD = {
	squadMode = "Follow",
	mounted = false,
	OnRideToggle = nil :: (() -> ())?,
	OnMountAttack = nil :: (() -> ())?,
}

local screen: ScreenGui
local main: Frame
local pills = {}
local levelFill: Frame
local levelText: TextLabel
local waveFrame: Frame
local waveText: TextLabel
local coreFill: Frame
local heistText: TextLabel
local bossFrame: Frame
local bossText: TextLabel
local bossFill: Frame
local toastList: Frame
local squadBar: Frame
local commandButtons = {}
local rideBtn: TextButton
local attackBtn: TextButton
local waveBtn: TextButton
local questTracker: TextLabel
local squadCards = {}

local TOAST_COLORS = {
	info = Color3.fromRGB(60, 70, 100),
	good = Color3.fromRGB(46, 150, 70),
	reward = Color3.fromRGB(200, 140, 20),
	warn = Color3.fromRGB(200, 110, 30),
	error = Color3.fromRGB(190, 50, 60),
	levelup = Color3.fromRGB(120, 70, 220),
	zone = Color3.fromRGB(40, 120, 160),
	secret = Color3.fromRGB(20, 20, 24),
}

----------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------

local function pill(icon: string, color: Color3, order: number): TextLabel
	local frame = Kit.new("Frame", {
		Size = UDim2.fromOffset(150, 44),
		BackgroundColor3 = K.Panel,
		LayoutOrder = order,
	}, { Kit.corner(22), Kit.stroke(3) })
	Kit.label(icon, 24, nil, { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 2), Parent = frame })
	local value = Kit.label("0", 22, color, {
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.fromOffset(44, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	return value, frame
end

local function menuButton(parent: Instance, icon: string, label: string, color: Color3, order: number, onClick: () -> ())
	local btn = Kit.button("", color, { Size = UDim2.fromOffset(78, 78), LayoutOrder = order, Parent = parent }, onClick)
	Kit.label(icon, 34, nil, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 4), Parent = btn })
	Kit.label(label, 15, nil, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -26), Parent = btn })
	return btn
end

function HUD.Start()
	screen = Kit.new("ScreenGui", {
		Name = "BeastHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = LOCAL:WaitForChild("PlayerGui"),
	})
	main = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = screen })
	local uiScale = Kit.new("UIScale", { Parent = main })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(vp.Y / 640, 0.6, 1.2)
		main.Size = UDim2.fromScale(1 / uiScale.Scale, 1 / uiScale.Scale)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	-- Top bar: currencies + level
	local top = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		Position = UDim2.fromOffset(0, 8),
		BackgroundTransparency = 1,
		Parent = main,
	})
	Kit.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center).Parent = top
	pills.coins = pill("💰", K.Coins, 1)
	pills.coins.Parent.Parent = top
	pills.mutagen = pill("🧪", K.Mutagen, 2)
	pills.mutagen.Parent.Parent = top
	pills.gems = pill("💎", K.Gems, 3)
	pills.gems.Parent.Parent = top
	local lvl = Kit.new("Frame", { Size = UDim2.fromOffset(170, 44), BackgroundColor3 = K.Panel, LayoutOrder = 4, Parent = top }, { Kit.corner(22), Kit.stroke(3) })
	local bar = Kit.new("Frame", { Size = UDim2.new(1, -16, 0, 12), Position = UDim2.new(0, 8, 1, -18), BackgroundColor3 = K.PanelLight, Parent = lvl }, { Kit.corner(6) })
	levelFill = Kit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = K.Purple, Parent = bar }, { Kit.corner(6) })
	levelText = Kit.label("Lv 1", 18, nil, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 2), Parent = lvl })

	-- Banners (wave, heist, boss) + toasts
	local center = Kit.new("Frame", {
		Size = UDim2.fromOffset(460, 400),
		Position = UDim2.new(0.5, 0, 0, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = main,
	})
	Kit.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center).Parent = center
	waveFrame = Kit.panel({ Size = UDim2.fromOffset(420, 62), Visible = false, LayoutOrder = 1, Parent = center })
	waveText = Kit.label("", 20, nil, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 4), Parent = waveFrame })
	local coreBar = Kit.new("Frame", { Size = UDim2.new(1, -24, 0, 14), Position = UDim2.new(0, 12, 1, -22), BackgroundColor3 = K.PanelLight, Parent = waveFrame }, { Kit.corner(7) })
	coreFill = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 70, 100), Parent = coreBar }, { Kit.corner(7) })
	heistText = Kit.label("", 18, K.Gold, { Size = UDim2.fromOffset(440, 50), Visible = false, LayoutOrder = 2, Parent = center })
	bossFrame = Kit.panel({ Size = UDim2.fromOffset(420, 56), Visible = false, LayoutOrder = 3, BackgroundColor3 = Color3.fromRGB(60, 20, 30), Parent = center })
	bossText = Kit.label("", 18, Color3.fromRGB(255, 120, 120), { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 2), Parent = bossFrame })
	local bossBar = Kit.new("Frame", { Size = UDim2.new(1, -24, 0, 14), Position = UDim2.new(0, 12, 1, -20), BackgroundColor3 = K.PanelLight, Parent = bossFrame }, { Kit.corner(7) })
	bossFill = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 60, 60), Parent = bossBar }, { Kit.corner(7) })
	toastList = Kit.new("Frame", { Size = UDim2.fromOffset(460, 200), BackgroundTransparency = 1, LayoutOrder = 4, Parent = center })
	Kit.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center).Parent = toastList

	-- Left menu
	local left = Kit.new("Frame", {
		Size = UDim2.fromOffset(90, 520),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = main,
	})
	Kit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left).Parent = left
	menuButton(left, "🐾", "Pets", K.Blue, 1, function()
		Panels.Toggle("Pets")
	end)
	menuButton(left, "🍉", "Fruits", K.Red, 2, function()
		Panels.Toggle("Fruits")
	end)
	menuButton(left, "🧪", "Lab", K.Purple, 3, function()
		Panels.Toggle("Lab")
	end)
	menuButton(left, "🛒", "Shop", K.Gold, 4, function()
		Panels.Toggle("Shop")
	end)
	menuButton(left, "🎁", "Daily", K.Pink, 5, function()
		Panels.Toggle("Daily")
	end)
	menuButton(left, "⚙️", "More", Color3.fromRGB(110, 120, 150), 6, function()
		Panels.Toggle("Settings")
	end)

	-- Right: quest tracker
	local questBtn = Kit.new("TextButton", {
		Size = UDim2.fromOffset(230, 120),
		Position = UDim2.new(1, -12, 0.3, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = K.Panel,
		BackgroundTransparency = 0.25,
		Text = "",
		Parent = main,
	}, { Kit.corner(14), Kit.stroke(3) })
	questTracker = Kit.label("", 14, nil, {
		Size = UDim2.new(1, -16, 1, -12),
		Position = UDim2.fromOffset(8, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = questBtn,
	})
	questBtn.Activated:Connect(function()
		Panels.Toggle("Quests")
	end)

	-- Right-bottom actions (above the mobile jump button)
	local actions = Kit.new("Frame", {
		Size = UDim2.fromOffset(120, 300),
		Position = UDim2.new(1, -16, 1, -150),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = main,
	})
	local actionList = Kit.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right)
	actionList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	actionList.Parent = actions
	waveBtn = Kit.button("🧟 WAVE", K.Green, { Size = UDim2.fromOffset(110, 64), TextSize = 22, LayoutOrder = 1, Visible = false, Parent = actions }, function()
		Net.Event("StartWave"):FireServer()
	end)
	rideBtn = Kit.button("🐎 RIDE", K.Gold, { Size = UDim2.fromOffset(110, 64), TextSize = 22, LayoutOrder = 2, Parent = actions }, function()
		if HUD.OnRideToggle then
			HUD.OnRideToggle()
		end
	end)
	attackBtn = Kit.button("⚔️", K.Red, { Size = UDim2.fromOffset(96, 96), TextSize = 46, LayoutOrder = 3, Visible = false, Parent = actions }, function()
		if HUD.OnMountAttack then
			HUD.OnMountAttack()
		end
	end)

	-- Squad commands + cards
	local bottom = Kit.new("Frame", {
		Size = UDim2.fromOffset(560, 150),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = main,
	})
	local commands = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, Parent = bottom })
	Kit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = commands
	for i, cmd in { { "Follow", "👣" }, { "Attack", "⚔️" }, { "Guard", "🛡️" }, { "Hunt", "🏹" } } do
		local mode = cmd[1]
		commandButtons[mode] = Kit.button(cmd[2] .. " " .. mode, K.PanelLight, { Size = UDim2.fromOffset(120, 46), TextSize = 18, LayoutOrder = i, Parent = commands }, function()
			HUD.SetSquadMode(mode)
		end)
	end
	squadBar = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromOffset(0, 56), BackgroundTransparency = 1, Parent = bottom })
	Kit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = squadBar
	HUD.SetSquadMode("Follow", true)

	Panels.Start(main)

	-- Clip mode escape hatch (always visible, tiny)
	local clip = Kit.new("ScreenGui", { Name = "ClipModeButton", ResetOnSpawn = false, DisplayOrder = 60, Parent = LOCAL.PlayerGui })
	Kit.button("🎬", Color3.fromRGB(40, 40, 50), {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -8, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 20,
		BackgroundTransparency = 0.5,
		Parent = clip,
	}, function()
		Cinematics.ToggleClipMode()
	end)

	-- Wiring
	Net.Event("Notify").OnClientEvent:Connect(HUD.Toast)
	Net.Event("Announce").OnClientEvent:Connect(HUD.Announce)
	ClientState.Changed:Connect(HUD.OnChanged)
	ClientState.Loaded:Connect(function()
		HUD.RefreshAll()
		local d = ClientState.data
		local today = math.floor(ClientState.Now() / 86400)
		if d.daily.lastClaim == 0 or math.floor(d.daily.lastClaim / 86400) ~= today then
			task.delay(2, function()
				Panels.Open("Daily")
			end)
		end
	end)
	if ClientState.loaded then
		HUD.RefreshAll()
	end
	RunService.Heartbeat:Connect(HUD.Tick)
end

----------------------------------------------------------------------------
-- Updates
----------------------------------------------------------------------------

function HUD.RefreshAll()
	for _, key in { "coins", "mutagen", "gems", "xp", "equipped", "quests" } do
		HUD.OnChanged(key)
	end
end

function HUD.OnChanged(key: string)
	local d = ClientState.data
	if not d then
		return
	end
	if key == "coins" or key == "mutagen" or key == "gems" then
		pills[key].Text = Format.Short(d[key])
	elseif key == "xp" or key == "level" then
		levelText.Text = ("Lv %d"):format(d.level)
		levelFill.Size = UDim2.fromScale(math.clamp(d.xp / Progression.PlayerXpToNext(d.level), 0, 1), 1)
	elseif key == "equipped" or key == "pets" or key == "alpha" then
		HUD.RebuildSquad()
	elseif key == "quests" or key == "stats" then
		HUD.RefreshQuests()
	elseif key == "wave" then
		HUD.RefreshWave()
	elseif key == "heist" then
		HUD.RefreshHeist()
	end
end

function HUD.RefreshQuests()
	local d = ClientState.data
	local lines = { "📜 DAILY QUESTS" }
	for i, q in d.quests.list do
		local progress = math.min((d.stats[q.stat] or 0) - q.base, q.goal)
		local mark = if d.quests.claimed[tostring(i)] then "✅" elseif progress >= q.goal then "🎁" else "▫️"
		table.insert(lines, ("%s %s (%d/%d)"):format(mark, q.text, progress, q.goal))
	end
	questTracker.Text = table.concat(lines, "\n")
end

function HUD.RefreshWave()
	local w = ClientState.wave
	waveFrame.Visible = w ~= nil and w.state ~= "Idle"
	if w then
		if w.state == "Fighting" then
			waveText.Text = ("🧟 WAVE %d · %d left"):format(w.wave, w.remaining)
		elseif w.state == "Break" then
			waveText.Text = ("✅ Wave %d cleared! Next in %ds"):format(w.wave, math.ceil(w.breakLeft))
		end
		coreFill.Size = UDim2.fromScale(math.clamp(w.coreHp / w.coreMax, 0, 1), 1)
	end
end

function HUD.RefreshHeist()
	local h = ClientState.heist
	heistText.Visible = h ~= nil
	if h then
		heistText.Text = if h.carrying then "🥚 RUN HOME! Guards are chasing you!"
			elseif h.bossDead then "🥚 Hold STEAL EGG on the pedestal!"
			else ("🥷 %s: defeat the %s"):format(h.name, h.bossName or "boss")
	end
end

function HUD.RebuildSquad()
	local d = ClientState.data
	Kit.clear(squadBar, { "UIListLayout" })
	table.clear(squadCards)
	for i, uid in d.equipped do
		local pet = d.pets[uid]
		if pet then
			local def = Pets.Species[pet.species]
			local card = Kit.new("TextButton", {
				Size = UDim2.fromOffset(84, 84),
				BackgroundColor3 = K.Panel,
				Text = "",
				LayoutOrder = i,
				Parent = squadBar,
			}, { Kit.corner(14), Kit.stroke(3, Rarity.Color(def.rarity)) })
			Kit.label(def.emoji, 32, nil, { Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 4), Parent = card })
			Kit.label("Lv" .. pet.level, 13, K.Muted, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 44), Parent = card })
			if pet.fruit then
				Kit.label(Fruits.List[pet.fruit.id].emoji, 18, nil, { Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -24, 0, 2), Parent = card })
			end
			if d.alpha == uid then
				Kit.label("👑", 18, nil, { Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(2, 2), Parent = card })
			end
			local bar = Kit.new("Frame", { Size = UDim2.new(1, -12, 0, 10), Position = UDim2.new(0, 6, 1, -16), BackgroundColor3 = K.PanelLight, Parent = card }, { Kit.corner(5) })
			local fill = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.Green, Parent = bar }, { Kit.corner(5) })
			squadCards[uid] = { fill = fill, card = card }
			card.Activated:Connect(function()
				Panels.Open("Pets", uid)
			end)
		end
	end
end

function HUD.SetSquadMode(mode: string, silent: boolean?)
	HUD.squadMode = mode
	for name, btn in commandButtons do
		btn.BackgroundColor3 = if name == mode then K.Green else K.PanelLight
	end
	if not silent then
		Net.Event("SquadCommand"):FireServer(mode)
	end
end

function HUD.SetMounted(mounted: boolean)
	HUD.mounted = mounted
	rideBtn.Text = if mounted then "🛑 HOP OFF" else "🐎 RIDE"
	attackBtn.Visible = mounted
end

local tickAcc = 0
function HUD.Tick(dt: number)
	tickAcc += dt
	if tickAcc < 0.2 then
		return
	end
	tickAcc = 0
	-- squad HP
	for uid, card in squadCards do
		local ent = EntityRenderer.PetByUid(uid)
		if ent then
			card.fill.Size = UDim2.fromScale(ent.hp, 1)
			card.fill.BackgroundColor3 = if ent.state == Protocol.State.Fainted then K.Muted elseif ent.hp < 0.3 then K.Red else K.Green
		end
	end
	-- boss bar
	local boss = EntityRenderer.NearestBoss(140)
	bossFrame.Visible = boss ~= nil
	if boss then
		bossText.Text = ("👹 %s · Lv %d"):format(boss.name or "Boss", boss.level or 1)
		bossFill.Size = UDim2.fromScale(boss.hp, 1)
	end
	-- wave button: on own plot and no wave running
	local plotIndex = LOCAL:GetAttribute("PlotIndex")
	local w = ClientState.wave
	local onPlot = false
	local character = LOCAL.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if plotIndex and root then
		local l = World.PlotCFrame(plotIndex):PointToObjectSpace(root.Position)
		onPlot = math.abs(l.X) < 60 and math.abs(l.Z) < 60
	end
	waveBtn.Visible = onPlot and (w == nil or w.state ~= "Fighting")
	if w and w.state == "Break" then
		w.breakLeft = math.max(0, w.breakLeft - 0.2)
		HUD.RefreshWave()
	end
end

----------------------------------------------------------------------------
-- Toasts & announcements
----------------------------------------------------------------------------

function HUD.Toast(text: string, style: string?)
	local toast = Kit.new("Frame", {
		Size = UDim2.fromOffset(440, 40),
		BackgroundColor3 = TOAST_COLORS[style or "info"] or TOAST_COLORS.info,
		LayoutOrder = -math.floor(os.clock() * 100),
		Parent = toastList,
	}, { Kit.corner(12), Kit.stroke(3) })
	Kit.label(text, 17, nil, { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), Parent = toast })
	Kit.pop(toast)
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 4 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	task.delay(3.5, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

function HUD.Announce(text: string, style: string?, fromOtherServer: boolean?)
	local color = TOAST_COLORS[style or "info"] or TOAST_COLORS.info
	local banner = Kit.new("Frame", {
		Size = UDim2.fromOffset(640, 64),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		Parent = main,
	}, { Kit.corner(18), Kit.stroke(4) })
	if style == "secret" then
		Kit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 60)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 60, 255)),
			}),
			Parent = banner,
		})
	end
	Kit.label((if fromOtherServer then "🌍 " else "📣 ") .. text, 22, nil, { Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = banner })
	Kit.pop(banner)
	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, -0.2, 0) }):Play()
		task.wait(0.4)
		banner:Destroy()
	end)
end

return HUD
