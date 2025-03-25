return {
  {
    'VonHeikemen/lsp-zero.nvim',
    branch = 'v4.x',
    lazy = true,
    config = false,
    init = function()
      -- Disable automatic setup, we are doing it manually
      vim.g.lsp_zero_extend_cmp = 0
      vim.g.lsp_zero_extend_lspconfig = 0
    end,
  },

  {
    'saghen/blink.cmp',
    -- optional: provides snippets for the snippet source
    dependencies = { 'rafamadriz/friendly-snippets', { 'L3MON4D3/LuaSnip', version = 'v2.*' } },

    -- use a release tag to download pre-built binaries
    version = '*',
    -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
    -- build = 'cargo build --release',
    -- If you use nix, you can build from source using latest nightly rust with:
    -- build = 'nix run .#build-plugin',

    init = function()
      -- add friendly snippets to luasnip
      require('luasnip.loaders.from_vscode').lazy_load()
    end,
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      -- 'default' (recommended) for mappings similar to built-in completions (C-y to accept, C-n/C-p for up/down)
      -- 'super-tab' for mappings similar to vscode (tab to accept, arrow keys for up/down)
      -- 'enter' for mappings similar to 'super-tab' but with 'enter' to accept
      --
      -- All presets have the following mappings:
      -- C-space: Open menu or open docs if already open
      -- C-e: Hide menu
      -- C-k: Toggle signature help
      --
      -- See the full "keymap" documentation for information on defining your own keymap.
      keymap = { preset = 'default' },

      appearance = {
        -- Sets the fallback highlight groups to nvim-cmp's highlight groups
        -- Useful for when your theme doesn't support blink.cmp
        -- Will be removed in a future release
        use_nvim_cmp_as_default = true,
        -- Set to 'mono' for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
        -- Adjusts spacing to ensure icons are aligned
        nerd_font_variant = 'mono',
      },

      -- preset snippets
      snippets = { preset = 'luasnip' },

      -- Default list of enabled providers defined so that you can extend it
      -- elsewhere in your config, without redefining it, due to `opts_extend`
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },

      -- Blink.cmp uses a Rust fuzzy matcher by default for typo resistance and significantly better performance
      -- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
      -- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
      --
      -- See the fuzzy documentation for more information
      fuzzy = { implementation = 'prefer_rust_with_warning' },
    },
    opts_extend = { 'sources.default' },
  },

  -- {
  --   'mtoohey31/cmp-fish',
  --   dependencies = { 'hrsh7th/nvim-cmp' },
  --   init = function()
  --     table.insert(require('cmp').get_config().sources, { name = 'fish' })
  --   end,
  -- },
  -- {
  --   'hrsh7th/cmp-emoji',
  --   dependencies = { 'hrsh7th/nvim-cmp' },
  --   init = function()
  --     table.insert(require('cmp').get_config().sources, { name = 'emoji' })
  --   end,
  -- },
  -- {
  --   'hrsh7th/cmp-buffer',
  --   dependencies = { 'hrsh7th/nvim-cmp' },
  --   init = function()
  --     table.insert(require('cmp').get_config().sources, { name = 'buffer' })
  --   end,
  -- },
  -- {
  --   'petertriho/cmp-git',
  --   dependencies = { 'hrsh7th/nvim-cmp' },
  --   opts = {
  --     -- ...
  --   },
  --   init = function()
  --     table.insert(require('cmp').get_config().sources, { name = 'git' })
  --   end,
  -- },
  -- Autocompletion
  -- {
  --   'hrsh7th/nvim-cmp',
  --   event = 'InsertEnter',
  --   dependencies = {
  --     { 'L3MON4D3/LuaSnip' },
  --     { 'hrsh7th/nvim-cmp' },
  --     { 'rafamadriz/friendly-snippets' },
  --     'saadparwaiz1/cmp_luasnip',
  --
  --     -- Adds other completion capabilities.
  --     --  nvim-cmp does not ship with all sources by default. They are split
  --     --  into multiple repos for maintenance purposes.
  --     'hrsh7th/cmp-nvim-lsp',
  --     'hrsh7th/cmp-path',
  --   },
  --   config = function()
  --     -- Here is where you configure the autocompletion settings.
  --     local lsp_zero = require 'lsp-zero'
  --     lsp_zero.extend_cmp()
  --
  --     -- add friendly snippets to luasnip
  --     require('luasnip.loaders.from_vscode').lazy_load()
  --
  --     -- And you can configure cmp even more, if you want to.
  --     local cmp = require 'cmp'
  --
  --     -- play nicely with copilot
  --     cmp.event:on('menu_opened', function()
  --       vim.b.copilot_suggestion_hidden = true
  --     end)
  --     cmp.event:on('menu_closed', function()
  --       vim.b.copilot_suggestion_hidden = false
  --     end)
  --
  --     local cmp_action = lsp_zero.cmp_action()
  --     local cmp_config = cmp.get_config()
  --     table.insert(cmp_config.sources, { name = 'luasnip' })
  --     table.insert(cmp_config.sources, { name = 'path' })
  --     table.insert(cmp_config.sources, { name = 'nvim_lsp' })
  --     local luasnip = require 'luasnip'
  --     cmp.setup {
  --       formatting = lsp_zero.cmp_format { details = true },
  --       mapping = cmp.mapping.preset.insert {
  --         ['<C-Space>'] = cmp.mapping.complete(),
  --         ['<C-u>'] = cmp.mapping.scroll_docs(-4),
  --         ['<C-d>'] = cmp.mapping.scroll_docs(4),
  --         ['<C-f>'] = cmp_action.luasnip_jump_forward(),
  --         ['<C-b>'] = cmp_action.luasnip_jump_backward(),
  --         ['<C-n>'] = cmp.mapping(function(fallback)
  --           if cmp.visible() then
  --             cmp.select_next_item { behavior = cmp.SelectBehavior.Select }
  --           elseif luasnip.choice_active() then
  --             luasnip.change_choice(1)
  --           else
  --             fallback()
  --           end
  --         end, { 'i', 's' }),
  --         ['<C-p>'] = cmp.mapping(function(fallback)
  --           if cmp.visible() then
  --             cmp.select_prev_item { behavior = cmp.SelectBehavior.Select }
  --           elseif luasnip.choice_active() then
  --             luasnip.change_choice(-1)
  --           else
  --             fallback()
  --           end
  --         end, { 'i', 's' }),
  --       },
  --       snippet = {
  --         expand = function(args)
  --           require('luasnip').lsp_expand(args.body)
  --         end,
  --       },
  --     }
  --   end,
  -- },

  -- LSP
  {
    'neovim/nvim-lspconfig',
    cmd = 'LspInfo',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {},
    config = function()
      -- This is where all the LSP shenanigans will live
      local configs = require 'lspconfig.configs'
      if not configs.cuepls then
        configs.cuepls = {
          default_config = {
            cmd = { 'cuepls' },
            filetypes = { 'cue' },
            root_dir = require('lspconfig.util').root_pattern 'cue.mod',
          },
        }
      end

      -- Reserve a space in the gutter
      -- This will avoid an annoying layout shift in the screen
      vim.opt.signcolumn = 'yes'

      local lsp_zero = require 'lsp-zero'
      lsp_zero.extend_lspconfig()

      local lspconfig_defaults = require('lspconfig').util.default_config
      lspconfig_defaults.capabilities = vim.tbl_deep_extend('force', lspconfig_defaults.capabilities, require('blink.cmp').get_lsp_capabilities())

      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(client, bufnr)
          -- see :help lsp-zero-keybindings
          -- to learn the available actions
          local opts = { buffer = bufnr }
          require('which-key').add {
            {
              {
                'gd',
                vim.lsp.buf.definition,
                desc = '[g]o to [d]efinition',
              },
              {
                'gD',
                vim.lsp.buf.declaration,
                desc = '[g]o to [D]eclaration',
              },
              {
                'gi',
                vim.lsp.buf.implementation,
                desc = '[g]o to [i]mplementation',
              },
              {
                'go',
                vim.lsp.buf.type_definition,
                desc = '[G][o] to type definition',
              },
              {
                'gr',
                vim.lsp.buf.references,
                desc = '[G]o to [r]eferences',
              },
              {
                'gs',
                vim.lsp.buf.signature_help,
                desc = '[G]o to [s]ignature',
              },
              -- call hierarchy
              {
                'gI',
                vim.lsp.buf.incoming_calls,
                desc = '[I]ncoming calls',
              },
              {
                'gO',
                vim.lsp.buf.outgoing_calls,
                desc = '[O]utgoing calls',
              },
              {
                'gl',
                vim.diagnostic.open_float,
                desc = 'Open f[l]oat',
              },
              {
                'K',
                vim.lsp.buf.hover,
                desc = 'Hover',
              },
              { '<F2>', vim.lsp.buf.rename, desc = 'Rename' },
              { '<F4>', vim.lsp.buf.code_action, desc = 'Code actions' },
              { '[d', vim.diagnostic.goto_prev, desc = 'previous diagnostic' },
              { ']d', vim.diagnostic.goto_next, desc = 'next diagnostic' },
            },
            {
              { '<F3>', ':lua vim.lsp.buf.format({async=true})<cr>', desc = 'format buffer' },
              mode = { 'n', 'x' },
            },
            {
              {
                '<C-k>',
                vim.lsp.buf.signature_help,
                desc = 'View argument signature',
              },
              mode = { 'i' },
            },
            buffer = bufnr,
          }
        end,
      })

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
              kubernetes = { 'charts/**/templates/*.yaml' },
            },
          },
        },
      })
      lsp_zero.configure('gopls', {
        settings = {
          gopls = {
            gofumpt = true,
            buildFlags = { '-tags=mage' },
          },
        },
      })
      lsp_zero.setup_servers {
        'basedpyright',
        'jsonls',
        'jsonnet_ls',
        -- 'marksman',
        'nushell',
        'regal',
        'nixd',
        'nil',
        'taplo',
        'terraformls',
        'tilt_ls',
        'cuepls',
        'tsserver',
      }
    end,
  },
}
