vim.filetype.add {
  extension = {
    ['tfstate.backup'] = 'json',
    gotmpl = 'gotmpl',
    hcl = 'hcl',
    kbd = 'clojure',
    plist = 'xml',
    shell = 'bash',
    tf = 'opentofu',
    tfstate = 'json',
    tfvars = 'opentofu-vars',
    libsonnet = 'jsonnet',
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
    ['.*/templates/.*%.tpl'] = 'helm',
    ['.*/templates/.*%.ya?ml'] = 'helm',
    ['helmfile.*%.ya?ml'] = 'helm',
    ['.*'] = {
      priority = -math.huge,
      function(path, bufnr)
        -- shebang configuration
        local content = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''
        if vim.regex([[^#!.*\<node\>]]):match_str(content) then
          return 'javascript'
        elseif vim.regex([[^#!.*\<osascript\>]]):match_str(content) then
          return 'applescript'
        elseif vim.regex([[^#!.*\(pipx\|python\|python3\)]]):match_str(content) then
          return 'python'
        end
      end,
    },
  },
}
