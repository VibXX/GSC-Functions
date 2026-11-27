-- Minimal signal (no BindableEvent serialisation, so tables pass by reference).

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handler = { Fn = fn, Connected = true }
	table.insert(self._handlers, handler)
	return {
		Disconnect = function()
			handler.Connected = false
			local index = table.find(self._handlers, handler)
			if index then
				table.remove(self._handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, handler in table.clone(self._handlers) do
		if handler.Connected then
			task.spawn(handler.Fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal
