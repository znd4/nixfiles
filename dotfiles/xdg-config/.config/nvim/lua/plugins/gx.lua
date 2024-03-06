-- if the current neovim version is 0.10.0 or greater, then return nothing
if vim.fn.has("nvim-0.10.0") == 1 then
  print("gx.nvim: neovim version is 0.10.0 or greater, skipping setup")
  return
end

return {
  "chrishrb/gx.nvim",
  keys = {
    { "gx", "<cmd>Browse<cr>", mode = { "n", "x" } },
  },
  cmd = { "Browse" },
  init = function()
    vim.g.netrw_nogx = 1
  end,
  dependencies = { "nvim-lua/plenary.nvim" },
  config = true, -- default settings
  submodules = false,
}
