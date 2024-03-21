return {
  "NeogitOrg/neogit",
  dependencies = {
    "nvim-lua/plenary.nvim", -- required
    "sindrets/diffview.nvim", -- optional - Diff integration

    -- Only one of these is needed, not both.
    "nvim-telescope/telescope.nvim", -- optional
    "ibhagwan/fzf-lua", -- optional
    "folke/which-key.nvim",
  },
  event = "VeryLazy",
  init = function()
    local wk = require("which-key")
    wk.register({
      g = {
        p = { ":Neogit pull<CR>", "Git Pull" },
        P = { ":Neogit push<CR>", "Git Push" },
        c = { ":Neogit commit<CR>", "Git Commit" },
        s = { ":Neogit open<CR>", "Open Git (fugitive)" },
      },
    }, { prefix = "<leader>" })
  end,
  config = true,
}
