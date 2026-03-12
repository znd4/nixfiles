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
    local file_browser = require('telescope').load_extension 'file_browser'
    require('telescope.builtin').file_browser = file_browser.file_browser

    -- Custom projects picker with worktree binding
    local function projects_with_worktree()
      local actions = require 'telescope.actions'
      local action_state = require 'telescope.actions.state'

      local create_worktree_in_project = function(prompt_bufnr)
        local selection = action_state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        if selection and selection.value then
          local project_path = selection.value
          vim.schedule(function()
            require('telescope').extensions.git_worktree.create_git_worktree { cwd = project_path }
          end)
        end
      end

      require('telescope').extensions.projects.projects {
        attach_mappings = function(_, map)
          map('i', '<C-w>', create_worktree_in_project)
          map('n', 'w', create_worktree_in_project)
          return true
        end,
      }
    end

    local wk = require 'which-key'
    wk.add({
      { "<leader>sp", projects_with_worktree, desc = '[S]earch [p]rojects' },
    })
  end,
  dependencies = {
    'nvim-telescope/telescope-file-browser.nvim',
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
    'folke/which-key.nvim',
    'ThePrimeagen/git-worktree.nvim',
  },
}
