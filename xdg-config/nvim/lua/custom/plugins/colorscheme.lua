local tokyonight = { -- You can easily change to a different colorscheme.
  -- Change the name of the colorscheme plugin below, and then
  -- change the command in the config to whatever the name of that colorscheme is.
  --
  -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
  'folke/tokyonight.nvim',
  priority = 1000, -- Make sure to load this before all the other start plugins.
  lazy = false,
  opts = {
    style = 'night',
    styles = {
      comments = { italic = true },
    },
  },
}

local starry = {
  'ray-x/starry.nvim',
  priority = 1000,
  init = function()
    vim.cmd.colorscheme 'mariana'
    -- vim.cmd.colorscheme 'moonlight'
    -- vim.cmd.colorscheme 'emerald'
  end,
  opts = {
    italics = {
      comments = true,
    },
  },
}

local evergarden = {
  'comfysage/evergarden',
  name = 'evergarden',
  priority = 1000,
  opts = {
    style = {
      comment = { italic = true },
    },
  },
}

local catppuccin = {
  'catppuccin/nvim',
  name = 'catppuccin',
  priority = 1000,
  opts = {
    styles = {
      comments = { 'italic' },
    },
    integrations = {
      cmp = true,
      gitsigns = true,
      treesitter = true,
      neogit = true,
      mini = {
        enabled = true,
      },
    },
  },
}
return starry
