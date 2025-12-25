local M = {}

local function to_cmd_string(cmd)
	if type(cmd) == "string" then
		return cmd
	end
	if type(cmd) == "table" then
		local parts = {}
		for _, part in ipairs(cmd) do
			table.insert(parts, vim.fn.shellescape(part))
		end
		return table.concat(parts, " ")
	end
	return tostring(cmd)
end

---@param cmd string|string[]
---@param opts? {cwd?:string, on_complete?:fun(output:string, obj:table), env?:table<string,string>}
---@return table
function M.run(cmd, opts)
	opts = opts or {}

	if vim.fn.exists(":Dispatch") == 2 then
		local dispatch_cmd = to_cmd_string(cmd)
		if opts.cwd then
			dispatch_cmd = "-dir=" .. opts.cwd .. " " .. dispatch_cmd
		end
		vim.cmd("Dispatch " .. dispatch_cmd)
		return { used_dispatch = true }
	end

	local system_cmd = cmd
	if type(cmd) == "string" then
		-- vim.system() does not reliably split a shell command string.
		-- Run through a shell to preserve expected behavior.
		if vim.fn.has("win32") == 1 then
			system_cmd = { "cmd.exe", "/C", cmd }
		else
			system_cmd = { "sh", "-c", cmd }
		end
	end

	vim.system(system_cmd, {
		text = true,
		cwd = opts.cwd,
		env = opts.env,
	}, function(obj)
		if opts.on_complete then
			local output = (obj.stdout or "") .. (obj.stderr or "")
			opts.on_complete(output, obj)
		end
	end)

	return { used_dispatch = false }
end

return M
