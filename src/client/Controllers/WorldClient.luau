--[[
	WorldClient: client-side world logic.
	  * prompt filtering (owner-only / visitor-only prompts)
	  * client-handled prompts (eggs, dealer, lab, rebirth -> panels)
	  * zone gates open locally once you hit the level
	  * conveyor goo sliding along every nearby base's belt (pure visuals)
	  * Fruit Notifier beams + distance markers
	  * waypoint home while carrying stolen loot
	  * tap/click a zombie to focus-fire your whole army on it
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local Base = require(Shared.Config.Base)
local Fruits = require(Shared.Config.Fruits)

local ClientState = require(script.Parent.Parent.ClientState)
local Panels = require(script.Parent.Parent.UI.Panels)
local HUD = require(script.Parent.Parent.UI.HUD)
local EntityRenderer = require(script.Parent.EntityRenderer)
local MountController = require(script.Parent.MountController)
local FX = require(script.Parent.FX)

local LOCAL = Players.LocalPlayer

local WorldClient = {}

local fxFolder: Folder
local beams: { [string]: any } = {}
local homeMarker: BillboardGui? = nil

----------------------------------------------------------------------------
-- Prompts
----------------------------------------------------------------------------

-- Hides prompts by zeroing their activation distance locally, so the
-- server stays free to toggle Enabled (e.g. a maxed-out build pad).
local baseDistance: { [ProximityPrompt]: number } = {}

local function applyPromptRule(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local base = baseDistance[prompt]
	if not base then
		base = prompt.MaxActivationDistance
		baseDistance[prompt] = base
		prompt.Destroying:Connect(function()
			baseDistance[prompt] = nil
		end)
	end
	local owner = prompt:GetAttribute("OwnerUserId")
	local visible = true
	if CollectionService:HasTag(prompt, "OwnerOnlyPrompt") then
		visible = owner == LOCAL.UserId
	elseif CollectionService:HasTag(prompt, "VisitorPrompt") then
		visible = owner ~= LOCAL.UserId
	end
	prompt.MaxActivationDistance = if visible then base else 0
end

local function watchTag(tag: string)
	local function hook(inst: Instance)
		applyPromptRule(inst)
		inst:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			applyPromptRule(inst)
		end)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
	for _, inst in CollectionService:GetTagged(tag) do
		hook(inst)
	end
end

----------------------------------------------------------------------------
-- Zone gates
----------------------------------------------------------------------------

local function refreshGates()
	local level = if ClientState.data then ClientState.data.level else 1
	for _, gate in CollectionService:GetTagged("ZoneGate") do
		if gate:IsA("BasePart") then
			local open = level >= (gate:GetAttribute("LevelReq") or 1)
			gate.CanCollide = not open
			gate.Transparency = if open then 0.93 else 0.7
		end
	end
end

----------------------------------------------------------------------------
-- Conveyor goo (visual only)
----------------------------------------------------------------------------

local GOO_COLORS = {
	Color3.fromRGB(120, 220, 255),
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(255, 220, 80),
	Color3.fromRGB(255, 140, 60),
	Color3.fromRGB(230, 100, 255),
	Color3.fromRGB(255, 80, 130),
}
local conveyorTimers: { [string]: number } = {}

local function stepConveyors()
	local camera = workspace.CurrentCamera
	local camPos = camera.CFrame.Position
	local info = ReplicatedStorage:FindFirstChild("PlotInfo")
	if not info then
		return
	end
	local now = os.clock()
	local q = FX.Quality()
	for _, plotInfo in info:GetChildren() do
		local levels = plotInfo:GetAttribute("Droppers")
		local index = plotInfo:GetAttribute("Index")
		if levels and index then
			local cf = World.PlotCFrame(index)
			if (cf.Position - camPos).Magnitude < 220 then
				local speed = plotInfo:GetAttribute("BeltSpeed") or 1
				local i = 0
				for lvl in string.gmatch(levels, "[^,]+") do
					i += 1
					local level = tonumber(lvl) or 0
					local def = Base.Conveyor.droppers[i]
					local key = index .. ":" .. i
					if level > 0 and def and now >= (conveyorTimers[key] or 0) then
						conveyorTimers[key] = now + Base.Conveyor.dropInterval / speed / q
						local startLocal = Vector3.new(Base.Conveyor.start.X, 1.8, def.offset.Z)
						local finishLocal = Vector3.new(Base.Conveyor.finish.X, 1.8, Base.Conveyor.finish.Z)
						local s = 0.8 + math.min(level, 10) * 0.05
						local goo = Instance.new("Part")
						goo.Anchored = true
						goo.CanCollide = false
						goo.CanQuery = false
						goo.CanTouch = false
						goo.CastShadow = false
						goo.Material = Enum.Material.Neon
						goo.Color = GOO_COLORS[i]
						goo.Size = Vector3.new(s, s, s)
						goo.CFrame = cf * CFrame.new(startLocal + Vector3.new(0, 4, 0))
						goo.Parent = fxFolder
						local distance = (finishLocal - startLocal).Magnitude
						local travel = distance / (7 * speed)
						TweenService:Create(goo, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), { CFrame = cf * CFrame.new(startLocal) }):Play()
						task.delay(0.35, function()
							TweenService:Create(goo, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = cf * CFrame.new(finishLocal) }):Play()
							task.delay(travel, function()
								goo:Destroy()
							end)
						end)
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------------
-- Fruit Notifier
----------------------------------------------------------------------------

