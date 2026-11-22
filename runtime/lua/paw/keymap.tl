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
--
-- The registers and macros are in paw/keymap/registers.tl, the marks, the
-- jump list and the change list in paw/keymap/marks.tl: this module gives
-- their functions.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local options = require("paw.options")
local registers = require("paw.keymap.registers")
local marks = require("paw.keymap.marks")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type LimitModule = require("paw.limit")
local type SeatsModule = require("paw.seats")
local type UtilModule = require("paw.util")

local type Region = contracts.Region
local type Context = contracts.KeyContext
local type Grid = contracts.Grid

--- The modes: "n" normal, "x" visual, "o" after an operator, "i" insert,
--- "c" a prompt. "v" is taken as "x" where a mode is given.
local enum Mode
  "n"
  "x"
  "o"
  "i"
  "c"
  "v"
end

--- An operator's function: it acts on a region of the focused view.
local type Operator = function(region: Region, ctx?: Context)
--- A text object's function: the region at the cursor, or nil.
local type TextObject = function(ctx?: Context): Region
--- What a key runs: a command line, or a function.
local type Rhs = string | contracts.KeyFn

--- What `set` takes besides the keys and what they run. See `set`.
local record MapOptions
  mode: Mode | {Mode}
  view: string
  desc: string
  motion: boolean
  linewise: boolean
  jump: boolean
  repeatable: boolean
  nowait: boolean
  role: string
  --- The mapping waits for one more key, which its function gets as `ctx.char`.
  char: boolean
  --- The key that starts a macro: typed while one is recorded, it ends it.
  record: boolean
  --- The key answers a question on the screen: the key rule leaves it out.
  prompt: boolean
  --- False to leave the key out of the insert mode list (`insert_hints`).
  hint: boolean
  --- Where the key goes in the insert mode list: lower first.
  order: number
  --- "operator": the count typed before an operator is its own (`ctx.op_count`).
  count: string
  --- The extension that made the mapping (the one that loads now by default).
  ext: string
  operator: Operator
  object: TextObject
end

--- A mapping as `set` keeps it: the options, with the keys split
--- (`keys`), its one mode, its scope (a view, or "global") and `norepeat`
--- for `repeatable = false`.
local record Map
  lhs: string
  keys: {string}
  rhs: Rhs
  mode: Mode
  scope: string
  desc: string
  motion: boolean
  linewise: boolean
  jump: boolean
  repeatable: boolean
  norepeat: boolean
  nowait: boolean
  role: string
  char: boolean
  record: boolean
  prompt: boolean
  hint: boolean
  order: number
  count: string
  ext: string
  operator: Operator
  object: TextObject
end

--- A test of a mapping (`first`).
local type MapTest = function(map: Map): boolean
--- What `each` calls for each mapping, with its mode, its scope and its joined keys.
local type EachMap = function(map: Map, mode: Mode, scope: string, keys: string)

--- What `all` gives for each mapping: how it is typed, as "key",
--- "motion", "operator", "object", "visual" or "insert".
local record KeyAll
  map: Map
  kind: string
end

--- A key that can come next (`hints`): the key, what it does, and how
--- many longer mappings start with it.
local record Hint
  key: string
  desc: string
  more: integer
end

--- A text object that made the selection, to take in one more with the
--- same object again (`vic` then `ic`): where it was asked from, its
--- count, and where it left the cursor.
local record VisualObject
  map: Map
  count: integer
  row: number
  col: number
  at_row: number
  at_col: number
end

--- A selection: its `kind` ("v" a range of time, "V" whole rows, "b" a
--- rectangle, "clips" clips chosen with the pointer), its fixed end (`row`,
--- `col`) in `view`, and `region` when it names its region outright. The
--- last selection also keeps where the cursor was (`cursor_row`, `cursor_col`).
local record Visual
  kind: string
  row: number
  col: number
  view: string
  region: function(): Region
  object: VisualObject
  cursor_row: number
  cursor_col: number
end

--- The payload of `mode.changed`: the mode, and the one before.
local record ModeChanged
  mode: Mode
  old: Mode
end

--- What belongs to the user, for `paw.shada`: the last search and the registers.
local record UserState
  search: string
  registers: {string: registers.Register}
end

--- The mappings of one mode and one scope: by their joined keys, and the
--- prefixes of them, so that `lookup` needs no walk of the mappings.
local record MapTable
  by_keys: {string: Map}
  --- A prefix of keys -> how many mappings are longer and start with it.
  longer: {string: integer}
  --- The joined keys of a mapping -> the prefixes counted for it in `longer`.
  prefixes: {string: {string}}
end

--- An operator that waits for a motion or a text object.
local record Op
  map: Map
  count: integer
  register: string
  key: string
end

--- The command being typed: its keys, the count of edits of the project
--- and of text changes when it began, and whether `.` leaves it out.
local record Command
  keys: {string}
  edits: integer
  texts: integer
  norepeat: boolean
end

--- A key that ran at once though longer mappings start with it (`nowait`),
--- until the next key or the wait ends: the edits before and after it, and
--- the count, the register and the mode it was typed with.
local record Eager
  key: string
  before: integer
  after: integer
  count: integer
  register: string
  visual: boolean
end

--- A mapping that `classic` made, with what it covered in each mode (to put back).
local record Classic
  lhs: string
  rhs: Rhs | boolean
  opts: MapOptions
  modes: {Mode}
  covered: {Mode: Map}
end

--- A group on a leader key: its scope, its prefix as written, its name,
--- and the keys that the prefix is now.
local record LeaderGroup
  scope: string
  prefix: string
  name: string
  keys: string
end

--- What each seat has its own of.
local record Kept
  pending: {string}
  count: integer
  register: string
  op: Op
  awaiting: function(key: string)
  timer: integer
  hint_at: number
  command: Command
  last_change: {string}
  mode: Mode
  visual: Visual
  last_visual: Visual
  search_text: string
end

-- paw/ui.tl and paw/commands.tl name this module's types, so this module
-- declares only the parts of them that it reads.
local record Ui
  focused: string
  views: {string: contracts.View}
  grabber: function(key: string)
end
local record Commands
  exec: function(line: string, ctx?: contracts.CommandContext)
  owner: function(): string
end
local record Paw is partial.Paw
  ui: Ui
  commands: Commands
  limit: LimitModule
  seats: SeatsModule
  util: UtilModule
  undo: function(): boolean
  try: function<A>(fn: function(...: A), ...: A): boolean
end
local paw = (_G as {string: Paw}).paw

