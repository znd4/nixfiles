return {
  'nvim-lua/plenary.nvim',
  config = function()
    vim.filetype.add {
      extension = {},
      filename = {},
    }

    local Path = require 'plenary.path'

    local function is_helm_file(path)
      local check = vim.fs.find('Chart.yaml', { path = vim.fs.dirname(path), upward = true })
      if vim.tbl_isempty(check) then
        return false
      end

      local values_yaml = Path:new(check[1]):parent():joinpath('values.yaml'):normalize()
      local file_path = Path:new(path):normalize()
      return file_path ~= values_yaml
    end

    --@private
    --@return string
    local function yaml_filetype(path, bufname)
      local is_helm = is_helm_file(path)
      return is_helm and 'helm' or 'yaml'
    end

    --@private
    --@return string
    local function tmpl_filetype(path, bufname)
      return is_helm_file(path) and 'helm' or 'template'
    end

    --@private
    --@return string
    local function tpl_filetype(path, bufname)
      return is_helm_file(path) and 'helm' or 'smarty'
    end

    vim.filetype.add {
      extension = {
        ['tfstate.backup'] = 'json',
        hcl = 'hcl',
        kbd = 'clojure',
        plist = 'xml',
        shell = 'bash',
        tf = 'terraform',
        tfstate = 'json',
        tfvars = 'terraform',
        tmpl = tmpl_filetype,
        tpl = tpl_filetype,
        yaml = yaml_filetype,
        yml = yaml_filetype,
      },
      filename = {
        ['.devcontainer.json'] = 'jsonc',
        ['.terraformrc'] = 'hcl',
        ['.yamllint'] = 'yaml',
        ['devbox.json'] = 'jsonc',
        ['Chart.lock'] = 'yaml',
        ['Chart.yaml'] = 'yaml',
        ['Tiltfile'] = 'tiltfile',
        ['devcontainer.json'] = 'jsonc',
        ['terraform.rc'] = 'hcl',
      },
      pattern = {
        ['${HOME}/%.ssh/config%.d/.*'] = 'sshconfig',
        ['.*'] = {
          priority = -math.huge,
          function(path, bufnr)
            local content = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''
            if vim.regex([[^#!.*\<node\>]]):match_str(content) then
              return 'javascript'
            elseif vim.regex([[^#!.*\<osascript\>]]):match_str(content) then
              return 'applescript'
            elseif vim.regex([[^#!.*(pipx|python|python3)]]):match_str(content) then
              return 'python'
            end
          end,
        },
      },
    }
  end,
}
