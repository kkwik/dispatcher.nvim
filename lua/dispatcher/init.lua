local M = {}

---
--- Types, Config, Setup
---

---@class (exact) PluginData
---@field name string
---@field target_path string
---@field source_paths string[]

---@class (exact) GitOperationResult
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

	if vim.fn.isdirectory(M.config.patches_directory) == 0 then
		vim.notify(
			"Dispatcher: could not find configured patches directory {" .. M.config.patches_directory .. "}",
			vim.log.levels.WARN
		)
		return
	end

	if vim.fn.isdirectory(M.config.plugin_directory) == 0 then
		vim.notify(
			"Dispatcher: could not find configured plugin directory {" .. M.config.plugin_directory .. "}",
			vim.log.levels.WARN
		)
		return
	end

	---@type PluginData[]
	M.patched_plugins = M.setup_plugin_data()
end

---@return PluginData[]
M.setup_plugin_data = function()
	local return_data = {}
	for _, plugin_patch_dir in ipairs(M.get_plugin_patch_directories()) do
		local plugin_name = M.basename(plugin_patch_dir)
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

---
--- Utility Functions
---

---@param path string
---@return string[]
M.get_dir_children = function(path)
	return vim.fn.glob(path .. "/*", false, true)
end

---@return string[]
M.get_plugin_patch_directories = function()
	return M.get_dir_children(M.config.patches_directory)
end

---@param path string
---@return string
M.basename = function(path)
	return path:sub(path:find("/[^/]*$") + 1)
end

---
--- Display
---

M.create_patch_window = function(window_title)
	local win_width = vim.fn.winwidth(0)
	local win_height = vim.fn.winheight(0)
	local editor_width = vim.opt.columns._value
	local left_start = (editor_width - win_width) / 2
	local margin = 4

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = margin,
		col = left_start + margin,
		width = win_width - (2 * margin),
		height = win_height - (2 * margin),
		style = "minimal",
		border = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
		title = window_title,
	})

	return buf
end

---@param operation_result GitOperationResult
---@returns table
M.git_op_result_to_table = function(operation_result)
	local lines = {}
	table.insert(lines, operation_result.name)

	for patch, status in pairs(operation_result.results) do
		local status_text = ""

		if status == nil then
			status_text = "not run"
		elseif status == true then
			status_text = "success"
		else
			status_text = "failed"
		end

		table.insert(lines, M.basename(patch) .. ": " .. status_text)
	end

	return lines
end

---@param operation_results GitOperationResult[]
---@returns table
M.list_of_git_ops_result_to_table = function(operation_results)
	local lines = {}

	for _, result in ipairs(operation_results) do
		local result_lines = M.git_op_result_to_table(result)

		for _, line in ipairs(result_lines) do
			table.insert(lines, line)
		end
		table.insert(lines, "")
	end

	return lines
end

---@param operation_results GitOperationResult[]
M.show_results = function(operation_results, window_title)
	local buf = M.create_patch_window(window_title)
	vim.api.nvim_buf_set_lines(buf, 0, 0, false, M.list_of_git_ops_result_to_table(operation_results))
end

---
--- Application Helpers
---

---@param plugin_data PluginData
---@param git_op string[]
---@param sort_reverse boolean
---@return GitOperationResult
M.apply_git_op_to_plugin = function(plugin_data, git_op, sort_reverse)
	local patches = vim.fn.deepcopy(plugin_data.source_paths)

	if sort_reverse then
		table.sort(patches)
	else
		table.sort(patches, function(a, b)
			return a > b
		end)
	end

	---@type GitOperationResult
	local git_apply_results = {
		name = plugin_data.name,
		results = {},
	}

	for _, patch in ipairs(patches) do
		git_apply_results.results[patch] = nil
	end

	for _, patch in ipairs(patches) do
		local command = vim.fn.deepcopy(git_op)
		table.insert(command, patch)

		local result_code = vim.system(command):wait()
		git_apply_results.results[patch] = result_code.code == 0
	end

	return git_apply_results
end

---@param f fun(PluginData): GitOperationResult
---@return GitOperationResult[]
M.map_over_all_plugins = function(f)
	---@type GitOperationResult[]
	local results = {}

	for _, plugin in ipairs(M.patched_plugins) do
		local application_result = f(plugin)
		table.insert(results, application_result)
	end

	return results
end

---
--- Apply Patches
---

---@param plugin_data PluginData
---@return GitOperationResult
M.apply_plugin_patches = function(plugin_data)
	return M.apply_git_op_to_plugin(plugin_data, { "git", "-C", plugin_data.target_path, "apply" }, false)
end

---@return GitOperationResult[]
M.apply_all_patches = function()
	return M.map_over_all_plugins(M.apply_plugin_patches)
end

---
--- Reset Patches
---

---@param plugin_data PluginData
---@return GitOperationResult
M.reset_plugin_patches = function(plugin_data)
	return M.apply_git_op_to_plugin(plugin_data, { "git", "-C", plugin_data.target_path, "apply", "--reverse" }, true)
end

---@return GitOperationResult[]
M.reset_all_patches = function()
	return M.map_over_all_plugins(M.reset_plugin_patches)
end

---
--- Check Patches
---

---@param plugin_data PluginData
---@return GitOperationResult
M.plugin_patches_applied = function(plugin_data)
	return M.apply_git_op_to_plugin(
		plugin_data,
		{ "git", "-C", plugin_data.target_path, "apply", "--reverse", "--check" },
		false
	)
end

---@return GitOperationResult[]
M.all_plugin_patches_applied = function()
	return M.map_over_all_plugins(M.plugin_patches_applied)
end

return M
