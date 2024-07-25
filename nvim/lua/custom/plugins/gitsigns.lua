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
      wk.register({
        ["]"] = {
          c = {
            function()
              if vim.wo.diff then
                vim.cmd.normal { ']c', bang = true }
              else
                gitsigns.nav_hunk("next")
              end
            end,
            "Jump to next [c]hange",
          }
        },
        ["["] = {
          c = {
            function()
              if vim.wo.diff then
                vim.cmd.normal { "[c", bang = true }
              else
                gitsigns.nav_hunk "prev"
              end
            end,
            "Jump to previous [c]hange",
          }
        },
      })
      wk.register({
        h = {
          s = { gitsigns.stage_hunk, 'git [s]tage hunk' },
          r = { gitsigns.reset_hunk, 'git [r]eset hunk' },
          S = { gitsigns.stage_buffer, 'git [S]tage buffer' },
          u = { gitsigns.undo_stage_hunk, 'git [u]ndo stage hunk' },
          R = { gitsigns.reset_buffer, 'git [R]eset buffer' },
          p = { gitsigns.preview_hunk, 'git [p]review hunk' },
          b = { gitsigns.blame_line, 'git [b]lame line' },
          d = { gitsigns.diffthis, 'git [d]iff against index' },
          D = {
            function()
              gitsigns.diffthis '@'
            end,
            'git [D]iff against last commit',
          },
        },
        t = {
          b = { gitsigns.toggle_current_line_blame, '[T]oggle git show [b]lame line' },
          D = { gitsigns.toggle_deleted, '[T]oggle git show [D]eleted' },
        },
      }, { prefix = '<leader>' })
      wk.register({
        h = {
          s = { function() gitsigns.stage_hunk { vim.fn.line('.'), vim.fn.line('v') } end, 'git [s]tage hunk' },
          r = { function() gitsigns.reset_hunk { vim.fn.line('.'), vim.fn.line('v') } end, 'git [r]eset hunk' },
        },
      }, { prefix = '<leader>', mode = 'v' })
    end,
  },
  dependencies = {
    'folke/which-key.nvim',
  },
}
