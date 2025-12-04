local prettier = { 'prettierd', 'prettier' }
return {
  'stevearc/conform.nvim',
  lazy = false,
  dependencies = {
    -- plenary
    'nvim-lua/plenary.nvim',
  },
  event = {
    'BufReadPre',
    'BufNewFile',
  },
  opts = {
    notify_on_error = false,
    formatters_by_ft = {
      fish = { 'fish_indent' },
      go = { 'gofumpt' },
      javascript = { prettier },
      json = { 'dprint' },
      jsonnet = { 'jsonnetfmt' },
      just = { 'just' },
      lua = { 'stylua' },
      markdown = { 'dprint' },
      python = { 'ruff_format', 'ruff_fix' },
      terraform = { 'tofu_fmt' },
      yaml = { 'dprint' },
      nix = { 'nixfmt' },
      -- we've got marksman now
      -- markdown = { prettier },
    },
    formatters = {
      dprint = {
        condition = function(ctx)
          return vim.fs.find({ 'dprint.json', '.dprint.json', 'dprint.jsonc', '.dprint.jsonc' }, { path = ctx.filename, upward = true })[1]
        end,
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
