local core = require("tester.core")
local util = require("tester.util")
local config = require("tester.config")

local function is_test_file(fname)
	fname = fname or vim.api.nvim_buf_get_name(0)
	return vim.endswith(fname, "_test.go")
end

---@return string|nil
---@return string|nil
---@return string|nil
local function get_closest_func()
	local parser = vim.treesitter.get_parser()
	if not parser then
		return
	end
	local tree = parser:trees()[1]
	if not tree then
		return
	end
	local query = vim.treesitter.query.get("go", "funcs")
	if not query then
		return
	end

	local nearest_match
	for _, match, _ in query:iter_matches(tree:root(), 0, 0, vim.api.nvim_win_get_cursor(0)[1]) do
		nearest_match = match
	end
	if not nearest_match then
		return
	end

	local capture_name, func_name, func_receiver
	for id, nodes in pairs(nearest_match) do
		for _, node in ipairs(nodes) do
			local capture = query.captures[id]
			if capture == "func" or capture == "method" then
				capture_name = capture
				func_name = vim.treesitter.get_node_text(node, 0)
			end
			if capture == "method_receiver" or capture == "method_recviver" then
				func_receiver = vim.treesitter.get_node_text(node, 0)
			end
		end
	end

	return capture_name, func_name, func_receiver
end

local function append_test_func_name(test, str)
	if str:sub(1, 1):match("%u") ~= nil then
		test = test .. str
	else
		test = test .. "_" .. str
	end
	return test
end

---@param func string
---@return string
local function generate_func_name(func)
	return append_test_func_name("Test", func)
end

---@param receiver string
---@param func string
---@return string
local function generate_method_name(receiver, func)
	return append_test_func_name(append_test_func_name("Test", receiver), func)
end

local function test_file_bufnr()
	local fname = vim.fn.expand("%:p")
	if not fname:match("_test%.go$") then
		fname = fname:gsub("%.go$", "_test.go")
		local bufnr = vim.fn.bufadd(fname)
		vim.fn.bufload(bufnr)
		return bufnr
	end
	return 0
end

local function test_func_linenr(bufnr, func_name)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for idx, line in ipairs(lines) do
		if line:match("^func " .. func_name .. "%(") then
			return idx
		end
	end
	return 0
end

local function default_template(func_name)
	local template = [[
func %s(t *testing.T) {
	testCases := []struct {
		desc string
	}{
		{
			desc: "",
		},
	}
	for _, tC := range testCases {
		t.Run(tC.desc, func(t *testing.T) {
		})
	}
}
	]]
	return string.format(template, func_name)
end

local function generate_test(func_name, lang_cfg)
	return core.resolve_template(lang_cfg.template, default_template, func_name)
end

local function find_project_root(fname, lang_cfg)
	local markers = (lang_cfg and lang_cfg.root_markers) or { "go.mod", ".git" }
	return util.find_project_root(fname, markers)
end

local Tester = {}

local function get_efm(lang_cfg)
	return lang_cfg.qf and lang_cfg.qf.efm or nil
end

Tester.gen_or_jump = function()
	local cfg = config.get()
	local lang_cfg = cfg.languages.go or {}

	core.gen_or_jump({
		get_symbol = function()
			local capture, func, receiver = get_closest_func()
			if not capture or not func then
				return nil
			end
			return {
				kind = capture,
				name = func,
				receiver = receiver,
			}
		end,
		get_test_bufnr = function()
			return test_file_bufnr()
		end,
		find_test_line = function(bufnr, symbol)
			local func_name
			if symbol.kind == "func" then
				func_name = generate_func_name(symbol.name)
			elseif symbol.kind == "method" then
				func_name = generate_method_name(symbol.receiver or "", symbol.name)
			end
			return func_name and test_func_linenr(bufnr, func_name) or 0
		end,
		generate_test = function(symbol)
			local func_name
			if symbol.kind == "func" then
				func_name = generate_func_name(symbol.name)
			elseif symbol.kind == "method" then
				func_name = generate_method_name(symbol.receiver or "", symbol.name)
			end
			return func_name and generate_test(func_name, lang_cfg) or ""
		end,
		describe = function(symbol)
			local func_name
			if symbol.kind == "func" then
				func_name = generate_func_name(symbol.name)
			elseif symbol.kind == "method" then
				func_name = generate_method_name(symbol.receiver or "", symbol.name)
			end
			return "func " .. (func_name or "")
		end,
		notify_jump = "[Test] jump to `%s`",
		notify_generate = "[Test] generate `%s`",
		jump_opts = { reuse_win = true, focus = true },
	})
