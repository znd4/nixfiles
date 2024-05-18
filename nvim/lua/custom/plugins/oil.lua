return {
  'stevearc/oil.nvim',
  opts = {},
  lazy = false,
  keys = {
    {
      '-',
      '<cmd>Oil<CR>',
      desc = 'open parent directory',
    },
  },
  -- Optional dependencies
  dependencies = { 'nvim-tree/nvim-web-devicons' },
}
