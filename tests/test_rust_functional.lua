-- tests/test_rust_functional.lua
-- Functional/Integration tests for Rust language adapter

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

-- Rust adapter workflow tests
T['Rust adapter'] = new_set()

T['Rust adapter']['loads without error'] = function()
	expect.no_error(function()
		child.lua([[require('tester.rust')]])
	end)
end

T['Rust adapter']['registers buffer-local commands'] = function()
	child.lua([[
		vim.fn.bufadd('test.rs')
		vim.cmd('file test.rs')
		vim.bo.filetype = 'rust'
	]])

	child.lua('vim.wait(100, function() return true end)')

	child.lua([[
		local ok = pcall(vim.api.nvim_buf_get_commands, 0, {})
		if not ok then
			_G.has_rusttest_cmd = false
		else
			local cmds = vim.api.nvim_buf_get_commands(0, {})
			_G.has_rusttest_cmd = cmds.RUSTTest ~= nil
		end
	]])
	local has_cmd = child.lua_get('_G.has_rusttest_cmd')

	eq(has_cmd, true)
end

T['Rust adapter']['registers RUSTTestRun command'] = function()
	child.lua([[
		vim.fn.bufadd('test.rs')
		vim.cmd('file test.rs')
		vim.bo.filetype = 'rust'
	]])

	child.lua('vim.wait(100, function() return true end)')

	child.lua([[
		local ok = pcall(vim.api.nvim_buf_get_commands, 0, {})
		if not ok then
			_G.has_rusttestrun_cmd = false
		else
			local cmds = vim.api.nvim_buf_get_commands(0, {})
			_G.has_rusttestrun_cmd = cmds.RUSTTestRun ~= nil
		end
	]])
	local has_cmd = child.lua_get('_G.has_rusttestrun_cmd')

	eq(has_cmd, true)
end

T['Rust adapter']['gen_or_jump does not crash on empty buffer'] = function()
	child.lua([[
		vim.fn.bufadd('empty.rs')
		vim.cmd('file empty.rs')
		vim.bo.filetype = 'rust'
		vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
	]])

	expect.no_error(function()
		child.lua([[require('tester.rust').gen_or_jump()]])
	end)
end

T['Rust adapter']['gen_or_jump handles function definition'] = function()
	child.lua([[
		vim.fn.bufadd('utils.rs')
		vim.cmd('file utils.rs')
		vim.bo.filetype = 'rust'
		local code = [===[pub fn calculate(x: i32, y: i32) -> i32 {
    x + y
}
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
		vim.api.nvim_win_set_cursor(0, {2, 1})
	]])

	expect.no_error(function()
		child.lua([[require('tester.rust').gen_or_jump()]])
	end)
end

T['Rust adapter']['gen_or_jump handles method in impl block'] = function()
	child.lua([[
		vim.fn.bufadd('calculator.rs')
		vim.cmd('file calculator.rs')
		vim.bo.filetype = 'rust'
		local code = [===[impl Calculator {
    pub fn add(&self, a: i32, b: i32) -> i32 {
        a + b
    }
}
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
		vim.api.nvim_win_set_cursor(0, {3, 1})
	]])

	expect.no_error(function()
		child.lua([[require('tester.rust').gen_or_jump()]])
	end)
end

T['Rust adapter']['run does not crash on test file'] = function()
	child.lua([[
		vim.fn.bufadd('utils_test.rs')
		vim.cmd('file utils_test.rs')
		vim.bo.filetype = 'rust'
		local code = [===[#[test]
fn test_calculate() {
    assert!(calculate(1, 2) == 3);
}
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
	]])

	expect.no_error(function()
		child.lua([[require('tester.rust').run({})]])
	end)
end

T['Rust adapter']['run respects bang modifier'] = function()
	child.lua([[
		vim.fn.bufadd('utils_test.rs')
		vim.cmd('file utils_test.rs')
		vim.bo.filetype = 'rust'
		local code = [===[#[test]
fn test_add() {}

#[test]
fn test_subtract() {}
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
	]])

	expect.no_error(function()
		child.lua([[require('tester.rust').run({bang = true})]])
	end)
end

T['Rust adapter']['config overrides work'] = function()
	child.lua([[
		require('tester.config').setup({
			languages = {
				rust = {
					root_markers = { 'custom.Cargo.toml' }
				}
			}
		})
		local config = require('tester.config')
		_G.result = config.get().languages.rust.root_markers
	]])

	eq(child.lua_get('_G.result'), { 'custom.Cargo.toml' })
end

return T
