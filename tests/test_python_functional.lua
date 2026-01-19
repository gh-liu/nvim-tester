-- tests/test_python_functional.lua
-- Functional/Integration tests for Python language adapter

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

-- Python adapter workflow tests
T['Python adapter'] = new_set()

T['Python adapter']['loads without error'] = function()
	expect.no_error(function()
		child.lua([[require('tester.python')]])
	end)
end

T['Python adapter']['registers buffer-local commands'] = function()
	child.lua([[
		vim.fn.bufadd('test.py')
		vim.cmd('file test.py')
		vim.bo.filetype = 'python'
	]])

	child.lua('vim.wait(100, function() return true end)')

	child.lua([[
		local ok = pcall(vim.api.nvim_buf_get_commands, 0, {})
		if not ok then
			_G.has_pythontest_cmd = false
		else
			local cmds = vim.api.nvim_buf_get_commands(0, {})
			_G.has_pythontest_cmd = cmds.PYTHONTest ~= nil
		end
	]])
	local has_cmd = child.lua_get('_G.has_pythontest_cmd')

	eq(has_cmd, true)
end

T['Python adapter']['registers PYTHONTestRun command'] = function()
	child.lua([[
		vim.fn.bufadd('test.py')
		vim.cmd('file test.py')
		vim.bo.filetype = 'python'
	]])

	child.lua('vim.wait(100, function() return true end)')

	child.lua([[
		local ok = pcall(vim.api.nvim_buf_get_commands, 0, {})
		if not ok then
			_G.has_pythontestrun_cmd = false
		else
			local cmds = vim.api.nvim_buf_get_commands(0, {})
			_G.has_pythontestrun_cmd = cmds.PYTHONTestRun ~= nil
		end
	]])
	local has_cmd = child.lua_get('_G.has_pythontestrun_cmd')

	eq(has_cmd, true)
end

T['Python adapter']['gen_or_jump does not crash on empty buffer'] = function()
	child.lua([[
		vim.fn.bufadd('empty.py')
		vim.cmd('file empty.py')
		vim.bo.filetype = 'python'
		vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
	]])

	expect.no_error(function()
		child.lua([[require('tester.python').gen_or_jump()]])
	end)
end

T['Python adapter']['gen_or_jump handles function definition'] = function()
	child.lua([[
		vim.fn.bufadd('utils.py')
		vim.cmd('file utils.py')
		vim.bo.filetype = 'python'
		local code = [===[def calculate(x, y):
    return x + y
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
		vim.api.nvim_win_set_cursor(0, {2, 1})
	]])

	expect.no_error(function()
		child.lua([[require('tester.python').gen_or_jump()]])
	end)
end

T['Python adapter']['gen_or_jump handles method definition'] = function()
	child.lua([[
		vim.fn.bufadd('calculator.py')
		vim.cmd('file calculator.py')
		vim.bo.filetype = 'python'
		local code = [===[class Calculator:
    def add(self, a, b):
        return a + b
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
		vim.api.nvim_win_set_cursor(0, {3, 1})
	]])

	expect.no_error(function()
		child.lua([[require('tester.python').gen_or_jump()]])
	end)
end

T['Python adapter']['gen_or_jump handles decorated function'] = function()
	child.lua([[
		vim.fn.bufadd('decorators.py')
		vim.cmd('file decorators.py')
		vim.bo.filetype = 'python'
		local code = [===[@staticmethod
def static_func():
    pass
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
		vim.api.nvim_win_set_cursor(0, {3, 1})
	]])

	expect.no_error(function()
		child.lua([[require('tester.python').gen_or_jump()]])
	end)
end

T['Python adapter']['run does not crash on test file'] = function()
	child.lua([[
		vim.fn.bufadd('test_utils.py')
		vim.cmd('file test_utils.py')
		vim.bo.filetype = 'python'
		local code = [===[def test_calculate():
    assert calculate(1, 2) == 3
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
		vim.api.nvim_win_set_cursor(0, {2, 1})
	]])

	expect.no_error(function()
		child.lua([[require('tester.python').run({})]])
	end)
end

T['Python adapter']['run respects bang modifier'] = function()
	child.lua([[
		vim.fn.bufadd('test_utils.py')
		vim.cmd('file test_utils.py')
		vim.bo.filetype = 'python'
		local code = [===[def test_add():
    pass

def test_subtract():
    pass
]===]
		vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(code, '\n'))
	]])

	expect.no_error(function()
		child.lua([[require('tester.python').run({bang = true})]])
	end)
end

T['Python adapter']['config overrides work'] = function()
	child.lua([[
		require('tester.config').setup({
			languages = {
				python = {
					root_markers = { 'custom.pyproject.toml' }
				}
			}
		})
		local config = require('tester.config')
		_G.result = config.get().languages.python.root_markers
	]])

	eq(child.lua_get('_G.result'), { 'custom.pyproject.toml' })
end

return T
