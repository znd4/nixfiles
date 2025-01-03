#!/usr/bin/env bash
set -euo pipefail
# set -x
NVIM="${NVIM:-nvim}"
input=$(mktemp)
cat - > "$input"
output=$(mktemp)
script=$(mktemp)
echo "
require('telescope.pickers').new({
    finder = require('telescope.finders').new_oneshot_job({'cat', '$input'}),
    sorter = require('telescope.sorters').get_generic_fuzzy_sorter(),
    layout_config = {
        horizontal = {
            width = 0.99,
            height = 0.99,
        },
        vertical = {
            width = 0.99,
            height = 0.99,
        },
    },
    attach_mappings = function(prompt_bufnr, map)
        local function send_to_output(prompt_bufnr)
            local selection = require('telescope.actions.state').get_selected_entry()
            vim.fn.writefile({selection.value}, '$output')
            require('telescope.actions').close(prompt_bufnr)
            vim.cmd.quit()
        end

        map('i', '<CR>', send_to_output)
        map('n', '<CR>', send_to_output)
        map('n', '<esc>', function(prompt_bufnr)
            require('telescope.actions').close(prompt_bufnr)
            vim.cmd.quit()
        end)

        return true
    end,
}):find()
" > "$script"
if [ ! -t 0 ]; then
  ${NVIM?} \
    -c "lua assert(loadfile('${script}'))()" \
    < /dev/tty > /dev/tty
fi
cat "$output"
