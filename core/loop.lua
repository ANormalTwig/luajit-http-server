---@type table<{ poll: fun(), _done: boolean }, boolean>
local objects = {}

--- Add an object to the loop
---@param object { poll: fun(), _done: boolean }
local function add(object)
	if not object.poll then return end
	objects[object] = true
end

--- Loop through all added objects poll() methods.
local function run()
	while next(objects) do
		for object in pairs(objects) do
			if object._done then
				objects[object] = nil
			else
				object:poll()
			end
		end
	end
end

return {
	add = add,
	run = run,
}

