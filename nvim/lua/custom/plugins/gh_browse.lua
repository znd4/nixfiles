return {
  'nvim-lua/plenary.nvim',
  event = 'VeryLazy',
  dependencies = { 'nvim-lua/plenary.nvim' },
  init = function()
    local function get_cursor_position()
      local buf_name = vim.fn.expand '%'            -- Get full path of current buffer
      local cursor = vim.api.nvim_win_get_cursor(0) -- Get cursor position
      local line = cursor[1]                        -- Line number

      -- Concatenate the information
      local result = string.format('%s:%d', buf_name, line)

      return result
    end
    local Job = require 'plenary.job'

    vim.api.nvim_create_user_command("GHBrowse",
      function()
        local position = get_cursor_position()
        print("position")
        print(position)
        Job:new({
          command = 'gh',
          args = { 'browse', position },
          -- cwd = '/usr/bin',
          -- env = { ['a'] = 'b' },
          on_exit = function(j, return_val)
            print(return_val)
            for i, data in ipairs(j:result()) do
              print(data)
            end
          end,
        }):sync() -- or start()
      end,
      { desc = "open current line in github" }
    )
  end,
}
