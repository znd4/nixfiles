return {
  -- This is a local plugin that depends on plenary and oil
  'nvim-lua/plenary.nvim',
  dependencies = { 'stevearc/oil.nvim' },
  config = function()
    local Path = require 'plenary.path'
    local Job = require 'plenary.job'

    ---Gets the current git branch name.
    -- @return (string) The branch name.
    local function get_current_branch()
      local result = Job:new({
        command = 'git',
        args = { 'rev-parse', '--abbrev-ref', 'HEAD' },
      }):sync()
      return result and result[1] or 'main'
    end

    ---Gets the git repository's root directory.
    -- @return (string|nil) The repo root path.
    local function get_git_root()
      local result = Job:new({
        command = 'git',
        args = { 'rev-parse', '--show-toplevel' },
      }):sync()
      return result and result[1]
    end

    ---Gets the git remote URL.
    -- @return (string|nil) The remote URL.
    local function get_remote_url()
      local result = Job:new({
        command = 'git',
        args = { 'config', '--get', 'remote.origin.url' },
      }):sync()
      return result and result[1]
    end

    ---Opens the current file or directory in GitLab.
    -- @param opts (table) Command options passed by nvim_create_user_command.
    local function GLBrowse(opts)
      local git_root = get_git_root()
      if not git_root then
        vim.notify('Error: Not a git repository.', vim.log.levels.ERROR)
        return
      end

      local remote_url = get_remote_url()
      if not remote_url then
        vim.notify("Error: Could not get remote 'origin' URL.", vim.log.levels.ERROR)
        return
      end

      -- Parse the remote URL to build a base HTTPS URL
      local base_url
      local ssh_match_domain, ssh_match_repo = remote_url:match 'git@(.*):(.*)%.git$'
      if ssh_match_domain then
        base_url = 'https://' .. ssh_match_domain .. '/' .. ssh_match_repo
      elseif remote_url:match 'https?://' then
        base_url = remote_url:gsub('%.git$', '')
      else
        vim.notify('Error: Unsupported remote URL format: ' .. remote_url, vim.log.levels.ERROR)
        return
      end

      -- Determine the system's open command
      local open_cmd = vim.fn.has 'macunix' and 'open' or 'xdg-open'
      local current_branch = get_current_branch()

      -- Handle oil.nvim buffers
      if vim.bo.filetype == 'oil' then
        local oil_dir = require('oil').get_current_dir()
        if oil_dir then
          local relative_dir = Path:new(oil_dir):make_relative(git_root)
          local final_url = base_url .. '/-/tree/' .. current_branch .. '/' .. relative_dir
          vim.notify('Opening URL: ' .. final_url)
          Job:new({ command = open_cmd, args = { final_url } }):start()
        end
        return
      end

      -- Guard against non-file buffers
      if vim.bo.buftype ~= '' then
        vim.notify('Error: Not a file buffer.', vim.log.levels.ERROR)
        return
      end

      local file_path_str = vim.fn.expand '%:p'
      if not file_path_str or file_path_str == '' then
        vim.notify('Error: No file in buffer.', vim.log.levels.ERROR)
        return
      end

      local relative_path = Path:new(file_path_str):make_relative(git_root)

      -- Determine the line range for the URL anchor from command options
      local line_anchor = ''
      if opts.range == 2 then -- Range was passed (visual selection)
        if opts.line1 ~= opts.line2 then
          line_anchor = ('#L%d-%d'):format(opts.line1, opts.line2)
        else
          line_anchor = ('#L%d'):format(opts.line1)
        end
      else -- No range, use current cursor position
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        line_anchor = ('#L%d'):format(line_num)
      end

      local final_url = base_url .. '/-/blob/' .. current_branch .. '/' .. relative_path .. line_anchor
      vim.notify('Opening URL: ' .. final_url)
      Job:new({ command = open_cmd, args = { final_url } }):start()
    end

    -- Create the user command
    vim.api.nvim_create_user_command('GLBrowse', GLBrowse, {
      range = '%',
      desc = 'Open current file or selection in GitLab',
    })
  end,
  keys = {
    {
      '<leader>gl',
      '<Cmd>GLBrowse<CR>',
      mode = { 'n', 'v' },
      desc = 'GitLab: Browse file or selection',
    },
  },
}
