return function(_, res, args)
	-- too lazy to make sure they can't .. out of the files directory
	if string.match(args[1], "%.%.") then
		res:setStatus(404);
		res:finish("can't open file");
		return
	end

	local file = io.open("files/" .. args[1], "r")
	if not file then
		res:setStatus(404);
		res:finish("can't open file");
		return
	end

	res:finish(file:read("*a"))
end

