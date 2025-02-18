return {
  "zbirenbaum/copilot.lua",
  event = "BufReadPre",
  keys = {
    {
      "<C-j>",
      function()
        require("copilot.suggestion").accept()
      end,
      desc = "Accept suggestion",
      mode = "i",
    },
  },
  opts = {
    filetypes = {
      yaml = true
    },
    suggestion = {
      auto_trigger = true
    },
  },
}
