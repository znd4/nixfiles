local prettier = { "prettierd", "prettier" }
return {
  "stevearc/conform.nvim",
  event = {
    "BufReadPre",
    "BufNewFile",
  },
  config = {
    formatters_by_ft = {
      fish = { "fish_indent" },
      go = { "gofumpt" },
      javascript = { prettier },
      json = { prettier },
      jsonnet = { "jsonnetfmt" },
      just = { "just" },
      lua = { "stylua" },
      markdown = { prettier },
      python = { "ruff_format" },
      yaml = { prettier },
      -- we've got marksman now
      -- markdown = { prettier },
    },
    formatters = {
      jsonnetfmt = {
        command = "jsonnetfmt",
        args = { "-" },
      },
    },
    format_on_save = {
      timeout_ms = 500,
      lsp_fallback = true,
      async = false,
    },
  },
}
