return {
  'nvim-lualine/lualine.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons', 'catppuccin/nvim' },
  opts = {
    options = {
      theme = 'catppuccin',
    },
    sections = {
      lualine_c = { { 'filename', path = 1 } },
    },
  },
}
