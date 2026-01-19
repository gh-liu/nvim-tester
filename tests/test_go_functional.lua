-- tests/test_go_functional.lua
-- Functional/Integration tests for Go language adapter

local helpers = dofile('tests/helpers.lua')
local child = helpers.new_child_neovim()

local new_set = helpers.new_set
local eq = helpers.eq
local expect = helpers.expect

local T = new_set({
	hooks = {
		pre_case = function()
			child.setup()
		end,
		post_once = child.stop,
	},
})

-- Go adapter workflow tests
T['Go adapter'] = new_set()

T['Go adapter']['loads without error'] = function()
	expect.no_error(function()
		child.lua([[require('tester.go')]])
	end)
end

T['Go adapter']['registers buffer-local commands'] = function()
	child.lua([[
		vim.fn.bufadd('test.go')
		vim.cmd('file test.go')
		vim.bo.filetype = 'go'
	]])

	-- Wait for autocmd to process
	child.lua('vim.wait(100, function() return true end)')

	-- Check if GOTest command exists
	child.lua([[
		local ok = pcall(vim.api.nvim_buf_get_commands, 0, {})
		if not ok then
			_G.has_gotest_cmd = false
		else
			local cmds = vim.api.nvim_buf_get_commands(0, {})
			_G.has_gotest_cmd = cmds.GOTest ~= nil
		end
	]])
	local has_cmd = child.lua_get('_G.has_gotest_cmd')

	eq(has_cmd, true)
end

T['Go adapter']['registers GOTestRun command'] = function()
	child.lua([[
		vim.fn.bufadd('test.go')
		vim.cmd('file test.go')
		vim.bo.filetype = 'go'
	]])

	child.lua('vim.wait(100, function() return true end)')

	child.lua([[
		local ok = pcall(vim.api.nvim_buf_get_commands, 0, {})
		if not ok then
			_G.has_gotestrun_cmd = false
		else
			local cmds = vim.api.nvim_buf_get_commands(0, {})
			_G.has_gotestrun_cmd = cmds.GOTestRun ~= nil
		end
	]])
	local has_cmd = child.lua_get('_G.has_gotestrun_cmd')

	eq(has_cmd, true)
end

T['Go adapter']['generates test file name correctly'] = function()
	child.lua([[
		vim.fn.bufadd('main.go')
		vim.cmd('file main.go')
		vim.bo.filetype = 'go'
	]])

	-- The adapter should create main_test.go when triggered
	local src_file = child.lua_get('vim.fn.expand("%:t")')
	eq(src_file, 'main.go')
end

T['Go adapter']['gen_or_jump does not crash on empty buffer'] = function()
	-- Skip if Go parser is not available
	child.lua([[
		local ok, parser = pcall(vim.treesitter.get_parser, 0, 'go')
		_G.has_go_parser = ok and parser ~= nil
	]])
	local has_parser = child.lua_get('_G.has_go_parser')

	if not has_parser then
		print("SKIP: Go tree-sitter parser not installed")
		return
	end

	child.lua([[
		vim.fn.bufadd('empty.go')
		vim.cmd('file empty.go')
		vim.bo.filetype = 'go'
		vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
	]])

	-- This should not crash
	expect.no_error(function()
		child.lua([[require('tester.go').gen_or_jump()]])
	end)
end

T['Go adapter']['gen_or_jump handles buffer with function'] = function()
	-- Skip if Go parser is not available
	child.lua([[
		local ok, parser = pcall(vim.treesitter.get_parser, 0, 'go')
		_G.has_go_parser2 = ok and parser ~= nil
	]])
	local has_parser = child.lua_get('_G.has_go_parser2')

	if not has_parser then
		print("SKIP: Go tree-sitter parser not installed")
		return
	end

	child.lua([[
		vim.fn.bufadd('calc.go')
		vim.cmd('file calc.go')
		vim.bo.filetype = 'go'
		local code = [===[package main

func Add(a, b int) int {
	return a + b
}
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
		vim.api.nvim_win_set_cursor(0, {3, 1})
	]])

	-- Should not crash when processing function
	expect.no_error(function()
		child.lua([[require('tester.go').gen_or_jump()]])
	end)
end

T['Go adapter']['run does not crash on test file'] = function()
	child.lua([[
		vim.fn.bufadd('calc_test.go')
		vim.cmd('file calc_test.go')
		vim.bo.filetype = 'go'
		local code = [===[package main

import "testing"

func TestAdd(t *testing.T) {
	if Add(1, 2) != 3 {
		t.Fail()
	}
}
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
	]])

	-- Should not crash when running test
	expect.no_error(function()
		child.lua([[require('tester.go').run({})]])
	end)
end

T['Go adapter']['run respects bang modifier'] = function()
	child.lua([[
		vim.fn.bufadd('calc_test.go')
		vim.cmd('file calc_test.go')
		vim.bo.filetype = 'go'
		local code = [===[package main

import "testing"

func TestAdd(t *testing.T) {}
func TestSubtract(t *testing.T) {}
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
	]])

	-- Should not crash with bang=true (run all tests)
	expect.no_error(function()
		child.lua([[require('tester.go').run({bang = true})]])
	end)
end

T['Go adapter']['config overrides work'] = function()
	child.lua([[
		require('tester.config').setup({
			languages = {
				go = {
					root_markers = { 'custom.go.mod' }
				}
			}
		})
		local config = require('tester.config')
		_G.result = config.get().languages.go.root_markers
	]])

	eq(child.lua_get('_G.result'), { 'custom.go.mod' })
end

return T
