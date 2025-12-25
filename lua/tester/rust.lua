local fn = vim.fn
local core = require("tester.core")
local util = require("tester.util")
local config = require("tester.config")

local query_str = [[
  (function_item name: (identifier) @name) @def
]]

local _query

local function get_query()
	if _query then
		return _query
	end
	local ok, q = pcall(vim.treesitter.query.parse, "rust", query_str)
	if not ok then
		vim.notify(string.format("[Tester] rust query.parse failed: %s", q), vim.log.levels.ERROR)
		return nil
	end
	_query = q
	return _query
end

---@param node userdata
---@param want_type string
---@return userdata|nil
local function find_ancestor(node, want_type)
	local cur = node
	while cur do
		if cur:type() == want_type then
			return cur
		end
		cur = cur:parent()
	end
	return nil
end

---@param impl_node userdata|nil
---@return string|nil
local function get_impl_type(impl_node)
	if not impl_node then
		return nil
	end

	local ok, type_nodes = pcall(function()
		return impl_node:field("type")
	end)
	if ok and type_nodes and type_nodes[1] then
		return vim.treesitter.get_node_text(type_nodes[1], 0)
	end

	local child_count = impl_node:named_child_count()
	for i = 0, child_count - 1 do
		local child = impl_node:named_child(i)
		if child and child:type() == "type_identifier" then
			return vim.treesitter.get_node_text(child, 0)
		end
	end

	return nil
end

---@param name string
---@return string
local function sanitize_name(name)
	return (name:gsub("[^%w_]", "_"))
end

---@return "func"|"method"|nil
---@return string|nil
---@return string|nil
local function get_closest_symbol()
	local query = get_query()
	if not query then
		return
	end

	local parser = vim.treesitter.get_parser(0, "rust")
	if not parser then
		return
	end
	local tree = parser:trees()[1]
	if not tree then
		return
	end

	local cursor_row = vim.api.nvim_win_get_cursor(0)[1]

	local best_def
	local best_name
	local best_row = -1

	for _, match, _ in query:iter_matches(tree:root(), 0, 0, cursor_row) do
		local def_node
		local name_node
		for id, nodes in pairs(match) do
			local cap = query.captures[id]
			for _, node in ipairs(nodes) do
				if cap == "def" then
					def_node = node
				elseif cap == "name" then
					name_node = node
				end
			end
		end

		if def_node then
			local sr = select(1, def_node:range())
			if sr >= best_row then
				best_row = sr
				best_def = def_node
				best_name = name_node
			end
		end
	end

	if not best_def then
		return
	end

	local name = best_name and vim.treesitter.get_node_text(best_name, 0) or vim.treesitter.get_node_text(best_def, 0)
	local impl_node = find_ancestor(best_def, "impl_item")
	local kind = impl_node and "method" or "func"
	local receiver = get_impl_type(impl_node)

	return kind, name, receiver
end

---@param fname string|nil
---@return boolean
local function is_test_file(fname)
	fname = fname or vim.api.nvim_buf_get_name(0)
	if fname:match("/tests/") then
		return true
	end
	return fname:match("_test%.rs$") ~= nil
end

local function find_project_root(fname, lang_cfg)
	local markers = (lang_cfg and lang_cfg.root_markers) or { "Cargo.toml", ".git" }
	return util.find_project_root(fname, markers)
end

