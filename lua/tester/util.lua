local M = {}

local api = vim.api
local fn = vim.fn

-- Cache project roots to reduce repeated upward filesystem scans.
-- key: "<start_dir>\n<marker1>|<marker2>|..."; value: root_dir
local _root_cache = {}

---@param start_dir string
---@param markers string[]
---@return string
local function root_cache_key(start_dir, markers)
	return start_dir .. "\n" .. table.concat(markers or {}, "|")
end

---Find project root by searching upwards for marker files/dirs.
---Falls back to current working directory when not found.
---@param fname string
---@param markers string[]
---@return string
function M.find_project_root(fname, markers)
	if not fname or fname == "" then
		return fn.getcwd()
	end
	local dir = vim.fs.dirname(fname)
	if not dir or dir == "" then
		return fn.getcwd()
	end

	local key = root_cache_key(dir, markers)
	local cached = _root_cache[key]
	if cached then
		return cached
	end

	local found = vim.fs.find(markers, { upward = true, path = dir })[1]
	local root = found and vim.fs.dirname(found) or fn.getcwd()
	_root_cache[key] = root
	return root
end

---Append a string body to the end of a buffer.
---@param bufnr number
---@param body string
---@return number appended_line_count
function M.append_to_buf(bufnr, body)
	local lines = vim.split(body or "", "\n")
	api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
	return #lines
end

---Jump to a (1-based) row in a buffer, optionally reusing an existing window.
---@param bufnr number
---@param row number
---@param opts? {reuse_win?: boolean, focus?: boolean}
function M.jump_to_line(bufnr, row, opts)
	opts = opts or {}
	local reuse_win = opts.reuse_win or false
	local focus = opts.focus or false

	if focus then
		vim.cmd("normal! m'")
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
		return nil
	end

	local win
	if reuse_win then
		win = bufwinid(bufnr)
	end
	if not win and focus then
		win = api.nvim_get_current_win()
	end
	if not win then
		win = api.nvim_get_current_win()
	end

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
		vim.cmd("normal! zv")
	end)
end

return M

