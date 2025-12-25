local fn = vim.fn
local core = require("tester.core")
local util = require("tester.util")
local config = require("tester.config")

local query_str = [[
  (decorated_definition
    (decorator) @decorator
    definition: (function_definition name: (identifier) @name) @def
  )

  (function_definition name: (identifier) @name) @def
]]

local _query

local function get_query()
	if _query then
		return _query
	end
	local ok, q = pcall(vim.treesitter.query.parse, "python", query_str)
	if not ok then
		vim.notify(string.format("[Tester] python query.parse failed: %s", q), vim.log.levels.ERROR)
		return nil
	end
	_query = q
	return _query
end

---@param name string
---@return string
local function test_name(name)
	return "test_" .. name
end

---@return boolean
local function is_test_file(fname)
	fname = fname or vim.api.nvim_buf_get_name(0)
	if fname:match("/tests/") then
		return true
	end
	return fname:match("test_[^/]+%.py$") ~= nil or fname:match("_test%.py$") ~= nil
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

---@param decorated_node userdata
---@return string[]
local function extract_decorators(decorated_node)
	local res = {}
	if not decorated_node or decorated_node:type() ~= "decorated_definition" then
		return res
	end

	local child_count = decorated_node:named_child_count()
	for i = 0, child_count - 1 do
		local child = decorated_node:named_child(i)
		if child and child:type() == "decorator" then
			local txt = vim.treesitter.get_node_text(child, 0) or ""
			res[#res + 1] = txt
		end
	end
	return res
end

---@param decorators string[]
---@param needle string
---@return boolean
local function decorators_contain(decorators, needle)
	for _, d in ipairs(decorators or {}) do
		if d:find(needle, 1, true) then
			return true
		end
	end
	return false
end

---@param class_node userdata
---@return string|nil
local function get_class_name(class_node)
	if not class_node or class_node:type() ~= "class_definition" then
		return nil
	end

	local ok, name_nodes = pcall(function()
		return class_node:field("name")
	end)
	if ok and name_nodes and name_nodes[1] then
		return vim.treesitter.get_node_text(name_nodes[1], 0)
	end

	local child_count = class_node:named_child_count()
	for i = 0, child_count - 1 do
		local child = class_node:named_child(i)
		if child and child:type() == "identifier" then
			return vim.treesitter.get_node_text(child, 0)
		end
	end

	return nil
end

---@return "func"|"method"|nil kind
---@return string|nil name
---@return string|nil class_name
---@return string[] decorators
local function get_closest_symbol()
	local query = get_query()
	if not query then
		return
	end

	local parser = vim.treesitter.get_parser(0, "python")
	if not parser then
		return
	end
	local tree = parser:trees()[1]
	if not tree then
		return
	end

	local cursor_row = vim.api.nvim_win_get_cursor(0)[1]

	local best_def
	local best_decorated
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
				best_decorated = def_node:parent()
				best_name = name_node
			end
		end
	end

	if not best_def then
		return
	end

	local name = best_name and vim.treesitter.get_node_text(best_name, 0) or vim.treesitter.get_node_text(best_def, 0)
	local class_node = find_ancestor(best_def, "class_definition")
	local class_name = get_class_name(class_node)
	local kind = class_node and "method" or "func"
	local decorators = extract_decorators(best_decorated)

	return kind, name, class_name, decorators
end

local function find_project_root(fname, lang_cfg)
	local markers = (lang_cfg and lang_cfg.root_markers) or { "pyproject.toml", "setup.py", ".git" }
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
	local test_fname = test_dir .. "/test_" .. basename .. ".py"

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
		if line:match("^def%s+" .. func_name .. "%(") then
			return idx
		end
	end
	return 0
end

---@param kind "func"|"method"
---@param decorators string[]
---@param test_func_name string
---@param orig_name string
---@param class_name string|nil
local function default_template(kind, decorators, test_func_name, orig_name, class_name)
	if kind == "method" then
		local cls = class_name or "ClassName"
		if decorators_contain(decorators, "staticmethod") or decorators_contain(decorators, "classmethod") then
			local template = [[

def %s():
    # TODO: from your_module import %s
    result = %s.%s()  # TODO: args
    assert result is not None
]]
			return string.format(template, test_func_name, cls, cls, orig_name)
		end

		local template = [[

def %s():
    # TODO: from your_module import %s
    obj = %s()
    result = obj.%s()  # TODO: args
    assert result is not None
]]
		return string.format(template, test_func_name, cls, cls, orig_name)
	end

	local template = [[

def %s():
    # TODO: from your_module import %s
    result = %s()  # TODO: args
    assert result is not None
]]
	return string.format(template, test_func_name, orig_name, orig_name)
end

local function generate_test(lang_cfg, kind, decorators, test_func_name, orig_name, class_name)
	local tmpl = lang_cfg.template
	if type(tmpl) == "function" then
		return tmpl(kind, decorators, test_func_name, orig_name, class_name)
	end
	return default_template(kind, decorators, test_func_name, orig_name, class_name)
end

local Tester = {}

local function get_efm(lang_cfg)
	return lang_cfg.qf and lang_cfg.qf.efm or nil
end

Tester.gen_or_jump = function()
	local cfg = config.get()
	local lang_cfg = cfg.languages.python or {}

	core.gen_or_jump({
		get_symbol = function()
			local kind, name, class_name, decorators = get_closest_symbol()
			if not kind or not name then
				return nil
			end
			return {
				kind = kind,
				name = name,
				class_name = class_name,
				decorators = decorators or {},
			}
		end,
		get_test_bufnr = function()
			return test_file_bufnr(lang_cfg)
		end,
		find_test_line = function(bufnr, symbol)
			local test_func_name = test_name(symbol.name)
			return test_func_linenr(bufnr, test_func_name)
		end,
		generate_test = function(symbol)
			local test_func_name = test_name(symbol.name)
			return generate_test(lang_cfg, symbol.kind, symbol.decorators or {}, test_func_name, symbol.name, symbol.class_name)
		end,
		describe = function(symbol)
			return "def " .. test_name(symbol.name)
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
	local lang_cfg = cfg.languages.python or {}
	local root = find_project_root(fname, lang_cfg)

	if opts.bang then
		local default_cmd = string.format("pytest -v %s", vim.fn.shellescape(fname))
		local cmd = core.resolve_cmd(lang_cfg.commands and lang_cfg.commands.file, default_cmd, fname, root)
		vim.notify(string.format("[Test] running: %s", cmd), vim.log.levels.INFO)

		core.run({
			cmd = cmd,
			cwd = root,
			title = "PyTest",
			efm = get_efm(lang_cfg),
			notify_items = "[Test] %d items in quickfix",
			notify_success = "[Test] PASSED",
			notify_empty = "[Test] no output",
		})
		return
	end

	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local func_name

	for i = cursor_line, 1, -1 do
		local line = lines[i]
		local name = line:match("^def%s+(test_%w+)%(")
		if name then
			func_name = name
			break
		end
	end

	if not func_name then
		vim.notify("[Test] no test function found at cursor", vim.log.levels.WARN)
		return
	end

	local default_cmd = string.format(
		"pytest -v -k %s %s",
		vim.fn.shellescape(func_name),
		vim.fn.shellescape(fname)
	)
	local cmd = core.resolve_cmd(lang_cfg.commands and lang_cfg.commands.single, default_cmd, func_name, fname, root)

	vim.notify(string.format("[Test] running: %s", cmd), vim.log.levels.INFO)

	core.run({
		cmd = cmd,
		cwd = root,
		title = "PyTest",
		efm = get_efm(lang_cfg),
		notify_items = "[Test] %d items in quickfix",
		notify_success = "[Test] PASSED",
		notify_empty = "[Test] no output",
	})
end

return Tester
