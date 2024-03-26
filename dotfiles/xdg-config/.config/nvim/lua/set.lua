-- set tabs to 4 spaces
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true

-- linux-specific settings
local uname_output = vim.fn.system("uname")
if uname_output:match("Linux") then
  vim.g.netrw_browsex_viewer = "xdg-open"
end

-- use system keyboard (I'm a scrub)
vim.o.clipboard = "unnamedplus"

-- show where my cursor is
vim.opt.cursorline = true

-- change splitting behavior
vim.opt.splitright = true
vim.opt.splitbelow = true

--preview substitutions live
vim.opt.inccommand = true

--enable editorconfig
vim.g.editorconfig = true

-- prettier line wrapping
vim.opt.breakindent = true

--enable .nvim.lua
vim.opt.exrc = true

-- set autoindent
vim.opt.smartindent = true

-- go away swapfiles
vim.opt.swapfile = false
vim.opt.undofile = true

-- line numbers
vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.confirm = true
vim.opt.hidden = true

vim.opt.mouse = "a"

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.colorcolumn = "100"

vim.opt.ignorecase = true
vim.opt.smartcase = true

-- configure folding to use treesitter
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
