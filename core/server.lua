local loop = require("core.loop")

local Client = require("core.client")
local Emitter = require("core.emitter")
local socket = require("socket")

---@class Server: Emitter
---@field clients table<Client, boolean>
---@field port number
---@field socket userdata
local Server = {}
Server.__index = Server
setmetatable(Server, Emitter)

--- Creates a new TCP server.
---@return Server TCPserver
function Server:new()
	local server = setmetatable(getmetatable(self):new(), self)
	loop.add(server)

	server.clients = {}

	return server
end

--- Listen to a port.
---@param port number
---@param backlog number?
function Server:listen(port, backlog)
	local sock = assert(socket.bind("0.0.0.0", port, backlog))
	sock:settimeout(0)

	self.socket = sock
	self.port = port
end

--- Closes server socket.
function Server:close()
	assert(self.socket, "No socket"):close()
	self:emit("close")
	self._done = true
end

--- Broadcast messages to every socket.
---@param cb fun(client: Client)
function Server:broadcast(cb)
	for client, _ in pairs(self.clients) do
		cb(client)
	end
end

--- Polls events from the server.
function Server:poll()
	if self._done or not self.socket then return end

	local clientSocket, errorMessage = self.socket:accept()
	if not clientSocket then
		if errorMessage == "closed" then
			self:close()
		elseif errorMessage ~= "timeout" then
			self:emit("error", errorMessage)
			self:close()
		end
	else
		self.clients[clientSocket] = true
		local client = Client:new(clientSocket)
		client:on("close", function()
			self.clients[clientSocket] = nil
		end)
		self:emit("connect", client)
	end
end

return Server

