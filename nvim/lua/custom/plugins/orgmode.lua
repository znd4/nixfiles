local org_dir = os.getenv 'ORGDIR' or (os.getenv 'HOME' .. '/knowledge/')
-- mkdir if not exist
if vim.fn.isdirectory(org_dir) == 0 then
  print 'logseq vault not present'
  return
end
return {
  'nvim-orgmode/orgmode',
  dependencies = {
    { 'nvim-treesitter/nvim-treesitter', lazy = true },
  },
  event = 'VeryLazy',
  ft = { 'org', 'orgagenda', 'orghelp' },
  cmd = {
    -- TODO: test these
    'OrgAgenda',
    'OrgCapture',
  },
  config = function()
    -- Load treesitter grammar for org
    require('orgmode').setup_ts_grammar()

    -- Setup treesitter
    require('nvim-treesitter.configs').setup {
      highlight = {
        enable = true,
      },
      ensure_installed = { 'org' },
    }

    require('orgmode').setup {
      org_agenda_files = { org_dir .. '/*', org_dir .. '/pages/*', org_dir .. '/journals/*' },
      org_default_notes_file = org_dir .. '/refile.org',
      org_agenda_templates = {
        m = {
          description = 'Magic card wishlist',
          target = org_dir .. 'magic_wishlist.org',
          template = '%^{Card name}',
        },
        j = {
          description = 'Jobs to apply to',
          target = org_dir .. 'jobs.org',
          template = '* TODO %?\n  %u',
        },
        t = { description = 'Task', template = '* TODO %?\n  %u' },
      },
    }
  end,
}
