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
        p = { require("neogit").pull, "Git Pull" },
        P = { require("neogit").push, "Git Push" },
        c = { require("neogit").commit, "Git Commit" },
        s = { require("neogit").open, "Open Git (fugitive)" },
      },
    }, { prefix = "<leader>" })
  end,
  config = true,
}
