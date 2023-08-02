local ffi = require("ffi")

local Emitter = require("core.emitter")
local loop = require("core.loop")

local stdin = 0
local stdout = 1
local stderr = 2

ffi.cdef([[
	struct pollfd {
		int fd;
		short int events;
		short int revents;
	};

	int pipe(int *pipedes);
	int dup2(int fd, int fd2);
	int close(int fd);
	int poll(struct pollfd *fds, int nfds, int timeout);
	int write(int fd, void *buf, size_t n);
	int read(int fd, void *buf, size_t n);
	int memset(void *, int, unsigned long);
	int fork();
	int execvp(const char *file, char *const *args);
	int setgpid(int pid, int gpid);
	int waitpid(int pid, int *status, int options);
	int kill(int pid);
	void exit(int status);
]])

local C = ffi.C

---@class Process: Emitter
---@field args string[]
---@field pid number
---@field input number
---@field output number
---@field exited boolean
---@field _done boolean
local Process = {}
Process.__index = Process
setmetatable(Process, Emitter)

--- Create a new Process.
---@vararg string
function Process:new(...)
	assert(select("#", ...) > 0, "Invalid varargs")
	local process = setmetatable(getmetatable(self):new(), self)
	process.args = {...}

	return process
end

--- Start the process
function Process:spawn()
	-- [0] = Read end, [1] = Write end
	local input = ffi.new("int[2]")
	C.pipe(input)

	local output = ffi.new("int[2]")
	C.pipe(output)

	local pid = C.fork()
	if pid == 0 then
		C.dup2(input[0], stdin)
		C.dup2(output[1], stdout)
		C.dup2(output[1], stderr)

		C.close(input[1])
		C.close(output[0])

		local cargs = ffi.new("const char *[?]", #self.args + 1)
		for i = 1, #self.args do
			cargs[i - 1] = self.args[i]
		end
		cargs = ffi.cast("char *const *", cargs)

		if C.execvp(cargs[0], cargs) == -1 then
			io.write("execvp() failed: ", ffi.errno(), "\n")
			C.exit(-1)
		end
	end

	C.close(input[0])
	C.close(output[1])

	self.input = input[1]
	self.output = output[0]
	self.pid = pid

	loop.add(self)
end

function Process:write(data)
	C.write(self.input, data, #data)
end

function Process:setgpid(n)
	C.setgpid(self.pid, n)
end

local readBuffer = ffi.new("char[8192]")
local statusPtr = ffi.new("int[1]")

local pollfd = ffi.new("struct pollfd", {
	events = 0x001, -- POLLIN
})

--- Poll events from the process.
---@private
function Process:poll()
	pollfd.fd = self.output

	::again::
	C.poll(pollfd, 1, 0)
	---@diagnostic disable-next-line: undefined-field
	if bit.band(pollfd.revents, 0x001) == 0x001 then
		C.memset(readBuffer, 0, 8192)
		local bytesRead = C.read(self.output, readBuffer, 8191)
		if bytesRead > 0 then
			self:emit("data", ffi.string(readBuffer))
			goto again
		end
	end

	local pid = C.waitpid(self.pid, statusPtr, 1) -- WNOHANG
	if pid == self.pid then
		self.exited = true
		self:emit("exit", statusPtr[0])
		self._done = true

		C.close(self.input)
		C.close(self.output)
	end
end

function Process:kill()
	C.kill(self.pid, 9) -- SIGKILL
end

return Process