local record M
  type Mode = Mode
  type Map = Map
  type MapOptions = MapOptions
  type Operator = Operator
  type TextObject = TextObject
  type Rhs = Rhs
  type KeyAll = KeyAll
  type Hint = Hint
  type Visual = Visual
  type ModeChanged = ModeChanged
  type UserState = UserState
  type Register = registers.Register
  type Place = marks.Place
  type ProjectPlaces = marks.ProjectPlaces

  --- The mode: "n", "i", "x" (visual), "o" (after an operator) or "c".
  mode: Mode
  --- The open selection, nil outside visual mode.
  visual: Visual
  --- The selection that visual mode closed last (`gv` opens it again).
  last_visual: Visual
  --- The text of the last search (`/`).
  search_text: string
  --- The event `mode.changed`: the mode of the keymap changed.
  mode_changed: events.Event<ModeChanged>
  --- Counts the jumps (what goes into the jump list), so that a view can tell
  --- a jump of the cursor from a step: the view scrolls to the target of a jump.
  jump_serial: integer
  --- The operator that a motion runs for, while it runs (`paw.cursor`
  --- then keeps to the tracks).
  motion_for: Map
  --- True when a prompt drew only its line for this key (`paw.views.cmdline`).
  screen_kept: boolean
  --- The registers by name.
  registers: {string: registers.Register}

  setreg: function(value: registers.Register, name?: string, yank?: boolean)
  getreg: function(name?: string): registers.Register
  record: function(name: string)
  recording: function(): string
  play: function(name: string, n?: integer)
  push_jump: function()
  jump: function(n: integer)
  change: function(n: integer)
  changes: function(view?: string): marks.Places
  mark: function(name: string)
  goto_mark: function(name: string)
  delmarks: function(spec: string, all?: boolean): integer, string
  marks: function(view?: string): {string: marks.Place}
  shada_project: function(): marks.ProjectPlaces
  shada_set_project: function(data: marks.ProjectPlaces)
  scopes: function(): {string}

  metamethod __call: function(M, lhs: string, rhs: Rhs, opts?: MapOptions)
end

M.mode = "n"
M.jump_serial = 0
M.mode_changed = events.event("mode.changed")
M.registers = registers.registers

marks.on_jump = function() M.jump_serial = M.jump_serial + 1 end

-- The registers and macros (paw/keymap/registers.tl).
M.setreg, M.getreg = registers.setreg, registers.getreg
M.record, M.recording, M.play = registers.record, registers.recording, registers.play

-- The marks and the lists of places (paw/keymap/marks.tl).
M.push_jump, M.jump, M.change, M.changes = marks.push_jump, marks.jump, marks.change, marks.changes
M.mark, M.goto_mark, M.delmarks, M.marks = marks.mark, marks.goto_mark, marks.delmarks, marks.marks
M.shada_project, M.shada_set_project = marks.shada_project, marks.shada_set_project

local opt = options.opt
local maps: {Mode: {string: MapTable}} = {} -- mode -> scope -> the mappings
local groups: {string: {string: string}} = {} -- scope -> keys -> name of a prefix that only leads to more keys
local group_lhs: {LeaderGroup} = {} -- the groups on a leader

-- Each seat's own: two people can be half way through two commands, in
-- two modes. (The registers and the marks keep theirs in their modules.)
local pending: {string} = {} -- keys typed so far of an unfinished sequence
local count: integer -- number typed before the sequence
local register: string -- register named with `"x` for the next command
local op: Op -- the operator waiting for a motion
local awaiting: function(key: string) -- takes the next key, whatever it is
local timer: integer
local hint_at: number -- when to start listing the keys that can follow
local command: Command = {} -- the command being typed
local last_change: {string} -- the keys of the last command that changed the project

paw.seats.keep(
  "keymap",
  function(): Kept
    return {
      pending = pending,
      count = count,
      register = register,
      op = op,
      awaiting = awaiting,
      timer = timer,
      hint_at = hint_at,
      command = command,
      last_change = last_change,
      mode = M.mode,
      visual = M.visual,
      last_visual = M.last_visual,
      search_text = M.search_text,
    }
  end,
  function(k: Kept)
    pending, count, register, op, awaiting = k.pending, k.count, k.register, k.op, k.awaiting
    timer, hint_at, command, last_change = k.timer, k.hint_at, k.command, k.last_change
    M.mode, M.visual, M.last_visual, M.search_text = k.mode, k.visual, k.last_visual, k.search_text
  end,
  function(): Kept return {pending = {}, command = {}, mode = "n"} end
)

local replaying = false -- `.` is running: its keys are not a new change
local depth = 0 -- how many replays (macros, `.`) are running inside each other

-- A one-field read of the project: the count of its edits, on each key.
local project_field = api.project_get as function(key: string): integer
local function edits(): integer
  return project_field("edits")
end

--- A leader option as a key: a space (the default leader) is `<Space>`.
local function leader_key(value: string): string
  return value == " " and "<Space>" or value
end

--- Write `<leader>` and `<localleader>` as the keys the options name.
function M.expand(lhs: string): string
  return (
    lhs:gsub("<[Ll]ocal[Ll]eader>", function(): string return leader_key(opt.localleader) end):gsub(
      "<[Ll]eader>", function(): string return leader_key(opt.leader) end
    )
  )
end

--- Split `gg<C-x>` into { "g", "g", "<C-x>" }, and expand `<leader>` and `<localleader>`.
function M.parse(lhs: string): {string}
  local keys: {string} = {}
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

