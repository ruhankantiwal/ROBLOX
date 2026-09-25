--[[
	Panels: the modal screens. One open at a time, centred, with a big X.

	  Pets     inventory grid -> detail (equip, alpha, lock, craft, sell,
	           feed a fruit, stats, abilities, mutations)
	  Fruits   your fruits -> pick a pet to feed
	  Lab      Mutation capsules -> pick a pet to apply (Mutagen cost)
	  Shop     VIP, passes, products (odds shown before buying), gems, codes
	  Egg      odds with your luck applied, Hatch x1 / x3 / Auto
	  Dealer   coin roll (hourly) + Robux roll (odds shown)
	  Rebirth, Daily, Quests, Settings
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Eggs = require(Shared.Config.Eggs)
local Fruits = require(Shared.Config.Fruits)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)
local World = require(Shared.Config.World)
local Progression = require(Shared.Config.Progression)
local Monetization = require(Shared.Config.Monetization)
local PetStats = require(Shared.Util.PetStats)
local Rng = require(Shared.Util.Rng)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Kit)
local ClientState = require(script.Parent.Parent.ClientState)
local Cinematics = require(script.Parent.Parent.Controllers.Cinematics)

local LOCAL = Players.LocalPlayer
local K = Kit.Colors

local Panels = { current = nil :: string? }

local root: Frame
local window: Frame
local titleLabel: TextLabel
local body: Frame
local builders = {}
local currentArg = nil
local autoHatch = false

----------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------

function Panels.Start(parent: Instance)
	root = Kit.new("Frame", {
		Name = "Panels",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	local shade = Kit.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Text = "",
		AutoButtonColor = false,
		Parent = root,
	})
	shade.Activated:Connect(Panels.Close)
	window = Kit.panel({
		Size = UDim2.fromOffset(760, 500),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = root,
	})
	titleLabel = Kit.label("", 30, K.Gold, {
		Size = UDim2.new(1, -120, 0, 44),
		Position = UDim2.fromOffset(20, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})
	Kit.button("✖", K.Red, {
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.new(1, -8, 0, -8),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 26,
		Parent = window,
	}, Panels.Close)
	body = Kit.new("Frame", {
		Size = UDim2.new(1, -32, 1, -72),
		Position = UDim2.fromOffset(16, 60),
		BackgroundTransparency = 1,
		Parent = window,
	})

	ClientState.Changed:Connect(function(key)
		if Panels.current and (key == "pets" or key == "equipped" or key == "alpha" or key == "fruits" or key == "capsules" or key == "daily" or key == "quests" or key == "mutagen" or key == "gems" or key == "lastFruitDealer") then
			Panels.Refresh()
		end
	end)
	Net.Event("OpenPanel").OnClientEvent:Connect(function(name, arg)
		Panels.Open(name, arg)
	end)
end

function Panels.Open(name: string, arg: any?)
	if not builders[name] or not ClientState.loaded then
		return
	end
	Panels.current = name
	currentArg = arg
	root.Visible = true
	Kit.pop(window)
	Panels.Refresh()
end

function Panels.Refresh()
	local name = Panels.current
	if not name then
		return
	end
	Kit.clear(body)
	builders[name](body, currentArg)
end

function Panels.Close()
	Panels.current = nil
	autoHatch = false
	root.Visible = false
	Kit.clear(body)
end

function Panels.Toggle(name: string, arg: any?)
	if Panels.current == name then
		Panels.Close()
	else
		Panels.Open(name, arg)
	end
end

local function setTitle(text: string)
	titleLabel.Text = text
end

local function scroll(parent: Instance, size: UDim2, position: UDim2?, grid: Vector2?): ScrollingFrame
	local s = Kit.new("ScrollingFrame", {
		Size = size,
		Position = position or UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = parent,
	})
	if grid then
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(grid.X, grid.Y),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = s,
		})
	else
		Kit.list(Enum.FillDirection.Vertical, 8).Parent = s
	end
	Kit.padding(6).Parent = s
	return s
end

----------------------------------------------------------------------------
-- Pet cards
----------------------------------------------------------------------------

local function sortedPets()
	local d = ClientState.data
	local list = {}
	for uid, pet in d.pets do
		table.insert(list, { uid = uid, pet = pet, stats = PetStats.Compute(pet), equipped = table.find(d.equipped, uid) ~= nil })
	end
	table.sort(list, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		return a.stats.powerScore > b.stats.powerScore
	end)
	return list
