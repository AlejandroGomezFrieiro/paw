-- Key mappings and modal editing, with Neovim's notation and grammar.
--
-- A mapping belongs to a mode and optionally to a view; a view's mappings win
-- over global ones while that view has focus. The right hand side is a
-- command line (`"track.mute"`) or a function.
--
--   mode   what it is                      how mappings get there
--   n      normal                          `set` (the default)
--   x      visual: a selection is open     `set` with `mode = "x"`; motions, operators
--   o      an operator waits for a motion  motions and text objects
--   i      insert: keys enter material     `set` with `mode = "i"`
--   c      a prompt has the keyboard       (not mapped)
--
-- Three kinds of mapping make up the grammar. A *motion* moves the cursor. An
-- *operator* acts on a region: after `d` the next motion or text object says
-- which, `dd` means whole rows, and in visual mode it is the selection. A
-- *text object* names a region outright, such as the clip under the cursor.
-- Counts (`3w`, `2dd`), registers (`"ayy`), `.`, macros and marks work on any
-- of them, so an extension that adds one operator gets all of that with it.
--
-- A view takes part by having a `grid`: `get()` returns the cursor as a row
-- and a column in beats, and `set(row, col)` moves it. See `paw.edit` for the
-- regions the built-in views work on.
local api = paw.api
local M = {}

local maps = {} -- mode -> scope -> lhs -> mapping
local pending = {} -- keys typed so far of an unfinished sequence
local count -- number typed before the sequence
local register -- register named with `"x` for the next command
local op -- the operator waiting for a motion: { map, count, register, key }
local awaiting -- function that takes the next key, whatever it is
local timer
local hint_at -- when to start listing the keys that can follow

local track = {} -- the command being typed: { keys, edits, norepeat }
local last_change -- the keys of the last command that changed the project
local replaying -- `.` is running: its keys are not a new change
local depth = 0 -- how many replays (macros, `.`) are running inside each other
local macro -- { name, keys } while recording
local last_macro

local registers = {}
local marks, jumps = {}, {}
local changes = {} -- view -> positions where the project was edited, newest last
local groups = {} -- scope -> keys -> name of a prefix that only leads to more keys
local group_lhs = {} -- the groups on a leader: { scope, prefix as written, name, keys now }

--- The mode: "n", "i", "x" (visual), "o" (after an operator) or "c".
--- @type string
M.mode = "n"
M.visual = nil -- the open selection's fixed end: { kind, row, col, view }
M.registers = registers

-- Everything above but the mappings is each seat's own: two people can be
-- half way through two commands, in two modes, with registers of their own.
paw.seats.keep(
  "keymap",
  function()
    return pending,
      count,
      register,
      op,
      awaiting,
      timer,
      hint_at,
      track,
      last_change,
      macro,
      last_macro,
      registers,
      marks,
      jumps,
      M.mode,
      M.visual,
      M.last_visual,
      M.search_text
  end,
  function(...)
    pending, count, register, op, awaiting, timer, hint_at, track, last_change, macro, last_macro, registers, marks, jumps, M.mode, M.visual, M.last_visual, M.search_text =
      ...
    M.registers = registers
  end,
  function() return {}, nil, nil, nil, nil, nil, nil, {}, nil, nil, nil, {}, {}, {}, "n", nil, nil, nil end
)

--- A leader option as a key: a space (the default leader) is `<Space>`.
local function leader_key(value) return value == " " and "<Space>" or value end

--- Write `<leader>` and `<localleader>` as the keys the options name.
function M.expand(lhs)
  return (
    lhs
      :gsub("<[Ll]ocal[Ll]eader>", function() return leader_key(paw.opt.localleader) end)
      :gsub("<[Ll]eader>", function() return leader_key(paw.opt.leader) end)
  )
end

