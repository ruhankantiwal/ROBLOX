--[[
	Every remote in the game, declared in one place. The server creates them
	at boot (Net.Setup); clients wait for them by name.

	Naming: client -> server requests are verbs ("EquipPet"); server ->
	client pushes are nouns/past tense ("DataChanged", "EntitySpawned").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local EVENTS = {
	-- server -> client
	"Init",
	"DataChanged",
	"Notify",
	"Announce",
	"EntitySpawned",
	"EntityRemoved",
	"EntityAppearance",
	"CombatEvents",
	"HatchResult",
	"MutationCinematic",
	"FruitSpawned",
	"FruitDespawned",
	"WaveState",
	"HeistState",
	"MountState",
	"ConveyorState",
	"OpenPanel",
	-- client -> server
	"SquadCommand",
	"EquipPet",
	"UnequipPet",
	"EquipBest",
	"SetAlpha",
	"LockPet",
	"SellPet",
	"CraftPet",
	"ToggleMount",
	"MountAttack",
	"StartWave",
	"LockBase",
	"ApplyMutation",
	"RedeemCode",
	"ClaimDaily",
	"ClaimQuest",
	"Purchase",
	"GemPurchase",
	"Rebirth",
	"AutoHatch",
}

local UNRELIABLE = {
	"EntitySnapshot",
}

local FUNCTIONS = {
	"HatchEgg",
	"FeedFruit",
	"RollFruit",
	"GetShopInfo",
}

local folder: Folder

function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup is server-only")
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in UNRELIABLE do
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in FUNCTIONS do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function getFolder(): Folder
	if not folder then
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder
end

function Net.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.Unreliable(name: string): UnreliableRemoteEvent
	return getFolder():WaitForChild(name) :: UnreliableRemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Net
