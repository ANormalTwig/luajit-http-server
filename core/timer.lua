local socket = require("socket")

local loop = require("core.loop")
local os_difftime, gettime = os.difftime, socket.gettime

local Emitter = require("core.emitter")

---@class Timer: Emitter
---@field looping boolean
---@field startTime number
---@field timeout number
---@field _done boolean
local Timer = {}
Timer.__index = Timer
setmetatable(Timer, Emitter)

--- Creates a new Timer.
---@param timeout number
---@param looping boolean?
---@return Timer
function Timer:new(timeout, looping)
	local timer = setmetatable(getmetatable(self):new(), self)
	loop.add(timer)

	timer.looping = looping and true or false
	timer.timeout = timeout
	timer.startTime = gettime()

	return timer
end

--- Stops the timer from executing again.
function Timer:stop()
	self._done = true
end

function Timer:poll()
	local currentTime = gettime()
	if currentTime - self.startTime > self.timeout then
		self:emit("Timeout")

		if self.looping then
			self.startTime = currentTime
			return
		end

		self._done = true
	end
end

return Timer

