return {
  'stevearc/oil.nvim',
  opts = {
    keymaps = {
      ['yp'] = {
        desc = 'Copy filepath to system clipboard',
        callback = function()
          require('oil.actions').copy_entry_path.callback()
          vim.fn.setreg('+', vim.fn.getreg(vim.v.register))
        end,
      },
    },
  },
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
