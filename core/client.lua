local loop = require("core.loop")

local Emitter = require("core.emitter")
local socket = require("socket")

---@class Client: Emitter
---@field closed boolean
---@field socket userdata
local Client = {}
Client.__index = Client
setmetatable(Client, Emitter)

--- Create a new TCP client.
---@return Client TCPclient.
---@param sock userdata? Socket to use instead of creating a new one.
function Client:new(sock)
	local client = setmetatable(getmetatable(self):new(), self)
	loop.add(client)

	if sock then
		sock:settimeout(0)
		client.socket = sock
	end

	return client
end

--- Connects the client to a TCP server.
---@param ip string
---@param port number
function Client:connect(ip, port)
	if self.socket then return end

	local sock = assert(socket.connect(ip, port))
	sock:settimeout(0)
	self.socket = sock
end

--- Get IP address, port, and family of the connection peer.
---@return string ip, number port, string family
function Client:getPeerName()
	return self.socket:getpeername()
end

--- Send data over the socket.
---@param str string data
---@param i number?
---@param j number?
function Client:send(str, i, j)
	self.socket:settimeout(-1)
	self.socket:send(str, i, j)
	self.socket:settimeout(0)
end

--- Closes client socket.
function Client:close()
	assert(self.socket, "No socket"):close()
	self.closed = true
	self:emit("close")

	self._done = true
end

--- Polls events from the client.
function Client:poll()
	if not self.socket then return end

	local data = {}
	while true do
		local chunk, errorMessage, partial = self.socket:receive(2048)
		if chunk or partial and #partial > 0 then
			table.insert(data, chunk or partial)
		else
			if errorMessage == "timeout" then
				if #data > 0 then
					self:emit("data", table.concat(data, ""))
				end
			elseif errorMessage == "closed" then
				self:close()
			else
				self:emit("error", errorMessage)
				self:close()
			end

			break
		end
	end
end

return Client

