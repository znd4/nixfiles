-- Create a mapping for the VS Code function
vim.keymap.set('n', '<leader>code', require('vscode').open_in_vscode, { noremap = true, silent = true })
