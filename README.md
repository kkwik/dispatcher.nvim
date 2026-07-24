## Introduction

On occasion you may have a Neovim plugin you use, but find that you wish some aspect of it's behavior were different. If the plugin does not expose configuration for that behavior your options are to attempt to have the maintainer(s) upstream your change, maintain a fork of the plugin, or maintain patches against the upstream. This project is intended to be a minimal helper tool for the latter use case.

## Features

The functionality provided by this plugin is sparse.

1. Apply patches to plugins
2. Remove patches from plugins
3. Check whether patches are applied to plugins
4. Inform you if patches are not applied on startup (Optional)

> [!WARNING]
> Updating plugins while patched could have interesting and unintended interactions.
> Dispatcher.nvim applies patches to the working tree of the plugin's cloned repo.
> As of writing vim.pack will stash changes in the working tree before updating and will not pop them afterwards, effectively unpatching the plugins.
> How you deal with this is up to you, but I would recommend removing patches before updating.

## Installation

With vim.pack:

```lua
vim.pack.add({
	{ src = "https://github.com/kkwik/dispatcher.nvim" },
})
```

## Setup

```lua
require("dispatcher").setup({
-- Optional configuration goes here
})
```

### Default config

```lua
-- The default configuration used if not overriden in setup()
{
    -- Notify user via vim.notify() if any patches are not applied on startup
	check_on_startup = false,

    -- The directory where you store your patches
	patches_directory = vim.fn.stdpath("config") .. "/patches",

    -- The directory where your package manager stores plugins. Default assumes usage of vim.pack
	plugin_directory = vim.fn.stdpath("data") .. "/site/pack/core/opt",
}
```