local function get_test_file_path(src_fname, lang_cfg)
	local root = find_project_root(src_fname, lang_cfg)
	local rel = src_fname
	if src_fname:sub(1, #root + 1) == root .. "/" then
		rel = src_fname:sub(#root + 2)
	end

	if rel:sub(1, 4) == "src/" then
		rel = rel:sub(5)
	end

	local rel_dir = vim.fs.dirname(rel)
	if rel_dir == "." then
		rel_dir = ""
	end

	local basename = fn.fnamemodify(src_fname, ":t:r")
	local test_dir = root .. "/tests" .. (rel_dir ~= "" and ("/" .. rel_dir) or "")
	local test_fname = test_dir .. "/" .. basename .. "_test.rs"

	return test_dir, test_fname
end

local function test_file_bufnr(lang_cfg)
	local fname = fn.expand("%:p")
	if is_test_file(fname) then
		return 0
	end

	local test_dir, test_fname = get_test_file_path(fname, lang_cfg)
	fn.mkdir(test_dir, "p")

	local bufnr = fn.bufadd(test_fname)
	fn.bufload(bufnr)
	return bufnr
end

local function test_func_linenr(bufnr, func_name)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for idx, line in ipairs(lines) do
		if line:match("^fn%s+" .. func_name .. "%(") then
			return idx
		end
	end
	return 0
end

---@param kind "func"|"method"
---@param name string
---@param receiver string|nil
---@return string
local function test_name(kind, name, receiver)
	if kind == "method" and receiver then
		return sanitize_name(string.format("test_%s_%s", receiver, name))
	end
	return sanitize_name("test_" .. name)
end

local function default_template(func_name)
	local template = [[

#[test]
fn %s() {
    // TODO: arrange
    assert!(true);
}
]]
	return string.format(template, func_name)
end

local function generate_test(func_name, lang_cfg)
	return core.resolve_template(lang_cfg.template, default_template, func_name)
end

local Tester = {}

local function get_efm(lang_cfg)
	return lang_cfg.qf and lang_cfg.qf.efm or nil
end

Tester.gen_or_jump = function()
	local cfg = config.get()
	local lang_cfg = cfg.languages.rust or {}

	core.gen_or_jump({
		get_symbol = function()
			local kind, name, receiver = get_closest_symbol()
			if not kind or not name then
				return nil
			end
			return {
				kind = kind,
				name = name,
				receiver = receiver,
			}
		end,
		get_test_bufnr = function()
			return test_file_bufnr(lang_cfg)
		end,
		find_test_line = function(bufnr, symbol)
			local func_name = test_name(symbol.kind, symbol.name, symbol.receiver)
			return test_func_linenr(bufnr, func_name)
		end,
		generate_test = function(symbol)
			local func_name = test_name(symbol.kind, symbol.name, symbol.receiver)
			return generate_test(func_name, lang_cfg)
		end,
		describe = function(symbol)
			return "fn " .. test_name(symbol.kind, symbol.name, symbol.receiver)
		end,
		notify_jump = "[Test] jump to `%s`",
		notify_generate = "[Test] generate `%s`",
		jump_opts = { reuse_win = true, focus = true },
	})
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
	local lang_cfg = cfg.languages.rust or {}
	local root = find_project_root(fname, lang_cfg)

	if opts.bang then
		local default_cmd = "cargo test"
		local cmd = core.resolve_cmd(lang_cfg.commands and lang_cfg.commands.file, default_cmd, fname, root)
		vim.notify(string.format("[Test] running: %s", cmd), vim.log.levels.INFO)

		core.run({
			cmd = cmd,
			cwd = root,
			title = "CargoTest",
			efm = get_efm(lang_cfg),
			notify_items = "[Test] %d items in quickfix",
			notify_success = "[Test] DONE",
			notify_empty = "[Test] no output",
		})
		return
	end

	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local func_name

	for i = cursor_line, 1, -1 do
		local line = lines[i]
		local name = line:match("^fn%s+(test_%w+)%(")
		if name then
			func_name = name
			break
		end
	end

	if not func_name then
		vim.notify("[Test] no test function found at cursor", vim.log.levels.WARN)
		return
	end

	local default_cmd = string.format("cargo test %s", vim.fn.shellescape(func_name))
	local cmd = core.resolve_cmd(lang_cfg.commands and lang_cfg.commands.single, default_cmd, func_name, fname, root)
	vim.notify(string.format("[Test] running: %s", cmd), vim.log.levels.INFO)

	core.run({
		cmd = cmd,
		cwd = root,
		title = "CargoTest",
		efm = get_efm(lang_cfg),
		notify_items = "[Test] %d items in quickfix",
		notify_success = "[Test] DONE",
		notify_empty = "[Test] no output",
	})
end

return Tester
