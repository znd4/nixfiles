-- Worktree creation form using nui.nvim
-- Registered as a dependency of git-worktree.nvim so it loads after both
-- git-worktree and nui.nvim are available.

local function create_worktree_form()
  local Input = require('nui.input')
  local Popup = require('nui.popup')
  local Layout = require('nui.layout')

  --- Get the default branch for the default remote
  local function get_default_branch()
    local result = vim.fn.systemlist('git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null')
    if vim.v.shell_error == 0 and result[1] then
      return result[1]:gsub('^refs/remotes/origin/', '')
    end
    for _, branch in ipairs({ 'main', 'master' }) do
      vim.fn.systemlist('git rev-parse --verify refs/remotes/origin/' .. branch .. ' 2>/dev/null')
      if vim.v.shell_error == 0 then
        return branch
      end
    end
    return 'main'
  end

  local function normalize_branch_to_folder(branch)
    return branch:gsub('/', '-')
  end

  local function get_git_root()
    local result = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')
    if vim.v.shell_error == 0 and result[1] then
      return result[1]
    end
    return vim.fn.getcwd()
  end

  local function read_input_value(input)
    if input.bufnr and vim.api.nvim_buf_is_valid(input.bufnr) then
      local lines = vim.api.nvim_buf_get_lines(input.bufnr, 0, 1, false)
      if lines[1] then
        return lines[1]:gsub('^> ', '')
      end
    end
    return ''
  end

  local default_branch = get_default_branch()
  local git_root = get_git_root()
  local base_path = git_root .. '/.zn-work/'

  local focused_field = 1
  local folder_manually_edited = false

  local folder_input

  local popup_opts = {
    border = {
      style = 'rounded',
      text = { top_align = 'left' },
    },
    win_options = {
      winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
    },
  }

  local title_popup = Popup(vim.tbl_deep_extend('force', popup_opts, {
    border = {
      style = 'rounded',
      text = {
        top = ' Create Worktree ',
        top_align = 'center',
      },
    },
    focusable = false,
    buf_options = {
      modifiable = true,
      readonly = false,
    },
  }))

  local branch_input = Input(
    vim.tbl_deep_extend('force', popup_opts, {
      border = { text = { top = ' Branch Name ' } },
    }),
    {
      prompt = '> ',
      default_value = '',
      on_change = function(value)
        if not folder_manually_edited and folder_input then
          local new_folder = normalize_branch_to_folder(value or '')
          vim.schedule(function()
            if folder_input.bufnr and vim.api.nvim_buf_is_valid(folder_input.bufnr) then
              vim.api.nvim_buf_set_lines(folder_input.bufnr, 0, -1, false, { '> ' .. new_folder })
            end
          end)
        end
      end,
    }
  )

  folder_input = Input(
    vim.tbl_deep_extend('force', popup_opts, {
      border = { text = { top = ' Folder Path (under .zn-work/) ' } },
    }),
    {
      prompt = '> ',
      default_value = '',
      on_change = function(value)
        if value and value ~= '' then
          folder_manually_edited = true
        end
      end,
    }
  )

  local from_input = Input(
    vim.tbl_deep_extend('force', popup_opts, {
      border = { text = { top = ' From Branch ' } },
    }),
    {
      prompt = '> ',
      default_value = default_branch,
    }
  )

  local inputs = { branch_input, folder_input, from_input }

  local layout = Layout(
    {
      position = '50%',
      size = { width = 70, height = 14 },
    },
    Layout.Box({
      Layout.Box(title_popup, { size = { height = 2 } }),
      Layout.Box(branch_input, { size = { height = 3 } }),
      Layout.Box(folder_input, { size = { height = 3 } }),
      Layout.Box(from_input, { size = { height = 3 } }),
    }, { dir = 'col' })
  )

  layout:mount()

  vim.api.nvim_buf_set_lines(title_popup.bufnr, 0, -1, false, {
    '  Tab/S-Tab: navigate  |  Enter: submit  |  Esc: cancel',
  })
  vim.bo[title_popup.bufnr].modifiable = false

  local function focus_field(idx)
    focused_field = idx
    local input = inputs[idx]
    if input and input.winid and vim.api.nvim_win_is_valid(input.winid) then
      vim.api.nvim_set_current_win(input.winid)
      vim.cmd('startinsert!')
    end
  end

  local function next_field()
    focus_field((focused_field % #inputs) + 1)
  end

  local function prev_field()
    focus_field(((focused_field - 2) % #inputs) + 1)
  end

  local function close_form()
    layout:unmount()
  end

  local function submit_form()
    local branch = read_input_value(branch_input)
    local folder = read_input_value(folder_input)
    local from = read_input_value(from_input)

    if branch == '' then
      vim.notify('Branch name is required', vim.log.levels.ERROR)
      focus_field(1)
      return
    end

    if folder == '' then
      folder = normalize_branch_to_folder(branch)
    end
    if from == '' then
      from = default_branch
    end

    local full_path = base_path .. folder

    close_form()

    vim.schedule(function()
      vim.notify(
        string.format('Creating worktree: branch=%s path=%s from=%s', branch, full_path, from),
        vim.log.levels.INFO
      )

      local cmd = string.format(
        'git worktree add -b %s %s %s',
        vim.fn.shellescape(branch),
        vim.fn.shellescape(full_path),
        vim.fn.shellescape(from)
      )
      local output = vim.fn.system(cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify('Failed to create worktree: ' .. output, vim.log.levels.ERROR)
        return
      end

      vim.notify('Worktree created successfully', vim.log.levels.INFO)
      require('git-worktree').switch_worktree(full_path)
    end)
  end

  for _, input in ipairs(inputs) do
    input:map('i', '<Tab>', next_field, { noremap = true })
    input:map('i', '<S-Tab>', prev_field, { noremap = true })
    input:map('n', '<Tab>', next_field, { noremap = true })
    input:map('n', '<S-Tab>', prev_field, { noremap = true })
    input:map('n', '<CR>', submit_form, { noremap = true })
    input:map('i', '<Esc>', close_form, { noremap = true })
    input:map('n', '<Esc>', close_form, { noremap = true })
    input:map('n', 'q', close_form, { noremap = true })
  end

  for _, input in ipairs(inputs) do
    vim.fn.prompt_setcallback(input.bufnr, function(_)
      submit_form()
    end)
    vim.fn.prompt_setinterrupt(input.bufnr, function()
      close_form()
    end)
  end

  vim.schedule(function()
    focus_field(1)
  end)
end

return {
  'MunifTanjim/nui.nvim',
  keys = {
    { '<leader>gw', create_worktree_form, desc = '[G]it [W]orktree create' },
  },
}
