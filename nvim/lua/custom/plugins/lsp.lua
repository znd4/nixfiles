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
      { 'hrsh7th/nvim-cmp' },
      { "rafamadriz/friendly-snippets" },
      'saadparwaiz1/cmp_luasnip',

      -- Adds other completion capabilities.
      --  nvim-cmp does not ship with all sources by default. They are split
      --  into multiple repos for maintenance purposes.
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-path',
    },
    config = function()
      -- Here is where you configure the autocompletion settings.
      local lsp_zero = require 'lsp-zero'
      lsp_zero.extend_cmp()

      -- add friendly snippets to luasnip
      require("luasnip.loaders.from_vscode").lazy_load()

      -- And you can configure cmp even more, if you want to.
      local cmp = require 'cmp'
      local cmp_action = lsp_zero.cmp_action()
      local cmp_config = cmp.get_config()
      table.insert(cmp_config.sources, { name = "luasnip" })
      table.insert(cmp_config.sources, { name = "path" })
      table.insert(cmp_config.sources, { name = "nvim_lsp" })
      local luasnip = require("luasnip")
      cmp.setup {
        formatting = lsp_zero.cmp_format { details = true },
        mapping = cmp.mapping.preset.insert {
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-u>'] = cmp.mapping.scroll_docs(-4),
          ['<C-d>'] = cmp.mapping.scroll_docs(4),
          ['<C-f>'] = cmp_action.luasnip_jump_forward(),
          ['<C-b>'] = cmp_action.luasnip_jump_backward(),
          ['<C-n>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.choice_active() then
              luasnip.change_choice(1)
            else
              fallback()
            end
          end, { "i", "s" }),
          ['<C-p>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.choice_active() then
              luasnip.change_choice(-1)
            else
              fallback()
            end
          end, { "i", "s" })
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
            -- call hierarchy
            I = { vim.lsp.buf.incoming_calls, "[I]ncoming calls" },
            O = { vim.lsp.buf.outgoing_calls, "[O]utgoing calls" },
            l = { vim.diagnostic.open_float, "Open f[l]oat" },
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
        require('which-key').register({
          ["<C-k>"] = { vim.lsp.buf.signature_help, "View argument signature" },
        }, { buffer = bufnr, mode = { "i" } })
      end)

      -- (Optional) Configure lua language server for neovim
      local lua_opts = lsp_zero.nvim_lua_ls()
      require('lspconfig').lua_ls.setup(lua_opts)
      lsp_zero.configure('helm_ls', {
        settings = {
          ['helm-ls'] = {
            yamlls = {
              path = 'yaml-language-server',
            },
          },
        },
        -- filetypes = { 'gotmpl', 'helm' },
      })
      lsp_zero.configure('yamlls', {
        settings = {
          yaml = {
            schemas = {
              ['https://json.schemastore.org/github-workflow.json'] = '/.github/workflows/*',
            },
          },
        },
      })
      lsp_zero.configure("gopls", {
        settings = {
          gopls = {
            gofumpt = true
          }
        }
      })
      lsp_zero.setup_servers {
        'basedpyright',
        'nushell',
        'tilt_ls',
        'tsserver',
      }
    end,
  },
}
