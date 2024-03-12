local org_dir = os.getenv("OBSIDIAN_VAULT") or os.getenv("HOME") .. "/logseq-graph/"
-- mkdir if not exist
if vim.fn.isdirectory(org_dir) == 0 then
  print("logseq vault not present")
  return
end
-- TODO: Convert :LSPLog to TODO list
-- TODO: Write yr and yg commands to query you.com
-- TODO: Configure hypridle properly
-- TODO: Set up automated TODO processor on this website
-- TODO: install latest clipboard-jh and test in wezterm / kitty
-- TODO: Try setting up launcher with arguments (https://you.com/search?q=Which+Linux+launchers+allow+for+passing+arguments%3F&cid=c1_0b3143fc-e873-4c61-9f69-3900a6aa0ba0&tbm=youchat)

require("orgmode").setup({
  org_agenda_files = { org_dir .. "/*" },
  org_default_notes_file = org_dir .. "/refile.org",
  org_agenda_templates = {
    m = {
      description = "Magic card wishlist",
      target = org_dir .. "magic_wishlist.org",
      template = "%^{Card name}",
    },
    j = {
      description = "Jobs to apply to",
      target = org_dir .. "jobs.org",
      template = "* TODO %?\n  %u",
    },
    t = { description = "Task", template = "* TODO %?\n  %u" },
  },
})
