local util = require("tester.util")
local runner = require("tester.runner")
local quickfix = require("tester.quickfix")

local M = {}

local function resolve_value(spec, default_value, ...)
	if type(spec) == "function" then
		return spec(...)
	end
	if type(spec) == "string" then
		local ok, res = pcall(string.format, spec, ...)
		if ok then
			return res
		end
	end
	if type(default_value) == "function" then
		return default_value(...)
	end
	if type(default_value) == "string" then
		local ok, res = pcall(string.format, default_value, ...)
		if ok then
			return res
		end
	end
	return default_value
end

function M.resolve_cmd(spec, default_value, ...)
	return resolve_value(spec, default_value, ...)
end

function M.resolve_template(spec, default_value, ...)
	return resolve_value(spec, default_value, ...)
end

local function notify_if(msg, level)
	if msg and msg ~= "" then
		vim.notify(msg, level or vim.log.levels.INFO)
	end
end

---@param adapter table
function M.gen_or_jump(adapter)
	if not adapter or type(adapter.get_symbol) ~= "function" then
		return
	end

	local symbol = adapter.get_symbol()
	if not symbol then
		return
	end

	local bufnr = adapter.get_test_bufnr(symbol)
	if not bufnr then
		return
	end

	local jump_opts = adapter.jump_opts or { reuse_win = true, focus = true }
	local line = adapter.find_test_line(bufnr, symbol) or 0

	if line > 0 then
		util.jump_to_line(bufnr, line, jump_opts)
		local desc = adapter.describe and adapter.describe(symbol) or ""
		local msg = resolve_value(adapter.notify_jump, "[Test] jump to `%s`", desc)
		notify_if(msg, vim.log.levels.INFO)
		return
	end

	local body = adapter.generate_test(symbol)
	if not body or body == "" then
		return
	end

	local count = util.append_to_buf(bufnr, body)
	util.jump_to_line(bufnr, -count + 1, jump_opts)
	local desc = adapter.describe and adapter.describe(symbol) or ""
	local msg = resolve_value(adapter.notify_generate, "[Test] generate `%s`", desc)
	notify_if(msg, vim.log.levels.INFO)
end

---@param opts table
function M.run(opts)
	opts = opts or {}

	local cmd = opts.cmd
	if not cmd or cmd == "" then
		return
	end

	return runner.run(cmd, {
		cwd = opts.cwd,
		env = opts.env,
		on_complete = function(output, obj)
			output = output or ""

			local count = quickfix.from_output(output, {
				title = opts.title or "Test",
				efm = opts.efm,
			})
			if count > 0 then
				local msg = resolve_value(opts.notify_items, "[Test] %d items in quickfix", count)
				notify_if(msg, vim.log.levels.INFO)
				return
			end

			-- Simple success detection
			if output:find("PASS", 1, true) or output:find("passed", 1, true) or output:find("test result", 1, true) then
				notify_if(opts.notify_success or "[Test] PASS", vim.log.levels.INFO)
			else
				notify_if(opts.notify_empty or "[Test] no output", vim.log.levels.WARN)
			end

			if opts.on_complete then
				opts.on_complete(output, obj)
			end
		end,
	})
end

return M
