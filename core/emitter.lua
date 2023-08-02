---@class Emitter
---@field listeners table
local Emitter = {}
Emitter.__index = Emitter

--- Create a new Emitter object.
---@return Emitter
function Emitter:new()
	return setmetatable({listeners = {}}, self)
end

--- Add a new event listener.
---@param name string Event name
---@param cb function Callback
---@return number index
function Emitter:on(name, cb)
	name = name:lower()
	if not self.listeners[name] then
		self.listeners[name] = {}
	end

	local index = #self.listeners + 1
	table.insert(self.listeners[name], cb)
	return index
end

--- Add a new event listener that only triggers once.
---@param name string Event name
---@param cb function Callback
---@return number index
function Emitter:once(name, cb)
	name = name:lower()
	if not self.listeners[name] then
		self.listeners[name] = {}
	end

	local index = #self.listeners + 1
	table.insert(self.listeners[name], function(...)
		table.remove(self.listeners[name], index)
		cb(...)
	end)
	return index
end

--- Remove an event callback.
---@param name string Event name
---@param index number Callback index
function Emitter:removeListener(name, index)
	name = name:lower()
	if not self.listeners[name] then return end
	table.remove(self.listeners[name], index)
end

--- Emit an event.
---@param name string
---@vararg any
function Emitter:emit(name, ...)
	name = name:lower()
	if not self.listeners[name] then return end
	for _, cb in ipairs(self.listeners[name]) do
		cb(...)
	end
end

return Emitter