end

local function petCard(parent: Instance, entry, onClick: () -> (), order: number)
	local pet = entry.pet
	local def = Pets.Species[pet.species]
	local color = Rarity.Color(def.rarity)
	local card = Kit.new("TextButton", {
		BackgroundColor3 = K.PanelLight,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.corner(12), Kit.stroke(3, color) })
	Kit.label(def.emoji, 40, nil, { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 6), Parent = card })
	Kit.label(def.displayName, 14, nil, { Size = UDim2.new(1, -6, 0, 18), Position = UDim2.fromOffset(3, 54), Parent = card })
	Kit.label(("Lv%d · ⚔%s"):format(pet.level, Format.Short(entry.stats.powerScore)), 13, K.Muted, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 74), Parent = card })
	local badges = ""
	if pet.variant ~= "Normal" then
		badges ..= Pets.Variants[pet.variant].label:sub(1, 4)
	end
	if pet.fruit then
		badges ..= Fruits.List[pet.fruit.id].emoji
	end
	for _, m in pet.mutations do
		badges ..= Mutations.List[m].emoji
	end
	if badges ~= "" then
		Kit.label(badges, 14, nil, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 92), Parent = card })
	end
	if entry.equipped then
		Kit.label("✅", 18, nil, { Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(4, 2), Parent = card })
	end
	if ClientState.data.alpha == entry.uid then
		Kit.label("👑", 18, nil, { Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -26, 0, 2), Parent = card })
	end
	if pet.locked then
		Kit.label("🔒", 16, nil, { Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -24, 1, -24), Parent = card })
	end
	card.Activated:Connect(onClick)
	return card
end

----------------------------------------------------------------------------
-- Pets
----------------------------------------------------------------------------

