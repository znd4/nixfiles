return {
  "jsongerber/thanks.nvim",
  config = function()
    require("thanks").setup({
      plugin_manager = "lazy",
    })
  end,
}
