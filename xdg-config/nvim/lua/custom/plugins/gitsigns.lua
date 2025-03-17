return {
  'lewis6991/gitsigns.nvim',
  opts = {
    current_line_blame = true,
    current_line_blame_opts = {
      delay = 500,
    },
    on_attach = function(bufnr)
      local wk = require 'which-key'
      local gitsigns = require 'gitsigns'
      wk.add {
        {
          ']c',
          function()
            if vim.wo.diff then
              vim.cmd.normal { ']c', bang = true }
            else
              gitsigns.nav_hunk 'next'
            end
          end,
          desc = 'Jump to next [c]hange',
        },
        {
          '[c',
          function()
            if vim.wo.diff then
              vim.cmd.normal { '[c', bang = true }
            else
              gitsigns.nav_hunk 'prev'
            end
          end,
          desc = 'Jump to previous [c]hange',
        },
      }
      wk.add {
        {
          '<leader>hs',
          gitsigns.stage_hunk,
          desc = 'git [s]tage hunk',
        },
        {
          '<leader>hs',
          gitsigns.stage_hunk,
          desc = 'git [s]tage hunk',
        },
        {
          '<leader>hr',
          gitsigns.reset_hunk,
          desc = 'git [r]eset hunk',
          mode = { 'v', 'n' },
        },
        {
          '<leader>hS',
          gitsigns.stage_buffer,
          desc = 'git [S]tage buffer',
          mode = { 'v', 'n' },
        },
        {
          '<leader>hu',
          gitsigns.undo_stage_hunk,
          desc = 'git [u]ndo stage hunk',
        },
        {
          '<leader>hR',
          gitsigns.reset_buffer,
          desc = 'git [R]eset buffer',
        },
        {
          '<leader>hp',
          gitsigns.preview_hunk,
          desc = 'git [p]review hunk',
        },
        {
          '<leader>hb',
          gitsigns.blame_line,
          desc = 'git [b]lame line',
        },
        {
          '<leader>hd',
          gitsigns.diffthis,
          desc = 'git [d]iff against index',
        },
        {
          '<leader>hD',
          function()
            gitsigns.diffthis '@'
          end,
          desc = 'git [D]iff against last commit',
        },
        {
          '<leader>tb',
          gitsigns.toggle_current_line_blame,
          desc = 'git [T]oggle git show [b]lame line',
        },
        {
          '<leader>td',
          gitsigns.toggle_deleted,
          desc = 'git [T]oggle git show [D]eleted',
        },
      }
    end,
  },
  dependencies = {
    'folke/which-key.nvim',
  },
}
