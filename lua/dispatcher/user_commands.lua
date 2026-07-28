local U = {}

local user_commands = {
	{ name = "patch", func = U.patch_user_command, nargs = "?" },
	{ name = "unpatch", func = U.unpatch_user_command, nargs = "?" },
}
-- Allow indexing by name
setmetatable(user_commands, {
	__index = function(self, desired_cmd_name)
		if type(desired_cmd_name) ~= "string" then
			return nil
		end

		for _, command in ipairs(self) do
			if command.name == desired_cmd_name then
				return command
			end
		end
		return nil
	end,
})

U.setup_user_commands = function()
	vim.api.nvim_create_user_command(
		"Dispatcher",
		U.handle_user_commands,
		{ desc = "Run Dispatcher commands", nargs = "*" }
	)
end

U.handle_user_commands = function(opts)
	local provided_args = opts.fargs

	if #provided_args == 0 then
		vim.notify("Dispatcher: no subcommand given")
	else
		local desired_user_command = provided_args[1]
		local command = user_commands[desired_user_command]

		if command == nil then
			vim.notify("Dispatcher: attempted to call unknown command {" .. desired_user_command .. "}")
			return nil
		end
		vim.notify(tostring(vim.inspect(command)))

		if command.nargs == "?" then
			command.func(provided_args[2]) -- Second arg or nil
		else
			vim.notify("Dispatcher: using nargs value that isn't implemented yet, oops")
			return
		end
	end
end

---@param plugin_name string?
U.patch_user_command = function(plugin_name)
	if plugin_name == nil then
		M.apply_all_patches()
		return
	else
		local plugin_data = M.get_plugin_data(plugin_name)

		if plugin_data == nil then
			vim.notify("Dispatcher: failed to find plugin {" .. plugin_name .. "}")
			return
		end

		local result = M.apply_plugin_patches(plugin_data)
		if result.results == false then
			vim.notify("Dispatcher: failed to patch plugin {" .. plugin_name("}"))
		end
	end
end

---@param plugin_name string?
U.unpatch_user_command = function(plugin_name)
	if plugin_name == nil then
		M.reset_all_patches()
		return
	else
		local plugin_data = M.get_plugin_data(plugin_name)

		if plugin_data == nil then
			vim.notify("Dispatcher: failed to find plugin {" .. plugin_name .. "}")
			return
		end

		local result = M.reset_plugin_patches(plugin_data)
		if result.results == false then
			vim.notify("Dispatcher: failed to reset plugin {" .. plugin_name("}"))
		end
	end
end

return U
