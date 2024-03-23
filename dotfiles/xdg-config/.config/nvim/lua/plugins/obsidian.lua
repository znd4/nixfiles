return {
  "epwalsh/obsidian.nvim",
  version = "*", -- recommended, use latest release instead of latest commit
  -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
  cmd = {
    "ObsidianSearch",
    "ObsidianQuickSwitch",
    "ObsidianNew",
    "ObsidianOpen",
  },
  dependencies = {
    -- Required.
    "nvim-lua/plenary.nvim",

    -- for searching
    "nvim-telescope/telescope.nvim",

    -- for completion
    "hrsh7th/nvim-cmp",

    -- Optional, alternative to nvim-treesitter for syntax highlighting.
    "nvim-treesitter/nvim-treesitter",

    -- see below for full list of optional dependencies 👇
  },
  opts = {
    workspaces = {
      {
        name = "personal",
        path = vault_path,
      },
    },
  },
}
