return {
  "lewis6991/gitsigns.nvim",
  dependencies = {
    "folke/which-key.nvim",
  },
  init = function()
    require("which-key").register({
      g = {
        a = {
          function()
            vim.cmd.Gitsigns("stage_hunk")
          end,
          "Stage current hunk",
        },
        A = {
          function()
            vim.cmd.Gitsigns("stage_buffer")
          end,
          "Stage entire buffer",
        },
      },
    }, { prefix = "<leader>" })
    require("which-key").register({
      ["]c"] = {
        function()
          vim.cmd.Gitsigns("next_hunk")
        end,
        "Jump to next hunk",
      },
      ["[c"] = {
        function()
          vim.cmd.Gitsigns("prev_hunk")
        end,
        "Jump to previous hunk",
      },
    })
  end,
  config = function()
    require("gitsigns").setup({
      current_line_blame = true,
    })
    require("scrollbar.handlers.gitsigns").setup()
  end,
  priority = 101,
}
