-- The line of keys at the bottom of the screen: the few keys worth knowing
-- first, for the view and the mode you are in. `?` lists them all.
--
-- An extension adds a line for its own view:
--   paw.ui.keybar.set("myview", "n", { { "<CR>", "open" }, { "x", "delete" } })
-- Each entry is a key as mappings write it and a word or two for what it
-- does; a third value replaces how the key is shown. An entry whose key is
-- "" is no key but news, shown as one: the note insert mode is drawing. A
-- line that changes as you type is a function that returns the entries.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local registry = require("paw.registry")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type DrawModule = require("paw.draw")

--- An entry of a line: the key as mappings write it, what it does, and
--- how to show the key in place of the key itself (optional).
local type Entry = {string}
--- A line that changes as you type: a function that gives the entries.
local type EntriesFn = function(): {Entry}
--- The entries of a line, or the function that gives them.
local type Line = {Entry} | EntriesFn
--- An entry as the screen shows it: the key as a person reads it, and the text.
local type Shown = DrawModule.KeyHint

-- paw/ui.tl, paw/insert.tl and paw/roll_draw.tl name this module's types
-- (paw/ui.tl keeps it as `paw.ui.keybar`), so this module declares only
-- the parts of them that it reads.
local record Ui
  focused: string
  views: registry.Registry<contracts.View>
end
local record InsertKind
  key: string
  desc: string
end
local record Insert
  count: function(): integer
  list: function(): {InsertKind}
end
local record RollDraw
  stepping: function(): boolean
  describe: function(): string
  edge_now: function(): string
  list: function(): {InsertKind}
end
local record Paw is partial.Paw
  ui: Ui
  keymap: KeymapModule
  insert: Insert
  roll_draw: RollDraw
end
local paw = (_G as {string: Paw}).paw

local record M
  type Entry = Entry
  type EntriesFn = EntriesFn
  type Line = Line
  type Shown = Shown
  --- The lines by view (or a part of a view, or "default"), then by mode.
  --- Made from `registry`.
  lines: {string: {string: Line}}
  --- The lines by `"<view> <mode>"`, with the extension that set each one.
  registry: registry.Registry<Line>
end
M.lines = {}
M.registry = registry.new(
  "keybar",
  "key bar lines",
  {
    changed = function(key: string, line: Line)
      local view, mode = key:match("^(%S+) (.*)$")
      M.lines[view] = M.lines[view] or {}
      M.lines[view][mode] = line
      if next(M.lines[view]) == nil then
        M.lines[view] = nil
      end
      api.ui_redraw()
    end,
  }
)

--- Set the keys shown for a view in a mode ("n", "x", "i"). Nil takes the
--- line away.
function M.set(view: string, mode: string, entries: Line)
  if entries then
    M.registry:put(view .. " " .. mode, entries)
  else
    M.registry:remove(view .. " " .. mode)
  end
end

--- Set the line of each mode of a view: `modes` is mode -> line.
local function set_all(view: string, modes: {string: Line})
  for mode, line in pairs(modes) do
    M.set(view, mode, line)
  end
end

local names: {string: string} = {
  ["<Space>"] = "Space", ["<CR>"] = "Enter", ["<Esc>"] = "Esc", ["<BS>"] = "Bksp", ["<Tab>"] = "Tab", ["<lt>"] = "<"
}

--- A key as a person reads it: `<leader>mm` is `Space mm`, `<C-w>c` is `Ctrl-w c`.
function M.show(lhs: string): string
  if lhs:lower():find("leader>", 1, true) then
    return paw.keymap.human(lhs)
  end
  local out = paw.keymap.expand(lhs)
  out = out:gsub("<C%-(.)>(.*)", "Ctrl-%1 %2"):gsub("%s+$", "")
  return names[out] or out
end

-- A key's `desc` as the key bar shows it: up to its first `;` `:` or
-- `,`, with no "A" or "An" before, in lower case. "A region; Enter names
-- it" is "region", "Staccato: half as long" is "staccato".
local function short_desc(desc: string): string
  local text = (desc or ""):gsub("^An? ", "")
  return (text:match("^[^;:,]+") or text):lower()
end

--- The entries of a line, called if it is a function.
local function entries_of(line: Line): {Entry}
  if line is EntriesFn then
    return line()
  end
  return line
end

--- The entries for what has the keyboard now, as `{ shown key, text }`.
function M.entries(): {Shown}
  local view = paw.ui.focused
  local mode = paw.keymap.mode as string
  local lines = M.lines[view]
  -- A part of the view whose keys come first (a suggestion showing) has
  -- its own line, when it sets one.
  local v = paw.ui.views:get(view)
  if v and v.subscope then
    local ok, sub = pcall(v.subscope, v) as (boolean, string | {string})
    local first: string
    if ok and sub is {string} then
      first = sub[1]
    elseif ok then
      first = sub as string
    end
    if first and M.lines[first] and M.lines[first][mode] then
      lines = M.lines[first]
    end
  end
  -- A view that takes every key itself has none of the usual ones.
  if v and v.modal and not lines then
    return {}
  end
  -- A view with a line of its own shows nothing in a mode it gives none
  -- for; any other view shows the default line in normal mode.
  local line: Line
  if lines then
    line = lines[mode] or (mode ~= "n" and {} or nil)
  elseif mode == "n" then
    line = M.lines.default.n
  end
  local out: {Shown} = {}
  for i, entry in ipairs(line and entries_of(line) or {}) do
    out[i] = {entry[3] or M.show(entry[1]), entry[2]}
  end
  return out
