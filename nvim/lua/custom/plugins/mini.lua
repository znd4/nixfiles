return {
  'echasnovski/mini.nvim',
  version = '*',
  vscode = true,
  config = function()
    require('mini.pairs').setup()
  end,
}
