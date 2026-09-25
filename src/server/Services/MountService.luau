--[[
	MountService: ride your Alpha pet.

	The mount is a normal pet entity flagged `mounted`. PetAIService glues it
	under the player every tick; clients draw it under the character and
	play the sit pose. The player's Humanoid does the moving, so riding
	uses Roblox's own responsive character controller (great on mobile).

	Mounted combat: MountAttack(aimDirection) swings a cone in front of the
	mount using the pet's power and fruit on-hit effects.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Fruits = require(Shared.Config.Fruits)
local BlockyBuilder = require(Shared.Art.BlockyBuilder)
local Protocol = require(Shared.Util.EntityProtocol)

local BASE_WALK = 18
local CARRY_ON_FOOT = 0.8

local MountService = { Name = "MountService" }

local S
local mounts: { [Player]: any } = {}
local heightCache: { [string]: number } = {}

function MountService:Init(services)
	S = services
end

function MountService:Start()
	Net.Event("ToggleMount").OnServerEvent:Connect(function(player)
		if mounts[player] then
			self:Dismount(player)
		else
			self:Mount(player)
		end
	end)
	Net.Event("MountAttack").OnServerEvent:Connect(function(player, aim)
		if typeof(aim) == "Vector3" then
			self:Attack(player, aim)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		mounts[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			mounts[player] = nil
			Net.Event("MountState"):FireAllClients(player.UserId, nil)
			task.defer(self.RefreshSpeed, self, player)
		end)
	end)
end

function MountService:IsMounted(player: Player): boolean
	return mounts[player] ~= nil
end

-- Height of the pet's back, so the rider sits on top of it.
function MountService:RigHeight(entity): number
	local a = entity.appearance
	local key = ("%s:%s:%.2f"):format(a.species, tostring(a.fruit), a.scale or 1)
	local cached = heightCache[key]
	if cached then
		return cached
	end
	local body = Pets.Species[a.species].body
	local rig = BlockyBuilder.Build(body, { scale = a.scale, fruit = a.fruit })
	local back = rig.height * 0.72
	heightCache[key] = back
	return back
end

function MountService:Mount(player: Player)
	local d = S.DataService:Get(player)
	local squad = S.PetService:GetSquad(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not d or not squad or not humanoid or humanoid.Health <= 0 then
		return
	end
	local alpha = d.alpha and squad.pets[d.alpha]
	if not alpha then
		S.AnnounceService:Notify(player, "Equip a pet and set it as Alpha to ride it!", "warn")
		return
	end
	if alpha.fainted then
		S.AnnounceService:Notify(player, "Your Alpha is recovering!", "warn")
		return
	end
	local height = self:RigHeight(alpha)
	mounts[player] = { pet = alpha, baseHip = humanoid.HipHeight, height = height, nextAttack = 0 }
	alpha.mounted = true
	alpha.target = nil
	humanoid.HipHeight = mounts[player].baseHip + height
	self:RefreshSpeed(player)
	Net.Event("MountState"):FireAllClients(player.UserId, { entityId = alpha.id, height = height })
end

function MountService:Dismount(player: Player)
	local m = mounts[player]
	if not m then
		return
	end
	mounts[player] = nil
	m.pet.mounted = false
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HipHeight = m.baseHip
	end
	self:RefreshSpeed(player)
	Net.Event("MountState"):FireAllClients(player.UserId, nil)
end

-- One place decides WalkSpeed: mount, pass, carrying loot.
function MountService:RefreshSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local m = mounts[player]
	local carry = S.CarryService:Get(player)
	local speed = BASE_WALK
	local jump = 50
	if m then
		speed = 28 + m.pet.stats.speed * 0.6
		if S.MonetizationService:HasPass(player, "MountBoost") then
			speed *= 1.3
		end
		jump = 65
		if carry then
			speed *= math.max(carry.opts.speedMult or 1, 0.9)
		end
	elseif carry then
		speed *= carry.opts.speedMult or CARRY_ON_FOOT
	end
	humanoid.WalkSpeed = speed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = jump
end

function MountService:Attack(player: Player, aim: Vector3)
	local m = mounts[player]
	local root = S.EntityService:RootOf(player)
	if not m or not root then
		return
	end
	local now = os.clock()
	local pet = m.pet
	if now < m.nextAttack or pet.fainted then
		return
	end
	m.nextAttack = now + 1 / math.max(pet.stats.attackRate, 0.5)
	local dir = Vector3.new(aim.X, 0, aim.Z)
	if dir.Magnitude < 1e-3 then
		dir = root.CFrame.LookVector
	end
	local fruit = pet.fruitId and Fruits.List[pet.fruitId]
	local fx = if fruit then fruit.element else "Slash"
	local origin = Vector3.new(root.Position.X, pet.pos.Y, root.Position.Z)
	local range = pet.stats.range + 9
	for _, z in S.ZombieService:Query(origin, range, player.UserId) do
		local to = Vector3.new(z.pos.X - origin.X, 0, z.pos.Z - origin.Z)
		if to.Magnitude < 3 or to.Unit:Dot(dir.Unit) > 0.5 then
			S.CombatService:PetBasicHit(pet, z, pet.stats.power * 1.3, fx)
		end
	end
	S.EntityService:Event(origin, { Protocol.Event.Ability, pet.id, "Mount_" .. fx, origin.X, origin.Z, range, dir.Unit.X, dir.Unit.Z })
end

return MountService
