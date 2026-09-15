return {
  'zk-org/zk-nvim',
  -- Keep eager loading. A `keys` table alone makes lazy.nvim defer `config`,
  -- which also defers the zk LSP auto_attach until the first keypress.
  lazy = false,
  keys = {
    -- Note-only commands (backlinks, links, insert link, new-from-selection)
    -- are buffer-local: see after/ftplugin/markdown.lua.
    { '<leader>zn', "<Cmd>ZkNew { title = vim.fn.input('Title: ') }<CR>", desc = '[Z]k [n]ew note' },
    { '<leader>zo', "<Cmd>ZkNotes { sort = { 'modified' } }<CR>", desc = '[Z]k [o]pen notes' },
    { '<leader>zt', '<Cmd>ZkTags<CR>', desc = '[Z]k [t]ags' },
    { '<leader>zf', "<Cmd>ZkNotes { sort = { 'modified' }, match = { vim.fn.input('Search: ') } }<CR>", desc = '[Z]k [f]ind in notes' },
    { '<leader>zf', ":'<,'>ZkMatch<CR>", mode = 'v', desc = '[Z]k [f]ind selection' },
    { '<leader>zB', '<Cmd>ZkBuffers<CR>', desc = '[Z]k open [B]uffers' },
    { '<leader>zc', '<Cmd>ZkCd<CR>', desc = '[Z]k [c]d to notebook' },
    { '<leader>zi', '<Cmd>ZkIndex<CR>', desc = '[Z]k re[i]ndex notebook' },
  },
  config = function()
    require('zk').setup {
      picker = 'telescope',
      -- See Setup section below
      lsp = {
        config = {
          cmd = { 'zk', 'lsp', '--log', '/tmp/zk-lsp.log' },
          name = 'zk',
          on_attach = function()
            require('blink.cmp').get_lsp_capabilities()
            -- key.nmap { 'gd', vim.lsp.buf.definition }
            -- keymaps()
          end,
        },
        -- automatically attach buffers in a zk notebook that match the given filetypes
        auto_attach = {
          enabled = true,
          filetypes = { 'markdown' },
        },
      },
    }
  end,
}
