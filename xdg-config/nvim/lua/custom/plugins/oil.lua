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
      ['gO'] = {
        desc = 'Open directory in file manager',
        callback = function()
          local oil = require 'oil'
          local dir = oil.get_current_dir()
          if dir then
            local cmd = vim.fn.has 'mac' == 1 and 'open' or 'xdg-open'
            vim.fn.system { cmd, dir }
          end
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
