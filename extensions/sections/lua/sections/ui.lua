-- Commands, keys, the list to jump from, and the ruler.
local api = paw.api
local S = require("sections")
local A = require("sections.arrange")
local keymap, cursor = paw.keymap, paw.cursor
local EPS = 1e-9

local M = {}

-- Names offered when adding or renaming a section.
M.names = {
  "Intro",
  "Verse",
  "Pre-Chorus",
  "Chorus",
  "Post-Chorus",
  "Bridge",
  "Breakdown",
  "Build",
  "Drop",
  "Solo",
  "Interlude",
  "Outro",
}

local function complete(text)
  local out, wanted = {}, text:lower()
  local seen = {}
  local function offer(name)
    if not seen[name] and name:lower():sub(1, #wanted) == wanted then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  for _, s in ipairs(S.list()) do
    offer(s.name)
  end
  for _, name in ipairs(M.names) do
    offer(name)
  end
  return out
end

local function bar_of(beat) return paw.time.bar_of(beat + EPS) end

--- One line describing a section, for lists.
function M.describe(s)
  -- Whole bars of the signature map, and the part of one left over.
  local first, last = paw.time.bar_of(s.start + EPS), paw.time.bar_of(s.finish - EPS)
  local bars = last
    - first
    + (s.finish - paw.time.bar_start(last)) / paw.time.bar(s.finish - EPS)
    - (s.start - paw.time.bar_start(first)) / paw.time.bar(s.start + EPS)
  bars = math.floor(bars * 1000 + 0.5) / 1000
  return string.format("%-16s bar %-4d %g bar%s", s.name, bar_of(s.start), bars, bars == 1 and "" or "s")
end

--- Go to a section's start, remembering where the cursor was for `<C-o>`.
function M.jump(s)
  if paw.ui.focused ~= "arrange" then paw.ui.focus("arrange") end
  keymap.push_jump()
  cursor.set_beat(s.start)
end

--- Choose a section and call `fn(section)`: with the picker if there is one,
--- otherwise by typing its name (Tab completes).
function M.choose(title, fn)
  local list = S.list()
  if #list == 0 then return paw.notify("no sections yet: `<localleader>Sa` adds one at the cursor", "warn") end
  if paw.pick then
    local items = {}
    for i, s in ipairs(list) do
      items[i] = { text = M.describe(s), start = s.start, section = s }
    end
    return paw.pick({
      title = title,
      items = items,
      on_choose = function(item)
        local s = item and S.at(item.start)
        if s then fn(s) end
      end,
    })
  end
  paw.ui.input({
    prompt = title .. ": ",
    complete = function(text)
      local out = {}
      for _, s in ipairs(list) do
        if s.name:lower():sub(1, #text) == text:lower() then out[#out + 1] = s.name end
      end
      return out
    end,
  }, function(text)
    if text == "" then return end
    local s = tonumber(text) and S.get(tonumber(text)) or S.find(text)
    if not s then return paw.notify("no section `" .. text .. "`", "warn") end
    fn(s)
  end)
end

-- Commands --------------------------------------------------------------------------

local command = paw.command

--- The section a command names (`ctx.args[1]`), or the one under the cursor.
local function target(ctx, key) return S.need(ctx.args[key or 1]) end

local function guarded(fn)
  return function(ctx)
    local ok, err = pcall(fn, ctx)
    if not ok then paw.notify(tostring(err), "warn") end
  end
end

command(
  "section.add",
  guarded(function(ctx)
    local at = tonumber(ctx.args.at) or cursor.beat
    local function add(name)
      if name == "" then return end
      local ok, err = pcall(S.add, name, at)
      if not ok then paw.notify(tostring(err), "warn") end
    end
    if ctx.args[1] then return add(table.concat(ctx.args, " ")) end
    local here = S.at(at)
    paw.ui.input({
      prompt = "Section at bar " .. bar_of(at) .. ": ",
      complete = complete,
      text = here and math.abs(here.start - at) < EPS and here.name or nil,
    }, add)
  end),
  { desc = "Add a section at the cursor: `section.add Chorus`, `section.add Outro at=64`" }
)

command(
  "section.rename",
  guarded(function(ctx)
    local s = target(ctx, "section")
    local function rename(name)
      if name == "" then return end
      local ok, err = pcall(S.rename, s.start and { start = s.start }, name)
      if not ok then paw.notify(tostring(err), "warn") end
    end
    if ctx.args[1] then return rename(table.concat(ctx.args, " ")) end
    paw.ui.input({ prompt = "Rename " .. s.name .. " to: ", text = s.name, complete = complete }, rename)
  end),
  { desc = "Rename the section at the cursor: `section.rename Hook`, or another: `section.rename Hook section=Chorus`" }
)

command(
  "section.remove",
  guarded(function(ctx)
    local s = target(ctx)
    S.remove({ start = s.start })
    paw.notify("removed section " .. s.name .. "; what was in it stays")
  end),
  { desc = "Remove the section marker at the cursor, or a named one; the timeline stays as it is" }
)

command(
  "section.list",
  function() require("sections.view").open() end,
  { desc = "List the sections, to go to, rename, add and remove" }
)

command("section.goto", function(ctx)
  if ctx.args[1] then
    local s = tonumber(ctx.args[1]) and S.get(tonumber(ctx.args[1])) or S.find(table.concat(ctx.args, " "))
    if not s then return paw.notify("no section `" .. table.concat(ctx.args, " ") .. "`", "warn") end
    return M.jump(s)
  end
  M.choose("Go to section", M.jump)
end, {
  desc = "Go to a section: `section.goto chorus`, `section.goto 3`, or choose from the list",
  complete = function()
    local out = {}
    for _, s in ipairs(S.list()) do
      out[#out + 1] = s.name
    end
    return out
  end,
})

command(
  "section.move",
  guarded(function(ctx)
    local by = tonumber(ctx.args.by) or 1
    by = by * (ctx.count or 1)
    local s = A.move(target(ctx), by)
    if s then cursor.set_beat(s.start) end
  end),
  { desc = "Move the section past the next one on every part: `section.move by=-1` past the one before" }
)

command(
  "section.duplicate",
  guarded(function(ctx)
    local copy
    for _ = 1, ctx.count or 1 do
      copy = A.duplicate(target(ctx))
    end
    if copy then cursor.set_beat(copy.start) end
  end),
  { desc = "Repeat the section after itself on every part, pushing the rest along" }
)

command(
  "section.delete",
  guarded(function(ctx)
    local s = target(ctx)
    keymap.setreg(A.delete({ start = s.start }), ctx.register)
    cursor.set_beat(s.start)
    paw.notify("deleted section " .. s.name)
  end),
  { desc = "Delete the section from every part and close the gap; `section.put` puts it back elsewhere" }
)

command(
  "section.yank",
  guarded(function(ctx)
    local s = target(ctx)
    keymap.setreg(A.yank({ start = s.start }), ctx.register, true)
    paw.notify("yanked section " .. s.name)
  end),
  { desc = "Yank the section on every part, with its automation and marker" }
)

--- Where to insert: before or after the section at the cursor, or at the
--- cursor if it is before the first one.
local function insert_point(after)
  local s = S.current()
  if not s then return cursor.beat end
  return after and s.finish or s.start
end

command(
  "section.put",
  guarded(function(ctx)
    local value = keymap.getreg(ctx.register)
    local at = insert_point(not ctx.args.before)
    local s
    for _ = 1, ctx.count or 1 do
      s = A.insert(value, at)
    end
    if s then cursor.set_beat(s.start) end
  end),
  {
    desc = "Insert the register after the section at the cursor on every part, pushing the rest along; `before=true` before it",
  }
)

command(
  "section.copy",
  guarded(function(ctx)
    local after = ctx.args.after
    local function copy(s)
      local ok, err = pcall(function()
        local new = A.copy({ start = s.start }, insert_point(after))
        if new then cursor.set_beat(new.start) end
      end)
      if not ok then paw.notify(tostring(err), "warn") end
    end
    if ctx.args[1] then return copy(S.need(table.concat(ctx.args, " "))) end
    M.choose(after and "Copy after this section" or "Copy before this section", copy)
  end),
  {
    desc = "Insert a copy of a section before the one at the cursor: `section.copy Chorus`; `after=true` after it; none named: choose",
  }
)

-- Keys ------------------------------------------------------------------------------

local function amap(lhs, rhs, desc, opts)
  keymap.set(lhs, rhs, paw.util.merge({ view = "arrange", desc = desc }, opts or {}))
end

local function to_section(dir)
  return function(ctx)
    local beat = cursor.beat
    for _ = 1, ctx.count or 1 do
      local found
      if dir > 0 then
        -- Past the last section: the end of the project.
        found = S.next_start(beat)
        local length = paw.project.length or 0
        if not found and length > beat + EPS then found = length end
      else
        -- Before the first: the start of the project.
        found = S.prev_start(beat)
        if not found and beat > EPS then found = 0 end
      end
      if not found then break end
      beat = found
    end
    cursor.set_beat(beat)
  end
end

-- `]]` `[[` as in Vim: the next and the previous of the kind. `]s` `[s` stay the
-- core's, the parts of a group.
amap("]]", to_section(1), "Start of the next section", { motion = true, jump = true })
amap("[[", to_section(-1), "Start of this section, or the one before", { motion = true, jump = true })

--- The sections from the one at the cursor, `count` of them, on every part.
local function section_region(ctx, whole_bars)
  local s = S.current()
  local n = #api.part_list()
  if not s or n == 0 then return end
  local last = S.list()[math.min(#S.list(), s.index + (ctx.count or 1) - 1)]
  local c0, c1 = s.start, last.finish
  if whole_bars then
    c0 = paw.time.bar_floor(c0 + EPS)
    if not paw.tempo.is_bar_line(c1) then c1 = paw.time.bar_start(paw.time.bar_of(c1) + 1) end
  end
  return { view = "arrange", kind = "block", r0 = 1, r1 = n, c0 = c0, c1 = c1 }
end

keymap.textobject(
  "is",
  function(ctx) return section_region(ctx, false) end,
  { view = "arrange", desc = "The section, on every part (`2is` two)" }
)
keymap.textobject(
  "as",
  function(ctx) return section_region(ctx, true) end,
  { view = "arrange", desc = "The section widened to whole bars, on every part" }
)

keymap.group("<localleader>S", "sections", { view = "arrange" })
amap("<localleader>Sa", "section.add", "Add a section at the cursor")
amap("<localleader>Sr", "section.rename", "Rename the section")
amap("<localleader>Sx", "section.remove", "Remove the section marker, keeping the timeline")
amap("<localleader>Ss", "section.goto", "Go to a section from the list")
amap("<localleader>Sl", "section.list", "List the sections")
amap(
  "<localleader>SL",
  function(ctx) paw.cmd("section.move", { by = 1 }, { count = ctx.count }) end,
  "Move the section later, past the next"
)
amap(
  "<localleader>SH",
  function(ctx) paw.cmd("section.move", { by = -1 }, { count = ctx.count }) end,
  "Move the section earlier, past the one before"
)
amap(
  "<localleader>S&",
  function(ctx) paw.cmd("section.duplicate", {}, { count = ctx.count }) end,
  "Repeat the section after itself"
)
amap(
  "<localleader>Sd",
  function(ctx) paw.cmd("section.delete", {}, { register = ctx.register }) end,
  "Delete the section and close the gap"
)
amap(
  "<localleader>Sy",
  function(ctx) paw.cmd("section.yank", {}, { register = ctx.register }) end,
  "Yank the section with its marker and automation"
)
amap(
  "<localleader>Sp",
  function(ctx) paw.cmd("section.put", {}, { register = ctx.register, count = ctx.count }) end,
  "Insert the register after this section"
)
amap(
  "<localleader>SP",
  function(ctx) paw.cmd("section.put", { before = true }, { register = ctx.register, count = ctx.count }) end,
  "Insert the register before this section"
)
amap("<localleader>Sc", "section.copy", "Insert a copy of a section before this one")

-- The ruler ---------------------------------------------------------------------------

-- On the theme's palette: a section is a quiet pill, the one at the cursor
-- lit in the colour of focus.
local palette = require("paw.theme").palette
paw.ui.hl("Section", { fg = palette.fg, bg = palette.raise })
paw.ui.hl("SectionCurrent", { fg = palette.bg, bg = palette.accent, bold = true })
paw.ui.hl("SectionEdge", { fg = palette.faint })

--- The first characters of a text that fit in `width` cells.
local function clip_text(text, width)
  if width <= 0 then return "" end
  if api.str_width(text) <= width then return text end
  local out, used = {}, 0
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local w = api.str_width(ch)
    if used + w > width then break end
    out[#out + 1], used = ch, used + w
  end
  return table.concat(out)
end

--- Draw the sections on the arrange view's second ruler row: each name where its
--- section starts, the one at the cursor brighter, and the one at the left
--- edge kept in sight when its start has scrolled away. A faint line marks
--- each start across the parts.
function M.draw(_, layer)
  local list = S.list()
  if #list == 0 then return end
  local ruler = layer.ruler2 or layer.ruler
  local width = ruler.width
  local current = S.current()
  for i, s in ipairs(list) do
    local x0 = layer.x(s.start)
    local x1 = list[i + 1] and layer.x(list[i + 1].start) or width
    if x1 > 0 and x0 < width then
      local lx = math.max(0, x0)
      local mark = x0 < 0 and "‹" or "▍"
      local label = clip_text(mark .. s.name, math.max(1, x1 - lx - 1))
      ruler:text(lx, 0, label, current and current.index == i and "SectionCurrent" or "Section")
      -- A click on it goes to the section, in either frontend.
      ruler:hit(lx, 0, math.max(1, math.min(x1, width) - lx), 1, {
        kind = "section",
        cmd = "section.goto " .. i,
        hint = "section " .. s.name .. ": click goes to its start",
      })
    end
    if x0 >= 0 and x0 < width then layer.lanes:fill(x0, 0, 1, layer.lanes.height, nil, "SectionEdge") end
  end
end

local arrange = paw.ui.views:get("arrange")
if arrange and arrange.layers then
  arrange.layers.sections = M.draw
  -- The ruler has a row for them while there are any.
  if arrange.ruler2 then arrange.ruler2.sections = function() return #S.list() > 0 end end
else
  paw.notify("sections: this arrange view has no layers to draw on; sections are not shown on the ruler", "warn")
end

-- A change made elsewhere (undo, loading) redraws the ruler.
paw.on("sections.changed", function() api.ui_redraw() end)

return M
