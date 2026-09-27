return {
  'epwalsh/obsidian.nvim',
  version = 'v3.9.0', -- recommended, use latest release instead of latest commit
  lazy = true,
  ft = 'markdown',
  -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
  -- event = {
  --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
  --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/**.md"
  --   "BufReadPre path/to/my-vault/**.md",
  --   "BufNewFile path/to/my-vault/**.md",
  -- },
  -- obsidian.nvim warns on BufEnter of a vault note when conceallevel is 0.
  -- FileType fires before BufEnter, so set it here for vault markdown buffers.
  init = function()
    local vault = vim.fn.resolve(vim.fn.expand '~/Documents/obsidian-gtd-main')
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('ObsidianConceal', { clear = true }),
      pattern = 'markdown',
      callback = function(ev)
        local path = vim.fn.resolve(vim.api.nvim_buf_get_name(ev.buf))
        if vim.startswith(path, vault .. '/') then
          vim.opt_local.conceallevel = 2
        end
      end,
    })
  end,
  dependencies = {
    -- Required.
    'nvim-lua/plenary.nvim',

    -- see below for full list of optional dependencies 👇
  },
  keys = {
    {
      '<leader>od',
      '<cmd>ObsidianToday<cr>',
      desc = 'Obsidian Daily note',
    },
  },
  opts = {
    workspaces = {
      {
        name = 'personal',
        path = '~/Documents/obsidian-gtd-main',
      },
      -- {
      --   name = 'work',
      --   path = '~/vaults/work',
      -- },
    },

    -- see below for full list of options 👇
  },
}
