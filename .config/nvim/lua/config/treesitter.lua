require("orgmode").setup_ts_grammar()

-- trick treesitter into thinking zsh files are bash
local ft_to_lang = require("nvim-treesitter.parsers").ft_to_lang
require("nvim-treesitter.parsers").ft_to_lang = function(ft)
    if ft == "zsh" then
        return "bash"
    elseif ft == "xml" then
        return "html"
    end
    return ft_to_lang(ft)
end

vim.filetype.add({
    extension = {
        sh = "bash",
        yml = "yaml",
    },
    filename = {
        ["justfile"] = "justfile",
    },
})

require("nvim-treesitter.install").prefer_git = true

require("nvim-treesitter.configs").setup({
    textobjects = {
        select = {
            enable = true,

            -- Automatically jump forward to textobj, similar to targets.vim
            lookahead = true,

            keymaps = {
                ["ab"] = "@block.outer",
                ["ib"] = "@block.inner",

                -- You can use the capture groups defined in textobjects.scm
                ["af"] = "@function.outer",
                ["if"] = "@function.inner",

                ["al"] = "@call.outer",
                ["il"] = { query = "@call.inner", desc = "Select inner part of a function call" },
            },
            -- You can choose the select mode (default is charwise 'v')
            selection_modes = {
                ["@parameter.outer"] = "v", -- charwise
                ["@function.outer"] = "V", -- linewise
                ["@class.outer"] = "<c-v>", -- blockwise
            },
            -- If you set this to `true` (default is `false`) then any textobject is
            -- extended to include preceding xor succeeding whitespace. Succeeding
            -- whitespace has priority in order to act similarly to eg the built-in
            -- `ap`.
            -- include_surrounding_whitespace = true,
        },
        move = {
            enable = true,
            set_jumps = true, -- whether to set jumps in the jumplist
            goto_next_start = {
                ["]m"] = "@function.outer",
                ["]]"] = "@class.outer",
            },
            goto_next_end = {
                ["]M"] = "@function.outer",
                ["]["] = "@class.outer",
            },
            goto_previous_start = {
                ["[m"] = "@function.outer",
                ["[["] = "@class.outer",
            },
            goto_previous_end = {
                ["[M"] = "@function.outer",
                ["[]"] = "@class.outer",
            },
        },
        swap = {
            enable = true,
            swap_next = {
                ["<leader>a"] = "@parameter.inner",
                ["<leader>o"] = "@binary_operator",
            },
            swap_previous = {
                ["<leader>A"] = "@parameter.inner",
                ["<leader>O"] = "@binary_operator",
            },
        },
    },
    ensure_installed = {
        "bash",
        "kotlin",
        "go",
        "gomod",
        "json",
        "lua",
        "markdown",
        "org",
        "python",
        "comment",
        "sql",
    },
    auto_install = true,
    highlight = {
        enable = true,
        -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
        -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
        -- Using this option may slow down your editor, and you may see some duplicate highlights.
        -- Instead of true it can also be a list of languages
        additional_vim_regex_highlighting = { "org", "vim" },
    },
    incremental_selection = {
        enable = true,
        keymaps = {
            init_selection = "gnn",
            node_incremental = "grn",
            scope_incremental = "grc",
            node_decremental = "grm",
        },
    },
    indent = {
        enable = true,
    },
})
