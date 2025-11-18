return {
  {
    'saghen/blink.cmp',
    -- optional: provides snippets for the snippet source
    dependencies = { 'milanglacier/minuet-ai.nvim', 'rafamadriz/friendly-snippets', { 'L3MON4D3/LuaSnip', version = 'v2.*' } },

    -- use a release tag to download pre-built binaries
    version = '1.*',
    -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
    -- build = 'cargo build --release',
    -- If you use nix, you can build from source using latest nightly rust with:
    -- build = 'nix run .#build-plugin',

    init = function()
      -- add friendly snippets to luasnip
      require('luasnip.loaders.from_vscode').lazy_load()
    end,
    config = function()
      require('blink.cmp').setup {
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
        keymap = {
          -- Manually invoke minuet completion.
          ['<A-y>'] = require('minuet').make_blink_map(),
          preset = 'default',
        },
        sources = {
          -- Enable minuet for autocomplete
          default = { 'lsp', 'path', 'buffer', 'snippets', 'minuet' },
          -- For manual completion only, remove 'minuet' from default
          providers = {
            minuet = {
              name = 'minuet',
              module = 'minuet.blink',
              async = true,
              -- Should match minuet.config.request_timeout * 1000,
              -- since minuet.config.request_timeout is in seconds
              timeout_ms = 3000,
              score_offset = 50, -- Gives minuet higher priority among suggestions
            },
          },
        },

        completion = {
          -- Manually invoke minuet completion.
          ['<A-y>'] = require('minuet').make_blink_map(),
          documentation = { auto_show = true },
        },

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

        -- Blink.cmp uses a Rust fuzzy matcher by default for typo resistance and significantly better performance
        -- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
        -- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
        --
        -- See the fuzzy documentation for more information
        fuzzy = { implementation = 'prefer_rust_with_warning' },
      }
    end,
    opts_extend = { 'sources.default' },
  },

  -- LSP
  {
    'neovim/nvim-lspconfig',
    cmd = 'LspInfo',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {},
    opts = {
      servers = {
        basedpyright = {},
        cuepls = {
          cmd = { 'cuepls' },
          filetypes = { 'cue' },
          root_markers = { 'cue.mod', '.git' },
        },
        gopls = {
          settings = {
            gopls = {
              gofumpt = true,
            },
          },
        },
        helm_ls = {
          settings = {
            ['helm-ls'] = {
              yamlls = {
                path = 'yaml-language-server',
              },
            },
          },
        },
        jsonls = {
          cmd = { 'vscode-json-languageserver', '--stdio' },
        },
        jsonnet_ls = {},
        lua_ls = {},
        nil_ls = {},
        nixd = {},
        nushell = {},
        regal = {},
        taplo = {},
        tilt_ls = {},
        tofu_ls = {},
        ts_ls = {},
        yamlls = {
          settings = {
            yaml = {
              schemas = {
                ['https://json.schemastore.org/github-workflow.json'] = '/.github/workflows/*',
                kubernetes = { 'charts/**/templates/*.yaml' },
              },
            },
          },
        },
      },
    },
    -- no need to load the plugin, since we just want its configs, adding the
    -- plugin to the runtime is enough
    lazy = true,
    init = function()
      vim.opt.signcolumn = 'yes'
      local lspConfigPath = require('lazy.core.config').options.root .. '/nvim-lspconfig'
      vim.opt.runtimepath:prepend(lspConfigPath)
      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(args)
          vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = args.buf, desc = 'go to definition' })
          vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { buffer = args.buf, desc = '[g]o to [D]eclaration' })
          vim.keymap.set('n', 'go', vim.lsp.buf.type_definition, { buffer = args.buf, desc = 'go to type definition' })
          vim.keymap.set('i', '<C-k>', vim.lsp.buf.signature_help, { buffer = args.buf, desc = 'signature help' })
          vim.keymap.set('n', 'gs', vim.lsp.buf.signature_help, { buffer = args.buf, desc = 'signature help' })
          vim.keymap.set('n', 'grI', vim.lsp.buf.incoming_calls, { buffer = args.buf, desc = '[I]ncoming calls' })
          vim.keymap.set('n', 'grO', vim.lsp.buf.outgoing_calls, { buffer = args.buf, desc = '[O]utgoing calls' })
          vim.keymap.set('n', 'gl', vim.diagnostic.open_float, { buffer = args.buf, desc = 'Open f[l]oat' })
        end,
      })
    end,
    config = function(_, opts)
      for server, config in pairs(opts.servers) do
        vim.lsp.config(server, config)
        vim.lsp.enable(server)
      end

      if false then
      end
    end,
  },
}
