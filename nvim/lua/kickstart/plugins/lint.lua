return {

  { -- Linting
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'
      lint.linters.actionlint = {
        cmd = 'actionlint',
        stdin = true, -- or false if it doesn't support content input via stdin. In that case the filename is automatically added to the arguments.
        append_fname = true, -- Automatically append the file name to `args` if `stdin = false` (default: true)
        args = {}, -- list of arguments. Can contain functions with zero arguments that will be evaluated once the linter is used.
        stream = nil, -- ('stdout' | 'stderr' | 'both') configure the stream to which the linter outputs the linting result.
        ignore_exitcode = false, -- set this to true if the linter exits with a code != 0 and that's considered normal.
        env = nil, -- custom environment table to use with the external process. Note that this replaces the *entire* environment, it is not additive.
      }
      lint.linters_by_ft = {
        markdown = { 'markdownlint' },
      }

      -- To allow other plugins to add linters to require('lint').linters_by_ft,
      -- instead set linters_by_ft like this:
      -- lint.linters_by_ft = lint.linters_by_ft or {}
      -- lint.linters_by_ft['markdown'] = { 'markdownlint' }
      --
      -- However, note that this will enable a set of default linters,
      -- which will cause errors unless these tools are available:
      -- {
      --   clojure = { "clj-kondo" },
      --   dockerfile = { "hadolint" },
      --   inko = { "inko" },
      --   janet = { "janet" },
      --   json = { "jsonlint" },
      --   markdown = { "vale" },
      --   rst = { "vale" },
      --   ruby = { "ruby" },
      --   terraform = { "tflint" },
      --   text = { "vale" }
      -- }
      --
      -- You can disable the default linters by setting their filetypes to nil:
      -- lint.linters_by_ft['clojure'] = nil
      -- lint.linters_by_ft['dockerfile'] = nil
      -- lint.linters_by_ft['inko'] = nil
      -- lint.linters_by_ft['janet'] = nil
      -- lint.linters_by_ft['json'] = nil
      -- lint.linters_by_ft['markdown'] = nil
      -- lint.linters_by_ft['rst'] = nil
      -- lint.linters_by_ft['ruby'] = nil
      -- lint.linters_by_ft['terraform'] = nil
      -- lint.linters_by_ft['text'] = nil

      -- Create autocommand which carries out the actual linting
      -- on the specified events.
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      local events = { 'BufEnter', 'BufWritePost', 'InsertLeave' }

      vim.api.nvim_create_autocmd(events, {
        group = lint_augroup,
        callback = function()
          local bufname = vim.api.nvim_buf_get_name(0)
          local is_yaml = vim.bo.filetype == 'yaml'
          local is_github_action = is_yaml and (bufname:match 'action%.ya?ml$' or bufname:match '%.github/workflows/.*%.ya?ml$')

          if is_github_action then
            require('lint').try_lint 'actionlint'
          else
            require('lint').try_lint()
          end
        end,
      })
    end,
  },
}
