local M = {}
local ns = vim.api.nvim_create_namespace("todo_plugin")

local todo_file = "todo.TODO"

local ICON_PENDING = "✖"
local ICON_DONE = "✓"

local function ensure_todo_file()
	local cwd = vim.fn.getcwd()
	local path = cwd .. "/" .. todo_file

	if vim.fn.filereadable(path) == 0 then
		vim.fn.writefile({}, path)
	end

	return path
end

local function add_to_gitignore()
	local gitignore = vim.fn.getcwd() .. "/.gitignore"

	if vim.fn.filereadable(gitignore) == 1 then
		local lines = vim.fn.readfile(gitignore)

		for _, line in ipairs(lines) do
			if line == "todo.TODO" then
				return
			end
		end

		table.insert(lines, "todo.TODO")
		vim.fn.writefile(lines, gitignore)
	end
end

local function read_todos(path)
	local lines = vim.fn.readfile(path)

	for i, line in ipairs(lines) do
		line = line:gsub("%[ %]", ICON_PENDING)
		line = line:gsub("%[x%]", ICON_DONE)
		lines[i] = line
	end

	return lines
end

local function extract_todo_from_line()
	local line = vim.api.nvim_get_current_line()

	local text = line:match("TODO:%s*(.+)")

	if text then
		local file = vim.fn.expand("%:p")
		local row = vim.api.nvim_win_get_cursor(0)[1]
		return string.format(" %s (%s:%d)", text, file, row)
	end

	return nil
end

local function parse_location(line)
	local file, row = line:match("%((.+):(%d+)%)")
	if file and row then
		return file, tonumber(row)
	end

	return nil, nil
end

local function open_todo_location(buf)
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]

	if not line then
		return
	end

	local file, target_row = parse_location(line)

	if not file then
		vim.notify("Nothing found", vim.log.levels.ERROR)
		return
	end

	vim.api.nvim_win_close(0, true)
	vim.cmd("edit " .. file)

	vim.api.nvim_win_set_cursor(0, { target_row, 0 })
end

local function highlight_todos(buf)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	for i, line in ipairs(lines) do
		if line:find(ICON_PENDING, 1, true) then
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
				end_line = i - 1,
				end_col = #line,
				hl_group = "TodoPending",
			})
		elseif line:find(ICON_DONE, 1, true) then
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
				end_line = i - 1,
				end_col = #line,
				hl_group = "TodoDone",
			})
		end
	end
end

local function telescope_todos(path)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local lines = vim.fn.readfile(path)

	pickers
		.new({}, {
			prompt_title = "TODO",
			finder = finders.new_table({
				result = lines,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					vim.cmd("edit " .. path)
					vim.api.nvim_win_set_cursor(0, { selection.index, 0 })
				end)

				return true
			end,
		})
		:find()
end

local function create_window(lines)
	local buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_set_hl(0, "TodoPending", { fg = "#E5C07B" })
	vim.api.nvim_set_hl(0, "TodoDone", { fg = "#98C379" })

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	highlight_todos(buf)

	local width = math.floor(vim.o.columns * 0.5)
	local height = math.floor(vim.o.lines * 0.5)

	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
	}

	local win = vim.api.nvim_open_win(buf, true, opts)

	return buf, win
end

local function toggle_todo(buf)
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]

	if not line then
		return
	end

	if line:match(ICON_PENDING) then
		line = line:gsub(ICON_PENDING, ICON_DONE)
	elseif line:match(ICON_DONE) then
		line = line:gsub(ICON_DONE, ICON_PENDING)
	end

	vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { line })

	highlight_todos(buf)
end

local function add_todo_from_code()
	local text = extract_todo_from_line()

	if not text then
		vim.notify("No TODO find", vim.log.levels.WARN)
		return
	end

	local path = ensure_todo_file()

	local lines = vim.fn.readfile(path)
	table.insert(lines, ICON_PENDING .. " " .. text)

	vim.fn.writefile(lines, path)

	vim.notify("TODO: " .. text .. " added")
end

local function add_todo(buf)
	vim.ui.input({ prompt = "Nuovo TODO: " }, function(input)
		if not input or input == "" then
			return
		end

		local line = ICON_PENDING .. " " .. input
		local line_count = vim.api.nvim_buf_line_count(buf)

		vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { line })
	end)
end

local function normalize_for_save(lines)
	local result = {}
	for _, line in ipairs(lines) do
		line = line:gsub(ICON_PENDING, "[ ]")
		line = line:gsub(ICON_DONE, "[x]")
		table.insert(result, line)
	end

	return result
end

local function attach_autosave(buf, path)
	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function()
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			vim.fn.writefile(normalize_for_save(lines), path)
		end,
	})
end

local function attach_mappings(buf)
	vim.keymap.set("n", "<CR>", function()
		toggle_todo(buf)
	end, { buffer = buf })

	vim.keymap.set("n", "a", function()
		add_todo(buf)
	end, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(0, true)
	end, { buffer = buf })

	vim.keymap.set("n", "<Space>", function()
		open_todo_location(buf)
	end, { buffer = buf })
end

function M.setup()
	vim.api.nvim_create_user_command("Todo", function()
		local path = ensure_todo_file()
		add_to_gitignore()

		local todos = read_todos(path)
		local buf, _ = create_window(todos)

		attach_mappings(buf)
		attach_autosave(buf, path)

		vim.bo[buf].modifiable = true
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false

		vim.wo.cursorline = true
	end, {})

	vim.api.nvim_create_user_command("TodoSearch", function()
		local path = ensure_todo_file()
		telescope_todos(path)
	end, {})

	vim.api.nvim_create_user_command("TodoFromCode", function()
		add_todo_from_code()
	end, {})
end

return M