local key_names: {string: string} = {
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
local modifier_names: {string: string} = {C = "Ctrl", A = "Alt", M = "Alt", S = "Shift", D = "Super"}

--- Keys as a person writes them: `<A-h>` is `Alt-h`, `<leader>at` is `Space at`,
--- `<localleader>d` is `\d`, `<C-w>o` is `Ctrl-w o`, `<CR>` is `Enter`. Takes an `lhs` or a list of keys.
function M.human(keys: string | {string}): string
  local list: {string}
  if keys is string then
    list = M.parse(keys)
  else
    list = keys
  end
  local out: {string} = {}
  local prev_word = false
  for i, key in ipairs(list) do
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
    if i > 1 and (word or prev_word) then
      out[#out + 1] = " "
    end
    out[#out + 1] = text
    prev_word = word
  end
  return table.concat(out)
end

-- The mapping table -------------------------------------------------------------

--- The mappings of `mode` in `scope`, made when `make` is true.
local function table_of(mode: Mode, scope: string, make?: boolean): MapTable
  local by_scope = maps[mode]
  if not by_scope then
    if not make then
      return nil
    end
    by_scope = {}
    maps[mode] = by_scope
  end
  local t = by_scope[scope]
  if not t and make then
    t = {by_keys = {}, longer = {}, prefixes = {}}
    by_scope[scope] = t
  end
  return t
end

--- The mapping of `mode` in `scope` with the joined keys `keys`, if any.
local function mapped(mode: Mode, scope: string, keys: string): Map
  local t = table_of(mode, scope)
  return t and t.by_keys[keys]
end

--- Put `map` under the joined keys `keys` of `mode` in `scope`, or remove
--- what is there with nil. Each change of the mappings goes through here,
--- so that the prefixes of `lookup` stay true.
local function store(mode: Mode, scope: string, keys: string, map: Map)
  local t = table_of(mode, scope, true)
  -- The prefixes of the mapping that goes away.
  for _, prefix in ipairs(t.prefixes[keys] or {}) do
    local n = t.longer[prefix] - 1
    t.longer[prefix] = n > 0 and n or nil
  end
  t.prefixes[keys] = nil
  t.by_keys[keys] = map
  if not map then
    return
  end
  -- Each prefix of the new mapping's keys, at the boundaries of keys.
  local list: {string} = {}
  local prefix = ""
  for i = 1, #map.keys - 1 do
    prefix = prefix .. map.keys[i]
    list[i] = prefix
    t.longer[prefix] = (t.longer[prefix] or 0) + 1
  end
  t.prefixes[keys] = list
end

--- Call `fn(map, mode, scope)` for each mapping, in no order.
local function each_map(fn: EachMap)
  for mode, by_scope in pairs(maps) do
    for scope, t in pairs(by_scope) do
      for keys, map in pairs(t.by_keys) do
        fn(map, mode, scope, keys)
      end
    end
  end
end

--- The modes a mapping goes in: `opts.mode` (one or a list), else `default`.
--- "v" is "x".
local function modes_of(opts: MapOptions, default: {Mode}): {Mode}
  local given = opts.mode
  local list: {Mode}
  if given is {Mode} then
    list = given
  elseif given then
    list = {given}
  else
    list = default
  end
  local out: {Mode} = {}
  for i, mode in ipairs(list) do
    out[i] = mode == "v" and "x" or mode
  end
  return out
end

--- Make the mapping of `lhs` in each of `modes`, with the options of `opts`.
local function define(lhs: string, rhs: Rhs, opts: MapOptions, modes: {Mode}, operator: Operator, object: TextObject)
  local scope = opts.view or "global"
  local keys = M.parse(lhs)
  local joined = table.concat(keys)
  for _, mode in ipairs(modes) do
    store(
      mode,
      scope,
      joined,
      {
        lhs = lhs,
        keys = keys,
        rhs = rhs,
        mode = mode,
        scope = scope,
        desc = opts.desc,
        motion = opts.motion,
        linewise = opts.linewise,
        jump = opts.jump,
        repeatable = opts.repeatable,
        norepeat = opts.repeatable == false,
        nowait = opts.nowait,
        role = opts.role,
        char = opts.char,
        record = opts.record,
        prompt = opts.prompt,
        hint = opts.hint,
        order = opts.order,
        count = opts.count,
        ext = opts.ext or paw.commands.owner(),
        operator = operator,
        object = object,
      }
    )
  end
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
---
--- `linewise = true` is for a motion across rows. `jump = true` keeps the
--- position of the cursor for `<C-o>`. With `repeatable = false`, `.` does
--- not repeat the mapping. `nowait = true` makes a key that also starts
--- longer mappings run at once, without the wait for more keys.
---
--- Each key with `role` "second+" or "second-" (the `[` and `]` of a view)
--- does so. The same key again is a second press. Another key soon after
--- it that makes a longer mapping (`]g`, `]q`) takes back its change and runs
--- that mapping. On a selection, the selection opens again for that mapping.
function M.set(lhs: string, rhs: Rhs, opts?: MapOptions)
  opts = opts or {}
  local default: {Mode} = opts.motion and {"n", "x", "o"} or {"n"}
  define(lhs, rhs, opts, modes_of(opts, default), opts.operator, opts.object)
end

--- Give a name to a prefix that only leads to more keys. The hints after it
--- then show `+mix`, not the number of keys after it.
---   paw.keymap.group("<leader>m", "mix")
--- With `opts.view`, the name applies only while that view has focus.
function M.group(prefix: string, name: string, opts?: MapOptions)
  local scope = opts and opts.view or "global"
  groups[scope] = groups[scope] or {}
  local keys = table.concat(M.parse(prefix))
  groups[scope][keys] = name
  if prefix:lower():find("leader>", 1, true) then
    group_lhs[#group_lhs + 1] = {scope = scope, prefix = prefix, name = name, keys = keys}
  end
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
function M.operator(lhs: string, fn: Operator, opts?: MapOptions)
  define(lhs, nil, opts or {}, {"n", "x"}, fn, nil)
end

--- Define a text object: `fn(ctx)` returns a region, or nil when there is
--- nothing of that kind at the cursor.
---   paw.keymap.textobject("ic", function() ... end, { view = "arrange", desc = "The clip" })
function M.textobject(lhs: string, fn: TextObject, opts?: MapOptions)
  define(lhs, nil, opts or {}, {"o", "x"}, nil, fn)
end

--- Remove a mapping: `opts.mode` and `opts.view` as `set` took them.
function M.del(lhs: string, opts?: MapOptions)
  opts = opts or {}
  local mode = (opts.mode or "n") as Mode
  local scope = opts.view or "global"
  if table_of(mode, scope) then
    store(mode, scope, table.concat(M.parse(lhs)), nil)
  end
end

--- Call `fn(map, mode, scope, keys)` for each mapping, in no order, with
--- `keys` joined as `put` takes them. It is `every` without the sort.
function M.each(fn: EachMap)
  each_map(fn)
end

--- Put a mapping back as `map` (a mapping that `every` gave), or remove it
--- with nil. The mapping is found by its mode, scope and joined keys
--- (`table.concat(map.keys)`). An extension that unloads does this with
--- the keys that it mapped.
function M.put(mode: Mode, scope: string, keys: string, map: Map)
  store(mode, scope, keys, map)
end

-- The keys as they were before every view kept to one rule (docs/reference/key-rule.md,
-- "The classic keys"), made only with `paw.opt.keys = "classic"`.
local classic: {Classic} = {}

--- Make a classic mapping, keeping what it covers to put back.
local function apply(entry: Classic)
  local opts, rhs = entry.opts, entry.rhs
  local default: {Mode} = (opts.motion or opts.operator ~= nil) and {"n", "x", "o"} or {"n"}
  local scope, keys = opts.view or "global", table.concat(M.parse(entry.lhs))
  entry.modes, entry.covered = modes_of(opts, default), {}
  for _, mode in ipairs(entry.modes) do
    entry.covered[mode] = mapped(mode, scope, keys)
    if rhs == false and entry.covered[mode] then
      store(mode, scope, keys, nil)
    end
  end
  if rhs ~= false then
    M.set(entry.lhs, rhs as Rhs, opts)
  end
end

--- Take a classic mapping away again, putting back what it covered.
local function revert(entry: Classic)
  local scope, keys = entry.opts.view or "global", table.concat(M.parse(entry.lhs))
  for _, mode in ipairs(entry.modes or {}) do
    store(mode, scope, keys, entry.covered[mode])
  end
  entry.modes, entry.covered = nil, nil
end

--- A mapping as it was before the key rule. paw makes it when
--- `paw.opt.keys` is "classic", now or later. It goes over the mapping that
--- the rule gives the same keys. paw removes it again when the option
--- changes back. A false `rhs` removes the keys.
---   paw.keymap.classic("j", "track.volume by=-1", { view = "mixer", desc = "Volume down 1 dB" })
function M.classic(lhs: string, rhs: Rhs | boolean, opts?: MapOptions)
  local entry: Classic = {lhs = lhs, rhs = rhs, opts = opts or {}}
  classic[#classic + 1] = entry
  if opt.keys == "classic" then
    apply(entry)
  end
end

events.on(
  options.changed,
  function(e: options.Changed)
    if e.name ~= "keys" then
      return
    end
    if e.value == "classic" then
      for _, entry in ipairs(classic) do
        apply(entry)
      end
    elseif e.old == "classic" then
      for i = #classic, 1, -1 do
        revert(classic[i])
      end
    end
  end
)

--- The names given to prefixes with `group`: scope -> keys -> name.
function M.groups(): {string: {string: string}}
  return groups
end

-- What `list` sorts each mapping by, made once for each: the status line
-- lists the mappings on each frame.
local sort_keys: {Map: string} = setmetatable({}, {__mode = "k"})
local function by_keys(a: Map, b: Map): boolean
  local ka, kb = sort_keys[a], sort_keys[b]
  if not ka then
    ka = a.lhs:lower() .. a.lhs
    sort_keys[a] = ka
  end
  if not kb then
    kb = b.lhs:lower() .. b.lhs
    sort_keys[b] = kb
  end
  return ka < kb
end

--- The mappings of `mode` in a view, then the global ones.
local function scope_tables(mode: Mode, view: string): {MapTable}
  local out: {MapTable} = {}
  for _, scope in ipairs({view or false, "global"} as {string}) do
    local t = scope and table_of(mode, scope)
    if t then
      out[#out + 1] = t
    end
  end
  return out
end

--- The first mapping of `mode` (in `view`, then global) that `test(map)`
--- is true for, in the order of `list`, with no list made and sorted.
function M.first(mode: Mode, test: MapTest, view?: string): Map
  for _, t in ipairs(scope_tables(mode, view)) do
    local best: Map
    for _, map in pairs(t.by_keys) do
      if test(map) and (not best or by_keys(map, best)) then
        best = map
      end
    end
    if best then
      return best
    end
  end
end

--- Mappings that apply in `mode` for `view`, the view's own first.
function M.list(mode: Mode, view?: string): {Map}
  local out: {Map} = {}
  for _, t in ipairs(scope_tables(mode, view)) do
    local list: {Map} = {}
    for _, map in pairs(t.by_keys) do
      list[#list + 1] = map
    end
    table.sort(list, by_keys)
    for _, map in ipairs(list) do
      out[#out + 1] = map
    end
  end
  return out
end

--- Every mapping in every mode and scope, sorted by scope, mode and keys.
--- What checks the key rules walks (`tests/keys_constitution.lua`).
function M.every(): {Map}
  local out: {Map} = {}
  each_map(function(map: Map) out[#out + 1] = map end)
  table.sort(
    out,
    function(a: Map, b: Map): boolean
      if a.scope ~= b.scope then
        return a.scope < b.scope
      end
      if a.mode ~= b.mode then
        return (a.mode as string) < (b.mode as string)
      end
      return a.lhs < b.lhs
    end
  )
  return out
end

--- True if a mapping with the same keys and scope is also made in `mode`.
function M.has(mode: Mode, map: Map): boolean
  return mapped(mode, map.scope, table.concat(map.keys)) ~= nil
end

--- Where paw finds mappings, first to last. First comes the part of the
--- focused view that has the cursor, if the view has such parts
--- (`view:subscope()`). For example, "arrange.lane" on an automation lane
--- row, or a list of parts, the first part first. Then comes the view,
--- then all views.
function M.scopes(): {string}
  local name = paw.ui.focused
  local view = name and paw.ui.views[name]
  local out: {string} = {}
  if view and view.subscope then
    local ok, sub = pcall(view.subscope, view) as (boolean, string | {string})
    if ok and sub is {string} then
      for _, s in ipairs(sub) do
        out[#out + 1] = s
      end
    elseif ok and sub then
      out[#out + 1] = sub as string
    end
  end
  if name then
    out[#out + 1] = name
  end
  out[#out + 1] = "global"
  return out
end

--- Every mapping that can be typed while `view` has focus, each once:
--- normal mode, then what only a selection, an operator or insert mode
--- takes. Each comes with `kind`: "key", "motion", "operator", "object",
--- "visual" or "insert".
function M.all(view: string): {KeyAll}
  local out: {KeyAll} = {}
  local shadowed: {string: boolean} = {} -- mode .. keys the part of the view takes over
  -- A part of the view the cursor is in comes first: its keys win.
  if view == paw.ui.focused then
    local sub = M.scopes()
    for i = 1, #sub - 2 do
      for _, mode in ipairs({"n", "x", "i"} as {Mode}) do
        local list: {Map} = {}
        local t = table_of(mode, sub[i])
        for _, map in pairs(t and t.by_keys or {}) do
          list[#list + 1] = map
        end
        table.sort(list, function(a: Map, b: Map): boolean return a.lhs:lower() .. a.lhs < b.lhs:lower() .. b.lhs end)
        for _, map in ipairs(list) do
          local id = mode .. table.concat(map.keys)
          if not shadowed[id] and (mode ~= "x" or not M.has("n", map)) then
            local kind = mode == "x" and "visual" or mode == "i" and "insert" or map.motion and "motion" or "key"
            out[#out + 1] = {map = map, kind = kind}
          end
          shadowed[id] = true
        end
      end
    end
  end
  for _, map in ipairs(M.list("n", view)) do
    if not shadowed["n" .. table.concat(map.keys)] then
      out[#out + 1] = {map = map, kind = map.operator and "operator" or map.motion and "motion" or "key"}
    end
  end
  for _, map in ipairs(M.list("x", view)) do
    if not shadowed["x" .. table.concat(map.keys)] and not map.motion and not map.object and not M.has("n", map) then
      out[#out + 1] = {map = map, kind = "visual"}
    end
  end
  for _, map in ipairs(M.list("o", view)) do
    if map.object then
      out[#out + 1] = {map = map, kind = "object"}
    end
  end
  for _, map in ipairs(M.list("i", view)) do
    if not shadowed["i" .. table.concat(map.keys)] then
      out[#out + 1] = {map = map, kind = "insert"}
    end
  end
  return out
end

-- Modes and the selection ----------------------------------------------------------

local grid = marks.grid

local function stop_timer()
  if timer then
    api.timer_stop(timer)
    timer = nil
  end
end

-- The undo state current when insert mode began. What is done from then
-- until insert mode ends (the clip `i` made, the notes drawn into it) is
-- one undo step, as an insert is in Vim: the steps after the first join it.
local insert_undo: integer
local insert_hint_at: number -- when insert mode's keys show, in a view that lists them
local key_serial = 0 -- counts the keys handled: what one key did together

--- The insert that ended last: its undo state, and the key that ended it.
local record LeftInsert
  undo: integer
  key: integer
end
local left_insert: LeftInsert

--- The selection `v` as it was closed with the cursor at `row`, `col`.
local function closed(v: Visual, row: number, col: number): Visual
  return {
    kind = v.kind,
    row = v.row,
    col = v.col,
    view = v.view,
    region = v.region,
    object = v.object,
    cursor_row = row,
    cursor_col = col,
  }
end

--- Change mode. When visual mode stops, the selection closes. `gv` opens it again.
function M.set_mode(mode: Mode)
  if mode == "v" then
    mode = "x"
  end
  local old = M.mode
  if M.visual and mode ~= "x" and mode ~= "c" then
    local g = grid()
    if g and M.visual.view == paw.ui.focused then
      local row, col = g.get()
      M.last_visual = closed(M.visual, row, col)
    end
    M.visual = nil
  end
  if mode == old then
    return
  end
  if mode == "i" then
    insert_undo = api.undo_current()
    -- Insert mode that hands over to another view's in the same key (the
    -- arrange view's `m` then Enter: the piano roll) is one insert still.
    if left_insert and left_insert.key == key_serial then
      insert_undo = left_insert.undo
    end
    -- A view whose insert mode is a choice of keys lists them after a moment.
    local view = paw.ui.views[paw.ui.focused]
    if view and view.insert_hints then
      insert_hint_at = api.now() + opt.hint_delay
      paw.defer(api.ui_redraw, opt.hint_delay + 1)
    end
  end
  M.mode = mode
  events.emit(M.mode_changed, {mode = mode, old = old})
  if old == "i" then
    left_insert = {undo = insert_undo, key = key_serial}
    insert_undo = nil
  end
  api.ui_redraw()
end

-- A key that ran at once though longer mappings start with it (`nowait`),
-- until the next key or the wait ends.
local eager: Eager

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

local function region(r: number, c: number, r2: number, c2: number, kind: string): Region
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
local function first_row(g: Grid, reg: Region): number
  return g.down == -1 and reg.r1 or reg.r0
end

--- Start a selection from the cursor: "v" a range of time, "V" whole rows,
--- "b" a rectangle. The same kind again stops visual mode.
function M.visual_start(kind: string)
  local g = grid()
  if not g then
    return paw.notify("nothing to select in this view", "warn")
  end
  if M.visual and M.visual.kind == kind then
    return M.set_mode("n")
  end
  if M.visual then
    M.visual.kind, M.visual.region = kind, nil
    return api.ui_redraw()
  end
  local row, col = g.get()
  M.visual = {kind = kind, row = row, col = col, view = paw.ui.focused}
  M.set_mode("x")
end

--- Open the last selection again.
function M.visual_restore()
  local g, last = grid(), M.last_visual
  if not (g and last and last.view == paw.ui.focused) then
    return
  end
  M.visual = {kind = last.kind, row = last.row, col = last.col, view = last.view, region = last.region}
  g.set(last.cursor_row, last.cursor_col)
  M.set_mode("x")
end

--- Swap the cursor with the selection's other end.
function M.visual_swap()
  local g, v = grid(), M.visual
  if not (g and v) then
    return
  end
  local row, col = g.get()
  g.set(v.row, v.col)
  v.row, v.col = row, col
end

--- The region a selection `v` covers with the cursor at `row`, `col`.
local function selected(v: Visual, g: Grid, row: number, col: number): Region
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

local ranged: Region -- the region `:'<,'>` names while its command runs

--- The region selected in the focused view, or nil outside visual mode. It
--- goes from the cursor to the start of the selection. Both ends are
--- included when the view tells the size of the item under the cursor
--- (`grid.extent`). A selection that did not grow covers one grid step.
--- While a command runs with `:'<,'>`, it is the selection that the command names.
function M.selection(): Region
  if ranged then
    return ranged
  end
  local v, g = M.visual, grid()
  if not (v and g) or v.view ~= paw.ui.focused then
    return nil
  end
  local row, col = g.get()
  return selected(v, g, row, col)
end

--- The last selection made in the focused view, as `'<,'>` names it: the
--- one open now, or the one visual mode last closed. Nil if there is none.
function M.last_selection(): Region
  local open = M.selection()
  if open then
    return open
  end
  local last, g = M.last_visual, grid()
  if not (last and g) or last.view ~= paw.ui.focused then
    return nil
  end
  return selected(last, g, last.cursor_row, last.cursor_col)
end

--- Run `fn(...)` with `region` as the selection, the way `:'<,'>` runs a
--- command: anything that asks for the selection meanwhile gets it.
function M.with_selection<A, R>(region_: Region, fn: function(...: A): (R...), ...: A): R...
  local outer = ranged
  ranged = region_
  local args = table.pack(...)
  local results: {R}
  local n: integer
  local ok, err = pcall(
    function() local packed = table.pack(fn(table.unpack(args, 1, args.n))); results, n = packed, packed.n end
  ) as (boolean, string)
  ranged = outer
  if not ok then
    error(err, 0)
  end
  return table.unpack(results, 1, n)
end

-- Search ----------------------------------------------------------------------

--- Move to the next (`dir` 1) or previous (-1) thing in the focused view that
--- matches the last search. Views say what matches through `grid.search`.
function M.search_next(dir: integer, n?: integer)
  local g = grid()
  if not (g and g.search) then
    return
  end
  if not M.search_text then
    return paw.notify("nothing searched for yet: `/`", "warn")
  end
  local hits = g.search(M.search_text)
  if #hits == 0 then
    return paw.notify("nothing matches `" .. M.search_text .. "`", "warn")
  end
  table.sort(
    hits,
    function(a: contracts.GridHit, b: contracts.GridHit): boolean
      if a.col ~= b.col then
        return a.col < b.col
      end
      return a.row < b.row
    end
  )
  local row, col = g.get()
  for _ = 1, n or 1 do
    local found: contracts.GridHit
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
function M.search(text: string, dir?: integer)
  M.search_text = text
  M.search_next(dir or 1)
end

--- What belongs to the user, for `paw.shada`: the last search and the
--- registers (as a table of registers by name).
function M.shada_user(): UserState
  return {search = M.search_text, registers = registers.registers}
end

--- Put back what `shada_user` gave.
function M.shada_set_user(data: UserState)
  if type(data.search) == "string" then
    M.search_text = data.search
  end
  for name, value in pairs(data.registers or {}) do
    if registers.registers[name] == nil then
      registers.registers[name] = value
    end
  end
end

-- Running mappings --------------------------------------------------------------

--- Name the undo step a key makes by its description. A key typed (not
--- one a macro or a mapping plays) first takes back the name of a key
--- before it that changed nothing: `3G` then `dd` is the delete.
local function label(text: string)
  if depth == 0 then
    api.undo_label(nil)
  end
  if text then
    api.undo_label(text)
  end
end

local function exec(map: Map, ctx: Context, motion?: boolean)
  -- The key's description names the undo step it makes. Keys that replay
  -- others (`.`, `@a`) leave the name to what they replay, and an
  -- operator's motion to the operator.
  if not map.norepeat and not motion then
    label(map.desc)
  end
  local rhs = map.rhs
  if rhs is string then
    paw.commands.exec(rhs, ctx as contracts.CommandContext)
  elseif rhs then
    paw.limit.named("the key " .. M.human(map.lhs) .. (map.desc and " (" .. map.desc .. ")" or ""), rhs, ctx)
  end
end

local function times(a: integer, b: integer): integer
  if a or b then
    return (a or 1) * (b or 1)
  end
end

-- A motion or a text object for the operator that was waiting for one.
local function run_for_operator(map: Map, ctx: Context, g: Grid)
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
  local reg: Region
  if map.object then
    reg = map.object(ctx)
  else
    -- The motion knows it moves for an operator (`paw.cursor` then
    -- keeps to the tracks).
    M.motion_for = o.map
    local ok, err = pcall(exec, map, ctx, true) as (boolean, string)
    M.motion_for = nil
    if not ok then
      error(err, 0)
    end
    local r2, c2 = g.get()
    if not map.linewise and r == r2 and c == c2 then
      return
    end
    reg = region(r, c, r2, c2, map.linewise and "line" or "char")
  end
  if not reg then
    return
  end
  -- The cursor ends up where the region starts.
  if reg.kind == "line" then
    g.set(first_row(g, reg), c)
  else
    g.set(r, reg.c0)
  end
  o.map.operator(reg, ctx)
end

-- An operator: on the selection in visual mode, else it waits for a motion.
local function run_operator(map: Map, ctx: Context, g: Grid)
  if M.mode == "x" then
    local reg = M.selection()
    local _, col = g.get()
    M.set_mode("n")
    if not reg then
      return
    end
    label(map.desc)
    if map.count == "operator" then
      ctx.op_count = ctx.count
    end
    if reg.kind == "line" then
      g.set(first_row(g, reg), col)
    else
      g.set(first_row(g, reg), reg.c0)
    end
    return map.operator(reg, ctx)
  end
  if not g then
    return paw.notify("nothing in this view for `" .. map.lhs .. "` to act on", "warn")
  end
  op = {map = map, count = ctx.count, register = ctx.register, key = map.keys[#map.keys]}
  M.set_mode("o")
end

-- A text object outside an operator: in visual mode it becomes the
-- selection. The same object again, with the cursor where it left it,
-- takes in one more (`vic` then `ic`): it is asked again from where the
-- first one started, with a count one higher.
local function run_object(map: Map, ctx: Context, g: Grid)
  local v = M.visual
  local again: VisualObject
  if g and v and v.object and v.object.map == map then
    local r, c = g.get()
    if r == v.object.at_row and c == v.object.at_col then
      again = v.object
    end
  end
  local from_row, from_col: number, number
  if g then
    from_row, from_col = g.get()
  end
  if again then
    from_row, from_col = again.row, again.col
    g.set(from_row, from_col)
    ctx.count = again.count + (ctx.count or 1)
  end
  local reg = map.object(ctx)
  if again and not reg then
    g.set(again.at_row, again.at_col)
  end
  if not (reg and M.visual and g) then
    return
  end
  -- A region that names its notes is the selection as it is: the
  -- cursor does not stretch it.
  local fixed: function(): Region
  if reg.notes then
    fixed = function(): Region return paw.util.copy(reg) end
  end
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
  M.visual.object = {
    map = map, count = ctx.count or 1, row = from_row, col = from_col, at_row = at_row, at_col = at_col
  }
end

local function run(map: Map, char?: string)
  local ctx: Context = {count = count, register = register, keys = map.lhs, char = char, mode = M.mode}
  local g = grid()
  pending, count, register, hint_at = {}, nil, nil, nil
  stop_timer()
  if map.norepeat then
    command.norepeat = true
  end
  if M.mode == "o" then
    return run_for_operator(map, ctx, g)
  end
  if map.operator then
    return run_operator(map, ctx, g)
  end
  if map.object then
    return run_object(map, ctx, g)
  end
  if map.jump then
    M.push_jump()
  end
  exec(map, ctx)
end

--- The mapping for exactly `seq`, and whether a longer mapping starts with it.
local function lookup(seq: string): Map, boolean
  local exact: Map
  local longer = false
  for _, scope in ipairs(M.scopes()) do
    local t = table_of(M.mode, scope)
    if t then
      exact = exact or t.by_keys[seq]
      longer = longer or t.longer[seq] ~= nil
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
local function held(key: string): boolean
  local list = M.scopes()
  for i = 1, #list - 2 do
    if mapped(M.mode, list[i], key) then
      return true
    end
  end
  return false
end

local function idle(): boolean
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
function M.changed()
  text_changes = text_changes + 1
end

--- What to run once the next whole command is done.
local record After
  fn: function()
  armed: boolean
end
local after: After

--- Run `fn` after paw gets and does the next whole command. Insert mode uses
--- it for Ctrl-o, to return to insert mode after one command.
function M.after_next(fn: function())
  after = {fn = fn}
end

--- Once a command is complete, remember it for `.` if it changed the project.
local function finish_command()
  if not idle() then
    return
  end
  local edited = command.keys and edits() ~= command.edits
  if edited then
    marks.push_change()
  end
  local changed = command.keys and (edited or text_changes ~= command.texts)
  if changed and not command.norepeat and not replaying then
    last_change = command.keys
  end
  command = {}
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
local function take(map: Map)
  if not map.char then
    return run(map)
  end
  awaiting = function(key: string)
    if key == "<Esc>" or key == "<C-c>" then
      return reset()
    end
    run(map, key == "<Space>" and " " or key == "<lt>" and "<" or key)
  end
end

local handle: function(key: string)

-- After a key that ran at once (`nowait`), this key either makes a longer
-- mapping with it, which takes back what that key changed, or starts afresh.
local function after_eager(key: string)
  local first = eager
  eager = nil
  stop_timer()
  -- A key that ran on a selection closed it: the longer mapping is looked
  -- for, and runs, on the selection open again (`v]n` after `]`).
  local reopened = false
  local last_visual = M.last_visual
  local g = grid()
  local cursor_row, cursor_col: number, number
  if first.visual and M.mode ~= "x" then
    if g then
      cursor_row, cursor_col = g.get()
    end
    M.visual_restore()
    reopened = M.mode == "x"
  end
  -- The same key again is a second step (`]]` pans twice), unless the
  -- view maps the pair itself (`]]` to the next section).
  local exact, longer = lookup(first.key .. key)
  if key == first.key and not exact then
    exact, longer = nil, false
  end
  if reopened and not (exact or longer) then
    -- Closed again as the key left it.
    M.set_mode("n")
    M.last_visual = last_visual
    g = grid()
    if g and cursor_row then
      g.set(cursor_row, cursor_col)
    end
  end
  if exact or longer then
    if first.after ~= first.before and edits() == first.after then
      paw.undo()
    end
    if command.keys then
      command.edits = edits()
    end
    -- The count typed first is the longer mapping's: `2[t`.
    count, register = first.count, first.register
  else
    pending = {}
    if command.keys then
      command.keys[#command.keys] = nil
    end
    finish_command()
    command.keys, command.edits, command.texts = {key}, edits(), text_changes
  end
end

-- The keys that a command starts with, before any mapping: a count, a
-- register, the key that ends the recording of a macro, and an operator's
-- own key again. True when the key was one of them.
local function command_start(key: string): boolean
  if key:match("^%d$") and (count or key ~= "0") then
    count = (count or 0) * 10 + math.floor(tonumber(key))
    api.ui_redraw()
    return true
  end
  if key == '"' then
    awaiting = function(name: string)
      if name:match('^[%w_"]$') then
        register = name
      else
        reset()
      end
    end
    return true
  end
  -- While a macro is being recorded, the key that started it ends it.
  if registers.recording() and (M.mode == "n" or M.mode == "x") then
    local map = lookup(key)
    if map and map.record then
      registers.stop()
      return true
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
    if o.map.desc then
      api.undo_label(o.map.desc)
    end
    o.map.operator(reg, {count = n, op_count = o.count, register = o.register, keys = o.map.lhs .. key})
    return true
  end
  return false
end

-- A key that may also start longer mappings runs at once (`nowait`, or the
-- second value keys): the wait is only for a key that makes a longer one.
-- Its change is a step of its own, so that one undo takes it back.
local function run_eager(key: string, exact: Map)
  api.undo_checkpoint()
  local before, typed_count, typed_register, visual = edits(), count, register, M.mode == "x"
  take(exact)
  pending = {key}
  eager = {
    key = key,
    before = before,
    after = edits(),
    count = typed_count,
    register = typed_register,
    visual = visual,
  }
  timer = api.timer_start(
    opt.timeoutlen,
    false,
    function()
      timer = nil
      if not eager then
        return
      end
      eager, pending = nil, {}
      finish_command()
      api.ui_redraw()
    end
  )
end

-- The keys led nowhere. Run the longest mapping they began with, if there
-- is one, and take what was typed after it as new keys.
local function dead_end()
  local keys, n = pending, #pending - 1
  local found: Map
  while n >= 1 and not found do
    found = lookup(table.concat(keys, "", 1, n))
    if not found then
      n = n - 1
    end
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
end

-- A key that no mapping starts with: the view's own `on_key` in normal
-- mode, or a word on what went wrong.
local function unmapped(key: string)
  local mode = M.mode
  reset()
  local view = paw.ui.views[paw.ui.focused]
  if mode == "i" and view and view.insert_hints and key ~= "<Esc>" then
    return paw.notify(M.human({key}) .. " inserts nothing here: K lists the keys, <Esc> ends insert mode", "warn")
  end
  if mode ~= "n" then
    return
  end
  if key == "<Esc>" then
    events.emit("escape", {})
    M.escape_hint()
  elseif view and view.on_key then
    view:on_key(key)
  end
end

--- Handle one key press.
handle = function(key: string)
  if paw.ui.grabber then
    return paw.ui.grabber(key)
  end
  local focused = paw.ui.views[paw.ui.focused]
  if focused and focused.modal then
    focused:on_key(key)
    return
  end
  if awaiting then
    local fn = awaiting
    awaiting = nil
    return fn(key)
  end
  if eager then
    after_eager(key)
  end

  local escape = key == "<Esc>" or key == "<C-c>"
  if escape and (#pending > 0 or count or register or op) then
    return reset()
  end
  -- Escape leaves visual and insert mode, unless something that holds keys
  -- for a while (a suggestion showing: see `view:subscope()`) maps it first.
  if escape and (M.mode == "x" or M.mode == "i") and not held(key) then
    return M.set_mode("n")
  end
  if #pending == 0 and M.mode ~= "i" and command_start(key) then
    return
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
    local second = exact and (exact.role == "second+" or exact.role == "second-")
    if exact and #pending == 1 and M.mode ~= "o" and not exact.char and (exact.nowait or second) then
      return run_eager(key, exact)
    end
    if exact then
      timer = api.timer_start(opt.timeoutlen, false, function() timer = nil; take(exact); finish_command() end)
    end
  elseif #pending > 1 then
    dead_end()
  else
    unmapped(key)
  end
end

local next_key: {function()} = {}

--- Run `fn` once, before the next key is handled: for what waits until the
--- person is back at the keyboard (a file changed outside paw).
function M.on_next_key(fn: function())
  for _, f in ipairs(next_key) do
    if f == fn then
      return
    end
  end
  next_key[#next_key + 1] = fn
end

--- Handle one key as if the user typed it. The kernel calls this. Scripts use `feed`.
function M.dispatch(key: string)
  if #next_key > 0 and depth == 0 then
    local due = next_key
    next_key = {}
    local grabber = paw.ui.grabber
    for _, fn in ipairs(due) do
      paw.try(fn)
    end
    -- What they asked takes the next key; this one only brought it up.
    if paw.ui.grabber and paw.ui.grabber ~= grabber then
      return
    end
  end
  key_serial = key_serial + 1
  M.screen_kept = false
  if depth == 0 then
    registers.typed(key)
  end
  -- A key of insert mode: its edits join the step the insert made first.
  if M.mode == "i" and insert_undo and api.undo_current() ~= insert_undo then
    api.undo_join(api.undo_current())
  end
  if not command.keys then
    command.keys, command.edits, command.texts = {}, edits(), text_changes
  end
  command.keys[#command.keys + 1] = key
  local ok, err = xpcall(handle, debug.traceback as (function(string): string), key) as (boolean, string)
  if not ok then
    reset()
    if M.mode == "o" then
      M.set_mode("n")
    end
    command = {}
    error(err, 0)
  end
  if #pending > 0 or op then
    -- Something is half typed: offer what can follow, after a moment.
    if not hint_at then
      hint_at = api.now() + opt.hint_delay
      paw.defer(api.ui_redraw, opt.hint_delay + 1)
    end
  else
    hint_at = nil
  end
  -- A prompt that drew only its line (`paw.views.cmdline`) has asked for that.
  if not M.screen_kept then
    api.ui_redraw()
  end
  finish_command()
end

--- Run keys inside the command that is running now, as a macro does.
local function replay(keys: {string}): boolean
  if depth > 40 then
    error("a macro is running itself without end", 0)
  end
  depth = depth + 1
  local outer = command
  command = {}
  local ok = true
  for _, key in ipairs(keys) do
    ok = paw.try(M.dispatch, key)
    if not ok then
      break
    end
  end
  command, depth = outer, depth - 1
  return ok
end

--- Type keys as if from the keyboard: `paw.keymap.feed("jj<Space>")`.
function M.feed(keys: string)
  for _, key in ipairs(M.parse(keys)) do
    paw.try(M.dispatch, key)
  end
end

--- Type keys from inside a mapping, as `:normal` does. The keys run as a
--- part of the current command, not as a separate command.
function M.normal(keys: string): boolean
  return replay(M.parse(keys))
end

registers.replay = M.normal

-- Repeating ---------------------------------------------------------------------

--- Do the last change again, with `n` in place of its count if given.
function M.repeat_last(n?: integer)
  if not last_change then
    return paw.notify("nothing to repeat yet")
  end
  local keys: {string} = {}
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
  if not ok then
    error(err, 0)
  end
end

--- Make `.` repeat `keys` (a list of keys), not the keys typed for the
--- command that runs now. `:adjust` does it, so that `.` does the adjusted
--- command again.
function M.repeat_as(keys: {string})
  last_change = keys
  command.norepeat = true
end

-- What to show --------------------------------------------------------------------

--- The keys typed for a command that is not complete, for display: `"a2d3`.
function M.pending(): string
  local out = ""
  if op then
    out = (op.register and '"' .. op.register or "") .. (op.count and tostring(op.count) or "") .. op.map.lhs
  end
  return out .. (register and '"' .. register or "") .. (count and tostring(count) or "") .. table.concat(pending)
end

--- The name given to a prefix with `group`, if any.
function M.group_name(keys: string): string
  for _, scope in ipairs(M.scopes()) do
    local name = groups[scope] and groups[scope][keys]
    if name then
      return name
    end
  end
end

--- In insert mode of a view that sets `insert_hints` (the arrange view),
--- its keys of insert mode, after a moment: what each key inserts.
local function insert_hints(): {Hint}, string
  local view = paw.ui.views[paw.ui.focused]
  if not (view and view.insert_hints and insert_hint_at and api.now() >= insert_hint_at) then
    return nil
  end
  local shown: {Map} = {}
  local t = table_of("i", paw.ui.focused)
  for _, map in pairs(t and t.by_keys or {}) do
    if map.hint ~= false then
      shown[#shown + 1] = map
    end
  end
  if #shown == 0 then
    return nil
  end
  table.sort(
    shown,
    function(a: Map, b: Map): boolean
      if (a.order or 1e9) ~= (b.order or 1e9) then
        return (a.order or 1e9) < (b.order or 1e9)
      end
      return a.lhs:lower() .. a.lhs < b.lhs:lower() .. b.lhs
    end
  )
  local out: {Hint} = {}
  for i, map in ipairs(shown) do
    out[i] = {key = map.lhs, desc = map.desc or ""}
  end
  return out, "-- INSERT -- <CR> opens, <BS> takes back, <Esc> ends"
end

--- The keys that can come after the typed keys, when the user stops to
--- type: a list of { key, desc }, and a title. Nil when there is nothing to show.
function M.hints(): {Hint}, string
  if M.mode == "i" and #pending == 0 and not op then
    return insert_hints()
  end
  if not hint_at or api.now() < hint_at then
    return nil
  end
  local seq = table.concat(pending)
  local found: {string: Hint} = {}
  for _, scope in ipairs(M.scopes()) do
    local t = table_of(M.mode, scope)
    for lhs, map in pairs(t and t.by_keys or {}) do
      if #lhs > #seq and lhs:sub(1, #seq) == seq then
        local key = map.keys[#pending + 1]
        local entry = found[key] or {key = key, more = 0}
        found[key] = entry
        if #map.keys == #pending + 1 then
          local rhs = map.rhs
          entry.desc = entry.desc or map.desc or (rhs is string and rhs) or ""
        else
          entry.more = entry.more + 1
        end
      end
    end
  end
  if op and #pending == 0 then
    found[op.key] = found[op.key] or {key = op.key, desc = "the whole row, or as many as the count", more = 0}
  end
  local out: {Hint} = {}
  for _, entry in pairs(found) do
    if not entry.desc then
      local named = M.group_name(seq .. entry.key)
      entry.desc = named and "+" .. named or "+" .. entry.more .. " more"
    end
    out[#out + 1] = entry
  end
  if #out == 0 then
    return nil
  end
  table.sort(out, function(a: Hint, b: Hint): boolean return a.key:lower() .. a.key < b.key:lower() .. b.key end)
  return out, op and (op.map.desc or op.map.lhs) .. " …" or M.pending() .. " …"
end

-- Changing view ends whatever was half done in the old one.
events.on(
  events.event("view.focused") as events.Event<events.Payload>,
  function()
    if M.mode == "x" or M.mode == "i" or M.mode == "o" then
      reset()
      M.set_mode("n")
    end
  end
)

-- A leader set in init.lua or with `:set` moves every key on it, the
-- keys mapped before too: `paw.opt.leader = ","` puts the mixer on `,m`.
events.on(
  options.changed,
  function(e: options.Changed)
    if e.name ~= "leader" and e.name ~= "localleader" then
      return
    end
    local record Moved
      map: Map
      keys: string
    end
    local moved: {Moved} = {}
    each_map(
      function(map: Map, _: Mode, _: string, keys: string)
        if map.lhs:lower():find("leader>", 1, true) then
          moved[#moved + 1] = {map = map, keys = keys}
        end
      end
    )
    for _, m in ipairs(moved) do
      store(m.map.mode, m.map.scope, m.keys, nil)
    end
    for _, m in ipairs(moved) do
      m.map.keys = M.parse(m.map.lhs)
      store(m.map.mode, m.map.scope, table.concat(m.map.keys), m.map)
    end
    for _, g in ipairs(group_lhs) do
      if groups[g.scope][g.keys] == g.name then
        groups[g.scope][g.keys] = nil
      end
    end
    for _, g in ipairs(group_lhs) do
      g.keys = table.concat(M.parse(g.prefix))
      groups[g.scope][g.keys] = g.name
    end
    reset()
  end
)

-- A seat that closes leaves no key waiting to run in it.
events.on(events.event("seat.closing") as events.Event<events.Payload>, function() reset() end)

return setmetatable(M, {__call = function(_: M, lhs: string, rhs: Rhs, opts?: MapOptions) M.set(lhs, rhs, opts) end})