--- Split `gg<C-x>` into { "g", "g", "<C-x>" }, and expand `<leader>` and `<localleader>`.
function M.parse(lhs)
  local keys = {}
  local expanded = M.expand(lhs)
  local pos = 1
  while pos <= #expanded do
    -- A key with modifiers may be a punctuation mark: `<C-]>`.
    local special = expanded:match("^<[%w%-]+>", pos) or expanded:match("^<[%a%-]-%a%-[^%w%s>]>", pos)
    local key = special or expanded:match("^[%z\1-\127\194-\244][\128-\191]*", pos)
    -- A space is the Space key, as the keyboard sends it: `paw.keymap.set(" z", ...)`.
    keys[#keys + 1] = key == " " and "<Space>" or key
    pos = pos + #key
  end
  return keys
end

local key_names = {
  CR = "Enter",
  Enter = "Enter",
  Return = "Enter",
  Space = "Space",
  Esc = "Esc",
  BS = "Backspace",
  Del = "Delete",
  Tab = "Tab",
  lt = "<",
  Bar = "|",
  Bslash = "\\",
  Up = "Up",
  Down = "Down",
  Left = "Left",
  Right = "Right",
  Home = "Home",
  End = "End",
  PageUp = "PageUp",
  PageDown = "PageDown",
}
local modifier_names = { C = "Ctrl", A = "Alt", M = "Alt", S = "Shift", D = "Super" }

--- Keys as a person writes them: `<A-h>` is `Alt-h`, `<leader>at` is `Space at`,
--- `<localleader>d` is `\d`, `<C-w>o` is `Ctrl-w o`, `<CR>` is `Enter`. Takes an `lhs` or a list of keys.
function M.human(keys)
  if type(keys) == "string" then keys = M.parse(keys) end
  local out, prev_word = {}, false
  for i, key in ipairs(keys) do
    local inner = key:match("^<(.+)>$")
    local text, word = key, false
    if inner then
      local mods = ""
      while inner:match("^%a%-.") do
        local m = inner:sub(1, 1):upper()
        mods = mods .. (modifier_names[m] or m) .. "-"
        inner = inner:sub(3)
      end
      text = mods .. (key_names[inner] or inner)
      -- `<lt>` alone is a plain character; anything else is a word of its own.
      word = mods ~= "" or #text > 1
    end
    if i > 1 and (word or prev_word) then out[#out + 1] = " " end
    out[#out + 1] = text
    prev_word = word
  end
  return table.concat(out)
end

--- Every mapping that can be typed while `view` has focus, each once:
--- normal mode, then what only a selection, an operator or insert mode
--- takes. Each comes with `kind`: "key", "motion", "operator", "object",
--- "visual" or "insert".
function M.all(view)
  local out = {}
  local shadowed = {} -- mode .. keys the part of the view takes over
  -- A part of the view the cursor is in comes first: its keys win.
  if view == paw.ui.focused then
    local sub = M.scopes()
    for i = 1, #sub - 2 do
      for _, mode in ipairs({ "n", "x", "i" }) do
        local list = {}
        for _, map in pairs(maps[mode] and maps[mode][sub[i]] or {}) do
          list[#list + 1] = map
        end
        table.sort(list, function(a, b) return a.lhs:lower() .. a.lhs < b.lhs:lower() .. b.lhs end)
        for _, map in ipairs(list) do
          if not shadowed[mode .. table.concat(map.keys)] and (mode ~= "x" or not M.has("n", map)) then
            local kind = mode == "x" and "visual" or mode == "i" and "insert" or map.motion and "motion" or "key"
            out[#out + 1] = { map = map, kind = kind }
          end
          shadowed[mode .. table.concat(map.keys)] = true
        end
      end
    end
  end
  for _, map in ipairs(M.list("n", view)) do
    if not shadowed["n" .. table.concat(map.keys)] then
      out[#out + 1] = { map = map, kind = map.operator and "operator" or map.motion and "motion" or "key" }
    end
  end
  for _, map in ipairs(M.list("x", view)) do
    if not shadowed["x" .. table.concat(map.keys)] and not map.motion and not map.object and not M.has("n", map) then
      out[#out + 1] = { map = map, kind = "visual" }
    end
  end
  for _, map in ipairs(M.list("o", view)) do
    if map.object then out[#out + 1] = { map = map, kind = "object" } end
  end
  for _, map in ipairs(M.list("i", view)) do
    if not shadowed["i" .. table.concat(map.keys)] then out[#out + 1] = { map = map, kind = "insert" } end
  end
  return out
end

--- Map keys.
---   paw.keymap.set("M", "track.mute", { desc = "Mute track" })
---   paw.keymap.set("<leader>mz", function(ctx) ... end, { desc = "Check the mix" })
--- `ctx` has `count`, `register` and, for mappings made with `char = true`,
--- the key typed after the mapping as `char`.
---
--- The options are `mode` (one mode or a list, default "n"), `view` and
--- `desc`. `motion = true` is for a mapping that only moves the cursor.
--- Such a mapping also works in visual mode and after an operator.
--- `linewise = true` is for a motion across rows. `jump = true` keeps the
--- position of the cursor for `<C-o>`. With `repeatable = false`, `.` does
--- not repeat the mapping. `nowait = true` makes a key that also starts
--- longer mappings run at once, without the wait for more keys. Each key
--- with `role` "second+" or "second-" (the `[` and `]` of a view) does so. The same key again is a second press. Another key soon after it
--- that makes a longer mapping (`]g`, `]q`) takes back its change and runs
--- that mapping. On a selection, the selection opens again for that mapping.
function M.set(lhs, rhs, opts)
  opts = opts or {}
  local default = opts.motion and { "n", "x", "o" } or { "n" }
  local modes = type(opts.mode) == "table" and opts.mode or opts.mode and { opts.mode } or default
  local scope = opts.view or "global"
  local keys = M.parse(lhs)
  for _, mode in ipairs(modes) do
    if mode == "v" then mode = "x" end
    maps[mode] = maps[mode] or {}
    maps[mode][scope] = maps[mode][scope] or {}
    local map = { lhs = lhs, keys = keys, rhs = rhs, mode = mode, scope = scope }
    for name, value in pairs(opts) do
      if name ~= "mode" and name ~= "view" then map[name] = value end
    end
    map.norepeat = opts.repeatable == false
    map.ext = map.ext or paw.commands.owner()
    maps[mode][scope][table.concat(keys)] = map
  end
end

--- Give a name to a prefix that only leads to more keys. The hints after it
--- then show `+mix`, not the number of keys after it.
---   paw.keymap.group("<leader>m", "mix")
--- With `opts.view`, the name applies only while that view has focus.
function M.group(prefix, name, opts)
  local scope = opts and opts.view or "global"
  groups[scope] = groups[scope] or {}
  local keys = table.concat(M.parse(prefix))
  groups[scope][keys] = name
  if prefix:lower():find("leader>", 1, true) then group_lhs[#group_lhs + 1] = { scope, prefix, name, keys } end
end

--- Define an operator: `fn(region, ctx)` acts on a region of the focused
--- view. A region has `r0`, `r1` (rows, inclusive), `c0`, `c1` (beats, the
--- end not included) and `kind`: "char" for a stretch of time, "line" for
--- whole rows, "block" for a rectangle.
---   paw.keymap.operator("gl", function(region) ... end, { view = "arrange", desc = "Loop" })
--- With `count = "operator"`, the count typed before the operator is its
--- own, as `ctx.op_count`. It tells how far or how many times: `3gUib` is
--- three steps up over a bar. `ctx.count` is the count of the motion or
--- object alone.
function M.operator(lhs, fn, opts) M.set(lhs, nil, paw.util.merge(opts or {}, { mode = { "n", "x" }, operator = fn })) end

--- Define a text object: `fn(ctx)` returns a region, or nil when there is
--- nothing of that kind at the cursor.
---   paw.keymap.textobject("ic", function() ... end, { view = "arrange", desc = "The clip" })
function M.textobject(lhs, fn, opts) M.set(lhs, nil, paw.util.merge(opts or {}, { mode = { "o", "x" }, object = fn })) end

--- Remove a mapping: `opts.mode` and `opts.view` as `set` took them.
function M.del(lhs, opts)
  opts = opts or {}
  local scope = maps[opts.mode or "n"] and maps[opts.mode or "n"][opts.view or "global"]
  if scope then scope[table.concat(M.parse(lhs))] = nil end
end

--- Call `fn(map, mode, scope, keys)` for each mapping, in no order, with
--- `keys` joined as `put` takes them. It is `every` without the sort.
function M.each(fn)
  for mode, by_scope in pairs(maps) do
    for scope, by_keys in pairs(by_scope) do
      for keys, map in pairs(by_keys) do
        fn(map, mode, scope, keys)
      end
    end
  end
end

--- Put a mapping back as `map` (a mapping that `every` gave), or remove it
--- with nil. The mapping is found by its mode, scope and joined keys
--- (`table.concat(map.keys)`). An extension that unloads does this with
--- the keys that it mapped.
function M.put(mode, scope, keys, map)
  maps[mode] = maps[mode] or {}
  maps[mode][scope] = maps[mode][scope] or {}
  maps[mode][scope][keys] = map
end

-- The keys as they were before every view kept to one rule (docs/reference/key-rule.md,
-- "The classic keys"), made only with `paw.opt.keys = "classic"`.
local classic = {}

--- Make a classic mapping, keeping what it covers to put back.
local function apply(entry)
  local lhs, rhs, opts = entry[1], entry[2], entry[3]
  local modes = type(opts.mode) == "table" and opts.mode
    or opts.mode and { opts.mode }
    or (opts.motion or opts.operator) and { "n", "x", "o" }
    or { "n" }
  local scope, keys = opts.view or "global", table.concat(M.parse(lhs))
  entry.covered = {}
  for _, mode in ipairs(modes) do
    if mode == "v" then mode = "x" end
    entry.covered[mode] = maps[mode] and maps[mode][scope] and maps[mode][scope][keys] or false
    if rhs == false then
      if maps[mode] and maps[mode][scope] then maps[mode][scope][keys] = nil end
    end
  end
  if rhs ~= false then M.set(lhs, rhs, opts) end
end

--- Take a classic mapping away again, putting back what it covered.
local function revert(entry)
  local scope, keys = entry[3].view or "global", table.concat(M.parse(entry[1]))
  for mode, map in pairs(entry.covered or {}) do
    maps[mode] = maps[mode] or {}
    maps[mode][scope] = maps[mode][scope] or {}
    maps[mode][scope][keys] = map or nil
  end
  entry.covered = nil
end

--- A mapping as it was before the key rule. paw makes it when
--- `paw.opt.keys` is "classic", now or later. It goes over the mapping that
--- the rule gives the same keys. paw removes it again when the option
--- changes back. A false `rhs` removes the keys.
---   paw.keymap.classic("j", "track.volume by=-1", { view = "mixer", desc = "Volume down 1 dB" })
function M.classic(lhs, rhs, opts)
  local entry = { lhs, rhs, opts or {} }
  classic[#classic + 1] = entry
  if paw.opt.keys == "classic" then apply(entry) end
end

paw.on("option.changed", function(e)
  if e.name ~= "keys" then return end
  if e.value == "classic" then
    for _, entry in ipairs(classic) do
      apply(entry)
    end
  elseif e.old == "classic" then
    for i = #classic, 1, -1 do
      revert(classic[i])
    end
  end
end)

--- The names given to prefixes with `group`: scope -> keys -> name.
function M.groups() return groups end

--- Mappings that apply in `mode` for `view`, the view's own first.
function M.list(mode, view)
  local out = {}
  for _, scope in ipairs({ view or false, "global" }) do
    local list = {}
    for _, map in pairs(scope and maps[mode] and maps[mode][scope] or {}) do
      list[#list + 1] = map
    end
    table.sort(list, function(a, b) return a.lhs:lower() .. a.lhs < b.lhs:lower() .. b.lhs end)
    for _, map in ipairs(list) do
      out[#out + 1] = map
    end
  end
  return out
end

--- Every mapping in every mode and scope, sorted by scope, mode and keys.
--- What checks the key rules walks (`tests/keys_constitution.lua`).
function M.every()
  local out = {}
  for _, by_scope in pairs(maps) do
    for _, by_keys in pairs(by_scope) do
      for _, map in pairs(by_keys) do
        out[#out + 1] = map
      end
    end
  end
  table.sort(out, function(a, b)
    if a.scope ~= b.scope then return a.scope < b.scope end
    if a.mode ~= b.mode then return a.mode < b.mode end
    return a.lhs < b.lhs
  end)
  return out
end

--- True if a mapping with the same keys and scope is also made in `mode`.
function M.has(mode, map)
  local scope = maps[mode] and maps[mode][map.scope]
  return scope ~= nil and scope[table.concat(map.keys)] ~= nil
end

local function grid()
  local view = paw.ui.views[paw.ui.focused]
  return view and view.grid
end

local function stop_timer()
  if timer then
    api.timer_stop(timer)
    timer = nil
  end
end

-- The undo state current when insert mode began. What is done from then
-- until insert mode ends (the clip `i` made, the notes drawn into it) is
-- one undo step, as an insert is in Vim: the steps after the first join it.
local insert_undo
local insert_hint_at -- when insert mode's keys show, in a view that lists them
local key_serial = 0 -- counts the keys handled: what one key did together
local left_insert -- the insert that ended last: { undo, key }

--- Change mode. When visual mode stops, the selection closes. `gv` opens it again.
function M.set_mode(mode)
  if mode == "v" then mode = "x" end
  local old = M.mode
  if M.visual and mode ~= "x" and mode ~= "c" then
    local g = grid()
    if g and M.visual.view == paw.ui.focused then
      local row, col = g.get()
      M.last_visual = paw.util.merge(M.visual, { cursor_row = row, cursor_col = col })
    end
    M.visual = nil
  end
  if mode == old then return end
  if mode == "i" then
    insert_undo = api.undo_current()
    -- Insert mode that hands over to another view's in the same key (the
    -- arrange view's `m` then Enter: the piano roll) is one insert still.
    if left_insert and left_insert.key == key_serial then insert_undo = left_insert.undo end
    -- A view whose insert mode is a choice of keys lists them after a moment.
    local view = paw.ui.views[paw.ui.focused]
    if view and view.insert_hints then
      insert_hint_at = api.now() + paw.opt.hint_delay
      paw.defer(api.ui_redraw, paw.opt.hint_delay + 1)
    end
  end
  M.mode = mode
  paw.emit("mode.changed", { mode = mode, old = old })
  if old == "i" then
    left_insert = { undo = insert_undo, key = key_serial }
    insert_undo = nil
  end
  api.ui_redraw()
end

-- A key that ran at once though longer mappings start with it (`nowait`):
-- { key, edits_before, edits_after } until the next key or the wait ends.
local eager

local function reset()
  eager = nil
  pending, count, register, awaiting, hint_at = {}, nil, nil, nil, nil
  stop_timer()
  if op then
    op = nil
    M.set_mode("n")
  end
  api.ui_redraw()
end

local function region(r, c, r2, c2, kind)
  return {
    view = paw.ui.focused,
    kind = kind,
    r0 = math.min(r, r2),
    r1 = math.max(r, r2),
    c0 = math.min(c, c2),
    c1 = math.max(c, c2),
  }
end

--- The row a region starts on: rows count downwards in most views, upwards
--- (`grid.down = -1`) in the piano roll.
local function first_row(g, reg) return g.down == -1 and reg.r1 or reg.r0 end

--- Start a selection from the cursor: "v" a range of time, "V" whole rows,
--- "b" a rectangle. The same kind again stops visual mode.
function M.visual_start(kind)
  local g = grid()
  if not g then return paw.notify("nothing to select in this view", "warn") end
  if M.visual and M.visual.kind == kind then return M.set_mode("n") end
  if M.visual then
    M.visual.kind, M.visual.region = kind, nil
    return api.ui_redraw()
  end
  local row, col = g.get()
  M.visual = { kind = kind, row = row, col = col, view = paw.ui.focused }
  M.set_mode("x")
end

--- Open the last selection again.
function M.visual_restore()
  local g, last = grid(), M.last_visual
  if not (g and last and last.view == paw.ui.focused) then return end
  M.visual = { kind = last.kind, row = last.row, col = last.col, view = last.view, region = last.region }
  g.set(last.cursor_row, last.cursor_col)
  M.set_mode("x")
end

--- Swap the cursor with the selection's other end.
function M.visual_swap()
  local g, v = grid(), M.visual
  if not (g and v) then return end
  local row, col = g.get()
  g.set(v.row, v.col)
  v.row, v.col = row, col
end

--- The region a selection `v` covers with the cursor at `row`, `col`.
local function selected(v, g, row, col)
  -- Clips chosen one by one with the pointer: the region they span, which
  -- names them (`clips`), and is not stretched by the cursor.
  if v.region then
    local out = v.region()
    if out then
      out.visual, out.view = true, v.view
    end
    return out
  end
  local out = region(v.row, v.col, row, col, v.kind == "V" and "line" or v.kind == "b" and "block" or "char")
  out.visual = true
  -- A view whose cursor stands on things that last (a note in the score)
  -- says where the one at the later end ends: it is selected too.
  if g.extent and out.kind ~= "line" then
    local last_row = col >= v.col and row or v.row
    out.c1 = math.max(out.c1, g.extent(last_row, out.c1) or out.c1)
  end
  if out.c1 - out.c0 < 1e-9 then
    out.c1 = out.c0 + g.step()
    out.unstretched = true
  end
  return out
end

local ranged -- the region `:'<,'>` names while its command runs

--- The region selected in the focused view, or nil outside visual mode. It
--- goes from the cursor to the start of the selection. Both ends are
--- included when the view tells the size of the item under the cursor
--- (`grid.extent`). A selection that did not grow covers one grid step.
--- While a command runs with `:'<,'>`, it is the selection that the command names.
--- @type function(): contracts.Region
function M.selection()
  if ranged then return ranged end
  local v, g = M.visual, grid()
  if not (v and g) or v.view ~= paw.ui.focused then return nil end
  local row, col = g.get()
  return selected(v, g, row, col)
end

--- The last selection made in the focused view, as `'<,'>` names it: the
--- one open now, or the one visual mode last closed. Nil if there is none.
function M.last_selection()
  local open = M.selection()
  if open then return open end
  local last, g = M.last_visual, grid()
  if not (last and g) or last.view ~= paw.ui.focused then return nil end
  return selected(last, g, last.cursor_row, last.cursor_col)
end

--- Run `fn(...)` with `region` as the selection, the way `:'<,'>` runs a
--- command: anything that asks for the selection meanwhile gets it.
function M.with_selection(region_, fn, ...)
  local outer = ranged
  ranged = region_
  local result = { pcall(fn, ...) }
  ranged = outer
  if not result[1] then error(result[2], 0) end
  return unpack(result, 2, table.maxn(result))
end

-- Registers -------------------------------------------------------------------

--- Put a value in a register: the unnamed register, and `name` if given.
--- With `yank` and no name, it also goes to `"0`, which a delete never
--- changes. A value is a table with a `kind`. The code that yanks and
--- pastes it decides what else it contains. `"_` discards.
function M.setreg(value, name, yank)
  if name == "_" then return end
  registers['"'] = value
  if name and name ~= '"' then registers[name:lower()] = value end
  if yank and not name then registers["0"] = value end
end

--- What a register holds (the unnamed one when `name` is nil).
function M.getreg(name) return registers[name and name:lower() or '"'] end

-- Marks and jumps -------------------------------------------------------------

local function position(g)
  if g.mark then return g.mark() end
  local row, col = g.get()
  return { row, col }
end

--- A place on the jump list: where the cursor is, with the scope of the
--- window (paw/scope.tl), so that `<C-o>` comes back into the scope.
local function spot(g)
  local pos = position(g)
  if paw.scope then
    pos.scoped, pos.scope = true, paw.scope.current()
  end
  return pos
end

local function go(g, pos)
  if pos.scoped and paw.scope then paw.scope.restore(pos.scope) end
  if g.jump then return g.jump(pos) end
  g.set(pos[1], pos[2])
end

local function same(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then return false end
  end
  -- A place in the song is not the same place in a scope.
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

--- Remember where the cursor is before it goes somewhere far away.
function M.push_jump()
  local g = grid()
  if not g then return end
  local list = jumps[paw.ui.focused] or {}
  jumps[paw.ui.focused] = list
  if list.at then
    for i = #list, list.at + 1, -1 do
      list[i] = nil
    end
    list.at = nil
  end
  local here = spot(g)
  if list[#list] and same(list[#list], here) then return end
  list[#list + 1] = here
  if #list > 100 then table.remove(list, 1) end
end

--- Return through the places of the jumps (with a negative `n`, go forward again).
function M.jump(n)
  local g, list = grid(), jumps[paw.ui.focused]
  if not (g and list) or #list == 0 then return end
  if not list.at then
    local here = spot(g)
    if not same(list[#list], here) then list[#list + 1] = here end
    list.at = #list
  end
  list.at = paw.util.clamp(list.at - n, 1, #list)
  go(g, list[list.at])
end

--- Remember where the cursor is after a command that edited the project.
local function push_change()
  local g = grid()
  if not g then return end
  local list = changes[paw.ui.focused] or {}
  changes[paw.ui.focused] = list
  list.at = nil
  local here = position(g)
  if list[#list] and same(list[#list], here) then return end
  list[#list + 1] = here
  if #list > 100 then table.remove(list, 1) end
end

--- Go to where an earlier edit happened (`n` back, a negative `n` forward
--- again). The first step from the place of the last edit goes to the one before.
function M.change(n)
  local g, list = grid(), changes[paw.ui.focused]
  if not (g and list) or #list == 0 then return paw.notify("no changes yet in this view", "warn") end
  local at = list.at
  if not at then
    at = #list + 1
    if same(list[#list], position(g)) then at = at - 1 end
  end
  local to = at - n
  if to < 1 then return paw.notify("at the oldest change", "warn") end
  if to > #list then return paw.notify("at the newest change", "warn") end
  list.at = to
  go(g, list[to])
end

--- The places edits happened in a view, oldest first.
function M.changes(view) return changes[view or paw.ui.focused] or {} end

--- Set mark `name` (a letter) at the cursor of the focused view.
function M.mark(name)
  local g = grid()
  if not g or not name:match("^%a$") then return end
  marks[paw.ui.focused] = marks[paw.ui.focused] or {}
  marks[paw.ui.focused][name] = position(g)
end

--- Move to a mark. With `'` or a backtick as the name, return to the start
--- of the last jump. With `.`, go to the place of the last edit.
function M.goto_mark(name)
  local g = grid()
  if not g then return end
  if name == "." then
    local list = changes[paw.ui.focused]
    if not list or #list == 0 then return paw.notify("no changes yet in this view", "warn") end
    M.push_jump()
    return go(g, list[#list])
  end
  if name == "'" or name == "`" then
    local list = jumps[paw.ui.focused]
    if not list or #list == 0 then return end
    local here = spot(g)
    go(g, list[#list])
    list[#list], list.at = here, nil
    return
  end
  local pos = marks[paw.ui.focused] and marks[paw.ui.focused][name]
  if not pos then return paw.notify("mark `" .. name .. "` is not set", "warn") end
  M.push_jump()
  go(g, pos)
end

--- Remove marks from every view, as Vim's `:delmarks` does: `spec` lists
--- letters and ranges (`"a b"`, `"a-d"`), and `all` removes every lowercase
--- one. Returns how many were removed, or nil and what is wrong.
function M.delmarks(spec, all)
  local names = {}
  if all then
    for c = ("a"):byte(), ("z"):byte() do
      names[#names + 1] = string.char(c)
    end
  else
    spec = spec:gsub("%s+", "")
    local i = 1
    while i <= #spec do
      local first, dash, last = spec:sub(i, i), spec:sub(i + 1, i + 1), spec:sub(i + 2, i + 2)
      if not first:match("^%a$") then return nil, "`" .. first .. "` is not a mark name" end
      if dash == "-" then
        if
          not last:match("^%a$")
          or last:byte() < first:byte()
          or (last:match("%l") == nil) ~= (first:match("%l") == nil)
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
function M.marks(view) return marks[view or paw.ui.focused] or {} end

-- Search ----------------------------------------------------------------------

--- Move to the next (`dir` 1) or previous (-1) thing in the focused view that
--- matches the last search. Views say what matches through `grid.search`.
function M.search_next(dir, n)
  local g = grid()
  if not (g and g.search) then return end
  if not M.search_text then return paw.notify("nothing searched for yet: `/`", "warn") end
  local hits = g.search(M.search_text)
  if #hits == 0 then return paw.notify("nothing matches `" .. M.search_text .. "`", "warn") end
  table.sort(hits, function(a, b)
    if a.col ~= b.col then return a.col < b.col end
    return a.row < b.row
  end)
  local row, col = g.get()
  for _ = 1, n or 1 do
    local found
    if dir > 0 then
      for _, hit in ipairs(hits) do
        if hit.col > col + 1e-9 or (math.abs(hit.col - col) < 1e-9 and hit.row > row) then
          found = hit
          break
        end
      end
      found = found or hits[1]
    else
      for i = #hits, 1, -1 do
        local hit = hits[i]
        if hit.col < col - 1e-9 or (math.abs(hit.col - col) < 1e-9 and hit.row < row) then
          found = hit
          break
        end
      end
      found = found or hits[#hits]
    end
    row, col = found.row, found.col
  end
  g.set(row, col)
end

--- Search the focused view for `text`, forward (`dir` 1) or back (-1).
function M.search(text, dir)
  M.search_text = text
  M.search_next(dir or 1)
end

-- Running mappings --------------------------------------------------------------

--- Name the undo step a key makes by its description. A key typed (not
--- one a macro or a mapping plays) first takes back the name of a key
--- before it that changed nothing: `3G` then `dd` is the delete.
local function label(text)
  if depth == 0 then api.undo_label(nil) end
  if text then api.undo_label(text) end
end

local function exec(map, ctx, motion)
  -- The key's description names the undo step it makes. Keys that replay
  -- others (`.`, `@a`) leave the name to what they replay, and an
  -- operator's motion to the operator.
  if not map.norepeat and not motion then label(map.desc) end
  if type(map.rhs) == "function" then
    return paw.limit.named("the key " .. M.human(map.lhs) .. (map.desc and " (" .. map.desc .. ")" or ""), map.rhs, ctx)
  end
  return paw.commands.exec(map.rhs, ctx)
end

local function times(a, b)
  if a or b then return (a or 1) * (b or 1) end
end

local function run(map, char)
  local ctx = { count = count, register = register, keys = map.lhs, char = char, mode = M.mode }
  local g = grid()
  pending, count, register, hint_at = {}, nil, nil, nil
  stop_timer()
  if map.norepeat then track.norepeat = true end

  if M.mode == "o" then
    -- A motion or text object, for the operator that was waiting for one.
    local o = op
    op = nil
    M.set_mode("n")
    label(o.map.desc)
    if o.map.count == "operator" then
      ctx.op_count, ctx.register = o.count, o.register
    else
      ctx.count, ctx.register = times(o.count, ctx.count), o.register
    end
    local r, c = g.get()
    local reg
    if map.object then
      reg = map.object(ctx)
    else
      -- The motion knows it moves for an operator (`paw.cursor` then
      -- keeps to the tracks).
      M.motion_for = o.map
      local ok, err = pcall(exec, map, ctx, true)
      M.motion_for = nil
      if not ok then error(err, 0) end
      local r2, c2 = g.get()
      if not map.linewise and r == r2 and c == c2 then return end
      reg = region(r, c, r2, c2, map.linewise and "line" or "char")
    end
    if not reg then return end
    -- The cursor ends up where the region starts.
    if reg.kind == "line" then
      g.set(first_row(g, reg), c)
    else
      g.set(r, reg.c0)
    end
    return o.map.operator(reg, ctx)
  end

  if map.operator then
    if M.mode == "x" then
      local reg = M.selection()
      local _, col = g.get()
      M.set_mode("n")
      if not reg then return end
      label(map.desc)
      if map.count == "operator" then ctx.op_count = ctx.count end
      if reg.kind == "line" then
        g.set(first_row(g, reg), col)
      else
        g.set(first_row(g, reg), reg.c0)
      end
      return map.operator(reg, ctx)
    end
    if not g then return paw.notify("nothing in this view for `" .. map.lhs .. "` to act on", "warn") end
    op = { map = map, count = ctx.count, register = ctx.register, key = map.keys[#map.keys] }
    return M.set_mode("o")
  end

  if map.object then
    -- In visual mode a text object becomes the selection. The same object
    -- again, with the cursor where it left it, takes in one more (`vic`
    -- then `ic`): it is asked again from where the first one started,
    -- with a count one higher.
    local v, again = M.visual, nil
    if g and v and v.object and v.object.map == map then
      local r, c = g.get()
      if r == v.object.at_row and c == v.object.at_col then again = v.object end
    end
    local from_row, from_col
    if g then
      from_row, from_col = g.get()
    end
    if again then
      from_row, from_col = again.row, again.col
      g.set(from_row, from_col)
      ctx.count = again.count + (ctx.count or 1)
    end
    local reg = map.object(ctx)
    if again and not reg then g.set(again.at_row, again.at_col) end
    if reg and M.visual and g then
      -- A region that names its notes is the selection as it is: the
      -- cursor does not stretch it.
      local fixed = reg.notes and function() return paw.util.merge(reg, {}) end or nil
      M.visual.row, M.visual.col, M.visual.region = reg.r0, reg.c0, fixed
      if reg.kind == "line" then
        M.visual.kind = "V"
      elseif reg.kind == "block" then
        M.visual.kind = "b"
      else
        M.visual.kind = "v"
      end
      g.set(reg.r1, reg.c1)
      local at_row, at_col = g.get()
      M.visual.object =
        { map = map, count = ctx.count or 1, row = from_row, col = from_col, at_row = at_row, at_col = at_col }
    end
    return
  end

  if map.jump then M.push_jump() end
  return exec(map, ctx)
end

--- Where paw finds mappings, first to last. First comes the part of the
--- focused view that has the cursor, if the view has such parts
--- (`view:subscope()`). For example, "arrange.lane" on an automation lane
--- row, or a list of parts, the first part first. Then comes the view,
--- then all views.
local function scopes()
  local name = paw.ui.focused
  local view = name and paw.ui.views[name]
  local out = {}
  if view and view.subscope then
    local ok, sub = pcall(view.subscope, view)
    if ok and type(sub) == "table" then
      for _, s in ipairs(sub) do
        out[#out + 1] = s
      end
    elseif ok and sub then
      out[#out + 1] = sub
    end
  end
  if name then out[#out + 1] = name end
  out[#out + 1] = "global"
  return out
end
M.scopes = scopes

--- The mapping for exactly `seq`, and whether a longer mapping starts with it.
local function lookup(seq)
  local exact, longer
  for _, scope in ipairs(scopes()) do
    local scoped = scope and maps[M.mode] and maps[M.mode][scope]
    for lhs, map in pairs(scoped or {}) do
      if lhs == seq then
        exact = exact or map
      elseif lhs:sub(1, #seq) == seq then
        longer = true
      end
    end
  end
  return exact, longer
end

-- Escape cancels and stays, in every view, as in Vim: a Vim hand presses it
-- to be sure it is in normal mode, and the keys after it must land where
-- they were going. Leaving is `<C-w>p`, `:q`, `ZZ` or the view's own key.
-- A second one soon after says so.
local escaped_at = -math.huge

--- After an Escape that had nothing to cancel: a second one within two
--- seconds outside the arrange view says how to leave.
function M.escape_hint()
  local now = api.now()
  if now - escaped_at < 2000 and paw.ui.focused and paw.ui.focused ~= "arrange" then
    paw.notify("normal mode: <C-w>p goes back to the window before, :q closes this one")
    escaped_at = -math.huge
    return
  end
  escaped_at = now
end

--- Whether a part of the focused view (not the view itself, nor the global
--- mappings) maps `key` in this mode.
local function held(key)
  local list = scopes()
  for i = 1, #list - 2 do
    if maps[M.mode] and maps[M.mode][list[i]] and maps[M.mode][list[i]][key] then return true end
  end
  return false
end

local function idle()
  return M.mode == "n"
    and #pending == 0
    and not count
    and not register
    and not op
    and not awaiting
    and not paw.ui.grabber
end

-- Changes made outside the project that `.` repeats too: a text buffer's.
local text_changes = 0

--- Record a change that is not an edit of the project (the lines of a text
--- buffer). Then `.` repeats the command that made it.
function M.changed() text_changes = text_changes + 1 end

local after -- { fn, armed }: to run once the next whole command is done

--- Run `fn` after paw gets and does the next whole command. Insert mode uses
--- it for Ctrl-o, to return to insert mode after one command.
function M.after_next(fn) after = { fn = fn } end

--- Once a command is complete, remember it for `.` if it changed the project.
local function finish_command()
  if not idle() then return end
  if track.keys and api.project_get("edits") ~= track.edits then push_change() end
  local changed = track.keys and (api.project_get("edits") ~= track.edits or text_changes ~= track.texts)
  if changed and not track.norepeat and not replaying then last_change = track.keys end
  track = {}
  -- The command that asked is done now; the one after it is the one waited for.
  if after and depth == 0 then
    if after.armed then
      local fn = after.fn
      after = nil
      fn()
    else
      after.armed = true
    end
  end
end

--- Run a mapping, or wait for the key it wants first (`ma`, `"ayy`, `@q`).
local function take(map)
  if not map.char then return run(map) end
  awaiting = function(key)
    if key == "<Esc>" or key == "<C-c>" then return reset() end
    run(map, key == "<Space>" and " " or key == "<lt>" and "<" or key)
  end
end

local handle

--- Handle one key press.
handle = function(key)
  if paw.ui.grabber then return paw.ui.grabber(key) end
  local focused = paw.ui.views[paw.ui.focused]
  if focused and focused.modal then return focused:on_key(key) end
  if awaiting then
    local fn = awaiting
    awaiting = nil
    return fn(key)
  end

  -- After a key that ran at once (`nowait`), this key either makes a longer
  -- mapping with it, which takes back what that key changed, or starts afresh.
  if eager then
    local first = eager
    eager = nil
    stop_timer()
    local exact, longer
    -- A key that ran on a selection closed it: the longer mapping is looked
    -- for, and runs, on the selection open again (`v]n` after `]`).
    local reopened
    if first.visual and M.mode ~= "x" then
      local g = grid()
      reopened = { last = M.last_visual, cursor = g and { g.get() } }
      M.visual_restore()
      if M.mode ~= "x" then reopened = nil end
    end
    -- The same key again is a second step (`]]` pans twice), unless the
    -- view maps the pair itself (`]]` to the next section).
    exact, longer = lookup(first.key .. key)
    if key == first.key and not exact then
      exact, longer = nil, nil
    end
    if reopened and not (exact or longer) then
      -- Closed again as the key left it.
      M.set_mode("n")
      M.last_visual = reopened.last
      local g = grid()
      if g and reopened.cursor then g.set(reopened.cursor[1], reopened.cursor[2]) end
    end
    if exact or longer then
      if first.after ~= first.before and api.project_get("edits") == first.after then paw.undo() end
      if track.keys then track.edits = api.project_get("edits") end
      -- The count typed first is the longer mapping's: `2[t`.
      count, register = first.count, first.register
    else
      pending = {}
      if track.keys then track.keys[#track.keys] = nil end
      finish_command()
      track.keys, track.edits, track.texts = { key }, api.project_get("edits"), text_changes
    end
  end

  local escape = key == "<Esc>" or key == "<C-c>"
  if escape and (#pending > 0 or count or register or op) then return reset() end
  -- Escape leaves visual and insert mode, unless something that holds keys
  -- for a while (a suggestion showing: see `view:subscope()`) maps it first.
  if escape and (M.mode == "x" or M.mode == "i") and not held(key) then return M.set_mode("n") end

  if #pending == 0 and M.mode ~= "i" then
    if key:match("^%d$") and (count or key ~= "0") then
      count = (count or 0) * 10 + tonumber(key)
      return api.ui_redraw()
    end
    if key == '"' then
      awaiting = function(name)
        if name:match('^[%w_"]$') then
          register = name
        else
          reset()
        end
      end
      return
    end
    -- While a macro is being recorded, the key that started it ends it.
    if macro and (M.mode == "n" or M.mode == "x") then
      local map = lookup(key)
      if map and map.record then
        macro.keys[#macro.keys] = nil
        registers[macro.name] = { kind = "keys", keys = table.concat(macro.keys) }
        paw.notify("recorded @" .. macro.name)
        macro = nil
        return api.ui_redraw()
      end
    end
    -- The operator's own key again: whole rows, as many as the count.
    if M.mode == "o" and key == op.key then
      local o, g = op, grid()
      local n = times(o.count, count) or 1
      op, count = nil, nil
      M.set_mode("n")
      local row, col = g.get()
      local reg = region(row, col, row + (n - 1) * (g.down or 1), col, "line")
      if o.map.desc then api.undo_label(o.map.desc) end
      return o.map.operator(reg, { count = n, op_count = o.count, register = o.register, keys = o.map.lhs .. key })
    end
  end

  pending[#pending + 1] = key
  local exact, longer = lookup(table.concat(pending))
  stop_timer()

  if exact and not longer then
    return take(exact)
  elseif longer then
    -- Wait for the rest. Only when what was typed is a mapping already does
    -- the wait end by itself, in favour of that one; a bare prefix stays
    -- until it is finished or Escape drops it.
    if
      exact
      and #pending == 1
      and M.mode ~= "o"
      and not exact.char
      and (exact.nowait or exact.role == "second+" or exact.role == "second-")
    then
      -- It runs now; the wait is only for a key that makes a longer one.
      -- Its change is a step of its own, so that one undo takes it back.
      api.undo_checkpoint()
      local before, typed_count, typed_register, visual = api.project_get("edits"), count, register, M.mode == "x"
      take(exact)
      pending = { key }
      eager = {
        key = key,
        before = before,
        after = api.project_get("edits"),
        count = typed_count,
        register = typed_register,
        visual = visual,
      }
      timer = api.timer_start(paw.opt.timeoutlen, false, function()
        timer = nil
        if not eager then return end
        eager, pending = nil, {}
        finish_command()
        api.ui_redraw()
      end)
      return
    end
    if exact then
      timer = api.timer_start(paw.opt.timeoutlen, false, function()
        timer = nil
        take(exact)
        finish_command()
      end)
    end
  elseif #pending > 1 then
    -- The sequence led nowhere. Run the longest mapping it began with, if
    -- there is one, and take what was typed after it as new keys.
    local keys, n, found = pending, #pending - 1, nil
    while n >= 1 and not found do
      found = lookup(table.concat(keys, "", 1, n))
      if not found then n = n - 1 end
    end
    if found then
      pending = {}
      take(found)
    elseif M.mode == "o" then
      return reset()
    else
      -- Nothing is mapped, not even the start of it: say so and drop the
      -- rest, rather than run the last key as if it were typed alone.
      local typed = M.human(keys)
      reset()
      return paw.notify(typed .. " is not mapped", "warn")
    end
    for i = n + 1, #keys do
      handle(keys[i])
    end
  else
    local mode = M.mode
    reset()
    local view = paw.ui.views[paw.ui.focused]
    if mode == "i" and view and view.insert_hints and key ~= "<Esc>" then
      return paw.notify(M.human({ key }) .. " inserts nothing here: K lists the keys, <Esc> ends insert mode", "warn")
    end
    if mode ~= "n" then return end
    local view = paw.ui.views[paw.ui.focused]
    if key == "<Esc>" then
      paw.emit("escape", {})
      M.escape_hint()
    elseif view and view.on_key then
      view:on_key(key)
    end
  end
end

local next_key = {}

--- Run `fn` once, before the next key is handled: for what waits until the
--- person is back at the keyboard (a file changed outside paw).
function M.on_next_key(fn)
  for _, f in ipairs(next_key) do
    if f == fn then return end
  end
  next_key[#next_key + 1] = fn
end

--- Handle one key as if the user typed it. The kernel calls this. Scripts use `feed`.
function M.dispatch(key)
  if #next_key > 0 and depth == 0 then
    local due = next_key
    next_key = {}
    local grabber = paw.ui.grabber
    for _, fn in ipairs(due) do
      paw.try(fn)
    end
    -- What they asked takes the next key; this one only brought it up.
    if paw.ui.grabber and paw.ui.grabber ~= grabber then return end
  end
  key_serial = key_serial + 1
  if macro and depth == 0 then macro.keys[#macro.keys + 1] = key end
  -- A key of insert mode: its edits join the step the insert made first.
  if M.mode == "i" and insert_undo and api.undo_current() ~= insert_undo then api.undo_join(api.undo_current()) end
  if not track.keys then
    track.keys, track.edits, track.texts = {}, api.project_get("edits"), text_changes
  end
  track.keys[#track.keys + 1] = key
  local ok, err = xpcall(handle, debug.traceback, key)
  if not ok then
    reset()
    if M.mode == "o" then M.set_mode("n") end
    track = {}
    error(err, 0)
  end
  if #pending > 0 or op then
    -- Something is half typed: offer what can follow, after a moment.
    if not hint_at then
      hint_at = api.now() + paw.opt.hint_delay
      paw.defer(api.ui_redraw, paw.opt.hint_delay + 1)
    end
  else
    hint_at = nil
  end
  api.ui_redraw()
  finish_command()
end

--- Run keys inside the command that is running now, as a macro does.
local function replay(keys)
  if depth > 40 then error("a macro is running itself without end", 0) end
  depth = depth + 1
  local outer = track
  track = {}
  local ok = true
  for _, key in ipairs(keys) do
    ok = paw.try(M.dispatch, key)
    if not ok then break end
  end
  track, depth = outer, depth - 1
  return ok
end

--- Type keys as if from the keyboard: `paw.keymap.feed("jj<Space>")`.
function M.feed(keys)
  for _, key in ipairs(M.parse(keys)) do
    paw.try(M.dispatch, key)
  end
end

--- Type keys from inside a mapping, as `:normal` does. The keys run as a
--- part of the current command, not as a separate command.
function M.normal(keys) return replay(M.parse(keys)) end

-- Repeating ---------------------------------------------------------------------

--- Do the last change again, with `n` in place of its count if given.
function M.repeat_last(n)
  if not last_change then return paw.notify("nothing to repeat yet") end
  local keys = {}
  for i, key in ipairs(last_change) do
    keys[i] = key
  end
  if n then
    -- The count sits after a register name, if there is one.
    local at = keys[1] == '"' and 3 or 1
    while keys[at] and keys[at]:match("^%d$") do
      table.remove(keys, at)
    end
    for digit in tostring(n):reverse():gmatch("%d") do
      table.insert(keys, at, digit)
    end
  end
  replaying = true
  local ok, err = pcall(replay, keys)
  replaying = false
  if not ok then error(err, 0) end
end

--- Start recording keys into a register, or stop with no name.
function M.record(name)
  if not name:match("^%a$") then return paw.notify("a macro goes in a register named a to z", "warn") end
  macro = { name = name:lower(), keys = {} }
  api.ui_redraw()
end

--- The register being recorded into, if any.
function M.recording() return macro and macro.name end

--- Play the keys in a register `n` times. `@` as the name plays the last register again.
function M.play(name, n)
  if name == "@" then name = last_macro end
  local value = name and registers[name:lower()]
  if not (value and value.kind == "keys") then
    return paw.notify("no macro in register `" .. tostring(name) .. "`", "warn")
  end
  last_macro = name
  local keys = M.parse(value.keys)
  for _ = 1, n or 1 do
    if not replay(keys) then break end
  end
end

-- What to show --------------------------------------------------------------------

--- The keys typed for a command that is not complete, for display: `"a2d3`.
function M.pending()
  local out = ""
  if op then out = (op.register and '"' .. op.register or "") .. (op.count or "") .. op.map.lhs end
  return out .. (register and '"' .. register or "") .. (count or "") .. table.concat(pending)
end

--- The name given to a prefix with `group`, if any.
function M.group_name(keys)
  for _, scope in ipairs(scopes()) do
    local name = groups[scope] and groups[scope][keys]
    if name then return name end
  end
end

--- In insert mode of a view that sets `insert_hints` (the arrange view),
--- its keys of insert mode, after a moment: what each key inserts.
local function insert_hints()
  local view = paw.ui.views[paw.ui.focused]
  if not (view and view.insert_hints and insert_hint_at and api.now() >= insert_hint_at) then return nil end
  local out = {}
  for _, map in pairs(maps.i and maps.i[paw.ui.focused] or {}) do
    if map.hint ~= false then out[#out + 1] = { key = map.lhs, desc = map.desc or "", order = map.order } end
  end
  if #out == 0 then return nil end
  table.sort(out, function(a, b)
    if (a.order or 1e9) ~= (b.order or 1e9) then return (a.order or 1e9) < (b.order or 1e9) end
    return a.key:lower() .. a.key < b.key:lower() .. b.key
  end)
  for _, entry in ipairs(out) do
    entry.order = nil
  end
  return out, "-- INSERT -- <CR> opens, <BS> takes back, <Esc> ends"
end

--- The keys that can come after the typed keys, when the user stops to
--- type: a list of { key, desc }, and a title. Nil when there is nothing to show.
function M.hints()
  if M.mode == "i" and #pending == 0 and not op then return insert_hints() end
  if not hint_at or api.now() < hint_at then return nil end
  local seq, found = table.concat(pending), {}
  for _, scope in ipairs(scopes()) do
    for lhs, map in pairs(scope and maps[M.mode] and maps[M.mode][scope] or {}) do
      if #lhs > #seq and lhs:sub(1, #seq) == seq then
        local key = map.keys[#pending + 1]
        local entry = found[key] or { key = key, more = 0 }
        found[key] = entry
        if #map.keys == #pending + 1 then
          entry.desc = entry.desc or map.desc or (type(map.rhs) == "string" and map.rhs) or ""
        else
          entry.more = entry.more + 1
        end
      end
    end
  end
  if op and #pending == 0 then
    found[op.key] = found[op.key] or { key = op.key, desc = "the whole row, or as many as the count", more = 0 }
  end
  local out = {}
  for _, entry in pairs(found) do
    if not entry.desc then
      local named = M.group_name(seq .. entry.key)
      entry.desc = named and "+" .. named or "+" .. entry.more .. " more"
    end
    out[#out + 1] = entry
  end
  if #out == 0 then return nil end
  table.sort(out, function(a, b) return a.key:lower() .. a.key < b.key:lower() .. b.key end)
  return out, op and (op.map.desc or op.map.lhs) .. " …" or M.pending() .. " …"
end

-- Changing view ends whatever was half done in the old one.
paw.on("view.focused", function()
  if M.mode == "x" or M.mode == "i" or M.mode == "o" then
    reset()
    M.set_mode("n")
  end
end)

-- A leader set in init.lua or with `:set` moves every key on it, the
-- keys mapped before too: `paw.opt.leader = ","` puts the mixer on `,m`.
paw.on("option.changed", function(e)
  if e.name ~= "leader" and e.name ~= "localleader" then return end
  for _, by_scope in pairs(maps) do
    for _, by_keys in pairs(by_scope) do
      local moved = {}
      for keys, map in pairs(by_keys) do
        if type(map.lhs) == "string" and map.lhs:lower():find("leader>", 1, true) then
          moved[#moved + 1] = map
          by_keys[keys] = nil
        end
      end
      for _, map in ipairs(moved) do
        map.keys = M.parse(map.lhs)
        by_keys[table.concat(map.keys)] = map
      end
    end
  end
  for _, g in ipairs(group_lhs) do
    if groups[g[1]][g[4]] == g[3] then groups[g[1]][g[4]] = nil end
  end
  for _, g in ipairs(group_lhs) do
    g[4] = table.concat(M.parse(g[2]))
    groups[g[1]][g[4]] = g[3]
  end
  reset()
end)

-- A seat that closes leaves no key waiting to run in it.
paw.on("seat.closing", function() reset() end)

return setmetatable(M, { __call = function(_, ...) return M.set(...) end })
