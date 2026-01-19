local M = {}

local function normalize_lines(output)
	local lines = vim.split(output or "", "\n", { plain = true })
	if #lines > 0 and lines[#lines] == "" then
		table.remove(lines, #lines)
	end
	return lines
end

---@param lines string[]
---@return table[]
function M.parse_file_line_msg(lines)
	local qf_list = {}
	for _, line in ipairs(lines or {}) do
		line = (line or ""):gsub("\r", "")
		if line ~= "" then
			local fname, lnum, msg = line:match("^(.-):(%d+):%s*(.+)$")
			if fname and lnum then
				table.insert(qf_list, {
					filename = fname,
					lnum = tonumber(lnum),
					text = msg,
				})
			else
				table.insert(qf_list, {
					text = line,
				})
			end
		end
	end
	return qf_list
end

---@param output string
---@param opts? {title?:string, open?:boolean, efm?:string}
---@return number item_count
function M.from_output(output, opts)
	opts = opts or {}

	local lines = normalize_lines(output or "")
	local title = opts.title or "Test"
	local efm = opts.efm

	if efm and efm ~= "" then
		-- Use errorformat to parse lines
		vim.fn.setqflist({}, "r", { title = title, lines = lines, efm = efm })
	else
		-- Use custom parser
		local items = M.parse_file_line_msg(lines)
		vim.fn.setqflist({}, "r", { title = title, items = items })
	end

	local count = #vim.fn.getqflist()

	if count > 0 and opts.open ~= false then
		vim.cmd("copen")
	end

	return count
end

return M
