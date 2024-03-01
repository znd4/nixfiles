return {
  "tpope/vim-fugitive",
  dependencies = { "tpope/vim-rhubarb" },
  cmd = "G",
  keys = {
    { "<leader>gp", ":G pull<CR>" },
    { "<leader>gs", ":G<CR>" },
    { "<leader>gP", ":G push<CR>" },
    { "<leader>gc", ":G commit<CR>" },
  },
}
