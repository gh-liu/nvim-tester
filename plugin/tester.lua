vim.api.nvim_create_autocmd("FileType", {
	pattern = { "go" },
	callback = function(args)
		local buf = args.buf
		local ft = args.match
		local mod = require("tester." .. ft)
		vim.api.nvim_buf_create_user_command(buf, vim.fn.toupper(ft) .. "Test", function(opts)
			mod.gen_or_jump()
		end, { desc = "generate or jump to test" })
	end,
})
