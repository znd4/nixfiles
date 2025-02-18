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
    require('which-key').add({
      { "<leader>so", "<cmd>Octo actions<cr>", desc = "Octo actions" },
    })
  end,
  config = true,
}
