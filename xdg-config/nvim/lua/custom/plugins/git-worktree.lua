return {
  'ThePrimeagen/git-worktree.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('git-worktree').setup {}
    require('telescope').load_extension 'git_worktree'

    -- Custom worktree picker that filters out the current worktree and adds file search bindings
    local function git_worktrees_custom()
      local pickers = require 'telescope.pickers'
      local finders = require 'telescope.finders'
      local conf = require('telescope.config').values
      local actions = require 'telescope.actions'
      local action_state = require 'telescope.actions.state'
      local strings = require 'plenary.strings'
      local utils = require 'telescope.utils'
      local git_worktree = require 'git-worktree'

      local output = utils.get_os_command_output { 'git', 'worktree', 'list' }
      local cwd = vim.fn.getcwd()
      local results = {}
      local widths = { path = 0, sha = 0, branch = 0 }

      for _, line in ipairs(output) do
        local fields = vim.split(string.gsub(line, '%s+', ' '), ' ')
        local entry = { path = fields[1], sha = fields[2], branch = fields[3] }
        -- Filter out bare repos and the current worktree
        if entry.sha ~= '(bare)' and vim.fn.fnamemodify(entry.path, ':p') ~= vim.fn.fnamemodify(cwd, ':p') then
          for key, val in pairs(widths) do
            widths[key] = math.max(val, strings.strdisplaywidth(entry[key] or ''))
          end
          table.insert(results, entry)
        end
      end

      if #results == 0 then
        vim.notify('No other worktrees found', vim.log.levels.INFO)
        return
      end

      local displayer = require('telescope.pickers.entry_display').create {
        separator = ' ',
        items = { { width = widths.branch }, { width = widths.path }, { width = widths.sha } },
      }

      local make_display = function(entry)
        return displayer {
          { entry.branch, 'TelescopeResultsIdentifier' },
          { entry.path },
          { entry.sha },
        }
      end

      local switch_worktree = function(prompt_bufnr)
        local selection = action_state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        if selection then
          git_worktree.switch_worktree(selection.path)
        end
      end

      local switch_and_find_files = function(prompt_bufnr)
        local selection = action_state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        if selection then
          git_worktree.switch_worktree(selection.path)
          vim.schedule(function()
            require('telescope.builtin').find_files { cwd = selection.path }
          end)
        end
      end

      local switch_and_live_grep = function(prompt_bufnr)
        local selection = action_state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        if selection then
          git_worktree.switch_worktree(selection.path)
          vim.schedule(function()
            require('telescope.builtin').live_grep { cwd = selection.path }
          end)
        end
      end

      pickers
        .new({}, {
          prompt_title = 'Git Worktrees',
          finder = finders.new_table {
            results = results,
            entry_maker = function(entry)
              entry.value = entry.branch
              entry.ordinal = entry.branch
              entry.display = make_display
              return entry
            end,
          },
          sorter = conf.generic_sorter {},
          attach_mappings = function(_, map)
            actions.select_default:replace(switch_worktree)
            map('i', '<C-f>', switch_and_find_files)
            map('n', '<C-f>', switch_and_find_files)
            map('i', '<C-s>', switch_and_live_grep)
            map('n', '<C-s>', switch_and_live_grep)
            return true
          end,
        })
        :find()
    end

    vim.keymap.set('n', '<leader>sw', git_worktrees_custom, { desc = '[S]earch [W]orktrees' })

    vim.keymap.set('n', '<leader>wn', function()
      require('telescope').extensions.git_worktree.create_git_worktree()
    end, { desc = '[W]orktree [N]ew' })
  end,
}
