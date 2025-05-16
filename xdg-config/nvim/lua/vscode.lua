local M = {}

-- Function to open current file in VS Code at cursor position
function M.open_in_vscode()
  local file_path = vim.fn.expand '%:p'
  local line_nr = vim.fn.line '.'
  local col_nr = vim.fn.col '.'
  local cmd = string.format('code -g %s:%s:%s', file_path, line_nr, col_nr)
  vim.fn.system(cmd)
end

return M
