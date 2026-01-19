-- tests/helpers.lua
-- Testing helper utilities for functional/integration tests

local MiniTest = require('mini.test')

-- Cache child processes for better performance
local child_table = {}
local child_counter = 0

---Create a new child Neovim process with custom helpers
---@return table child object with helper methods
local function new_child_neovim()
	child_counter = child_counter + 1
	local child = MiniTest.new_child_neovim()
	child_table[child_counter] = child

	-- Custom setup method - restart with clean state
	child.setup = function()
		child.restart({ '-u', 'scripts/minimal_init.lua' })
	end

	-- Common helper wrappers
	child.set_lines = function(...)
		return child.lua_get('set_lines(...)', { ... })
	end

	child.get_lines = function(...)
		return child.lua_get('get_lines(...)', { ... })
	end

	child.set_cursor = function(...)
		return child.lua_get('set_cursor(...)', { ... })
	end

	child.get_cursor = function(...)
		return child.lua_get('get_cursor(...)', { ... })
	end

	-- Get current buffer name
	child.get_buf_name = function()
		return child.lua_get('vim.api.nvim_buf_get_name(0)')
	end

	-- Get all buffer lines
	child.buf_get_lines = function(buf)
		return child.lua_get('vim.api.nvim_buf_get_lines(...)', { buf or 0, 0, -1, true })
	end

	-- Execute command and capture result
	child.exec_capture = function(cmd)
		return child.cmd_capture(cmd)
	end

	-- Type Lua code and return result
	child.exec_lua = function(code, ...)
		return child.lua_get(code, { ... })
	end

	return child
end

---Stop all child processes
local function stop_all()
	for _, child in pairs(child_table) do
		child.stop()
	end
	child_table = {}
	child_counter = 0
end

return {
	new_child_neovim = new_child_neovim,
	stop_all = stop_all,
	-- MiniTest shortcuts
	new_set = MiniTest.new_set,
	eq = MiniTest.expect.equality,
	expect = MiniTest.expect,
	no_error = MiniTest.expect.no_error,
}
