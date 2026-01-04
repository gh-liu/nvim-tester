vim.api.nvim_create_autocmd("FileType", {
	pattern = { "go", "python" },
	callback = function(args)
		local buf = args.buf
		local ft = args.match

		local ok, mod = pcall(require, "tester." .. ft)
		if not ok then
			vim.notify(string.format("[Tester] Failed to load module: %s", mod), vim.log.levels.ERROR)
			return
		end

		vim.api.nvim_buf_create_user_command(buf, vim.fn.toupper(ft) .. "Test", function(opts)
			mod.gen_or_jump()
		end, { desc = "generate or jump to test" })

		vim.api.nvim_buf_create_user_command(buf, vim.fn.toupper(ft) .. "TestRun", function(opts)
			mod.run()
		end, { desc = "run current test function" })
	end,
})
