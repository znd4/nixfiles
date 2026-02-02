return {
  'ThePrimeagen/git-worktree.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('git-worktree').setup {}
    require('telescope').load_extension 'git_worktree'

    vim.keymap.set('n', '<leader>sw', function()
      require('telescope').extensions.git_worktree.git_worktrees()
    end, { desc = '[S]earch [W]orktrees' })

    vim.keymap.set('n', '<leader>wn', function()
      require('telescope').extensions.git_worktree.create_git_worktree()
    end, { desc = '[W]orktree [N]ew' })
  end,
}
