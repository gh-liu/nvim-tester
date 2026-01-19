-- scripts/minimal_init.lua
-- Minimal Neovim configuration for testing

-- Add current directory to runtimepath
vim.cmd([[let &rtp.=','.getcwd()]])

-- Only setup mini.test in headless mode
if #vim.api.nvim_list_uis() == 0 then
	-- Add mini.nvim to runtimepath
	vim.cmd('set rtp+=deps/mini.nvim')
	-- Setup mini.test
	require('mini.test').setup()
end

-- Test environment settings
vim.opt.swapfile = false
vim.opt.shadafile = 'none'
vim.opt.backup = false
vim.opt.writebackup = false

-- Helper functions for child processes
function set_lines(...)
	local buf = 0
	local lines = { ... }
	vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
end

function get_lines(...)
	local buf = 0
	return vim.api.nvim_buf_get_lines(buf, 0, -1, true)
end

function set_cursor(line, col)
	vim.api.nvim_win_set_cursor(0, { line, col })
end

function get_cursor()
	return vim.api.nvim_win_get_cursor(0)
end