end

local function collect_file_tests(buf_lines)
	local seen = {}
	local names = {}
	for _, line in ipairs(buf_lines or {}) do
		line = (line or ""):gsub("\r", "")
		local name = line:match("^func%s+(Test[%w_]+)%s*%(")
		if name and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	return names
end

local function find_test_name_at_cursor(lines, cursor_line)
	local line_count = #lines
	local func_name

	for i = cursor_line, line_count do
		local line = lines[i]
		if not line then
			break
		end
		line = line:gsub("\r", "")
		local name = line:match("^func%s+([%w_]+)%s*%(")
		if not name then
			name = line:match("^func%s+([^%s(]+)%(")
		end
		if name then
			func_name = name
			break
		end
	end

	if not func_name then
		for i = cursor_line, 1, -1 do
			local line = lines[i]
			if not line then
				break
			end
			line = line:gsub("\r", "")
			local name = line:match("^func%s+([%w_]+)%s*%(")
			if not name then
				name = line:match("^func%s+([^%s(]+)%(")
			end
			if name then
				func_name = name
				break
			end
		end
	end

	return func_name
end

---@param opts? {bang:boolean}
Tester.run = function(opts)
	opts = opts or {}
	local fname = vim.api.nvim_buf_get_name(0)
	if not is_test_file(fname) then
		vim.notify("[Test] not in a test file", vim.log.levels.WARN)
		return
	end

	local cfg = config.get()
	local lang_cfg = cfg.languages.go or {}

	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local root = find_project_root(fname, lang_cfg)

	if opts.bang then
		local tests = collect_file_tests(lines)
		if #tests == 0 then
			vim.notify("[Test] no Test* functions found in current file", vim.log.levels.WARN)
			return
		end
		local pattern = "^(" .. table.concat(tests, "|") .. ")$"
		local default_cmd = string.format("go test -v -run %s ./...", vim.fn.shellescape(pattern))
		local cmd = core.resolve_cmd(lang_cfg.commands and lang_cfg.commands.file, default_cmd, pattern, fname, root)

		vim.notify(string.format("[Test] running: %s", cmd), vim.log.levels.INFO)

		core.run({
			cmd = cmd,
			cwd = root,
			title = "GoTest",
			efm = get_efm(lang_cfg),
			notify_items = "[Test] %d items in quickfix",
			notify_success = "[Test] PASS",
			notify_empty = "[Test] no output",
		})
		return
	end

	local func_name = find_test_name_at_cursor(lines, cursor_line)
	if not func_name then
		local current_line = lines[cursor_line] or ""
		vim.notify(
			"[Test] no test function found at cursor (line " .. cursor_line .. "): " .. current_line:sub(1, 50),
			vim.log.levels.WARN
		)
		return
	end

	local pattern = "^" .. func_name .. "$"
	local default_cmd = string.format("go test -v -run %s ./...", vim.fn.shellescape(pattern))
	local cmd = core.resolve_cmd(lang_cfg.commands and lang_cfg.commands.single, default_cmd, pattern, fname, root)

	vim.notify(string.format("[Test] running: %s", cmd), vim.log.levels.INFO)

	core.run({
		cmd = cmd,
		cwd = root,
		title = "GoTest",
		efm = get_efm(lang_cfg),
		notify_items = "[Test] %d items in quickfix",
		notify_success = "[Test] PASS",
		notify_empty = "[Test] no output",
	})
end

return Tester
