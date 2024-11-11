return {
  'L3MON4D3/LuaSnip',
  build = (function()
    -- Build Step is needed for regex support in snippets.
    -- This step is not supported in many windows environments.
    -- Remove the below condition to re-enable on windows.
    if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
      return
    end
    return 'make install_jsregexp'
  end)(),
  dependencies = {
    -- "folke/which-key",
    "znd4/mermaid-luasnip.nvim",
  },
  --[[

  -- --]]
  --                               (block_mapping_pair ; [30, 8] - [30, 23]
  --                                 key: (flow_node ; [30, 8] - [30, 17]
  --                                   (plain_scalar ; [30, 8] - [30, 17]
  --                                     (string_scalar))) ; [30, 8] - [30, 17]
  --                                 value: (flow_node ; [30, 19] - [30, 23]
  --                                   (plain_scalar ; [30, 19] - [30, 23]
  --                                     (string_scalar))))))) ; [30, 19] - [30, 23]
  --
  init = function()
    local ls = require("luasnip")
    require("mermaid-luasnip").setup()
    local s = ls.snippet
    local sn = ls.snippet_node
    local isn = ls.indent_snippet_node
    local t = ls.text_node
    local i = ls.insert_node
    local f = ls.function_node
    local c = ls.choice_node
    local d = ls.dynamic_node
    local r = ls.restore_node
    -- require('which-key').register({
    --   ['<C-s>'] =
    -- }, { mode = { "i" }})

    local treesitter_postfix = require("luasnip.extras.treesitter_postfix").treesitter_postfix
    ls.add_snippets("yaml", {
      s("repl", {
        t('\'{{repl '),
        c(1, {
          t('ConfigOption'),
          t('ConfigOptionEquals'),
        }),
        t(' '),
        d(2, function(args)
          vim.print(args[1])
          if args[1][1] == "ConfigOption" then
            return sn(nil, {
              t('"'),
              i(1, "option_key"),
              t('"'),
            })
          elseif args[1][1] == "ConfigOptionEquals" then
            return sn(nil, {
              t('"'),
              i(1, "option_key"),
              t('" "'),
              i(2, "option_value"),
              t('"'),
            })
          end
        end, { 1 }),

        t(" }}'"),
      })
    })
    -- treesitter_postfix({
    --   trig = "repl",
    --   matchTSNode = {
    --     query = [[
    --
    --     ]],
    --   },
    -- })
  end,
}