end

--- The keys shown that nothing is mapped to, as `view mode key` strings:
--- empty when every line tells the truth.
function M.check(): {string}
  local wrong: {string} = {}
  for view, modes in pairs(M.lines) do
    for mode, line in pairs(modes) do
      local mapped: {string: boolean} = {}
      for _, map in ipairs(paw.keymap.list(mode as KeymapModule.Mode, view ~= "default" and view or nil)) do
        mapped[map.lhs] = true
      end
      for _, entry in ipairs(entries_of(line) or {}) do
        -- Leaving a mode with Escape is not a mapping: it always works.
        local built_in = entry[1] == "<Esc>" and mode ~= "n" or entry[1] == ""
        if not mapped[entry[1]] and not built_in then
          wrong[#wrong + 1] = view .. " " .. mode .. " " .. entry[1]
        end
      end
    end
  end
  table.sort(wrong)
  return wrong
end

set_all(
  "default",
  {
    n = {{"<Tab>", "next panel"}, {"<leader>f:", "commands"}, {"?", "keys"}},
  }
)
set_all(
  "arrange",
  {
    n = {
      {"<leader><Space>", "play"},
      {"o", "track"},
      {"a", "device"},
      {"i", "insert"},
      {"<CR>", "open clip"},
      {"<leader>mm", "mixer"},
      {"x", "delete"},
      {"u", "undo"},
      {"<leader>f:", "commands"},
      {"?", "keys"},
    },
    x = {
      {"d", "delete"},
      {"y", "copy"},
      {">", "later"},
      {"<lt>", "earlier"},
      {"gl", "loop"},
      {"<Esc>", "done"},
    },
    -- Insert mode: the count typed, then the keys that insert (paw/insert.tl).
    i = function(): {Entry}
      local out: {Entry} = {}
      local count = paw.insert and paw.insert.count()
      if count then
        out[1] = {"", "times", tostring(count)}
      end
      for _, spec in ipairs(paw.insert and paw.insert.list() or {}) do
        out[#out + 1] = {spec.key, short_desc(spec.desc)}
      end
      for _, entry in ipairs({{"<CR>", "open"}, {"<BS>", "back"}, {"K", "keys"}, {"<Esc>", "done"}}) do
        out[#out + 1] = entry
      end
      return out
    end,
  }
)
set_all(
  "pianoroll",
  {
    n = {
      {"<CR>", "note"},
      {"i", "draw notes"},
      {"x", "delete"},
      {"+", "up"},
      {"<A-l>", "longer"},
      {"w", "next note"},
      {"<leader><Space>", "play"},
      {"<C-w>p", "back"},
      {"?", "keys"},
    },
    x = {
      {"d", "delete"},
      {"y", "copy"},
      {">", "later"},
      {"<lt>", "earlier"},
      {"<C-a>", "up"},
      {"<Esc>", "done"},
    },
    -- Insert mode: the note being drawn, then the keys that draw it.
    i = function(): {Entry}
      if paw.roll_draw and paw.roll_draw.stepping() then
        return {
          {"=", "value"},
          {"<Space>", "rest"},
          {"<BS>", "back"},
          {"c", "chord"},
          {"I", "draw"},
          {"<Esc>", "write"},
        }
      end
      local now = paw.roll_draw and paw.roll_draw.describe()
      local at_start = paw.roll_draw and paw.roll_draw.edge_now() == "start"
      local out: {Entry} = {
        {"l", at_start and "shorter" or "longer"},
        {"h", at_start and "longer" or "shorter"},
        {"o", "other edge"},
        {"+", "up"},
        {"k", "bend"},
        {"c", "chord"},
        {"<CR>", "next"},
        {"<Space>", "rest"},
      }
      -- The keys that extensions added (`paw.roll_draw.key`), in their order.
      for _, spec in ipairs(paw.roll_draw and paw.roll_draw.list() or {}) do
        out[#out + 1] = {spec.key, short_desc(spec.desc)}
      end
      out[#out + 1] = {"<Esc>", "write"}
      if now then
        local pitch, length = now:match("^(.-) · (.*)$")
        table.insert(out, 1, {"", length, pitch})
      end
      return out
    end,
  }
)
-- The mixer's first: what the rule changed (`j` `k` move, `+` `-` change).
set_all(
  "mixer",
  {
    n = {
      {"j", "row"},
      {"+", "up"},
      {"-", "down"},
      {"]", "pan"},
      {"l", "strip"},
      {"gc", "mute"},
      {"s", "solo"},
      {"x", "clear"},
      {"?", "keys"},
    },
    x = {{"+", "up"}, {"-", "down"}, {"]", "pan"}, {"x", "clear"}, {"<Esc>", "done"}},
  }
)
set_all(
  "devices",
  {
    n = {
      {"j", "row"},
      {"w", "device"},
      {"+", "raise"},
      {"-", "lower"},
      {"a", "add"},
      {"gc", "bypass"},
      {"<CR>", "curve"},
      {"x", "remove"},
      {"?", "keys"},
    },
  }
)

return M