local function addBeam(id: string, fruitId: string, pos: Vector3, hidden: boolean)
	local fruit = Fruits.List[fruitId]
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = fruit.color
	beam.Transparency = 0.45
	beam.Size = Vector3.new(1.4, 300, 1.4)
	beam.Position = pos + Vector3.new(0, 150, 0)
	beam.Parent = fxFolder
	local marker = Instance.new("BillboardGui")
	marker.Size = UDim2.fromOffset(220, 50)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.StudsOffsetWorldSpace = Vector3.new(0, -140, 0)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = fruit.color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = marker
	marker.Parent = beam
	beams[id] = { part = beam, label = label, pos = pos, name = fruit.emoji .. " " .. fruit.displayName .. (if hidden then " (hidden!)" else "") }
	HUD.Toast(("🔔 %s %s spawned!"):format(fruit.emoji, fruit.displayName), "reward")
end

local function removeBeam(id: string)
	local b = beams[id]
	if b then
		b.part:Destroy()
		beams[id] = nil
	end
end

----------------------------------------------------------------------------
-- Waypoint home while carrying loot
----------------------------------------------------------------------------

local function refreshHome()
	local carrying = LOCAL:GetAttribute("Carrying")
	local plotIndex = LOCAL:GetAttribute("PlotIndex")
	if homeMarker then
		local oldAnchor = homeMarker.Parent
		if oldAnchor then
			oldAnchor:Destroy()
		end
		homeMarker = nil
	end
	if not carrying or not plotIndex then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	local target = if carrying == "Egg" then Base.IncubatorOffset else Vector3.zero
	anchor.CFrame = World.PlotCFrame(plotIndex) * CFrame.new(target + Vector3.new(0, 8, 0))
	anchor.Parent = fxFolder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 60)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "T"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 255, 140)
	label.Text = "🏠 HOME"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	homeMarker = gui
end

----------------------------------------------------------------------------
-- Start
----------------------------------------------------------------------------

function WorldClient.Start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "WorldClientFX"
	fxFolder.Parent = workspace

	watchTag("OwnerOnlyPrompt")
	watchTag("VisitorPrompt")

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if CollectionService:HasTag(prompt, "EggPrompt") then
			Panels.Open("Egg", prompt:GetAttribute("EggId"))
		elseif CollectionService:HasTag(prompt, "DealerPrompt") then
			Panels.Open("Dealer")
		elseif CollectionService:HasTag(prompt, "LabPrompt") then
			Panels.Open("Lab")
		elseif CollectionService:HasTag(prompt, "RebirthPrompt") then
			Panels.Open("Rebirth")
		end
	end)

	CollectionService:GetInstanceAddedSignal("ZoneGate"):Connect(refreshGates)
	ClientState.Loaded:Connect(refreshGates)
	ClientState.Changed:Connect(function(key)
		if key == "level" then
			refreshGates()
		end
	end)

	Net.Event("FruitSpawned").OnClientEvent:Connect(addBeam)
	Net.Event("FruitDespawned").OnClientEvent:Connect(removeBeam)

	LOCAL:GetAttributeChangedSignal("Carrying"):Connect(refreshHome)

	-- Tap / click a zombie: the whole army focuses it.
	local function tryFocus(screenPos: Vector2)
		if MountController.mounted then
			return
		end
		local zombie = EntityRenderer.PickZombie(screenPos, 60)
		if zombie then
			Net.Event("SquadCommand"):FireServer("Attack", zombie.id)
			HUD.SetSquadMode("Attack", true)
			FX.Ring(zombie.pos, 5, Color3.fromRGB(255, 80, 80), 0.5)
			FX.Text(zombie.pos + Vector3.new(0, 6, 0), "🎯 FOCUS!", Color3.fromRGB(255, 90, 90), true)
		end
	end
	UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
		if not processedByUI then
			tryFocus(position)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			local p = UserInputService:GetMouseLocation()
			tryFocus(Vector2.new(p.X, p.Y))
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		stepConveyors()
		local character = LOCAL.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			for _, b in beams do
				b.label.Text = ("%s · %dm"):format(b.name, math.floor((b.pos - root.Position).Magnitude))
			end
			if homeMarker then
				local text = homeMarker:FindFirstChild("T") :: TextLabel?
				if text and homeMarker.Parent then
					local anchor = homeMarker.Parent :: BasePart
					text.Text = ("🏠 HOME · %dm"):format(math.floor((anchor.Position - root.Position).Magnitude))
				end
			end
		end
	end)
end

return WorldClient
