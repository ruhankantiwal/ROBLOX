--[[
	ClientState: the client's mirror of its own profile, fed by the Init
	and DataChanged remotes. UI subscribes with ClientState.Changed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local ClientState = {
	data = nil :: any,
	loaded = false,
	Changed = Signal.new(), -- (key, value)
	Loaded = Signal.new(),
	serverTimeOffset = 0,
	wave = nil :: any,
	heist = nil :: any,
}

function ClientState.Start()
	Net.Event("Init").OnClientEvent:Connect(function(snapshot)
		ClientState.data = snapshot
		ClientState.serverTimeOffset = snapshot.serverTime - os.time()
		ClientState.loaded = true
		ClientState.Loaded:Fire(snapshot)
	end)
	Net.Event("DataChanged").OnClientEvent:Connect(function(key, a, b)
		local d = ClientState.data
		if not d then
			return
		end
		if key == "pet" then
			d.pets[a] = b
			ClientState.Changed:Fire("pets", d.pets)
		else
			d[key] = a
			ClientState.Changed:Fire(key, a)
		end
	end)
	Net.Event("WaveState").OnClientEvent:Connect(function(state)
		ClientState.wave = state
		ClientState.Changed:Fire("wave", state)
	end)
	Net.Event("HeistState").OnClientEvent:Connect(function(state)
		ClientState.heist = state
		ClientState.Changed:Fire("heist", state)
	end)
end

function ClientState.Now(): number
	return os.time() + ClientState.serverTimeOffset
end

return ClientState
