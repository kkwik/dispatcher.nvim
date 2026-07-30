local M = {}
local G = require("dispatcher.git")

---
--- Types, Config, Setup
---

---@class (exact) PluginData
---@field name string
---@field target_path string
---@field source_paths string[]

---@class (exact) PluginOperationResult
---@field name string
---@field results { [string]: boolean? }

M.default_config = {
	check_on_startup = false,
	create_user_commands = true,
	patches_directory = vim.fn.stdpath("config") .. "/patches",
	plugin_directory = vim.fn.stdpath("data") .. "/site/pack/core/opt",
}

M.setup = function(cfg)
	if vim.fn.executable("git") == 0 then
		vim.notify("Dispatcher: git not available, aborting", vim.log.levels.ERROR)
		return
	end

	M.config = vim.tbl_deep_extend("force", M.default_config, cfg)

	if vim.fn.isdirectory(M.config.patches_directory) == 0 then
		vim.notify(
			"Dispatcher: could not find configured patches directory {" .. M.config.patches_directory .. "}",
			vim.log.levels.ERROR
		)
		return
	end

	if vim.fn.isdirectory(M.config.plugin_directory) == 0 then
		vim.notify(
			"Dispatcher: could not find configured plugin directory {" .. M.config.plugin_directory .. "}",
			vim.log.levels.ERROR
		)
		return
	end

	---@type PluginData[]
	M.patched_plugins = M.setup_plugin_data()

	if M.config.check_on_startup == true then
		if not M.all_plugin_patches_applied() then
			vim.notify("Not all plugins patched, run :Dispatcher status for details", vim.log.levels.WARN)
		end
	end

	if M.config.create_user_commands == true then
		require("dispatcher.user_commands")
	end
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

	-- Allow indexing by name
	setmetatable(return_data, {
		__index = function(self, desired_plugin_name)
			if type(desired_plugin_name) ~= "string" then
				return nil
			end

			for _, plugin in ipairs(self) do
				if plugin.name == desired_plugin_name then
					return plugin
				end
			end
			return nil
		end,
	})

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

---@param window_title string
---@return integer
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

---@param operation_result PluginOperationResult
---@return string[]
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

---@param operation_results PluginOperationResult[]
---@return string[]
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

---@param operation_results PluginOperationResult[]
---@param window_title string
M.show_results = function(operation_results, window_title)
	local buf = M.create_patch_window(window_title)
	vim.api.nvim_buf_set_lines(buf, 0, 0, false, M.list_of_git_ops_result_to_table(operation_results))
end

---
--- Application Helpers
---

---@param f fun(PluginData): PluginOperationResult
---@return any[]
M.map_over_all_plugins = function(f)
	---@type any[]
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
---@return PluginOperationResult
M.apply_plugin_patches = function(plugin_data)
	return G.apply_git_action_to_plugin(plugin_data, "patch", false)
end

---@return PluginOperationResult[]
M.apply_all_patches = function()
	return M.map_over_all_plugins(M.apply_plugin_patches)
end

---
--- Reset Patches
---

---@param plugin_data PluginData
---@return PluginOperationResult
M.reset_plugin_patches = function(plugin_data)
	return G.apply_git_action_to_plugin(plugin_data, "unpatch", true)
end

---@return PluginOperationResult[]
M.reset_all_patches = function()
	return M.map_over_all_plugins(M.reset_plugin_patches)
end

---
--- Check Patches
---

---@param plugin_data PluginData
---@return PluginOperationResult
M.plugin_patches_status = function(plugin_data)
	return G.apply_git_action_to_plugin(plugin_data, "status", false)
end

---@return PluginOperationResult[]
M.all_plugin_patches_status = function()
	return M.map_over_all_plugins(M.plugin_patches_status)
end

---@param plugin_data PluginData
---@return boolean
M.plugin_patches_applied = function(plugin_data)
	local git_op_results = M.plugin_patches_status(plugin_data)

	for _, value in pairs(git_op_results.results) do
		if value == false then
			return false
		end
	end

	return true
end

---@return boolean
M.all_plugin_patches_applied = function()
	local patches_applied = M.map_over_all_plugins(M.plugin_patches_applied)

	for _, value in ipairs(patches_applied) do
		if value == false then
			return false
		end
	end

	return true
end

return M
