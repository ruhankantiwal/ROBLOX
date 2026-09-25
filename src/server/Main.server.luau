--[[
	Grow Your Pets: Animal Farm — server bootstrap.

	Services are plain ModuleScripts in ./Services with optional
	:Init(services) and :Start() methods. Init wires references (no yielding),
	Start begins work. A single Heartbeat scheduler drives every fixed-rate
	simulation step, so the whole server has one predictable game loop.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

Net.Setup()

local services = {}
for _, module in script.Parent.Services:GetChildren() do
	if module:IsA("ModuleScript") then
		services[module.Name] = require(module) :: any
	end
end

-- Start order matters: the world must exist before plots, plots before
-- the systems that live on them.
local START_ORDER = {
	"WorldBuilder",
	"AnnounceService",
	"DataService",
	"MonetizationService",
	"EntityService",
	"CombatService",
	"PlotService",
	"PetService",
	"PetAIService",
	"ZombieService",
	"ConveyorService",
	"MutationService",
	"CarryService",
	"FruitService",
	"EggHeistService",
	"MountService",
	"ZoneService",
	"RewardsService",
}

for name, service in services do
	if service.Init then
		service:Init(services)
	end
	if not table.find(START_ORDER, name) then
		warn("[Main] service not in START_ORDER:", name)
	end
end

for _, name in START_ORDER do
	local service = services[name]
	if service and service.Start then
		local ok, err = pcall(service.Start, service)
		if not ok then
			warn(("[Main] %s failed to start: %s"):format(name, tostring(err)))
		end
	end
end

-- Fixed-rate scheduler: { service, method, interval }
local jobs = {
	{ services.PetAIService, "Step", 0.1 },
	{ services.ZombieService, "Step", 0.1 },
	{ services.PlotService, "StepDefenses", 0.1 },
	{ services.EntityService, "Replicate", 0.1 },
	{ services.CarryService, "Step", 0.2 },
	{ services.ConveyorService, "Step", 1 },
	{ services.FruitService, "Step", 1 },
	{ services.MutationService, "Step", 1 },
	{ services.EggHeistService, "Step", 0.5 },
	{ services.ZoneService, "Step", 1.5 },
	{ services.RewardsService, "Step", 5 },
}
local accum = {}
for i in jobs do
	accum[i] = 0
end

RunService.Heartbeat:Connect(function(dt)
	for i, job in jobs do
		accum[i] += dt
		local interval = job[3]
		if accum[i] >= interval then
			local step = accum[i]
			accum[i] = 0
			local service = job[1]
			local ok, err = pcall(service[job[2]], service, math.min(step, interval * 3))
			if not ok then
				warn(("[Main] %s.%s error: %s"):format(tostring(service.Name or "?"), job[2], tostring(err)))
			end
		end
	end
end)

print("[Grow Your Pets] server ready")
