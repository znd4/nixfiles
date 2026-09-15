-- zk keymaps for markdown files that are inside a zk notebook.
-- notebook_root returns nil elsewhere, so ordinary markdown keeps stock keys.
-- pcall guards the first run after a clean checkout, before lazy.nvim has
-- installed zk-nvim: without it every markdown buffer opens with an error.
local ok, zk_util = pcall(require, 'zk.util')
if not ok or zk_util.notebook_root(vim.fn.expand '%:p') == nil then
  return
end

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { buffer = 0, silent = false, desc = desc })
end

-- Shadows the global <leader>zn: in a note, put the new note in this note's
-- directory instead of the notebook root.
map('n', '<leader>zn', "<Cmd>ZkNew { dir = vim.fn.expand('%:p:h'), title = vim.fn.input('Title: ') }<CR>", '[Z]k [n]ew note here')

map('n', '<leader>zb', '<Cmd>ZkBacklinks<CR>', '[Z]k [b]acklinks')
map('n', '<leader>zl', '<Cmd>ZkLinks<CR>', '[Z]k outbound [l]inks')
map('n', '<leader>zk', '<Cmd>ZkInsertLink<CR>', '[Z]k insert lin[k]')

map('v', '<leader>zk', ":'<,'>ZkInsertLinkAtSelection<CR>", '[Z]k lin[k] selection')
map('v', '<leader>zK', ":'<,'>ZkInsertLinkAtSelection { matchSelected = true }<CR>", '[Z]k lin[K] selection, filtered')
map('v', '<leader>zN', ":'<,'>ZkNewFromTitleSelection { dir = vim.fn.expand('%:p:h') }<CR>", '[Z]k [N]ew note from selected title')
map('v', '<leader>zC', ":'<,'>ZkNewFromContentSelection { dir = vim.fn.expand('%:p:h'), title = vim.fn.input('Title: ') }<CR>", '[Z]k new note from selected [C]ontent')
