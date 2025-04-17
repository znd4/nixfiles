return {
  'zbirenbaum/copilot.lua',
  event = 'BufReadPre',
  keys = {
    {
      '<C-j>',
      function()
        require('copilot.suggestion').accept()
      end,
      desc = 'Accept suggestion',
      mode = 'i',
    },
  },
  opts = {
    filetypes = {
      yaml = true,
    },
    copilot_model = 'gpt-4-1',
    suggestion = {
      auto_trigger = true,
    },
  },
}
