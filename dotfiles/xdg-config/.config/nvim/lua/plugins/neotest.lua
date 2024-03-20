return {
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-neotest/neotest-python",
    "nvim-neotest/neotest-go",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    adapters = {
      require("neotest-python")({
        dap = { justMyCode = false },
      }),
      require("neotest-go")({
        dap = { justMyCode = false },
      }),
    },
  },
}
