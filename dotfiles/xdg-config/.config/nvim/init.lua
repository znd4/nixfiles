require("env")
require("set")

vim.g.mapleader = " "

if os.getenv("NVIM_PYTHON") then
  vim.g.python3_host_prog = os.getenv("NVIM_PYTHON")
end

if vim.g.neovide ~= nil then
  print("changing directory to home")
  vim.cmd.cd()
end

require("colorscheme")

require("config.lazy")
vim.cmd.colorscheme("tokyonight")

require("neovide")
require("fonts")
require("mappings")
require("commands")

if vim.fn.executable("fd") ~= 1 then
  print("please brew install fd")
end
if vim.fn.executable("rg") ~= 1 then
  print("please brew install ripgrep")
end

require("filetype")
