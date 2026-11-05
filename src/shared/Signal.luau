-- Signal
-- A simple event for passing data between scripts on the same side
-- (server to server, or client to client).
--
-- Use this instead of BindableEvent when passing tables: BindableEvents hand
-- listeners a COPY of any table, so changes to the original are never seen.
--
--   local changed = Signal.new()
--   local connection = changed:Connect(function(a, b) ... end)
--   changed:Fire(a, b)
--   connection:Disconnect()

export type Connection = { Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(callback: (...any) -> ())
	local handler = { callback = callback, connected = true }
	table.insert(self._handlers, handler)
	local handlers = self._handlers
	return {
		Disconnect = function()
			handler.connected = false
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

-- Calls every listener right away (each in its own thread, so one listener
-- erroring or yielding can't break the others or the caller).
function Signal:Fire(...: any)
	for _, handler in table.clone(self._handlers) do
		if handler.connected then
			task.spawn(handler.callback, ...)
		end
	end
end

return Signal
