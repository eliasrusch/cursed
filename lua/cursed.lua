local M = {}

-- a alternative cursors with <M-c>[+-*]
-- then type <M-C> to edit at all cursor positions
-- <M-c>_ collapses all cursors to real cursor

local function get_highlight(group, attr)
  local hl = vim.api.nvim_get_hl_by_name(group, true)
  if hl[attr] then
    return string.format("#%06x", hl[attr])
  end
end

local function set_highlight(group, ref_group, attr1, attr2)
  local color1 = get_highlight(ref_group, attr1)
  local color2 = get_highlight(ref_group, attr2)
  if color1 and color2 then
    vim.cmd(string.format("highlight %s guifg=%s guibg=%s", group, color1, color2))
  end
end

local function gen_virt_text(char)
  if char == "" then
    return " "
  else
    return char
  end
end

function remove_and_resort(table, index)
  local new_table = {}
  for i, v in ipairs(table) do
    if i ~= index then
      new_table[#new_table + 1] = v
    end
  end
  return new_table
end

function M.spairs(t, order)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end

  if order then
    table.sort(keys, function(a, b)
      return order(t, a, b)
    end)
  else
    table.sort(keys)
  end
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

function M.run_autocommands()
  vim.api.nvim_command("augroup cursed")
  vim.api.nvim_command("autocmd!")
  vim.api.nvim_command("autocmd ColorScheme * lua require'cursed'.init_highlight_group()")

  vim.api.nvim_command("autocmd CursorMoved * lua require'cursed'.edit()")
  vim.api.nvim_command("autocmd CursorMovedI * lua require'cursed'.edit()")
  vim.api.nvim_command("autocmd CursorMoved * lua require'cursed'.update_cursor()")
  vim.api.nvim_command("autocmd CursorMovedI * lua require'cursed'.update_cursor()")
  vim.api.nvim_command("autocmd TextChanged * lua require'cursed'.draw_cursors()")
  vim.api.nvim_command("autocmd TextChangedI * lua require'cursed'.draw_cursors()")
  vim.api.nvim_command("augroup end")
end

function M.edit()
  if M.is_editing and vim.api.nvim_get_mode()["mode"] == "n" then
    M.is_editing = false

    vim.api.nvim_feedkeys("q", "n", true)

    local win_id = vim.api.nvim_get_current_win()
    local main_c = M.active_cursor

    for i, v in ipairs(M.cursors) do
      if i == main_c then
        goto continue
      end

      local pos = { v["row"] + 1, v["col"] }
      M.active_cursor = i
      vim.api.nvim_win_set_cursor(win_id, pos)
      vim.api.nvim_feedkeys("@z", "n", true)
      M.update_cursor()
      ::continue::
    end

    vim.api.nvim_feedkeys("qz", "n", true)

    M.is_editing = true
  end
end

function M.update_cursor()
  local win_id = vim.api.nvim_get_current_win()
  local row = vim.api.nvim_win_get_cursor(win_id)[1] - 1
  local col = vim.api.nvim_win_get_cursor(win_id)[2]

  M.cursors[M.active_cursor] = {
    row = row,
    col = col,
  }

  M.draw_cursors()
end

function M.init_highlight_group()
  set_highlight("cursed_cursor", "Cursor", "foreground", "background")
  namespace = "cursed"
  namespace_id = vim.api.nvim_create_namespace(namespace)
end

M.cursors = {}
M.active_cursor = 1

local function get_line_by_number(buf_id, line)
  local start_line = line
  local end_line = line + 1

  local lines = vim.api.nvim_buf_get_lines(buf_id, start_line, end_line, false)

  return lines[1]
end

function M.draw_cursors()
  local buffer_id = vim.api.nvim_get_current_buf()

  for i, v in ipairs(M.cursors) do
    if i == M.active_cursor then
      goto continue
    end

    local row = v["row"]
    local col = v["col"]
    local id = i

    vim.api.nvim_buf_del_extmark(buffer_id, namespace_id, id)
    vim.api.nvim_buf_set_extmark(buffer_id, namespace_id, row, col, {
      id = id,
      virt_text = {
        {
          tostring(i), -- gen_virt_text(string.sub(get_line_by_number(buffer_id, row), col + 1, col + 1))
          "cursed_cursor",
        },
      },
      virt_text_pos = "overlay",
      right_gravity = false,
    })
    ::continue::
  end
  -- print(vim.inspect(M.cursors))
end

function M.create_cursor()
  local win_id = vim.api.nvim_get_current_win()
  local row = vim.api.nvim_win_get_cursor(win_id)[1] - 1
  local col = vim.api.nvim_win_get_cursor(win_id)[2]

  M.cursors[#M.cursors + 1] = {
    row = row,
    col = col,
  }

  M.active_cursor = #M.cursors

  M.draw_cursors()
end

function M.cursor_order()
  return M.spairs(M.cursors, function(t, a, b)
    if t[a]["row"] < t[b]["row"] then
      return true
    elseif t[a]["row"] == t[b]["row"] then
      return t[a]["col"] < t[b]["col"]
    else
      return false
    end
  end)
end

function M.cycle_cursor(direction)
  local idx = M.active_cursor

  for i, v in M.cursor_order() do
    if v == M.cursors[M.active_cursor] then
      idx = i
    end
  end

  if direction == "up" then
    if idx == 1 then
      -- last
      for i, v in M.cursor_order() do
        M.active_cursor = i
      end
    else
      for i, v in M.cursor_order() do
        if i+1 == idx then
          M.active_cursor = i
          break
        end
      end
    end
  elseif direction == "down" then
    if M.active_cursor == #M.cursors then
      M.active_cursor = 1
    else
      M.active_cursor = M.active_cursor + 1
    end
  end

  local win_id = vim.api.nvim_get_current_win()
  local c = M.cursors[M.active_cursor]
  vim.api.nvim_win_set_cursor(win_id, { c["row"] + 1, c["col"] })
end

function M.delete_cursor()
  local c = M.cursors[M.active_cursor]

  for i, v in ipairs(M.cursors) do
    if i == M.active_cursor then
      goto continue
    end

    if v["row"] == c["row"] and v["col"] == c["col"] then
      M.cursors = remove_and_resort(M.cursors, i)
      if i < M.active_cursor then
        M.active_cursor = M.active_cursor - 1
      end
    end

    ::continue::
  end

  M.draw_cursors()
end

M.is_editing = false
M.m = ""
M.mt = nil

function save_z_reg()
  local z_register_contents = vim.fn.getreg("z")
  local z_register_type = vim.fn.getregtype("z")
  return z_register_contents, z_register_type
end

function restore_z_reg(contents, reg_type)
  vim.fn.setreg("z", contents, reg_type)
end

function M.toggle_editing()
  M.is_editing = not M.is_editing
  if M.is_editing then
    M.start_editing()
  else
    M.stop_editing()
  end
end

function M.start_editing()
  M.m, M.mt = save_z_reg()
  vim.api.nvim_feedkeys("qz", "n", true)
end

function M.stop_editing()
  vim.api.nvim_feedkeys("q", "n", true)
  restore_z_reg(M.m, M.mt)
end

function M.setup()
  require("cursed").init_highlight_group()
  require("cursed").run_autocommands()
  -- set keymaps
  vim.keymap.set("n", "<M-c>+", "<cmd>lua require'cursed'.create_cursor()<cr>")
  vim.keymap.set("n", "<M-c>-", "<cmd>lua require'cursed'.delete_cursor()<cr>")
  vim.keymap.set("n", "<M-c><Up>", "<cmd>lua require'cursed'.cycle_cursor('up')<cr>")
  vim.keymap.set("n", "<M-c><Down>", "<cmd>lua require'cursed'.cycle_cursor('down')<cr>")
  vim.keymap.set({ "n", "i", "v" }, "<M-C>", "<cmd>lua require'cursed'.toggle_editing()<cr>")
end

return M
