local ensure_installed = {
  "bash",
  "comment",
  "go",
  "gomod",
  "gotmpl",
  "json",
  "kotlin",
  "lua",
  "markdown",
  "markdown_inline",
  "org",
  "python",
  "sql",
  "typescript",
}
local leader = "<leader>"

vim.g.skip_ts_context_commentstring_module = true

return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    require("orgmode").setup_ts_grammar()

    local ft_to_lang_tbl = {
      ["zsh"] = "bash",
      ["xml"] = "html",
      ["tiltfile"] = "python",
      -- ["helm"] = "yaml",
    }

    local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
    parser_config.gotmpl = {
      install_info = {
        url = "https://github.com/ngalaiko/tree-sitter-go-template",
        files = { "src/parser.c" },
      },
      filetype = "gotmpl",
      used_by = { "gohtmltmpl", "gotexttmpl", "gotmpl", "yaml" },
    }

    -- trick treesitter into thinking zsh files are bash
    local ft_to_lang = require("nvim-treesitter.parsers").ft_to_lang
    require("nvim-treesitter.parsers").ft_to_lang = function(ft)
      if ft_to_lang_tbl[ft] == nil then
        return ft_to_lang(ft)
      end
      return ft_to_lang_tbl[ft]
    end

    vim.filetype.add({
      extension = {
        sh = "bash",
        yml = "yaml",
      },
      filename = {
        ["justfile"] = "justfile",
      },
    })

    vim.treesitter.query.add_directive("colzero!", function(match, pattern, bufnr, predicate, metadata)
      for i, m in pairs(metadata) do
        m.range[2] = 0
      end
    end)

    require("nvim-treesitter.install").prefer_git = true

    require("nvim-treesitter.configs").setup({
      ensure_installed = ensure_installed,
      auto_install = true,
      highlight = {
        enable = true,
        -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
        -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
        -- Using this option may slow down your editor, and you may see some duplicate highlights.
        -- Instead of true it can also be a list of languages
        additional_vim_regex_highlighting = { "org", "vim", "markdown" },
      },
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = leader .. "gnn",
          node_incremental = leader .. "grn",
          scope_incremental = leader .. "grc",
          node_decremental = leader .. "grm",
        },
      },
      indent = {
        enable = true,
      },
    })
    require("ts_context_commentstring").setup({})
  end,
  dependencies = {
    "nushell/tree-sitter-nu",
    "nvim-treesitter/nvim-treesitter-textobjects",
    "JoosepAlviste/nvim-ts-context-commentstring",
  },
}
