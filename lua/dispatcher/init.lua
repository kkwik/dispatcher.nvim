local M = {}

M.default_config = {
	check_on_startup = false,
	patched_plugins = {},
}

M.setup = function(cfg)
	if vim.fn.executable("git") == 0 then
		print("Dispatcher: git not available, aborting")
		return
	end

	M.config = vim.tbl_deep_extend("force", M.default_config, cfg)
end

return M
