vim.api.nvim_create_autocmd("FileType", {
	pattern = { "go", "python", "rust" },
	callback = function(args)
		local buf = args.buf
		local ft = args.match

		local ok, mod = pcall(require, "tester." .. ft)
		if not ok then
			vim.notify(string.format("[Tester] Failed to load module: %s", mod), vim.log.levels.ERROR)
			return
		end

		local test_cmd = vim.fn.toupper(ft) .. "TestRun"
		vim.api.nvim_buf_create_user_command(buf, vim.fn.toupper(ft) .. "Test", function()
			mod.gen_or_jump()
		end, { desc = "generate or jump to test" })

		vim.api.nvim_buf_create_user_command(buf, test_cmd, function(opts)
			mod.run(opts)
		end, { desc = "run current test function", bang = true })

	end,
})
