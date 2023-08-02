local Server = require("core.server")
local Timer = require("core.timer")

local string_format, string_gmatch, string_gsub, string_match, string_sub = string.format, string.gmatch, string.gsub, string.match, string.sub
local table_concat, table_insert, table_remove = table.concat, table.insert, table.remove

---@enum statusCodes
local statusCodes = {
	[100] = "Continue",
	[101] = "Switching Protocols",
	[102] = "Processing",
	[103] = "Early Hints",
	[200] = "OK",
	[201] = "Created",
	[202] = "Accepted",
	[203] = "Non-Authoritative Information",
	[204] = "No Content",
	[205] = "Reset Content",
	[206] = "Partial Content",
	[207] = "Multi-Status",
	[208] = "Already Reported",
	[226] = "IM Used",
	[300] = "Multiple Choices",
	[301] = "Moved Permanently",
	[302] = "Found",
	[303] = "See Other",
	[304] = "Not Modified",
	[305] = "Use Proxy",
	[307] = "Temporary Redirect",
	[308] = "Permanent Redirect",
	[400] = "Bad Request",
	[401] = "Unauthorized",
	[402] = "Payment Requred",
	[403] = "Forbidden",
	[404] = "Not Found",
	[405] = "Method Not Allowed",
	[406] = "Not Acceptable",
	[407] = "Proxy Authentication Required",
	[408] = "Request Timeout",
	[409] = "Conflict",
	[410] = "Gone",
	[411] = "Length Required",
	[412] = "Precondition Failed",
	[413] = "Payload Too Large",
	[414] = "URI Too Long",
	[415] = "Unsupported Media Type",
	[416] = "Range Not Satisfiable",
	[417] = "Expectation Failed",
	[418] = "I'm a Teapot",
	[421] = "Misdirected Request",
	[422] = "Unprocessable Entity",
	[423] = "Locked",
	[424] = "Failed Dependency",
	[425] = "Too Early",
	[426] = "Upgrade Required",
	[428] = "Precondition Required",
	[429] = "Too Many Requests",
	[431] = "Request Header Fields Too Large",
	[451] = "Unavailable For Legal Reasons",
	[500] = "Internal Server Error",
	[501] = "Not Implemented",
	[502] = "Bad Gateway",
	[503] = "Service Unavailable",
	[504] = "Gateway Timeout",
	[505] = "HTTP Version Not Supported",
	[506] = "Variant Also Negotiates",
	[507] = "Insufficient Storage",
	[508] = "Loop Detected",
	[509] = "Bandwidth Limit Exceeded",
	[510] = "Not Extended",
	[511] = "Network Authentication Required",
}

---@enum httpMethods
local httpMethods = {
	["CONNECT"] = true,
	["DELETE"] = true,
	["GET"] = true,
	["HEAD"] = true,
	["OPTIONS"] = true,
	["POST"] = true,
	["PUT"] = true,
	["TRACE"] = true,
}

---@class HTTPRequest
---@field client Client
---@field method string
---@field path string
---@field rawpath string
---@field version string
---@field headers table<string, string[]>
local HTTPRequest = {}
HTTPRequest.__index = HTTPRequest

--- Create new HTTPRequest object
---@param client Client
---@param data string
---@return HTTPRequest | nil object or nil if it failed to parse the request.
function HTTPRequest:new(client, data)
	local head = string_match(data, "^(.-)\r\n")
	if not head then return client:close() end

	local info = {}
	for s in string_gmatch(head, "%S+") do
		table_insert(info, s)
	end

	local headers = {}
	for s in string_gmatch(string_sub(data, #head + 3), "([^\r\n]+)\r?\n") do
		local name, value = string_match(s, "([%w-_]+): ([%w_ :;.,\\/\"'?!(){}%[%]@<>=-+*#$&`|~^%%]+)")
		if not name or not value then goto continue end

		if not headers[name] then
			headers[name] = {}
		end
		table_insert(headers[name], value)

		::continue::
	end

	local method = info[1]
	if not httpMethods[method] then
		client:send("HTTP/1.1 405 Method Not Allowed\r\n\r\n")
		client:close()
		return
	end

	local rawpath = info[2]
	local pathArray = {}
	for s in string_gmatch(string_gsub(rawpath, "\\", "/"), "[^/]+") do
		if s == "." then
			goto continue
		end

		if s == ".." then
			table_remove(pathArray)
			goto continue
		end

		table_insert(pathArray, s)

		::continue::
	end

	return setmetatable({
		client = client,
		method = method,
		path = table_concat(pathArray, "/"),
		rawpath = rawpath,
		version = info[3],
		headers = headers,
		ip = client:getPeerName(),
	}, self)
end

---@class HTTPResponse
---@field client Client
---@field status number
---@field headers string[]
---@field sentHeaders boolean
---@field parts string[]
local HTTPResponse = {}
HTTPResponse.__index = HTTPResponse

function HTTPResponse:new(client)
	return setmetatable({
		client = client,
		status = 200,
		headers = {},
		sentHeaders = false,
		parts = {},
	}, self)
end

function HTTPResponse:setStatus(n)
	assert(not self.sentHeaders, "Cannot set status after headers have been sent.")
	assert(statusCodes[n], "Invalid status code.")
	self.status = n
end

function HTTPResponse:addHeader(name, value)
	assert(not self.sentHeaders, "Cannot add headers after they have been sent.")
	table_insert(self.headers, string_format("%s: %s", name, value))
end

function HTTPResponse:sendHeaders()
	assert(not self.sentHeaders, "Cannot resend headers.")
	if #self.headers > 0 then
		self.client:send(string_format("HTTP/1.1 %d %s\r\n%s\r\n\r\n", self.status, statusCodes[self.status], table_concat(self.headers, "\r\n")))
	else
		self.client:send(string_format("HTTP/1.1 %d %s\r\n\r\n", self.status, statusCodes[self.status]))
	end
	self.sentHeaders = true
end

function HTTPResponse:write(chunk)
	if not self.sentHeaders then
		self:sendHeaders()
	end

	self.client:send(chunk)
end

function HTTPResponse:finish(chunk)
	if chunk then
		self:write(chunk)
	end

	self.client:close()
end

---@class HTTP: Server
local HTTPServer = {}
HTTPServer.__index = HTTPServer
setmetatable(HTTPServer, Server)

--- New HTTPServer
---@param callback fun(req: HTTPRequest, res: HTTPResponse)
function HTTPServer:new(callback)
	local http = setmetatable(getmetatable(self):new(), self)

	http:on("connect", function(client)
		local timer = Timer:new(10)
		timer:once("Timeout", function()
			client:close()
		end)

		client:once("data", function(data)
			timer:stop()
			local request = HTTPRequest:new(client, data)
			if not request then return end

			callback(request, HTTPResponse:new(client))
		end)
	end)

	return http
end

return {
	HTTPServer = HTTPServer,
}

