return {
  "tpope/vim-fugitive",
  dependencies = { "tpope/vim-rhubarb" },
  cmd = "G",
  keys = {
    { "<leader>gp", [[lua vim.cmd.G("pull")]] },
    { "<leader>gs", [[lua vim.cmd.G()]] },
    { "<leader>gP", [[lua vim.cmd.G("push")]] },
    { "<leader>gc", [[lua vim.cmd.G("commit")]] },
  },
}
