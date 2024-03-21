local function dap_go_setup() end
return {
  "mfussenegger/nvim-dap",
  dependencies = { "leoluz/nvim-dap-go", "mfussenegger/nvim-dap-python", "nvim-lua/plenary.nvim" },
  init = function()
    print("loading dap")
    print("python3_host_prog: " .. vim.g.python3_host_prog)

    require("dap-python").setup(vim.g.python3_host_prog or "python3", {})
    require("dap-python").test_runner = "pytest"

    require("dap-go").setup()

    local wk = require("which-key")
    local dap = require("dap")
    wk.register({
      ["<F5>"] = { dap.continue, "Continue" },
      ["<F10>"] = { dap.step_over, "Step over" },
      ["<F11>"] = { dap.step_into, "Step into" },
      ["<F12>"] = { dap.step_out, "Step out" },
    })
    wk.register({
      ["b"] = { dap.toggle_breakpoint, "Toggle breakpoint" },
      ["B"] = {
        function()
          require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
        end,
        "Set breakpoint condition",
      },
      ["lp"] = {
        function()
          require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
        end,
        "Set log point message",
      },
      ["ds"] = {
        function()
          local widgets = require("dap.ui.widgets")
          widgets.centered_float(widgets.scopes)
        end,
        "Open scopes in sidebar",
      },
      ["dh"] = {
        function()
          require("dap.ui.widgets").hover()
        end,
        "View value of expression under cursor",
      },
      ["dr"] = { dap.repl.open, "Open debugger repl" },
      ["dl"] = { dap.run_last, "Run last debugger" },
    }, { prefix = "<Leader>" })
  end,
}
