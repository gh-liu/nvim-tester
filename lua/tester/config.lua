local M = {}

local defaults = {
	languages = {
		go = {
			root_markers = { "go.mod", ".git" },
		},
		python = {
			root_markers = { "pyproject.toml", "setup.py", ".git" },
		},
		rust = {
			root_markers = { "Cargo.toml", ".git" },
		},
	},
}

local user_config = nil
local merged_config = nil

local function normalize_user_config(cfg)
	if type(cfg) == "table" then
		return cfg
	end
	return {}
end

local function rebuild()
	local global_cfg = normalize_user_config(vim.g.tester)
	local local_cfg = normalize_user_config(user_config)
	merged_config = vim.tbl_deep_extend("force", {}, defaults, global_cfg, local_cfg)
end

function M.get()
	if not merged_config then
		rebuild()
	end
	return merged_config
end

function M.setup(cfg)
	user_config = cfg
	rebuild()
end

return M
