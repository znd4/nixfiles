local prettier = { "prettierd", "prettier" }
return {
  "stevearc/conform.nvim",
  dependencies = {
    -- plenary
    "nvim-lua/plenary.nvim",
  },
  event = {
    "BufReadPre",
    "BufNewFile",
  },
  opts = {
    notify_on_error = false,
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
      nix = function(bufnr)
        -- if there is a flake.nix in a parent directory, use `nix fmt`
        local path = vim.api.nvim_buf_get_name(bufnr)
        local git_root = require("plenary.path"):new(path):find_upwards(".git")
        if not (git_root and git_root:is_dir() and git_root:parent():joinpath("flake.nix"):is_file()) then
          return { "alejandra" }
        end
        return { "nix fmt" }
      end,
      -- we've got marksman now
      -- markdown = { prettier },
    },
    formatters = {
      jsonnetfmt = {
        command = "jsonnetfmt",
        args = { "-" },
      },
      ["nix fmt"] = {
        command = "nix",
        args = { "fmt", "$FILENAME" },
      },
    },
    format_on_save = function(bufnr)
      -- Disable "format_on_save lsp_fallback" for languages that don't
      -- have a well standardized coding style. You can add additional
      -- languages here or re-enable it for the disabled ones.
      local disable_filetypes = { c = true, cpp = true }
      return {
        timeout_ms = 500,
        lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype],
      }
    end,
  },
}
