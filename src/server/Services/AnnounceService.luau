--[[
	AnnounceService: toasts for one player, banners for the server, and
	cross-server banners via MessagingService for the moments people clip
	(Secret hatches, Dragon Egg steals, nukes).
]]

local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local TOPIC = "GrowYourPets_Announce"

local AnnounceService = { Name = "AnnounceService" }

local lastGlobal = 0

function AnnounceService:Start()
	if RunService:IsStudio() then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local payload = message.Data
				if type(payload) == "table" and payload.jobId ~= game.JobId then
					Net.Event("Announce"):FireAllClients(payload.text, payload.style, true)
				end
			end)
		end)
		if not ok then
			warn("[AnnounceService] subscribe failed:", err)
		end
	end)
end

-- style: "info" | "good" | "warn" | "error" | "levelup" | "reward"
function AnnounceService:Notify(player: Player, text: string, style: string?)
	Net.Event("Notify"):FireClient(player, text, style or "info")
end

-- Big banner for everyone in this server; optionally every server.
function AnnounceService:Announce(text: string, style: string?, global: boolean?)
	Net.Event("Announce"):FireAllClients(text, style or "info", false)
	if global and not RunService:IsStudio() and os.clock() - lastGlobal > 5 then
		lastGlobal = os.clock()
		task.spawn(function()
			pcall(function()
				MessagingService:PublishAsync(TOPIC, { text = text, style = style, jobId = game.JobId })
			end)
		end)
	end
end

return AnnounceService
