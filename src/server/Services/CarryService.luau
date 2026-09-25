--[[
	CarryService: "steal it and run" for both stolen Mutation Capsules and
	heist eggs.

	While carrying, the loot floats over your head with a big red label so
	everyone can see you, you move slower (unless mounted), and:
	  * the victim's pets hunt you (PetAIService -> Catch)
	  * heist guardians chase you (ZombieService)
	  * any hit from a zombie/guardian makes you drop it
	  * dying, leaving or timing out drops it
	Reach the delivery point (your base) and it's yours.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local StudStyle = require(Shared.Art.StudStyle)
local Protocol = require(Shared.Util.EntityProtocol)

local EV = Protocol.Event

local CarryService = { Name = "CarryService" }

local S
local carrying: { [Player]: any } = {}

function CarryService:Init(services)
	S = services
end

function CarryService:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:Drop(player, "left")
	end)
	Players.PlayerAdded:Connect(function(player)
		self:WatchDeaths(player)
	end)
	for _, player in Players:GetPlayers() do
		self:WatchDeaths(player)
	end
end

function CarryService:WatchDeaths(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				self:Drop(player, "died")
			end)
		end
	end)
end

function CarryService:IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function CarryService:Get(player: Player)
	return carrying[player]
end

--[[
	opts = {
		kind, label, victim?, speedMult, timeout,
		visual(parent, cf) -> Model,
		deliverCheck() -> boolean,
		onDeliver(), onDrop(reason),
		pursuers = encounter?  (heist)
	}
]]
function CarryService:StartCarry(player: Player, opts): boolean
	if carrying[player] then
		return false
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return false
	end
	local folder = Instance.new("Model")
	folder.Name = "CarriedLoot"
	local model = opts.visual(folder, head.CFrame * CFrame.new(0, 3.5, 0))
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = p
			weld.Part1 = head
			weld.Parent = p
		end
	end
	local primary = model.PrimaryPart
	if primary then
		local label = StudStyle.Label(primary, opts.label, Color3.fromRGB(255, 90, 90), 400, 1.1)
		label.AlwaysOnTop = true
	end
	folder.Parent = character

	carrying[player] = {
		opts = opts,
		visual = folder,
		startedAt = os.clock(),
	}
	player:SetAttribute("Carrying", opts.kind)
	S.MountService:RefreshSpeed(player)
	S.AnnounceService:Notify(player, "RUN! Get it back to your base!", "warn")
	return true
end

function CarryService:Step(_dt: number)
	local now = os.clock()
	for player, c in carrying do
		if not player.Parent or not player.Character then
			self:Drop(player, "left")
		elseif c.opts.deliverCheck() then
			self:Deliver(player)
		elseif now - c.startedAt > (c.opts.timeout or 120) then
			self:Drop(player, "timeout")
		end
	end
end

function CarryService:Finish(player: Player)
	local c = carrying[player]
	if not c then
		return nil
	end
	carrying[player] = nil
	if c.visual then
		c.visual:Destroy()
	end
	player:SetAttribute("Carrying", nil)
	S.MountService:RefreshSpeed(player)
	return c
end

function CarryService:Deliver(player: Player)
	local c = self:Finish(player)
	if c then
		c.opts.onDeliver()
		S.AnnounceService:Notify(player, "✅ Delivered!", "reward")
	end
end

function CarryService:Drop(player: Player, reason: string)
	local c = self:Finish(player)
	if not c then
		return
	end
	c.opts.onDrop(reason)
	if player.Parent then
		local text = if reason == "caught" then "You got caught! Loot returned."
			elseif reason == "hit" then "You got hit and dropped it!"
			elseif reason == "timeout" then "Too slow! The loot vanished back home."
			else "You dropped the loot!"
		S.AnnounceService:Notify(player, text, "error")
	end
end

-- Zombies / guardians hitting a carrier make them drop the loot.
function CarryService:OnCarrierHit(player: Player, _source)
	if carrying[player] then
		self:Drop(player, "hit")
	end
end

-- Victim's pet reached the thief.
function CarryService:Catch(thief: Player, victim: Player, pet)
	local c = carrying[thief]
	if not c or c.opts.victim ~= victim then
		return
	end
	S.EntityService:Event(pet.pos, { EV.Text, pet.id, "CAUGHT YOU!", "#FF5050" })
	self:Drop(thief, "caught")
end

-- Everyone currently carrying loot stolen from `victim`.
function CarryService:ThievesFrom(victim: Player)
	local list = {}
	for player, c in carrying do
		if c.opts.victim == victim then
			local root = S.EntityService:RootOf(player)
			if root then
				table.insert(list, { player = player, pos = root.Position })
			end
		end
	end
	return list
end

return CarryService
