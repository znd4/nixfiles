return {
  'akinsho/toggleterm.nvim',
  version = '*',
  config = function()
    local Terminal = require('toggleterm.terminal').Terminal

    -- Lazygit terminal on C-g
    local lazygit = Terminal:new {
      cmd = 'lazygit',
      direction = 'tab',
      hidden = true,
    }
    vim.keymap.set({ 'n', 't' }, '<C-g>', function()
      lazygit:toggle()
    end, { desc = 'Toggle Lazygit' })

    -- Vanilla terminal on C-t
    local shell = Terminal:new {
      cmd = 'fish',
      direction = 'tab',
      hidden = true,
    }
    vim.keymap.set({ 'n', 't' }, '<C-t>', function()
      shell:toggle()
    end, { desc = 'Toggle Terminal' })

    require('toggleterm').setup {}
  end,
}
