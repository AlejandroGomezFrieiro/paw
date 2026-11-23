-- Marks, the jump list and the change list of the keymap, each by view
-- (paw/keymap.tl gives their functions as `paw.keymap.mark`, `goto_mark`,
-- `push_jump`, `jump`, `change` and the others).
--
-- A place is what the focused view's grid gives: `grid.mark()` when the
-- view keeps places that move with what is there, else the row and the
-- column of the cursor. A place on the jump list also keeps the scope of
-- the window (paw/scope.tl), so that `<C-o>` comes back into the scope.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type contracts = require("paw.contracts")
local type registry = require("paw.registry")
local type partial = require("paw.partial")
local type SeatsModule = require("paw.seats")
local type UtilModule = require("paw.util")

local type Place = contracts.GridMark

--- The places of one view, oldest first. `at` is where `<C-o>` or `g;`
--- stands while it walks the list (nil at the end).
local record Places is {Place}
  at: integer
end

--- What belongs to a project, by view: the marks, the jump lists and the
--- places of the edits (`paw.shada` keeps them).
local interface ProjectPlaces
  marks: {string: {string: Place}}
  jumps: {string: {Place}}
  changes: {string: {Place}}
end

--- What each seat has its own of.
local record Kept
  marks: {string: {string: Place}}
  jumps: {string: Places}
end

-- paw/ui.tl and paw/scope.tl name the types of paw/keymap.tl, so this
-- module declares only the parts of them that it reads.
local record Ui
  focused: string
  views: registry.Registry<contracts.View>
end
local record Scope
  current: function(): contracts.Scope
  restore: function(s: contracts.Scope)
end
local record Paw is partial.Paw
  ui: Ui
  scope: Scope
  seats: SeatsModule
  util: UtilModule
end
local paw = (_G as {string: Paw}).paw

local record M
  type Place = Place
  type Places = Places
  type ProjectPlaces = ProjectPlaces
  --- Called on each jump that goes into the jump list: paw/keymap.tl sets
  --- it, to count the jumps (`paw.keymap.jump_serial`).
  on_jump: function()
end

local marks: {string: {string: Place}} = {} -- view -> name -> place
local jumps: {string: Places} = {} -- view -> the places jumped from
local changes: {string: Places} = {} -- view -> places where the project was edited, newest last

-- Each seat has marks and jumps of its own; the places of the edits are
-- the project's, the same for every seat.
paw.seats.keep(
  "keymap.marks",
  function(): Kept return {marks = marks, jumps = jumps} end,
  function(k: Kept) marks, jumps = k.marks, k.jumps end,
  function(): Kept return {marks = {}, jumps = {}} end
)

--- The grid of the focused view: the cursor that keys move, if the view has one.
function M.grid(): contracts.Grid
  local view = paw.ui.views:get(paw.ui.focused)
  return view and view.grid
end

local function position(g: contracts.Grid): Place
  if g.mark then
    return g.mark()
  end
  local row, col = g.get()
  return {row, col}
end

--- A place on the jump list: where the cursor is, with the scope of the
--- window, so that `<C-o>` comes back into the scope.
local function spot(g: contracts.Grid): Place
  local pos = position(g)
  if paw.scope then
    pos.scoped, pos.scope = true, paw.scope.current()
  end
  return pos
end

local function go(g: contracts.Grid, pos: Place)
  if pos.scoped and paw.scope then
    paw.scope.restore(pos.scope)
  end
  if g.jump then
    return g.jump(pos)
  end
  g.set(pos[1] as number, pos[2] as number)
end

