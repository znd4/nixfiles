return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = {
    sections = {
      lualine_c = {
        {
          "filename",
          path = 1, -- relative path
          -- path = 4, -- filename and parent dir, with tilde as the home directory
        },
      },
    },
  },
}
