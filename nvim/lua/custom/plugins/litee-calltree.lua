return {
  {
    'ldelossa/litee.nvim',
    event = 'VeryLazy',
    opts = {
      notify = { enabled = false },
      panel = {
        orientation = 'bottom',
        panel_size = 10,
      },
    },
    config = function(_, opts)
      require('litee.lib').setup(opts)
    end,
  },

  {
    'ldelossa/litee-calltree.nvim',
    dependencies = 'ldelossa/litee.nvim',
    event = 'VeryLazy',
    opts = {
      on_open = 'panel',
      map_resize_keys = false,
    },
    config = function(_, opts)
      require('litee.calltree').setup(opts)
      require('which-key').add {
        { '<M-h>', vim.lsp.buf.incoming_calls, desc = 'Incoming call tree' },
      }
    end,
  },
}
