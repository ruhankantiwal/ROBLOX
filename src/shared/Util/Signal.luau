--[[
	Minimal synchronous signal for service-to-service events.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	table.insert(handlers, fn)
	return {
		Disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, fn in table.clone(self._handlers) do
		task.spawn(fn, ...)
	end
end

return Signal
