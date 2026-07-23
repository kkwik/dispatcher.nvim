local M = {}

---@class PluginData
---@field name string
---@field target_path string
---@field source_paths string[]

---@class GitOperationResult
---@field name string
---@field results { [string]: boolean? }

M.default_config = {
	check_on_startup = false,
	patches_directory = vim.fn.stdpath("config") .. "/patches",
	plugin_directory = vim.fn.stdpath("data") .. "/site/pack/core/opt",
}

M.setup = function(cfg)
	if vim.fn.executable("git") == 0 then
		print("Dispatcher: git not available, aborting")
		return
	end

	M.config = vim.tbl_deep_extend("force", M.default_config, cfg)

	---@type PluginData[]
	M.patched_plugins = M.setup_plugin_data()
end

---@return PluginData[]
M.setup_plugin_data = function()
	local function basename(path)
		return path:sub(path:find("/[^/]*$") + 1)
	end

	local return_data = {}
	for _, plugin_patch_dir in ipairs(M.get_plugin_patch_directories()) do
		local plugin_name = basename(plugin_patch_dir)
		local plugin_target_dir = M.config.plugin_directory .. "/" .. plugin_name

		if vim.fn.isdirectory(plugin_target_dir) then
			table.insert(return_data, {
				name = plugin_name,
				target_path = plugin_target_dir,
				source_paths = M.get_dir_children(plugin_patch_dir),
			})
		else
			vim.notify(
				"Dispatcher: patches exist for plugin "
					.. plugin_name
					.. " but the plugin was not found at "
					.. M.config.plugin_directory,
				vim.log.levels.WARN
			)
		end
	end

	return return_data
end

---@param path string
---@return string[]
M.get_dir_children = function(path)
	return vim.fn.glob(path .. "/*", false, true)
end

---@return string[]
M.get_plugin_patch_directories = function()
	return M.get_dir_children(M.config.patches_directory)
end

---@param plugin_data PluginData
M.apply_plugin_patches = function(plugin_data)
	local patches = vim.fn.deepcopy(plugin_data.source_paths)
	table.sort(patches)

	---@type GitOperationResult
	local git_apply_results = {
		name = plugin_data.name,
		results = {},
	}

	for _, patch in ipairs(patches) do
		git_apply_results.results[patch] = nil
	end

	for _, patch in ipairs(patches) do
		local result_code = vim.system({ "git", "-C", plugin_data.target_path, "apply", patch }):wait()
		git_apply_results.results[patch] = result_code == 0
	end

	return git_apply_results
end

M.apply_all_patches = function()
	---@type GitOperationResult[]
	local results = {}

	for _, plugin in ipairs(M.patched_plugins) do
		local plugin_apply_result = M.apply_plugin_patches(plugin)
		table.insert(results, plugin_apply_result)
	end

	return results
end

---@param plugin_data PluginData
---@return GitOperationResult
M.reset_plugin_patches = function(plugin_data)
	local patches = vim.fn.deepcopy(plugin_data.source_paths)
	table.sort(patches, function(a, b)
		return a > b
	end)

	---@type GitOperationResult
	local git_reset_results = {
		name = plugin_data.name,
		results = {},
	}

	for _, patch in ipairs(patches) do
		git_reset_results.results[patch] = nil
	end

	for _, patch in ipairs(patches) do
		local result_code = vim.system({ "git", "-C", plugin_data.target_path, "apply", "--reverse", patch }):wait()
		git_reset_results.results[patch] = result_code == 0
	end

	return git_reset_results
end

---@return GitOperationResult[]
M.reset_all_patches = function()
	---@type GitOperationResult[]
	local results = {}

	for _, plugin in ipairs(M.patched_plugins) do
		local plugin_reset_result = M.reset_plugin_patches(plugin)
		table.insert(results, plugin_reset_result)
	end

	return results
end

return M
