local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local input_file = vim.g.search_input_file
if not input_file then
    error("search_input_file not set")
end
vim.print({ "input_file_contents", vim.fn.readfile(input_file) })

local output_file = vim.g.search_output_file
if not output_file then
    error("search_output_file not set")
end

local cmd = { "cat", input_file }

local opts = {
    finder = finders.new_oneshot_job(cmd),
    sorter = sorters.get_generic_fuzzy_sorter(),
}
local picker = pickers.new(opts)
picker:find()

vim.print({ "output_file_contents", vim.fn.readfile(output_file) })
