return {
  "stevearc/oil.nvim",
  config = {
    view_options = {
      show_hidden = true,
    },
  },
  event = "LazyDone",
  keys = {
    {
      "-",
      function()
        require("oil").open()
      end,
      desc = "Open parent directory in oil",
    },
  },
  -- Optional dependencies
  dependencies = { "nvim-tree/nvim-web-devicons" },
}
