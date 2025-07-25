return {
  'nvim-lua/plenary.nvim',
  dependencies = { 'stevearc/oil.nvim' },
  config = function()
    local Path = require 'plenary.path'
    local Job = require 'plenary.job'

    ---Gets the current git branch name.
    -- @return (string) The branch name, defaulting to 'main'.
    local function get_current_branch()
      local result = Job:new({
        command = 'git',
        args = { 'rev-parse', '--abbrev-ref', 'HEAD' },
      }):sync()
      -- Return the first line of output, or 'main' if it fails
      return result and result[1] or 'main'
    end

    ---GLBrowse: Opens the current file or directory in GitLab/GitHub.
    -- @param is_visual (boolean, optional) A flag passed from the keymap to indicate if it was called from visual mode.
    local function GLBrowse(is_visual)
      -- Helper function to execute a shell command and return its output.
      local function get_cmd_output(cmd)
        local handle = io.popen(cmd)
        if not handle then
          return nil
        end
        local output = handle:read '*a'
        handle:close()
        -- Trim whitespace from the output for cleaner processing.
        return output and output:match '^%s*(.-)%s*$'
      end

      -- 1. Get the root directory of the git repository.
      local git_root = get_cmd_output 'git rev-parse --show-toplevel'
      if not git_root or git_root == '' then
        vim.notify('Error: Not a git repository.', vim.log.levels.ERROR)
        return
      end

      -- 2. Get the remote URL for 'origin'.
      local remote_url = get_cmd_output 'git config --get remote.origin.url'
      if not remote_url or remote_url == '' then
        vim.notify("Error: Could not get remote 'origin' URL.", vim.log.levels.ERROR)
        return
      end

      -- 3. Parse the remote URL to build a base HTTPS URL.
      local base_url
      -- Handles SSH format: git@host:group/repo.git
      local domain, repo_path = remote_url:match 'git@(.*):(.*)%.git$'
      if domain then
        base_url = 'https://' .. domain .. '/' .. repo_path
      -- Handles HTTPS format
      elseif remote_url:match 'https?://' then
        base_url = remote_url:gsub('%.git$', '')
      else
        vim.notify('Error: Unsupported remote URL format: ' .. remote_url, vim.log.levels.ERROR)
        return
      end

      -- Determine the system's open command
      local open_cmd = vim.fn.has 'macunix' and 'open' or 'xdg-open'
      local current_branch = get_current_branch()

      -- 4. Handle oil.nvim buffers
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

      -- 5. Handle standard file buffers.
      local file_path_str = vim.fn.expand '%:p'
      if not file_path_str or file_path_str == '' then
        vim.notify('Error: No file in buffer.', vim.log.levels.ERROR)
        return
      end

      local relative_path = Path:new(file_path_str):make_relative(git_root)

      -- Determine the line range for the URL anchor.
      local line_anchor = ''
      if is_visual then
        -- If called from visual mode, use the visual selection marks '< and '>
        local _, start_line = unpack(vim.fn.getpos "'<")
        local _, end_line = unpack(vim.fn.getpos "'>")
        if start_line and end_line and start_line ~= end_line then
          line_anchor = ('#L%d-%d'):format(start_line, end_line)
        elseif start_line then
          line_anchor = ('#L%d'):format(start_line)
        end
      else
        -- If called from normal mode, use the current cursor line.
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        line_anchor = ('#L%d'):format(line_num)
      end

      -- Construct the final URL with the file path and line anchor.
      local final_url = base_url .. '/-/blob/' .. current_branch .. '/' .. relative_path .. line_anchor
      vim.notify('Opening URL: ' .. final_url)
      Job:new({ command = open_cmd, args = { final_url } }):start()
    end

    -- Create user command (optional, but good practice)
    vim.api.nvim_create_user_command('GLBrowse', function()
      -- Check if the command was called with a range (from command line)
      if vim.v.count > 0 then
        GLBrowse(true)
      else
        GLBrowse(false)
      end
    end, {
      range = '%',
      desc = 'Open current file or selection in GitLab',
    })

    -- Setup keymaps
    vim.keymap.set('n', '<leader>gl', function()
      GLBrowse(false)
    end, { desc = 'GitLab: Browse current line' })
    vim.keymap.set('v', '<leader>gl', function()
      GLBrowse(true)
    end, { desc = 'GitLab: Browse visual selection' })
  end,
}
