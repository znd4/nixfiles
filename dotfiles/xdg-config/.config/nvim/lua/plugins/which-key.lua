local delayed = function(module, method, ...)
  local args = { ... }
  return function()
    local ok, lib = pcall(require, module)
    if not ok then
      -- error
      vim.api.nvim_err_writeln("Error loading " .. module)
      return
    end
    lib[method](unpack(args))
  end
end
local factory = function(func, ...)
  local args = { ... }
  return function()
    func(unpack(args))
  end
end
return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 300
    local wk = require("which-key")
    wk.register({
      ["<Space>"] = {
        ["<Space>"] = {
          function()
            require("neotest").run.run()
          end,
          "Test Nearest Function",
        },
        f = {
          function()
            require("neotest").run.run(vim.fn.expand("%"))
          end,
          "Test Current File",
        },
        d = {
          function()
            require("neotest").run.run({ strategy = "dap" })
          end,
          "Debug nearest test",
        },
        s = {
          function()
            require("neotest").run.stop()
          end,
          "stop nearest test",
        },
        a = {
          function()
            require("neotest").run.attach()
          end,
          "Attach to nearest test",
        },
      },
      g = {
        p = { factory(vim.cmd.Neogit, "pull"), "Git Pull" },
        P = { factory(vim.cmd.Neogit, "push"), "Git Push" },
        c = { factory(vim.cmd.Neogit, "commit"), "Git Commit" },
        s = { vim.cmd.Neogit, "Open Git (fugitive)" },
      },
      w = {
        w = { vim.cmd.w, ":w" },
      },
      G = { vim.cmd.Gitsigns, "Gitsigns" },
      c = {
        name = "ChatGPT",
        c = { vim.cmd.ChatGPT, "ChatGPT" },
        e = { vim.cmd.ChatGPTEditWithInstruction, "Edit with instruction", mode = { "n", "v" } },
        g = { "<cmd>ChatGPTRun grammar_correction<CR>", "Grammar Correction", mode = { "n", "v" } },
        t = { "<cmd>ChatGPTRun translate<CR>", "Translate", mode = { "n", "v" } },
        k = { "<cmd>ChatGPTRun keywords<CR>", "Keywords", mode = { "n", "v" } },
        d = { "<cmd>ChatGPTRun docstring<CR>", "Docstring", mode = { "n", "v" } },
        a = { "<cmd>ChatGPTRun add_tests<CR>", "Add Tests", mode = { "n", "v" } },
        o = { "<cmd>ChatGPTRun optimize_code<CR>", "Optimize Code", mode = { "n", "v" } },
        s = { "<cmd>ChatGPTRun summarize<CR>", "Summarize", mode = { "n", "v" } },
        f = { "<cmd>ChatGPTRun fix_bugs<CR>", "Fix Bugs", mode = { "n", "v" } },
        x = { "<cmd>ChatGPTRun explain_code<CR>", "Explain Code", mode = { "n", "v" } },
        r = { "<cmd>ChatGPTRun roxygen_edit<CR>", "Roxygen Edit", mode = { "n", "v" } },
        l = { "<cmd>ChatGPTRun code_readability_analysis<CR>", "Code Readability Analysis", mode = { "n", "v" } },
      },
    }, { prefix = "<leader>" })
  end,
  opts = {},
}