-- Two places are the same when each of their parts is: the row, the
-- column and what else the view keeps (`grid.mark`), and the scope. A
-- place in the song is not the same place in a scope.
local function same(a: Place, b: Place): boolean
  for i = 1, math.max(#a, #b) do
    if a[i] ~= b[i] then
      return false
    end
  end
  return a.track == b.track and a.beat == b.beat and a.scoped == b.scoped and a.scope == b.scope
end

-- Add `here` at the end of a list of places, unless it is there already,
-- and keep the newest 100.
local function append(list: Places, here: Place)
  if list[#list] and same(list[#list], here) then
    return
  end
  list[#list + 1] = here
  if #list > 100 then
    table.remove(list, 1)
  end
end

--- Remember where the cursor is before it goes somewhere far away.
function M.push_jump()
  local g = M.grid()
  if not g then
    return
  end
  M.on_jump()
  local list = jumps[paw.ui.focused] or {}
  jumps[paw.ui.focused] = list
  if list.at then
    for i = #list, list.at + 1, -1 do
      list[i] = nil
    end
    list.at = nil
  end
  append(list, spot(g))
end

--- Return through the places of the jumps (with a negative `n`, go forward again).
function M.jump(n: integer)
  local g, list = M.grid(), jumps[paw.ui.focused]
  if not (g and list) or #list == 0 then
    return
  end
  if not list.at then
    local here = spot(g)
    if not same(list[#list], here) then
      list[#list + 1] = here
    end
    list.at = #list
  end
  list.at = math.floor(paw.util.clamp(list.at - n, 1, #list))
  go(g, list[list.at])
end

--- Remember where the cursor is after a command that edited the project.
function M.push_change()
  local g = M.grid()
  if not g then
    return
  end
  local list = changes[paw.ui.focused] or {}
  changes[paw.ui.focused] = list
  list.at = nil
  append(list, position(g))
end

--- Go to where an earlier edit happened (`n` back, a negative `n` forward
--- again). The first step from the place of the last edit goes to the one before.
function M.change(n: integer)
  local g, list = M.grid(), changes[paw.ui.focused]
  if not (g and list) or #list == 0 then
    return paw.notify("no changes yet in this view", "warn")
  end
  local at = list.at
  if not at then
    at = #list + 1
    if same(list[#list], position(g)) then
      at = at - 1
    end
  end
  local to = at - n
  if to < 1 then
    return paw.notify("at the oldest change", "warn")
  end
  if to > #list then
    return paw.notify("at the newest change", "warn")
  end
  list.at = to
  go(g, list[to])
end

--- The places edits happened in a view, oldest first.
function M.changes(view?: string): Places
  return changes[view or paw.ui.focused] or {}
end

--- Set mark `name` (a letter) at the cursor of the focused view.
function M.mark(name: string)
  local g = M.grid()
  if not g or not name:match("^%a$") then
    return
  end
  marks[paw.ui.focused] = marks[paw.ui.focused] or {}
  marks[paw.ui.focused][name] = position(g)
end

--- Move to a mark. With `'` or a backtick as the name, return to the start
--- of the last jump. With `.`, go to the place of the last edit.
function M.goto_mark(name: string)
  local g = M.grid()
  if not g then
    return
  end
  if name == "." then
    local list = changes[paw.ui.focused]
    if not list or #list == 0 then
      return paw.notify("no changes yet in this view", "warn")
    end
    M.push_jump()
    return go(g, list[#list])
  end
  if name == "'" or name == "`" then
    local list = jumps[paw.ui.focused]
    if not list or #list == 0 then
      return
    end
    local here = spot(g)
    go(g, list[#list])
    list[#list], list.at = here, nil
    return
  end
  local pos = marks[paw.ui.focused] and marks[paw.ui.focused][name]
  if not pos then
    return paw.notify("mark `" .. name .. "` is not set", "warn")
  end
  M.push_jump()
  go(g, pos)
end

-- The mark names that a spec of `:delmarks` lists: letters and ranges
-- (`"a b"`, `"a-d"`). Nil and what is wrong when a part is not a name.
local function mark_names(spec: string): {string}, string
  local names: {string} = {}
  spec = spec:gsub("%s+", "")
  local i = 1
  while i <= #spec do
    local first, dash, last = spec:sub(i, i), spec:sub(i + 1, i + 1), spec:sub(i + 2, i + 2)
    if not first:match("^%a$") then
      return nil, "`" .. first .. "` is not a mark name"
    end
    if dash == "-" then
      -- A range goes up, and from a lowercase letter to a lowercase one
      -- or from an uppercase one to an uppercase one.
      if
        not last:match("^%a$") or last:byte() < first:byte() or (last:match("%l") == nil) ~= (first:match("%l") == nil)
      then
        return nil, "`" .. spec:sub(i, i + 2) .. "` is not a range of marks"
      end
      for c = first:byte(), last:byte() do
        names[#names + 1] = string.char(c)
      end
      i = i + 3
    else
      names[#names + 1] = first
      i = i + 1
    end
  end
  return names
end

--- Remove marks from every view, as Vim's `:delmarks` does: `spec` lists
--- letters and ranges (`"a b"`, `"a-d"`), and `all` removes every lowercase
--- one. Returns how many were removed, or nil and what is wrong.
function M.delmarks(spec: string, all?: boolean): integer, string
  local names: {string} = {}
  if all then
    for c = ("a"):byte(), ("z"):byte() do
      names[#names + 1] = string.char(c)
    end
  else
    local err: string
    names, err = mark_names(spec)
    if not names then
      return nil, err
    end
  end
  local removed = 0
  for _, name in ipairs(names) do
    for _, list in pairs(marks) do
      if list[name] then
        list[name], removed = nil, removed + 1
      end
    end
  end
  return removed
end

--- The marks of a view: name -> position.
function M.marks(view?: string): {string: Place}
  return marks[view or paw.ui.focused] or {}
end

--- What belongs to a project, for `paw.shada`: the marks, the jump lists
--- (without where `<C-o>` is) and the places of the edits, each by view.
function M.shada_project(): ProjectPlaces
  local out: ProjectPlaces = {marks = marks, jumps = {}, changes = {}}
  for view, list in pairs(jumps) do
    out.jumps[view] = {table.unpack(list)}
  end
  for view, list in pairs(changes) do
    out.changes[view] = {table.unpack(list)}
  end
  return out
end

--- Put back what `shada_project` gave, in place of the marks and places now.
function M.shada_set_project(data: ProjectPlaces)
  for view in pairs(marks) do
    marks[view] = nil
  end
  for view in pairs(jumps) do
    jumps[view] = nil
  end
  for view in pairs(changes) do
    changes[view] = nil
  end
  for view, set in pairs(data.marks or {}) do
    marks[view] = set
  end
  for view, list in pairs(data.jumps or {}) do
    jumps[view] = list as Places
  end
  for view, list in pairs(data.changes or {}) do
    changes[view] = list as Places
  end
end

return M
