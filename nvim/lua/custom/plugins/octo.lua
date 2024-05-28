return {
  'pwntester/octo.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
    -- OR 'ibhagwan/fzf-lua',
    'nvim-tree/nvim-web-devicons',
    'folke/which-key.nvim',
  },
  init = function()
    require('which-key').register({
      s = {
        o = { '<cmd>Octo actions<cr>', 'Octo actions' },
      },
    }, { prefix = '<leader>' })
  end,
  config = true,
}
