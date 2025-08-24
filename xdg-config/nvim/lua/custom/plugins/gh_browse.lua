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
    -- @param range (table, optional) A table with {start, finish} line numbers for a visual selection.
    local function GLBrowse(range)
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

      -- Helper function to parse remote URL to HTTPS format
      local function parse_remote_url(url)
        -- Handles SSH format: git@host:group/repo[.git]
        local domain, repo_path = url:match 'git@(.*):(.*)'
        if domain then
          -- Remove .git suffix if present
          repo_path = repo_path:gsub('%.git$', '')
          return 'https://' .. domain .. '/' .. repo_path
        end

        -- Handles HTTPS format
        if url:match 'https?://' then
          return url:gsub('%.git$', '')
        end

        return nil
      end

      -- 3. Parse the remote URL to build a base HTTPS URL.
      local base_url = parse_remote_url(remote_url)
      if not base_url then
        vim.notify('Error: Unsupported remote URL format: ' .. remote_url, vim.log.levels.ERROR)
        return
      end

      -- Determine the system's open command
      local open_cmd = vim.fn.has 'macunix' and 'open' or 'xdg-open'
      local current_branch = get_current_branch()
      
      -- Determine URL format based on domain
      local domain = base_url:match('https://([^/]+)')
      local is_github = domain == 'github.com' or domain:match('github%..*%.com$')
      local tree_path = is_github and '/tree/' or '/-/tree/'
      local blob_path = is_github and '/blob/' or '/-/blob/'

      -- 4. Handle oil.nvim buffers
      if vim.bo.filetype == 'oil' then
        local oil_dir = require('oil').get_current_dir()
        if oil_dir then
          local relative_dir = Path:new(oil_dir):make_relative(git_root)
          local final_url = base_url .. tree_path .. current_branch .. '/' .. relative_dir
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
      if range then
        -- If a range table is passed, we are in visual mode.
        if range.start and range.finish and range.start ~= range.finish then
          line_anchor = ('#L%d-%d'):format(range.start, range.finish)
        elseif range.start then
          line_anchor = ('#L%d'):format(range.start)
        end
      else
        -- If no range, we are in normal mode. Use the current cursor line.
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        line_anchor = ('#L%d'):format(line_num)
      end

      -- Construct the final URL with the file path and line anchor.
      local final_url = base_url .. blob_path .. current_branch .. '/' .. relative_path .. line_anchor
      vim.notify('Opening URL: ' .. final_url)
      Job:new({ command = open_cmd, args = { final_url } }):start()
    end

    -- Setup keymaps
    vim.keymap.set('n', '<leader>gb', function()
      -- In normal mode, call with no arguments.
      GLBrowse()
    end, { desc = 'Git: Browse current line' })

    vim.keymap.set('v', '<leader>gb', function()
      -- In visual mode, capture the marks *immediately* and pass them.
      local _, start_line = unpack(vim.fn.getpos "'<")
      local _, end_line = unpack(vim.fn.getpos "'>")
      GLBrowse { start = start_line, finish = end_line }
    end, { desc = 'Git: Browse visual selection' })
  end,
}