builders.Pets = function(container: Frame, selectedUid: string?)
	local d = ClientState.data
	local count = 0
	for _ in d.pets do
		count += 1
	end
	setTitle(("🐾 Your Army (%d) · Equipped %d/%d"):format(count, #d.equipped, LOCAL:GetAttribute("EquipSlots") or Pets.BaseEquipSlots))
	local grid = scroll(container, UDim2.new(0.58, 0, 1, -56), nil, Vector2.new(96, 114))
	for i, entry in sortedPets() do
		petCard(grid, entry, function()
			currentArg = entry.uid
			Panels.Refresh()
		end, i)
	end
	Kit.button("⭐ Equip Best", K.Green, { Size = UDim2.new(0.28, 0, 0, 46), Position = UDim2.new(0, 0, 1, -48), Parent = container }, function()
		Net.Event("EquipBest"):FireServer()
	end)

	-- Detail pane
	local pane = Kit.panel({ Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.new(0.6, 0, 0, 0), BackgroundColor3 = K.PanelLight, Parent = container })
	local uid = selectedUid
	local pet = uid and d.pets[uid]
	if not pet then
		Kit.label("Tap a pet to see its powers.", 20, K.Muted, { Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = pane })
		return
	end
	local def = Pets.Species[pet.species]
	local stats = PetStats.Compute(pet)
	local list = scroll(pane, UDim2.new(1, -8, 1, -118), UDim2.fromOffset(4, 4))
	local function line(text: string, color: Color3?, size: number?)
		Kit.label(text, size or 16, color, { Size = UDim2.new(1, -10, 0, (size or 16) + 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = list })
	end
	line(("%s %s"):format(def.emoji, def.displayName), Rarity.Color(def.rarity), 24)
	line(("%s · %s · Lv %d"):format(def.rarity, stats.role, pet.level), K.Muted)
	line(("⚔ Power %s   ❤ HP %s"):format(Format.Short(stats.power), Format.Short(stats.hp)))
	line(("⚡ %.1f hits/s   🏃 %d speed   🎯 %d%% crit"):format(stats.attackRate, math.floor(stats.speed), math.floor(stats.critChance * 100)))
	if pet.fruit then
		local fruit = Fruits.List[pet.fruit.id]
		line(("%s %s · Mastery %d"):format(fruit.emoji, fruit.displayName, pet.fruit.mastery or 0), fruit.color, 18)
		for _, ability in fruit.abilities do
			local unlocked = (pet.fruit.mastery or 0) >= ability.mastery
			line(("%s %s%s"):format(if unlocked then "✅" else "🔒", ability.name, if unlocked then "" else (" (M%d)"):format(ability.mastery)), if unlocked then K.Text else K.Muted, 14)
		end
	else
		line("No Beast Fruit yet. Feed one in 🍉 Fruits!", K.Muted, 14)
	end
	for _, m in pet.mutations do
		local mut = Mutations.List[m]
		line(("%s %s: %s"):format(mut.emoji, mut.displayName, mut.joke), Rarity.Color(mut.rarity), 14)
	end
	line(("Mutation slots: %d/%d"):format(#pet.mutations, PetStats.MutationSlots(pet)), K.Muted, 14)

	local equipped = table.find(d.equipped, uid) ~= nil
	local buttons = Kit.new("Frame", { Size = UDim2.new(1, -10, 0, 104), Position = UDim2.new(0, 5, 1, -108), BackgroundTransparency = 1, Parent = pane })
	Kit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 48), CellPadding = UDim2.fromOffset(8, 8), Parent = buttons })
	Kit.button(if equipped then "Unequip" else "Equip", if equipped then K.Red else K.Green, { TextSize = 18, Parent = buttons }, function()
		Net.Event(if equipped then "UnequipPet" else "EquipPet"):FireServer(uid)
	end)
	Kit.button("👑 Alpha", K.Gold, { TextSize = 18, Parent = buttons }, function()
		Net.Event("SetAlpha"):FireServer(uid)
	end)
	Kit.button(if pet.locked then "🔓 Unlock" else "🔒 Lock", K.Blue, { TextSize = 18, Parent = buttons }, function()
		Net.Event("LockPet"):FireServer(uid)
	end)
	if pet.variant == "Normal" or pet.variant == "Golden" then
		Kit.button(if pet.variant == "Normal" then "🟡 Craft x5" else "🌈 Craft x5", K.Purple, { TextSize = 18, Parent = buttons }, function()
			Net.Event("CraftPet"):FireServer(uid)
		end)
	elseif not pet.locked and not equipped then
		Kit.button("💰 Sell", K.Red, { TextSize = 18, Parent = buttons }, function()
			Net.Event("SellPet"):FireServer({ uid })
			currentArg = nil
		end)
	end
end

----------------------------------------------------------------------------
-- Fruits (feed)
----------------------------------------------------------------------------

builders.Fruits = function(container: Frame, selectedFruit: string?)
	local d = ClientState.data
	setTitle("🍉 Beast Fruits: feed one to a pet to MUTATE it")
	local left = scroll(container, UDim2.new(0.42, 0, 1, 0))
	local any = false
	for _, id in Fruits.Order do
		local count = d.fruits[id] or 0
		local fruit = Fruits.List[id]
		local row = Kit.new("TextButton", {
			Size = UDim2.new(1, -8, 0, 86),
			BackgroundColor3 = if selectedFruit == id then K.Purple else K.PanelLight,
			Text = "",
			AutoButtonColor = count > 0,
			Parent = left,
		}, { Kit.corner(12), Kit.stroke(3, fruit.color) })
		Kit.label(("%s %s  x%d"):format(fruit.emoji, fruit.displayName, count), 20, if count > 0 then K.Text else K.Muted, { Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Kit.label(("%s · %s"):format(Fruits.Categories[fruit.category].label, fruit.rarity), 14, Rarity.Color(fruit.rarity), { Size = UDim2.new(1, -10, 0, 18), Position = UDim2.fromOffset(8, 32), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Kit.label(fruit.tagline, 13, K.Muted, { Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(8, 52), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		if count > 0 then
			any = true
			row.Activated:Connect(function()
				currentArg = id
				Panels.Refresh()
			end)
		end
	end
	local right = Kit.panel({ Size = UDim2.new(0.56, 0, 1, 0), Position = UDim2.new(0.44, 0, 0, 0), BackgroundColor3 = K.PanelLight, Parent = container })
	if not selectedFruit then
		Kit.label(if any then "Pick a fruit on the left." else "No fruits yet! They spawn around the Long Valley, drop from bosses and dungeons, or roll one at the Fruit Dealer.", 18, K.Muted, { Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = right })
		return
	end
	local fruit = Fruits.List[selectedFruit]
	Kit.label(("Feed %s %s to…"):format(fruit.emoji, fruit.displayName), 20, fruit.color, { Size = UDim2.new(1, -10, 0, 28), Position = UDim2.fromOffset(6, 6), Parent = right })
	local grid = scroll(right, UDim2.new(1, -8, 1, -44), UDim2.fromOffset(4, 40), Vector2.new(96, 114))
	for i, entry in sortedPets() do
		petCard(grid, entry, function()
			local ok = Net.Function("FeedFruit"):InvokeServer(entry.uid, selectedFruit)
			if ok then
				Panels.Close()
			end
		end, i)
	end
end

----------------------------------------------------------------------------
-- Mutation Lab
----------------------------------------------------------------------------

builders.Lab = function(container: Frame, selected: string?)
	local d = ClientState.data
	setTitle(("🧪 Mutation Lab · 🧪 %s Mutagen"):format(Format.Short(d.mutagen)))
	local left = scroll(container, UDim2.new(0.42, 0, 1, 0))
	if #d.capsules == 0 then
		Kit.label("No capsules. Build a 🧠 Brainrot Extractor at your base, buy them on the hub Brainrot Belt… or steal them. 👀", 18, K.Muted, { Size = UDim2.new(1, -10, 0, 120), Parent = left })
	end
	for _, capsule in d.capsules do
		local m = Mutations.List[capsule.mutation]
		local row = Kit.new("TextButton", {
			Size = UDim2.new(1, -8, 0, 78),
			BackgroundColor3 = if selected == capsule.id then K.Purple else K.PanelLight,
			Text = "",
			Parent = left,
		}, { Kit.corner(12), Kit.stroke(3, Rarity.Color(m.rarity)) })
		Kit.label(("%s %s"):format(m.emoji, m.displayName), 20, nil, { Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Kit.label(("%s · costs 🧪%s"):format(m.rarity, Format.Short(Mutations.ApplyCost[m.rarity])), 14, Rarity.Color(m.rarity), { Size = UDim2.new(1, -10, 0, 18), Position = UDim2.fromOffset(8, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Kit.label(m.joke, 13, K.Muted, { Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(8, 50), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		row.Activated:Connect(function()
			currentArg = capsule.id
			Panels.Refresh()
		end)
	end
	local right = Kit.panel({ Size = UDim2.new(0.56, 0, 1, 0), Position = UDim2.new(0.44, 0, 0, 0), BackgroundColor3 = K.PanelLight, Parent = container })
	if not selected then
		Kit.label("Pick a capsule, then a pet. A full pet swaps out its oldest mutation.", 18, K.Muted, { Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), Parent = right })
		return
	end
	local grid = scroll(right, UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4), Vector2.new(96, 114))
	for i, entry in sortedPets() do
		petCard(grid, entry, function()
			Net.Event("ApplyMutation"):FireServer(selected, entry.uid)
			Panels.Close()
		end, i)
	end
end

----------------------------------------------------------------------------
-- Shop
----------------------------------------------------------------------------

local function oddsText(odds): string
	local parts = {}
	for _, o in odds do
		local name = if Pets.Species[o.name] then Pets.Species[o.name].displayName else o.name
		table.insert(parts, ("%s %s"):format(name, Format.Percent(o.chance)))
	end
	return table.concat(parts, " · ")
end

builders.Shop = function(container: Frame, _focus)
	setTitle("🛒 Shop")
	local list = scroll(container, UDim2.fromScale(1, 1))
	Kit.label("Loading…", 20, K.Muted, { Parent = list })
	task.spawn(function()
		local info = Net.Function("GetShopInfo"):InvokeServer()
		if Panels.current ~= "Shop" or not list.Parent then
			return
		end
		Kit.clear(list, { "UIListLayout", "UIPadding" })

		-- VIP subscription card
		local vip = Kit.panel({ Size = UDim2.new(1, -12, 0, 150), BackgroundColor3 = Color3.fromRGB(70, 50, 20), Parent = list })
		Kit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(200, 120, 20)), Rotation = 20, Parent = vip })
		Kit.label(("👑 %s"):format(info.subscription.name), 26, Color3.new(1, 1, 1), { Size = UDim2.new(0.65, 0, 0, 34), Position = UDim2.fromOffset(14, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = vip })
		Kit.label(table.concat(info.subscription.perks, " · "), 14, Color3.new(1, 1, 1), { Size = UDim2.new(0.65, 0, 0, 96), Position = UDim2.fromOffset(14, 44), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = vip })
		Kit.button(if info.vip then "✅ Active" elseif info.subscription.configured then ("$%.2f / month"):format(info.subscription.priceUsd) else ("R$%d lifetime"):format(Monetization.GamePasses.VIP.price), K.Green, {
			Size = UDim2.new(0.3, 0, 0, 56),
			Position = UDim2.new(1, -14, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = vip,
		}, function()
			if not info.vip then
				Net.Event("Purchase"):FireServer("subscription", "VIP")
			end
		end)

		local function section(text: string)
			Kit.label(text, 22, K.Gold, { Size = UDim2.new(1, -12, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = list })
		end
		local function item(icon: string, name: string, desc: string, price: string, owned: boolean, onBuy: () -> (), odds)
			local row = Kit.panel({ Size = UDim2.new(1, -12, 0, if odds then 104 else 76), BackgroundColor3 = K.PanelLight, Parent = list })
			Kit.label(icon, 34, nil, { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(8, 10), Parent = row })
			Kit.label(name, 20, nil, { Size = UDim2.new(1, -230, 0, 24), Position = UDim2.fromOffset(70, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
			Kit.label(desc, 13, K.Muted, { Size = UDim2.new(1, -230, 0, 34), Position = UDim2.fromOffset(70, 34), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = row })
			if odds then
				Kit.label("📊 Odds: " .. oddsText(odds), 12, Color3.fromRGB(200, 230, 255), { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 70), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
			end
			Kit.button(if owned then "Owned" else price, if owned then K.Muted else K.Green, { Size = UDim2.fromOffset(140, 50), Position = UDim2.new(1, -12, 0, 12), AnchorPoint = Vector2.new(1, 0), Parent = row }, function()
				if not owned then
					onBuy()
				end
			end)
		end

		section("Game Passes")
		for _, p in info.passes do
			if p.key ~= "VIP" then
				item(p.icon, p.name, p.desc, "R$" .. p.price, p.owned, function()
					Net.Event("Purchase"):FireServer("pass", p.key)
				end)
			end
		end
		section("Boosts & Tickets")
		for _, p in info.products do
			if not p.key:match("^Gems") then
				item(p.icon, p.name, if p.randomItem then "Random reward: odds below." else "", "R$" .. p.price, false, function()
					Net.Event("Purchase"):FireServer("product", p.key)
				end, p.odds)
			end
		end
		section("💎 Gems (skips, vault slots, cosmetics; never random)")
		for _, p in info.products do
			if p.key:match("^Gems") then
				item(p.icon, p.name, "", "R$" .. p.price, false, function()
					Net.Event("Purchase"):FireServer("product", p.key)
				end)
			end
		end
		for key, g in Monetization.GemShop do
			item("💎", g.name, "", ("%d 💎"):format(g.gems), false, function()
				Net.Event("GemPurchase"):FireServer(key)
			end)
		end
		if not info.canBuyRandom then
			Kit.label("Some random items are unavailable in your region.", 14, K.Muted, { Parent = list })
		end

		section("🎟️ Codes")
		local codeRow = Kit.new("Frame", { Size = UDim2.new(1, -12, 0, 56), BackgroundTransparency = 1, Parent = list })
		local box = Kit.new("TextBox", {
			Size = UDim2.new(1, -160, 1, 0),
			BackgroundColor3 = K.PanelLight,
			Font = Kit.Font,
			TextSize = 20,
			TextColor3 = K.Text,
			PlaceholderText = "Enter code (try RELEASE)",
			Text = "",
			ClearTextOnFocus = false,
			Parent = codeRow,
		}, { Kit.corner(12), Kit.stroke(3) })
		Kit.button("Redeem", K.Blue, { Size = UDim2.fromOffset(148, 56), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = codeRow }, function()
			Net.Event("RedeemCode"):FireServer(box.Text)
			box.Text = ""
		end)
	end)
end

----------------------------------------------------------------------------
-- Egg (odds + hatch)
----------------------------------------------------------------------------

local function clientLuck(): number
	if LOCAL:GetAttribute("RandomRestricted") then
		return 1
	end
	local luck = 1
	if LOCAL:GetAttribute("Pass_LuckyHatch") then
		luck *= Monetization.GamePasses.LuckyHatch.luck
	end
	if (workspace:GetAttribute("ServerLuckUntil") or 0) > ClientState.Now() then
		luck *= 2
	end
	return luck
end

local function nearEgg(eggId: string): boolean
	local character = LOCAL.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pos = World.EggStands[eggId]
	return rootPart ~= nil and pos ~= nil and (rootPart.Position - pos).Magnitude < Eggs.HatchRange + 6
end

local function hatch(eggId: string, count: number)
	local result = Net.Function("HatchEgg"):InvokeServer(eggId, count)
	if result and result.ok then
		Cinematics.Hatch(result)
	elseif result and result.err and result.err ~= "cooldown" then
		autoHatch = false
		Panels.Notify(result.err)
	end
	return result
end

builders.Egg = function(container: Frame, eggId: string)
	local egg = Eggs.List[eggId]
	if not egg then
		return
	end
	local luck = clientLuck()
	setTitle(("🥚 %s · 💰%s"):format(egg.displayName, Format.Short(egg.price)))
	local odds = Rng.LuckAdjustedOdds(egg.odds, luck, Eggs.LuckMaxChance)
	local list = scroll(container, UDim2.new(0.6, 0, 1, 0), nil, Vector2.new(130, 120))
	for i, o in odds do
		local def = Pets.Species[o.pet]
		local card = Kit.panel({ BackgroundColor3 = K.PanelLight, LayoutOrder = i, Parent = list })
		card:FindFirstChildOfClass("UIStroke").Color = Rarity.Color(def.rarity)
		Kit.label(def.emoji, 38, nil, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 6), Parent = card })
		Kit.label(def.displayName, 14, nil, { Size = UDim2.new(1, -6, 0, 18), Position = UDim2.fromOffset(3, 52), Parent = card })
		Kit.label(Format.Percent(o.chance), 18, Rarity.Color(def.rarity), { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 74), Parent = card })
		Kit.label(def.rarity, 12, K.Muted, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 98), Parent = card })
	end
	local side = Kit.new("Frame", { Size = UDim2.new(0.37, 0, 1, 0), Position = UDim2.new(0.63, 0, 0, 0), BackgroundTransparency = 1, Parent = container })
	Kit.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center).Parent = side
	Kit.label(("🍀 Luck x%.2g%s"):format(luck, if luck > 1 then " (applied)" else ""), 18, if luck > 1 then K.Green else K.Muted, { Size = UDim2.new(1, 0, 0, 24), Parent = side })
	Kit.label("Shiny chance: 1 in 250 ✨", 14, K.Muted, { Size = UDim2.new(1, 0, 0, 20), Parent = side })
	Kit.button("Hatch x1", K.Green, { Size = UDim2.new(1, 0, 0, 60), TextSize = 24 }, function()
		hatch(eggId, 1)
	end).Parent = side
	local triple = LOCAL:GetAttribute("Pass_TripleHatch") == true
	Kit.button(if triple then "Hatch x3" else "Hatch x3 🔒", if triple then K.Blue else K.Muted, { Size = UDim2.new(1, 0, 0, 60), TextSize = 24 }, function()
		if triple then
			hatch(eggId, 3)
		else
			Panels.Open("Shop")
		end
	end).Parent = side
	local autoBtn
	autoBtn = Kit.button(if autoHatch then "Auto: ON" else "Auto Hatch", if autoHatch then K.Gold else K.Purple, { Size = UDim2.new(1, 0, 0, 60), TextSize = 22 }, function()
		autoHatch = not autoHatch
		autoBtn.Text = if autoHatch then "Auto: ON" else "Auto Hatch"
		autoBtn.BackgroundColor3 = if autoHatch then K.Gold else K.Purple
		if autoHatch then
			task.spawn(function()
				while autoHatch and Panels.current == "Egg" and nearEgg(eggId) do
					hatch(eggId, if triple then 3 else 1)
					task.wait(Eggs.HatchCooldown + 0.2)
				end
				autoHatch = false
			end)
		end
	end)
	autoBtn.Parent = side
end

----------------------------------------------------------------------------
-- Fruit Dealer
----------------------------------------------------------------------------

builders.Dealer = function(container: Frame)
	local d = ClientState.data
	setTitle("🍉 Fruit Dealer")
	local total = 0
	for _, id in Fruits.Order do
		total += Fruits.List[id].spawnWeight
	end
	local list = scroll(container, UDim2.new(0.55, 0, 1, 0))
	Kit.label("Odds (coin roll & world spawns):", 18, K.Gold, { Parent = list })
	for _, id in Fruits.Order do
		local f = Fruits.List[id]
		Kit.label(("%s %s: %s"):format(f.emoji, f.displayName, Format.Percent(f.spawnWeight / total * 100)), 18, f.color, { TextXAlignment = Enum.TextXAlignment.Left, Parent = list })
	end
	local side = Kit.new("Frame", { Size = UDim2.new(0.42, 0, 1, 0), Position = UDim2.new(0.58, 0, 0, 0), BackgroundTransparency = 1, Parent = container })
	Kit.list(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center).Parent = side
	local wait = d.lastFruitDealer + Fruits.DealerCooldown - ClientState.Now()
	local msg = Kit.label(if wait > 0 then "Restocks in " .. Format.Duration(wait) else "Fresh stock!", 18, K.Muted, { Size = UDim2.new(1, 0, 0, 24), Parent = side })
	Kit.button(("Roll 💰%s"):format(Format.Short(Fruits.DealerCost)), K.Green, { Size = UDim2.new(1, 0, 0, 64), TextSize = 24 }, function()
		local r = Net.Function("RollFruit"):InvokeServer("coins")
		if r and r.ok and r.fruit then
			Cinematics.Mutation({ kind = "FruitRoll", id = r.fruit })
		elseif r and r.err then
			msg.Text = r.err
		end
	end).Parent = side
	if not LOCAL:GetAttribute("RandomRestricted") then
		Kit.button(("🎲 Robux Roll R$%d"):format(Monetization.Products.FruitRoll.price), K.Purple, { Size = UDim2.new(1, 0, 0, 64), TextSize = 22 }, function()
			Net.Function("RollFruit"):InvokeServer("robux")
		end).Parent = side
		local rTotal = 0
		for _, id in Fruits.Order do
			rTotal += Fruits.List[id].robuxWeight
		end
		local parts = {}
		for _, id in Fruits.Order do
			table.insert(parts, ("%s %s"):format(Fruits.List[id].emoji, Format.Percent(Fruits.List[id].robuxWeight / rTotal * 100)))
		end
		Kit.label("Robux roll odds: " .. table.concat(parts, "  "), 14, K.Muted, { Size = UDim2.new(1, 0, 0, 40), Parent = side })
	end
end

----------------------------------------------------------------------------
-- Rebirth / Daily / Quests / Settings
----------------------------------------------------------------------------

builders.Rebirth = function(container: Frame)
	local d = ClientState.data
	setTitle("🧬 Evolve Farm")
	local cost = Progression.RebirthCost(d.rebirths)
	local list = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = container })
	Kit.list(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center).Parent = list
	Kit.label(("Rebirths: %d · Coin bonus: +%d%%"):format(d.rebirths, d.rebirths * 25), 24, nil, { Parent = list })
	Kit.label("Evolving resets your coins and conveyor. You KEEP pets, fruits, mutations, defenses and level.", 18, K.Muted, { Size = UDim2.new(1, 0, 0, 50), Parent = list })
	Kit.label("Reward: +25% coins forever. Rebirth 1, 3 and 6 also give +1 pet slot.", 18, K.Green, { Size = UDim2.new(1, 0, 0, 50), Parent = list })
	Kit.button(("Evolve for 💰%s"):format(Format.Short(cost)), if d.coins >= cost then K.Green else K.Muted, { Size = UDim2.fromOffset(320, 70), TextSize = 26, Parent = list }, function()
		Net.Event("Rebirth"):FireServer()
		Panels.Close()
	end)
end

local function rewardText(r): string
	local parts = {}
	if r.coins then
		table.insert(parts, "💰" .. Format.Short(r.coins))
	end
	if r.mutagen then
		table.insert(parts, "🧪" .. r.mutagen)
	end
	if r.gems then
		table.insert(parts, "💎" .. r.gems)
	end
	if r.heistTickets then
		table.insert(parts, "🎟️" .. r.heistTickets)
	end
	if r.fruit then
		table.insert(parts, "🍉 Fruit")
	end
	if r.capsule then
		table.insert(parts, "💊 Capsule")
	end
	return table.concat(parts, " ")
end

builders.Daily = function(container: Frame)
	local d = ClientState.data
	setTitle("🎁 Daily Rewards")
	local row = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 170), BackgroundTransparency = 1, Parent = container })
	Kit.new("UIGridLayout", { CellSize = UDim2.new(1 / 7, -8, 1, 0), CellPadding = UDim2.fromOffset(8, 0), Parent = row })
	local nextDay = d.daily.streak % #Progression.DailyRewards + 1
	for i, r in Progression.DailyRewards do
		local card = Kit.panel({ BackgroundColor3 = if i < nextDay then K.Green elseif i == nextDay then K.Gold else K.PanelLight, Parent = row })
		Kit.label("Day " .. i, 18, nil, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 8), Parent = card })
		Kit.label(rewardText(r), 15, nil, { Size = UDim2.new(1, -8, 0, 100), Position = UDim2.fromOffset(4, 40), Parent = card })
	end
	local today = math.floor(ClientState.Now() / 86400)
	local claimed = d.daily.lastClaim > 0 and math.floor(d.daily.lastClaim / 86400) == today
	Kit.button(if claimed then "Come back tomorrow!" else "CLAIM", if claimed then K.Muted else K.Green, {
		Size = UDim2.fromOffset(320, 70),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 26,
		Parent = container,
	}, function()
		Net.Event("ClaimDaily"):FireServer()
	end)
	Kit.label(("🔥 Streak: %d days"):format(d.daily.streak), 22, K.Gold, { Position = UDim2.fromOffset(0, 190), Parent = container })
end

builders.Quests = function(container: Frame)
	local d = ClientState.data
	setTitle("📜 Daily Quests")
	local list = scroll(container, UDim2.fromScale(1, 1))
	for i, q in d.quests.list do
		local progress = math.min((d.stats[q.stat] or 0) - q.base, q.goal)
		local done = progress >= q.goal
		local claimed = d.quests.claimed[tostring(i)] == true
		local row = Kit.panel({ Size = UDim2.new(1, -12, 0, 96), BackgroundColor3 = K.PanelLight, Parent = list })
		Kit.label(q.text, 22, nil, { Size = UDim2.new(1, -200, 0, 28), Position = UDim2.fromOffset(14, 10), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Kit.label(("%d / %d   ·   %s"):format(progress, q.goal, rewardText(q.reward)), 16, K.Muted, { Size = UDim2.new(1, -200, 0, 22), Position = UDim2.fromOffset(14, 44), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local bar = Kit.new("Frame", { Size = UDim2.new(1, -200, 0, 10), Position = UDim2.fromOffset(14, 72), BackgroundColor3 = K.Panel, Parent = row }, { Kit.corner(5) })
		Kit.new("Frame", { Size = UDim2.fromScale(progress / q.goal, 1), BackgroundColor3 = K.Green, Parent = bar }, { Kit.corner(5) })
		Kit.button(if claimed then "Claimed" elseif done then "Claim" else "…", if claimed then K.Muted elseif done then K.Green else K.Muted, {
			Size = UDim2.fromOffset(160, 56),
			Position = UDim2.new(1, -14, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = row,
		}, function()
			if done and not claimed then
				Net.Event("ClaimQuest"):FireServer(i)
			end
		end)
	end
end

builders.Settings = function(container: Frame)
	local d = ClientState.data
	setTitle("⚙️ Settings")
	local list = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = container })
	Kit.list(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center).Parent = list
	Kit.button("🎬 Clip Mode (hide UI)", K.Pink, { Size = UDim2.fromOffset(360, 64), TextSize = 22, Parent = list }, function()
		Panels.Close()
		Cinematics.ToggleClipMode()
	end)
	Kit.button("📨 Invite Friends (+luck together)", K.Blue, { Size = UDim2.fromOffset(360, 64), TextSize = 20, Parent = list }, function()
		pcall(function()
			game:GetService("SocialService"):PromptGameInvite(LOCAL)
		end)
	end)
	Kit.label(("Auto next wave: %s (walk off your farm to pause)"):format(if d.settings.autoWave then "ON" else "OFF"), 18, K.Muted, { Parent = list })
end

-- Small inline notice used by panels when the server rejects something.
function Panels.Notify(text: string)
	local label = Kit.label(text, 18, K.Red, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, 4), Parent = window })
	task.delay(2.5, function()
		label:Destroy()
	end)
end

return Panels
