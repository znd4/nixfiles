local function get_current_branch()
  local Job = require 'plenary.job'
  local result = Job:new({
    command = 'git',
    args = { 'rev-parse', '--abbrev-ref', 'HEAD' },
    on_exit = function(j, return_val)
      return j:result()[1]
    end,
  }):sync()
  return result[1]
end

-- GLBrowse: Opens the current file or directory in GitLab.
--
-- This function intelligently constructs a GitLab URL based on the current context
-- in Neovim and opens it in the default web browser.
--
-- It handles:
--  - Parsing SSH and HTTPS git remote URLs.
--  - Opening the current directory view from an oil.nvim buffer.
--  - Opening a specific file to a line or line range from a standard buffer.
local function GLBrowse()
  -- Use plenary.path for robust path manipulation.
  local Path = require 'plenary.path'

  -- Helper function to execute a shell command and return its output.
  -- It trims leading/trailing whitespace from the result.
  local function get_cmd_output(cmd)
    local handle = io.popen(cmd)
    if not handle then
      return nil
    end
    local output = handle:read '*a'
    handle:close()
    -- Trim whitespace from the output for cleaner processing.
    return output:match '^%s*(.-)%s*$'
  end

  -- 1. Get the root directory of the git repository.
  local git_root = get_cmd_output 'git rev-parse --show-toplevel'
  if not git_root or git_root == '' then
    print 'Error: Not a git repository.'
    return
  end

  -- 2. Get the remote URL for 'origin'.
  local remote_url = get_cmd_output 'git config --get remote.origin.url'
  if not remote_url or remote_url == '' then
    print "Error: Could not get remote 'origin' URL."
    return
  end

  -- 3. Parse the remote URL to build a base HTTPS URL for GitLab.
  -- Handles two common formats:
  --   - SSH: git@gitlab.com:group/repo.git
  --   - HTTPS: https://gitlab.com/group/repo.git
  local base_url
  -- Check for SSH format and convert it.
  local ssh_match = remote_url:match 'git@(.-):(.*)%.git'
  if ssh_match then
    local domain, repo_path = remote_url:match 'git@(.-):(.*)%.git'
    base_url = 'https://' .. domain .. '/' .. repo_path
  -- Check for HTTPS format.
  elseif remote_url:match 'https?://' then
    base_url = remote_url:gsub('%.git$', '')
  else
    print('Error: Unsupported remote URL format: ' .. remote_url)
    return
  end

  -- Determine the system's open command
  local open_cmd
  if vim.fn.has 'macunix' then
    open_cmd = 'open'
  elseif vim.fn.has 'unix' then
    open_cmd = 'xdg-open'
  else
    print 'Error: Unsupported operating system for opening URLs.'
    return
  end

  -- 4. Handle different buffer types (oil.nvim vs. standard file).
  -- Check if the current buffer is an oil buffer.
  if vim.bo.filetype == 'oil' then
    -- For oil.nvim, get the current directory path.
    local oil_dir = require('oil').get_current_dir()
    if not oil_dir then
      print 'Error: Could not determine oil.nvim directory.'
      return
    end
    -- Make the path relative to the git root using plenary.path.
    local oil_path = Path:new(oil_dir)
    local relative_dir = oil_path:make_relative(git_root)
    -- Construct the URL to the directory tree.
    local final_url = base_url .. '/-/tree/main/' .. relative_dir
    print('Opening URL: ' .. final_url)
    vim.fn.system(open_cmd .. " '" .. final_url .. "'")
    return
  end

  -- Guard against running in non-file buffers (e.g., help, terminal, quickfix).
  if vim.bo.buftype ~= '' then
    print 'Error: Not a file buffer. Cannot open in GitLab.'
    return
  end

  -- 5. Handle standard file buffers.
  local file_path_str = vim.fn.expand '%:p' -- Get full path of the current buffer.
  if not file_path_str or file_path_str == '' then
    print 'Error: No file open in the current buffer.'
    return
  end

  -- Make the file path relative to the git root using plenary.path.
  local file_path = Path:new(file_path_str)
  -- Add a defensive check in case Path:new returns nil for an unexpected reason.
  if not file_path then
    print('Error: Could not create Path object for: ' .. file_path_str)
    return
  end
  local relative_path = file_path:make_relative(git_root)

  -- Get current mode to determine if we are selecting lines.
  local mode = vim.fn.mode()
  local line_anchor = ''

  if mode == 'n' then
    print 'normal mode'
    -- Normal mode: get the current cursor line.
    local line_num = vim.fn.line '.'
    line_anchor = '#L' .. line_num
  elseif mode == 'v' or mode == 'V' then
    print 'visual mode'
    -- Visual mode (line or character): get the start and end of the selection.
    local _, start_line, _, _ = unpack(vim.fn.getpos "'<")
    local _, end_line, _, _ = unpack(vim.fn.getpos "'>")
    print('start_line', start_line)
    print('end_line', end_line)
    if start_line and end_line and start_line ~= end_line then
      line_anchor = '#L' .. start_line .. '-' .. end_line
    elseif start_line then
      line_anchor = '#L' .. start_line
    end
  end

  -- Construct the final URL with the file path and line anchor.
  -- Assumes the default branch is 'main'. You could enhance this to dynamically find the default branch.
  local final_url = base_url .. '/-/blob/main/' .. relative_path .. line_anchor
  print('Opening URL: ' .. final_url)
  vim.fn.system(open_cmd .. " '" .. final_url .. "'")
end

return {
  'nvim-lua/plenary.nvim',
  event = 'VeryLazy',
  dependencies = { 'nvim-lua/plenary.nvim' },
  init = function()
    -- TODO: make this support ranges
    local function get_cursor_position()
      local buf_name = vim.fn.expand '%:.' -- Get full path of current buffer
      local cursor = vim.api.nvim_win_get_cursor(0) -- Get cursor position
      local line = cursor[1] -- Line number

      -- Concatenate the information
      local result = string.format('%s:%d', buf_name, line)

      return result
    end
    local Job = require 'plenary.job'

    -- To make this function available as a command in Neovim, you can add:
    vim.api.nvim_create_user_command('GLBrowse', GLBrowse, { range = '%' })
    vim.keymap.set({ 'n', 'v', 'V' }, '<leader>gl', GLBrowse, { desc = 'Open in GitLab', range = '%' })

    vim.api.nvim_create_user_command('GHBrowse', function()
      local position = get_cursor_position()
      print 'position'
      print(position)
      local args = { 'browse', position, '--branch', get_current_branch() }
      Job:new({
        command = 'gh',
        args = args,
        -- cwd = '/usr/bin',
        -- env = { ['a'] = 'b' },
        on_exit = function(j, return_val)
          print(return_val)
          for i, data in ipairs(j:result()) do
            print(data)
          end
        end,
      }):sync() -- or start()
    end, { desc = 'open current line in github' })
  end,
}
