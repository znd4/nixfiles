local leader = "<leader>"
local factory = function(func, ...)
  local args = { ... }
  return function()
    func(unpack(args))
  end
end

local get_project_root = function()
  local result = vim.fn.system("git rev-parse --show-toplevel")
  result = string.gsub(result, "^%s*(.-)%s*$", "%1")
  return result
end

local delayed = function(module, method, ...)
  local args = { ... }
  return function()
    local ok, lib = pcall(require, module)
    if not ok then
      -- error
      vim.api.nvim_err_writeln("Error loading " .. module)
      return
    end
    lib[method](unpack(args))
  end
end

local config = function()
  local telescope = require("telescope")
  local actions = require("telescope.actions")
  telescope.setup({
    extensions = {
      zoxide = {
        mappings = {
          default = {
            action = function(selection)
              vim.cmd.cd({ selection.path })
              vim.cmd.edit({ selection.path })
            end,
          },
        },
      },
    },
    pickers = {
      find_files = {
        hidden = true,
      },
      builtin = {
        include_extensions = true,
      },
      man_pages = {
        sections = { "1", "4", "5" },
      },
    },
    defaults = {
      file_ignore_patterns = { "%.git/*", "rpc/*" },
      vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--hidden",
        "--smart-case",
      },
      mappings = {
        n = {
          [","] = telescope.extensions.hop.hop,
          -- map backspace to delete_buffer
          ["<BS>"] = actions.delete_buffer,
        },
        i = {
          ["<C-BS>"] = actions.delete_buffer,
          ["<C-,>"] = telescope.extensions.hop.hop, -- hop.hop_toggle_selection
          -- custom hop loop to multi selects and sending selected entries to quickfix list
          ["<C-space>"] = function(prompt_bufnr)
            local opts = {
              callback = actions.toggle_selection,
              loop_callback = actions.send_selected_to_qflist,
            }
            telescope.extensions.hop._hop_loop(prompt_bufnr, opts)
          end,
        },
      },
    },
  })
  telescope.load_extension("hop")
  telescope.load_extension("file_browser")
end
return {
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope-file-browser.nvim" },
  init = function()
    local vimp = require("vimp")
    local builtin = require("telescope.builtin")
    vimp.map_command("Buffers", factory(builtin.buffers))
    vimp.map_command("Projects", factory(vim.cmd.Telescope, "projects"))
    vimp.map_command("Help", factory(builtin.help_tags))
    vimp.map_command("GF", factory(builtin.git_files))
    vimp.map_command("GS", factory(builtin.git_status))
    vimp.map_command("Commands", factory(builtin.commands))
    vimp.map_command("Files", factory(builtin.find_files))
  end,
  config = config,
  keys = {
    {
      leader .. "ff",
      delayed("telescope.builtin", "find_files"),
      desc = "Telescope find files (current directory)",
    },
    {
      leader .. "fF",
      function()
        require("telescope.builtin").find_files({
          cwd = get_project_root(),
        })
      end,
      desc = "Telescope find files (project root)",
    },
    {
      leader .. "fg",
      delayed("telescope.builtin", "live_grep"),
      desc = "Telescope live grep (current directory)",
    },
    {
      leader .. "fG",
      function()
        require("telescope.builtin").live_grep({
          cwd = get_project_root(),
        })
      end,
      desc = "Telescope live grep (project root)",
    },
    {
      leader .. "fa",
      factory(vim.cmd.Telescope, "file_browser"),
      desc = "Telescope file browser",
    },
    {
      leader .. "fb",
      delayed("telescope.builtin", "buffers"),
      desc = "Telescope buffers",
    },
    {
      leader .. "fh",
      delayed("telescope.builtin", "help_tags"),
      desc = "Telescope help tags",
    },
    {
      leader .. "fp",
      factory(vim.cmd.Telescope, "projects"),
      desc = "Telescope projects",
    },
    {
      leader .. "fd",
      delayed("telescope.builtin", "current_buffer_fuzzy_find"),
      desc = "Telescope lsp_document_symbols",
    },
    {
      leader .. "fl",
      delayed("telescope.builtin", "lsp_dynamic_workspace_symbols"),
      desc = "Telescope lsp_dynamic_workspace_symbols",
    },
    {
      leader .. "fc",
      delayed("telescope.builtin", "commands"),
      desc = "Telescope commands",
    },
    {
      leader .. "fs",
      delayed("telescope.builtin", "git_status"),
      desc = "Search git status",
    },
    {
      leader .. "fm",
      delayed("telescope.builtin", "keymaps"),
      desc = "Telescope keymaps",
    },
    {
      leader .. "t",
      ":Telescope<CR>",
      desc = "telescope builtins",
    },
  },
  priority = 2,
}
