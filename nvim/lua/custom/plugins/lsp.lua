return {
  {
    'VonHeikemen/lsp-zero.nvim',
    branch = 'v3.x',
    lazy = true,
    config = false,
    init = function()
      -- Disable automatic setup, we are doing it manually
      vim.g.lsp_zero_extend_cmp = 0
      vim.g.lsp_zero_extend_lspconfig = 0
    end,
  },

  -- Autocompletion
  {
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      { 'L3MON4D3/LuaSnip' },
    },
    config = function()
      -- Here is where you configure the autocompletion settings.
      local lsp_zero = require 'lsp-zero'
      lsp_zero.extend_cmp()

      -- And you can configure cmp even more, if you want to.
      local cmp = require 'cmp'
      local cmp_action = lsp_zero.cmp_action()

      cmp.setup {
        formatting = lsp_zero.cmp_format { details = true },
        mapping = cmp.mapping.preset.insert {
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-u>'] = cmp.mapping.scroll_docs(-4),
          ['<C-d>'] = cmp.mapping.scroll_docs(4),
          ['<C-f>'] = cmp_action.luasnip_jump_forward(),
          ['<C-b>'] = cmp_action.luasnip_jump_backward(),
        },
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
      }
    end,
  },

  -- LSP
  {
    'neovim/nvim-lspconfig',
    cmd = 'LspInfo',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      { 'hrsh7th/cmp-nvim-lsp' },
    },
    config = function()
      -- This is where all the LSP shenanigans will live
      local lsp_zero = require 'lsp-zero'
      lsp_zero.extend_lspconfig()

      lsp_zero.on_attach(function(client, bufnr)
        -- see :help lsp-zero-keybindings
        -- to learn the available actions
        local opts = { buffer = bufnr }
        require('which-key').register({
          g = {
            d = { vim.lsp.buf.definition, '[g]o to [d]efinition' },
            D = { vim.lsp.buf.declaration, '[g]o to [D]eclaration' },
            i = { vim.lsp.buf.implementation, '[g]o to [i]mplementation' },
            o = { vim.lsp.buf.type_definition, '[G][o] to type definition' },
            r = { vim.lsp.buf.references, '[G]o to [r]eferences' },
            s = { vim.lsp.buf.signature_help, '[G]o to [s]ignature' },
            l = { vim.lsp.buf.open_float, '[G]o to f[l]oat' },
          },
          K = { vim.lsp.buf.hover, 'Hover' },
          ['<F2>'] = { vim.lsp.buf.rename, 'Rename' },
          ['<F4>'] = { vim.lsp.buf.code_action, 'Code actions' },
          ['[d'] = { vim.diagnostic.goto_prev, 'previous diagnostic' },
          [']d'] = { vim.diagnostic.goto_next, 'next diagnostic' },
        }, { buffer = bufnr })
        require('which-key').register({
          ['<F3>'] = { ':lua vim.lsp.buf.format({async=true})<cr>', 'format buffer' },
        }, { buffer = bufnr, mode = { 'n', 'x' } })
      end)

      -- (Optional) Configure lua language server for neovim
      local lua_opts = lsp_zero.nvim_lua_ls()
      require('lspconfig').lua_ls.setup(lua_opts)
      lsp_zero.configure('yamlls', {
        settings = {
          yaml = {
            schemas = {
              ['https://json.schemastore.org/github-workflow.json'] = '/.github/workflows/*',
            },
          },
        },
      })
      lsp_zero.configure('helm_ls', {
        settings = {
          ['helm-ls'] = {
            yamlls = {
              path = 'yaml-language-server',
            },
          },
        },
        filetypes = { 'gotmpl', 'helm' },
      })
      lsp_zero.setup_servers {
        'basedpyright',
        'gopls',
        'tilt_ls',
      }
    end,
  },
}
