local G = {}

-- List of valid actions
local git_actions = {
	{
		name = "patch",
		generator = function(plugin_data)
			return { "git", "-C", plugin_data.target_path, "apply" }
		end,
	},
	{
		name = "unpatch",
		generator = function(plugin_data)
			return { "git", "-C", plugin_data.target_path, "apply", "--reverse" }
		end,
	},
	{
		name = "status",
		generator = function(plugin_data)
			return { "git", "-C", plugin_data.target_path, "apply", "--reverse", "--check" }
		end,
	},
}
-- Allow indexing by name
setmetatable(git_actions, {
	__index = function(self, desired_action_name)
		if type(desired_action_name) ~= "string" then
			return nil
		end

		for _, action in ipairs(self) do
			if action.name == desired_action_name then
				return action
			end
		end
		return nil
	end,
})

---@param plugin_data PluginData
---@param git_action_name "patch" | "unpatch" | "status"
---@param sort_reverse boolean
---@return PluginOperationResult
G.apply_git_action_to_plugin = function(plugin_data, git_action_name, sort_reverse)
	local git_action = git_actions[git_action_name]
	if git_action == nil then
		vim.notify("Dispatcher: invalid git action {" .. git_action_name .. "}")
		return
	end

	local patches = vim.fn.deepcopy(plugin_data.source_paths)

	if sort_reverse then
		table.sort(patches)
	else
		table.sort(patches, function(a, b)
			return a > b
		end)
	end

	-- Setup return object
	---@type PluginOperationResult
	local git_apply_results = {
		name = plugin_data.name,
		results = {},
	}
	for _, patch in ipairs(patches) do
		git_apply_results.results[patch] = nil
	end

	for _, patch in ipairs(patches) do
		local command = vim.fn.deepcopy(git_action.generator(plugin_data))
		table.insert(command, patch)

		local result_code = vim.system(command):wait()
		git_apply_results.results[patch] = result_code.code == 0
	end

	return git_apply_results
end

return G
