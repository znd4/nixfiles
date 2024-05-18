return {
  'ahmedkhalf/project.nvim',
  config = function()
    -- local statepath = vim.fn.stdpath("state")
    local datapath = vim.fn.stdpath 'data'
    require('project_nvim').setup {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      ignore_lsp = { 'null-ls', 'terraform_lsp' },
      detection_methods = { 'pattern', 'lsp' },
      patterns = { '.git', '.hg', '.svn', 'package.json', 'go.mod', 'pyproject.toml' },
      show_hidden = true,
      datapath = datapath,
    }
    require('telescope').load_extension 'projects'
    local wk = require 'which-key'
    wk.register({
      s = {
        p = { ':Telescope projects<CR>', '[S]earch [p]rojects' },
      },
    }, { prefix = '<leader>' })
  end,
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'folke/which-key.nvim',
  },
}
