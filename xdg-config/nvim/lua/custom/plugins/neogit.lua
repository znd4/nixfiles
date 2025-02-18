return {
  'NeogitOrg/neogit',
  dependencies = {
    'nvim-lua/plenary.nvim',  -- required
    'sindrets/diffview.nvim', -- optional - Diff integration

    -- Only one of these is needed, not both.
    'nvim-telescope/telescope.nvim', -- optional
    'ibhagwan/fzf-lua',              -- optional
    'folke/which-key.nvim',
  },
  event = 'VeryLazy',
  init = function()
    local wk = require 'which-key'
    wk.add({
      { "<leader>gP", ":Neogit push<CR>",   desc = "Git Push" },
      { "<leader>gc", ":Neogit commit<CR>", desc = "Git Commit" },
      { "<leader>gp", ":Neogit pull<CR>",   desc = "Git Pull" },
      { "<leader>gs", ":Neogit<CR>",        desc = "Open Git (fugitive)" },
    })
  end,
  config = true,
}
