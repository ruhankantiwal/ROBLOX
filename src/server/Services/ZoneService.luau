--[[
	ZoneService: level-gated zones of the Long Valley.

	Gates are physical barriers built by WorldBuilder. The client turns
	collision off locally for gates the player has unlocked; the server
	double-checks positions so exploiters can't skip ahead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)

local ZoneService = { Name = "ZoneService" }

local S
local lastZone: { [Player]: string } = {}

function ZoneService:Init(services)
	S = services
end

function ZoneService:Start()
	Players.PlayerRemoving:Connect(function(player)
		lastZone[player] = nil
	end)
end

function ZoneService:Step(_dt: number)
	for _, player in Players:GetPlayers() do
		local d = S.DataService:Get(player)
		local root = S.EntityService:RootOf(player)
		if d and root and root.Position.Y > -100 then
			local zone = World.ZoneAt(root.Position.Z)
			if zone.levelReq > d.level then
				local backZ = zone.zStart - 12
				local x = World.CenterX(backZ)
				local character = root.Parent :: Model
				character:PivotTo(CFrame.new(x, World.GroundHeight(x, backZ) + 5, backZ))
				S.AnnounceService:Notify(player, ("🔒 %s unlocks at Lv %d"):format(zone.name, zone.levelReq), "warn")
			elseif lastZone[player] ~= zone.id then
				if lastZone[player] ~= nil then
					S.AnnounceService:Notify(player, ("📍 %s"):format(zone.name), "zone")
				end
				lastZone[player] = zone.id
				player:SetAttribute("Zone", zone.id)
			end
		end
	end
end

return ZoneService
