-- see "https://docs.pytest.org/en/stable/explanation/goodpractices.html#test-discovery"

local api = vim.api
local fn = vim.fn

-- Inline TreeSitter query (lazy init to avoid parse failures during module load)
-- Finds the nearest function definition (including ones wrapped by decorators).
-- Whether it's a top-level function or a class method is determined by walking ancestors.
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

	-- A decorated_definition may contain multiple decorator nodes; just scan them.
	local child_count = decorated_node:named_child_count()
	for i = 0, child_count - 1 do
		local child = decorated_node:named_child(i)
		if child and child:type() == "decorator" then
			local txt = vim.treesitter.get_node_text(child, 0) or ""
			-- Examples: "@staticmethod", "@pkg.staticmethod", "@decorator(args)"
			-- We only do a substring check for: staticmethod / classmethod
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

	-- python class_definition has a name field
	local ok, name_nodes = pcall(function()
		return class_node:field("name")
	end)
	if ok and name_nodes and name_nodes[1] then
		return vim.treesitter.get_node_text(name_nodes[1], 0)
	end

	-- Fallback: find the first identifier
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
			-- Choose the definition whose start row is closest to the cursor.
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

-- Try to locate project root: pyproject.toml / setup.py / .git (first match upwards)
local function find_project_root(fname)
	local dir = vim.fs.dirname(fname)
	local markers = { "pyproject.toml", "setup.py", ".git" }
	local found = vim.fs.find(markers, { upward = true, path = dir })[1]
	if found then
		return vim.fs.dirname(found)
	end
	return fn.getcwd()
end

-- Map source file to a test file under tests/
local function get_test_file_path(src_fname)
	local root = find_project_root(src_fname)
	local rel = src_fname
	if src_fname:sub(1, #root + 1) == root .. "/" then
		rel = src_fname:sub(#root + 2)
	end

	-- Common src-layout: src/pkg/mod.py -> tests/pkg/test_mod.py (strip leading src/)
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

local function test_file_bufnr()
	local fname = fn.expand("%:p")
	if is_test_file(fname) then
		return 0
	end

	local test_dir, test_fname = get_test_file_path(fname)
	fn.mkdir(test_dir, "p")

	local bufnr = fn.bufadd(test_fname)
	fn.bufload(bufnr)
	return bufnr
end

local function test_func_linenr(bufnr, func_name)
	local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for idx, line in ipairs(lines) do
		if line:match("^def%s+" .. func_name .. "%(") then
			return idx
		end
	end
	return 0
end

--- jump to line
---@param bufnr number
---@param row number
---@param opts? {reuse_win: boolean, focus:boolean}
local function jump_to_line(bufnr, row, opts)
	opts = opts or {}
	local reuse_win = opts.reuse_win or false
	local focus = opts.focus or false

	if focus then
		-- Save position in jumplist
		vim.cmd("normal! m'")

		-- Push a new item into tagstack
		local from = { fn.bufnr("%"), fn.line("."), fn.col("."), 0 }
		local items = { { tagname = fn.expand("<cword>"), from = from } }
		fn.settagstack(fn.win_getid(), { items = items }, "t")
	end

	local function bufwinid(buf)
		for _, win in ipairs(api.nvim_list_wins()) do
			if api.nvim_win_get_buf(win) == buf then
				return win
			end
		end
	end

	local win = reuse_win and bufwinid(bufnr) or focus and api.nvim_get_current_win()

	vim.bo[bufnr].buflisted = true
	api.nvim_win_set_buf(win, bufnr)
	if focus then
		api.nvim_set_current_win(win)
	end

	if row < 0 then
		row = api.nvim_buf_line_count(bufnr) + row
	end
	api.nvim_win_set_cursor(win, { row, 0 })
	api.nvim_win_call(win, function()
		-- Open folds under the cursor
		vim.cmd("normal! zv")
	end)
end

local function append_to_file(bufnr, body)
	local lines = vim.split(body, "\n")
	api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
	return #lines
end

---@param kind "func"|"method"
---@param decorators string[]
---@param test_func_name string
---@param orig_name string
---@param class_name string|nil
local function generate_test(kind, decorators, test_func_name, orig_name, class_name)
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

local Tester = {}

Tester.gen_or_jump = function()
	local kind, name, class_name, decorators = get_closest_symbol()
	if not kind or not name then
		return
	end

	local test_func_name = test_name(name)

	local test_bufnr = test_file_bufnr()
	local linenr = test_func_linenr(test_bufnr, test_func_name)
	if linenr > 0 then
		jump_to_line(test_bufnr, linenr, { reuse_win = true, focus = true })
		vim.notify(string.format("[Test] jump to `def %s`", test_func_name), vim.log.levels.INFO)
		return
	end

	local body = generate_test(kind, decorators or {}, test_func_name, name, class_name)
	local count = append_to_file(test_bufnr, body)
	jump_to_line(test_bufnr, -count + 1, { reuse_win = true, focus = true })
	vim.notify(string.format("[Test] generate `def %s`", test_func_name), vim.log.levels.INFO)
end

return Tester
