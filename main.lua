local http = require("core.http")
local port = 80

local paths = {}
paths["file"] = require("path.file")

http.HTTPServer:new(function(req, res)
	local path, strarg = string.match(req.path, "^(%w+)%??=?(.*)")
	if paths[path] then
		local args = {}
		for arg in string.gmatch(strarg, "[^,]+") do
			table.insert(args, arg)
		end
		paths[path](req, res, args)
		return
	end

	res:finish("no path")
end):listen(port)

require("core.loop").run()

