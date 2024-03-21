local function dap_python_setup()
  require("dap-python").setup(vim.g.python3_host_prog)
  require("dap-python").test_runner = "pytest"
end
local function dap_go_setup()
  local dapgo = require("dap-go")
  dapgo.setup()
end
return {
  "mfussenegger/nvim-dap",
  dependencies = { "leoluz/nvim-dap-go", "mfussenegger/nvim-dap-python", "nvim-lua/plenary.nvim" },
  config = function()
    dap_python_setup()
    dap_go_setup()
    -- local async = require("plenary.async").async
    -- local dap_go = async(dap_go_setup)()
    -- local dap_python = async(dap_python_setup)()
    -- dap_go:await()
    -- dap_python:await()

    local vimp = require("vimp")
    local dap = require("dap")
    vimp.nnoremap({ "silent" }, "<F5>", dap.continue, { desc = "debugger continue" })
    vimp.nnoremap({ "silent" }, "<F10>", dap.step_over, { desc = "debugger step over" })
    vimp.nnoremap({ "silent" }, "<F11>", dap.step_into, { desc = "debugger step into" })
    vimp.nnoremap({ "silent" }, "<F12>", dap.step_out, { desc = "debugger step out" })
    vimp.nnoremap({ "silent" }, "<Leader>b", dap.toggle_breakpoint, { desc = "debugger toggle breakpoint" })
    vimp.nnoremap({ "silent" }, "<Leader>B", function()
      require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
    end, { desc = "debugger set breakpoint condition" })
    vimp.nnoremap({ "silent" }, "<Leader>lp", function()
      require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
    end, { desc = "debugger set log point message" })
    vimp.nnoremap({ "silent" }, "<Leader>ds", function()
      local widgets = require("dap.ui.widgets")
      widgets.centered_float(widgets.scopes)
    end, { desc = "Open scopes in sidebar" })
    vimp.nnoremap({ "silent" }, "<Leader>dh", function()
      require("dap.ui.widgets").hover()
    end, { desc = "View value of expression under cursor" })
    vimp.nnoremap({ "silent" }, "<Leader>dr", dap.repl.open, { desc = "open debugger repl" })
    vimp.nnoremap({ "silent" }, "<Leader>dl", dap.run_last, { desc = "run last debugger" })
  end,
}
