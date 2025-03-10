return {
  'zk-org/zk-nvim',
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
