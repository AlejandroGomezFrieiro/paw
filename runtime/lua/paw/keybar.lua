-- The line of keys at the bottom of the screen: the few keys worth knowing
-- first, for the view and the mode you are in. `?` lists them all.
--
-- An extension adds a line for its own view:
--   paw.ui.keybar.set("myview", "n", { { "<CR>", "open" }, { "x", "delete" } })
-- Each entry is a key as mappings write it and a word or two for what it
-- does; a third value replaces how the key is shown. An entry whose key is
-- "" is no key but news, shown as one: the note insert mode is drawing. A
-- line that changes as you type is a function that returns the entries.
local M = { lines = {} }

--- Set the keys shown for a view in a mode ("n", "x", "i").
function M.set(view, mode, entries)
  M.lines[view] = M.lines[view] or {}
  M.lines[view][mode] = entries
  paw.api.ui_redraw()
end

local names = { ["<Space>"] = "Space", ["<CR>"] = "Enter", ["<Esc>"] = "Esc", ["<BS>"] = "Bksp", ["<Tab>"] = "Tab", ["<lt>"] = "<" }

--- A key as a person reads it: `<leader>m` is `Space m`, `<C-w>c` is `Ctrl-w c`.
function M.show(lhs)
  if lhs:lower():find("leader>", 1, true) then return paw.keymap.human(lhs) end
  local out = paw.keymap.expand(lhs)
  out = out:gsub("<C%-(.)>(.*)", "Ctrl-%1 %2"):gsub("%s+$", "")
  return names[out] or out
end

--- The entries for what has the keyboard now, as `{ shown key, text }`.
function M.entries()
  local view = paw.ui.focused
  local mode = paw.keymap.mode
  local lines = M.lines[view]
  -- A part of the view whose keys come first (a suggestion showing) has
  -- its own line, when it sets one.
  local v = paw.ui.views[view]
  if v and v.subscope then
    local ok, sub = pcall(v.subscope, v)
    if ok and type(sub) == "table" then sub = sub[1] end
    if ok and sub and M.lines[sub] and M.lines[sub][mode] then lines = M.lines[sub] end
  end
  -- A view that takes every key itself has none of the usual ones.
  local modal = paw.ui.views[view] and paw.ui.views[view].modal
  if modal and not lines then return {} end
  local entries = lines and (lines[mode] or mode ~= "n" and {} or nil) or mode == "n" and M.lines.default.n or {}
  if type(entries) == "function" then entries = entries() end
  local out = {}
  for i, entry in ipairs(entries or {}) do out[i] = { entry[3] or M.show(entry[1]), entry[2] } end
  return out
end

--- The keys shown that nothing is mapped to, as `view mode key` strings:
--- empty when every line tells the truth.
function M.check()
  local wrong = {}
  for view, modes in pairs(M.lines) do
    for mode, entries in pairs(modes) do
      if type(entries) == "function" then entries = entries() or {} end
      local mapped = {}
      for _, map in ipairs(paw.keymap.list(mode, view ~= "default" and view or nil)) do mapped[map.lhs] = true end
      for _, entry in ipairs(entries) do
        -- Leaving a mode with Escape is not a mapping: it always works.
        local built_in = entry[1] == "<Esc>" and mode ~= "n" or entry[1] == ""
        if not mapped[entry[1]] and not built_in then wrong[#wrong + 1] = view .. " " .. mode .. " " .. entry[1] end
      end
    end
  end
  table.sort(wrong)
  return wrong
end

M.lines.default = {
  n = { { "<Tab>", "next panel" }, { "<leader>fc", "commands" }, { "?", "keys" } },
}
M.lines.arrange = {
  n = {
    { "<leader><Space>", "play" }, { "o", "track" }, { "a", "device" }, { "i", "notes" }, { "<CR>", "open clip" },
    { "<leader>m", "mixer" }, { "x", "delete" }, { "u", "undo" }, { "<leader>fc", "commands" }, { "?", "keys" },
  },
  x = { { "d", "delete" }, { "y", "copy" }, { ">", "later" }, { "<lt>", "earlier" }, { "gl", "loop" }, { "<Esc>", "done" } },
}
M.lines.pianoroll = {
  n = {
    { "<CR>", "note" }, { "i", "draw notes" }, { "x", "delete" }, { "+", "up" }, { "<A-l>", "longer" },
    { "w", "next note" }, { "<leader><Space>", "play" }, { "<C-w>p", "back" }, { "?", "keys" },
  },
  x = { { "d", "delete" }, { "y", "copy" }, { ">", "later" }, { "<lt>", "earlier" }, { "<C-a>", "up" }, { "<Esc>", "done" } },
  -- Insert mode: the note being drawn, then the keys that draw it.
  i = function()
    local now = paw.roll_draw and paw.roll_draw.describe()
    local out = {
      { "l", "longer" }, { "h", "shorter" }, { "k", "up" }, { "j", "down" }, { "<CR>", "next" }, { "<Space>", "rest" },
      { "o", "chord" }, { "<Esc>", "write" },
    }
    if now then
      local pitch, length = now:match("^(%S+) · (.*)$")
      table.insert(out, 1, { "", length, pitch })
    end
    return out
  end,
}
-- Insert mode with the keyboard as a piano (`I`).
M.lines["pianoroll.keys"] = {
  i = {
    { "a", "notes, w e t y u between", "a s d f g h j k" }, { "<Space>", "rest" }, { "<BS>", "back" },
    { "z", "octave down" }, { "x", "octave up" }, { "<Esc>", "done" },
  },
}
-- The mixer's first: what the rule changed (`j` `k` move, `+` `-` change).
M.lines.mixer = {
  n = {
    { "j", "row" }, { "+", "up" }, { "-", "down" }, { "]", "pan" }, { "l", "strip" }, { "gc", "mute" },
    { "s", "solo" }, { "x", "clear" }, { "?", "keys" },
  },
  x = { { "+", "up" }, { "-", "down" }, { "]", "pan" }, { "x", "clear" }, { "<Esc>", "done" } },
}
M.lines.devices = {
  n = {
    { "j", "row" }, { "w", "device" }, { "+", "raise" }, { "-", "lower" }, { "a", "add" }, { "gc", "bypass" },
    { "<CR>", "curve" }, { "x", "remove" }, { "?", "keys" },
  },
}

return M
