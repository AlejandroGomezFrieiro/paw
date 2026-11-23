-- The quickfix list, as Neovim's: one shared place for what is wrong (or
-- found) anywhere in the project, each entry with an address (paw/address.tl)
-- to go to, and maybe a fix. docs/reference/quickfix.md says how it is used,
-- docs/reference/lua-addresses.md how to fill it.
--
-- An entry is `{ address, selector?, text, level?, source, fix?, nest? }`:
-- `address` a `paw://` address (or a location, `{ uri, selector }`),
-- `level` "error", "warning", "info" or "hint" (or 1 to 4; none for a
-- plain match), `fix` `{ title, edit = { workspace changes } }`,
-- `{ title, apply = function(entry) end }` or a command line run with the
-- cursor on the entry, `nest` the subproject of an entry whose address
-- names no track in it.
--
-- Lists are kept in a history of ten (`:colder`, `:cnewer`); each has a
-- title. The quickfix lists are shared; every window has location lists of
-- its own (`:lopen`, `:lnext`). One quickfix list, "Problems", is kept by
-- the program: each source (`paw.qf.feed`) owns its entries in it, and the
-- program feeds it the diagnostics, renders that clipped, were too loud or
-- failed, missing sound files, plugins that stopped or are not installed,
-- and plugin files that could not be looked into.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local render = require("paw.render")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local commands = require("paw.commands")
local A = require("paw.address")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type UiModule = require("paw.ui")
local type LayoutModule = require("paw.layout")
local type objects = require("paw.objects")
local type DiagnosticModule = require("paw.diagnostic")
local type LanesModule = require("paw.lanes")
local type CursorModule = require("paw.cursor")
local type Roll = require("paw.views.pianoroll")
local type NestModule = require("paw.nest")
local type ScopeModule = require("paw.scope")

local type Level = DiagnosticModule.Level
local type Diagnostic = DiagnosticModule.Diagnostic

--- What a source keeps in an entry: the diagnostics keep the diagnostic.
local record Data
  diagnostic: Diagnostic
end

--- A fix of an entry: changes of a workspace edit (`edit`, see
--- `paw.address.edit`), a function (`apply`), or a command line (a `Fix`
--- that is text) run with the cursor on the entry.
local record FixSpec
  title: string
  edit: {A.Change}
  apply: function(entry: Entry)
end
local type Fix = string | FixSpec

--- An entry as `paw.qf.set` and `paw.qf.feed` take it: an `address` (or a
--- location) or a `location`, with a `selector`; the `text` (or
--- `message`), the `level` (or `severity`), the `source`, a `fix` (or the
--- first of `fixes`), the source's own `data` and the `nest` (`Located`).
local record Item
  address: string | contracts.Location
  location: contracts.Location
  selector: contracts.Selector
  text: string
  message: string
  level: Level
  severity: Level
  source: string
  fix: Fix
  fixes: {Fix}
  data: Data
  nest: integer
end

--- What `paw.qf.go` takes: an entry, or anything with a location. `nest`
--- is the subproject that the entry is about when the address does not
--- name a thing in it (`paw://project` for the name of a subproject).
local interface Located
  location: contracts.Location
  nest: integer
end

--- An entry as the list keeps it: the severity 1 to 4 and its word, or
--- neither for a plain match; `fixed` once its fix was made.
local record Entry is Located
  address: string
  text: string
  severity: integer
  level: string
  source: string
  fix: Fix
  data: Data
  fixed: boolean
end

--- A list: its title, its entries and the current one (0: none yet).
local record List
  id: integer
  title: string
  entries: {Entry}
  idx: integer
end

--- A history of lists, and the current one.
local record Stack
  lists: {List}
  at: integer
end

--- What `paw.qf.set` takes besides the entries: `win` a window for its
--- location lists (true: the current one), the `title`, the `source` of
--- the entries, and `current = false` to keep another list current.
local record SetOptions
  win: integer | boolean
  title: string
  source: string
  current: boolean
end

--- How many entries of each level a list has.
local record Count
  error: integer
  warning: integer
  info: integer
  hint: integer
  total: integer
end

--- What `paw.qf.cdo` takes: the stack, and `per_track` to run once for
--- each track of the entries.
local record CdoOptions
  stack: Stack
  per_track: boolean
end

--- What `paw.qf.fix` takes: the stack, and the label of the undo step.
local record FixOptions
  stack: Stack
  label: string
end

--- What `paw.qf.open` takes: `loc` for a location list (of window `win`,
--- the current one by default) and its height in rows.
local record OpenOptions
  loc: boolean
  win: integer
  height: number
end

--- The payload of `qf.changed`: the title of the list, and the window of
--- a location list.
local record Changed
  title: string
  win: integer | boolean
end

--- What a command run on an entry (`:cdo`, a fix that is a command line)
--- gets besides the arguments: the address, the whole location and the entry.
local record EntryContext is commands.Context
  target: string
  location: contracts.Location
  entry: Entry
end

--- A value of the options of a render (paw/render.tl), which this module
--- passes on.
local record RenderValue
end
local type RenderOptions = {string: RenderValue}

--- The payload of `plugins.scanned`: the notes of the scan, and the name
--- it was about (`:plugins.rescan name`).
local record Scanned
  notes: {string}
  name: string
end

-- What this module reads of paw/layout.tl, as records of its own, and of
-- the modules that are still in Lua.

--- A window of the layout (paw/layout.tl): its id, its view, its buffer,
--- its size in rows and its weight.
local record Win
  id: integer
  view: string
  buf: integer
  size: number
  weight: number
end

--- A buffer of the layout: its number and the target it was made for (a
--- window, or "quickfix").
local record LayoutBuf
  id: integer
  target: integer | string
end

--- What `paw.layout.split` takes.
local record SplitOptions
  win: Win
  view: string
  buf: integer
end

--- What `paw.layout.leaf` takes besides the view.
local record LeafFields
  buf: integer
  size: number
end

--- paw/layout.tl, as far as this module calls it.
local record Layout
  current: function(): Win
  get: function(id: integer): Win
  buf_of: function(win: Win): LayoutBuf
  buf_create: function(type_name: string, target: integer | string): LayoutBuf
  windows: function(): {Win}
  enter: function(win: Win)
  split: function(opts: SplitOptions): Win
  leaf: function(view: string, fields: LeafFields): Win
  tidy: function(root: {Win})
  close: function(win: Win): boolean
end

--- What a key's function gets (`paw.keymap.set`).
local type KeyContext = contracts.KeyContext

local record Paw is partial.Paw
  keymap: KeymapModule
  ui: UiModule
  layout: LayoutModule
  lanes: LanesModule
  cursor: CursorModule
  time: objects.Time
  diagnostic: DiagnosticModule
  nest: NestModule
  scope: ScopeModule
  render: function(path: string, opts: RenderOptions)
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local record M
  type Data = Data
  type FixSpec = FixSpec
  type Fix = Fix
  type Item = Item
  type Entry = Entry
  type List = List
  type Stack = Stack
  type SetOptions = SetOptions
  type Count = Count
  type CdoOptions = CdoOptions
  type FixOptions = FixOptions
  type OpenOptions = OpenOptions
  type Changed = Changed
  --- How many lists a history keeps.
  HISTORY: integer
  --- The title of the list that the program keeps.
  PROBLEMS: string
  -- The descriptor is `event`, because `changed` is a function: the
  -- entries of a source can be different now.
  --- The event `qf.changed`: the quickfix list or a location list changed.
  event: events.Event<Changed>
  type Located = Located
  severity_of: function(level: Level | boolean): integer
  refresh: function()
  open: function(opts?: OpenOptions): Win
end

options.define("qf_height", 10) -- rows of the window `:copen` opens
options.define(
  "qf_diagnostics", "warning"
) -- diagnostics this severe and worse go into Problems; "hint" for all, "off" for none
options.define("render_loudest", -9) -- LUFS: a render louder than this is listed as too loud

M.HISTORY = 10
M.PROBLEMS = "Problems"
M.event = events.event("qf.changed")

local LEVELS = {"error", "warning", "info", "hint"}
local by_word: {string: integer} = {
  error = 1, e = 1, warning = 2, warn = 2, w = 2, info = 3, information = 3, i = 3, hint = 4, h = 4
}

--- A severity from 1 (error) to 4 (hint) from a number or a word. Nil for none.
local function severity_of(level: Level | boolean): integer
  if level == nil or level == false then
    return nil
  end
  if level is number then
    return math.max(1, math.min(4, math.floor(level)))
  end
  return by_word[tostring(level):lower()]
end
M.severity_of = severity_of

-- Stacks of lists: the quickfix one, and each window's location lists.
local next_id = 0
local function new_stack(): Stack
  return {lists = {}, at = 0}
end
local quickfix = new_stack()
local locations: {integer: Stack} = {} -- window number -> stack

local function layout(): Layout
  return paw.layout as Layout
end

--- The quickfix lists.
function M.stack(): Stack
  return quickfix
end

--- The location lists of a window (of the current window without `win`),
--- made when you ask with `make`. A window that shows a location list uses
--- the list that it shows, as in Neovim.
function M.loc_stack(win?: integer, make?: boolean): Stack, integer
  if not win then
    local cur = layout().current()
    local buf = cur and cur.view == "qflist" and layout().buf_of(cur)
    local target = buf and buf.target
    win = target is integer and target or (cur and cur.id)
  end
  if not win then
    return nil
  end
  if not locations[win] and make then
    locations[win] = new_stack()
  end
  return locations[win], win
end

-- Entries ------------------------------------------------------------------------

--- An entry as the list keeps it: `{ address, location, text, level,
--- severity, source, fix, data }`.
function M.entry(e: Item, source?: string): Entry
  local loc = e.location
  local address = e.address
  if not loc and address is contracts.Location then
    loc = address
  end
  if not loc and address is string then
    loc = {uri = address, selector = e.selector}
  end
  local severity = severity_of(e.level or e.severity)
  local fix = e.fix
  local fixes = e.fixes
  if fix == nil and type(fixes) == "table" then
    fix = fixes[1]
  end
  return {
    address = loc and loc.uri,
    location = loc,
    text = tostring(e.text or e.message or ""),
    severity = severity,
    level = severity and LEVELS[severity] or nil,
    source = e.source or source,
    fix = fix,
    data = e.data,
    nest = e.nest,
  }
end

local function key_of(e: Entry): string
  return tostring(e.address) .. "\0" .. e.text
end

local function make_list(title: string, entries: {Entry}): List
  next_id = next_id + 1
  return {id = next_id, title = title or "", entries = entries or {}, idx = 0}
end

-- Put new entries in a list, keeping the entry that was current where it is.
local function replace(list: List, entries: {Entry})
  local was = list.entries[list.idx]
  list.entries = entries
  list.idx = 0
  if was then
    for i, e in ipairs(entries) do
      if key_of(e) == key_of(was) then
        list.idx = i
        break
      end
    end
  end
end

local function find(stack: Stack, title: string): List, integer
  for i, list in ipairs(stack.lists) do
    if list.title == title then
      return list, i
    end
  end
end

-- Add a list after the current one, dropping the newer, as Neovim does;
-- the oldest goes past ten.
local function push(stack: Stack, list: List, current: boolean)
  if current ~= false then
    for i = #stack.lists, stack.at + 1, -1 do
      stack.lists[i] = nil
    end
  end
  stack.lists[#stack.lists + 1] = list
  while #stack.lists > M.HISTORY do
    table.remove(stack.lists, 1)
    stack.at = stack.at - 1
  end
  if current ~= false or stack.at < 1 then
    stack.at = #stack.lists
  end
end

local refresh: function()

--- The current list of a stack (the quickfix lists by default), or nil.
function M.current(stack?: Stack): List
  refresh()
  stack = stack or quickfix
  return stack.lists[stack.at]
end

--- Put a list of entries in the quickfix lists (the location lists of a
--- window with `opts.win`, of the current window with `opts.win = true`),
--- with the title `opts.title`, and make it current. A list with the same
--- title in the history is replaced at its place. Its current entry stays.
--- `opts.current = false` keeps a different list current. Returns the list.
---   paw.qf.set({ { address = "paw://track/3", text = "too quiet", level = "warning" } }, { title = "Levels" })
function M.set(entries: {Item}, opts?: SetOptions): List
  opts = opts or {}
  local stack = quickfix
  local win = opts.win
  if win then
    stack = M.loc_stack(win is integer and win or nil, true)
  end
  assert(stack, "no window for a location list")
  local list_entries: {Entry} = {}
  for i, e in ipairs(entries or {}) do
    list_entries[i] = M.entry(e, opts.source or opts.title)
  end
  local title = opts.title or ""
  local list, at = find(stack, title)
  if list then
    replace(list, list_entries)
    if opts.current ~= false then
      stack.at = at
    end
  else
    list = make_list(title, list_entries)
    push(stack, list, opts.current)
  end
  api.ui_redraw()
  events.emit(M.event, {title = title, win = opts.win})
  return list
end

-- Problems: what each source says, kept by source ---------------------------------

local feeds: {string: {Entry}} = {} -- source -> entries
local pulls: {string: function(): {Item}} = {} -- source -> function giving its entries
local dirty: {string: boolean} = {} -- sources to ask again
local ORDER = {"diagnostic", "render", "media", "plugins", "plugin scan"}

local function problems_entries(): {Entry}
  local names: {string} = {}
  for name in pairs(feeds) do
    names[#names + 1] = name
  end
  local rank: {string: integer} = {}
  for i, name in ipairs(ORDER) do
    rank[name] = i
  end
  table.sort(
    names,
    function(a: string, b: string): boolean
      local ra, rb = rank[a] or 99, rank[b] or 99
      if ra ~= rb then
        return ra < rb
      end
      return a < b
    end
  )
  local out: {Entry} = {}
  for _, name in ipairs(names) do
    for _, e in ipairs(feeds[name]) do
      out[#out + 1] = e
    end
  end
  -- The worst first, each source's own order kept within a level.
  local order: {Entry: integer} = {}
  for i, e in ipairs(out) do
    order[e] = i
  end
  table.sort(
    out,
    function(a: Entry, b: Entry): boolean
      local sa, sb = a.severity or 5, b.severity or 5
      if sa ~= sb then
        return sa < sb
      end
      return order[a] < order[b]
    end
  )
  return out
end

local function store_problems()
  local entries = problems_entries()
  local list = find(quickfix, M.PROBLEMS)
  if list then
    replace(list, entries)
  elseif #entries > 0 then
    -- Made by the program, it does not take the place of the list being
    -- worked through.
    local current = quickfix.lists[quickfix.at]
    push(quickfix, make_list(M.PROBLEMS, entries), not (current and #current.entries > 0) and true or false)
  end
  api.ui_redraw()
  events.emit(M.event, {title = M.PROBLEMS})
end

--- The current entries of a source, in the Problems list. These entries
--- replace the old entries of the source (none removes them). Each
--- extension can feed it.
---   paw.qf.feed("tuning", { { address = "paw://clip/4", text = "out of tune", level = "warning" } })
function M.feed(source: string, entries: {Item})
  local list: {Entry} = {}
  for i, e in ipairs(entries or {}) do
    list[i] = M.entry(e, source)
  end
  feeds[source] = #list > 0 and list or nil
  store_problems()
end

--- A source that paw asks for its entries when they can change. `fn()`
--- returns them. paw calls it again after `paw.qf.changed(source)`, one
--- time, when a user next looks at the list.
function M.source(source: string, fn: function(): {Item})
  pulls[source] = fn
  dirty[source] = true
  api.ui_redraw()
end

--- Tell paw that the entries of a source can be different now.
function M.changed(source: string)
  if pulls[source] then
    dirty[source] = true
    api.ui_redraw()
  end
end

local refreshing = false
refresh = function()
  if refreshing or not next(dirty) then
    return
  end
  refreshing = true
  local ok, err = pcall(
    function(): string
      local some = false
      for source in pairs(dirty) do
        dirty[source] = nil
        local fn = pulls[source]
        local okf, entries = pcall(fn)
        if not okf then
          api.log("qf: " .. source .. ": " .. tostring(entries))
          entries = {}
        end
        local list: {Entry} = {}
        for i, e in ipairs(entries or {}) do
          list[i] = M.entry(e, source)
        end
        local before = feeds[source]
        feeds[source] = #list > 0 and list or nil
        some = some or before ~= nil or #list > 0
      end
      if some then
        store_problems()
      end
    end
  )
  refreshing = false
  if not ok then
    error(err, 0)
  end
end
--- Read every source of the Problems list again.
M.refresh = function() refresh() end

--- What a source has in the Problems list now.
function M.fed(source: string): {Entry}
  refresh()
  return feeds[source] or {}
end

-- Where an entry is, in words ------------------------------------------------------

--- A marker as `paw.address.resolve` gives it.
local record MarkerThing is A.Thing
  name: string
  beat: number
  start: number
end

--- The subject of an entry, in a few words: `Bass 3.1.00`, `Lead › Synth`,
--- `mix.wav`. Empty without an address.
function M.where(e: Entry): string
  local loc = e.location
  if not loc then
    return ""
  end
  local p = A.parse(loc.uri)
  local t = loc.selector and loc.selector.time
  local scheme = p and A.schemes:get(p.kind)
  if scheme and scheme.where then
    return scheme.where(loc, p)
  end
  if p and p.kind == "lane" then
    local ok, lane = pcall(api.lane_get, p.lane)
    return (ok and paw.lanes.name(lane) or "a lane") .. (t and (" " .. paw.time.format(t[1])) or "")
  end
  if p and p.kind == "marker" then
    local m = A.resolve(loc.uri) as MarkerThing
    return m and (m.name or "marker") .. " " .. paw.time.format(m.beat or m.start or 0) or "a marker"
  end
  return paw.diagnostic.where({location = loc, at = t and t[1] or 0})
end

--- An entry in one line, as said when going to it: `(2 of 7) error: …`.
function M.format(e: Entry, list?: List): string
  local at = ""
  if list then
    for i, x in ipairs(list.entries) do
      if x == e then
        at = string.format("(%d of %d) ", i, #list.entries)
      end
    end
  end
  return string.format(
    "%s%s%s%s", at, e.level and (e.level .. ": ") or "", e.text, e.source and (" [" .. e.source .. "]") or ""
  )
end

-- Going to an entry ------------------------------------------------------------------

local GONE: {string: boolean} = {
  clip = true, note = true, control = true, track = true, device = true, param = true, send = true, lane = true
}

local track_nest = api.track_get as function(id: integer, key: string): integer

--- Put the window in the subproject of an entry (its `nest`, else the
--- subproject of the track of its address), or in the song for a thing
--- of the song. An address with no track and no `nest` leaves the window
--- where it is. False, with a message, when the subproject is gone.
local function show_nest_of(e: Located, uri: string): boolean
  local inside = e.nest
  if not inside then
    local track = A.track_of(uri)
    if not track then
      return true
    end
    local ok, nest = pcall(track_nest, track, "nest") as (boolean, integer)
    inside = ok and nest or nil
  end
  local ok, why = paw.nest.show(inside)
  if not ok then
    paw.notify(why, "warn")
  end
  return ok
end

--- Put the cursor on the address of an entry, in the view that shows it
--- best, and focus that view. A thing inside a subproject goes inside
--- that subproject first. A note goes to the piano roll, and a device
--- or a parameter to the device panel. A clip, a track, a lane or a range
--- of time goes to the arrange view. Returns true if there was a place to go.
function M.go(e: Located): boolean
  local loc = e.location
  if not loc then
    return false
  end
  local p = A.parse(loc.uri)
  if not p then
    return false
  end
  if GONE[p.kind] and not A.resolve(loc.uri) then
    paw.notify("what this entry is about is gone", "warn")
    return false
  end
  if not show_nest_of(e, loc.uri) then
    return false
  end
  -- An address of an extension's own kind goes where the kind says.
  local scheme = A.schemes:get(p.kind)
  if scheme and scheme.go then
    return scheme.go(loc, p) ~= false
  end
  if p.kind == "lane" then
    local lane = api.lane_get(p.lane)
    local arrange = paw.ui.locators.arrange
    paw.ui.focus("arrange")
    arrange.go(loc)
    if lane.track then
      paw.lanes.open(lane.track, true)
      paw.cursor.set_track(lane.track, p.lane)
    end
    return true
  end
  -- A clip of audio, or one named as a whole, is gone to in the arrange view.
  if p.kind == "clip" and not (loc.selector and loc.selector.notes) then
    local c = api.clip_get(p.clip)
    if c.kind == "audio" or not loc.selector then
      paw.ui.focus("arrange")
      paw.ui.locators.arrange.go(loc)
      return true
    end
  end
  for _, name in ipairs({"pianoroll", "devices", "arrange", "mixer"}) do
    local locator = paw.ui.locators[name]
    if locator and locator.place(loc, true) then
      paw.ui.go(loc)
      return true
    end
  end
  return false
end

local function say(e: Entry, list: List)
  paw.notify(M.format(e, list), e.severity == 1 and "error" or e.severity == 2 and "warn" or "info")
end

--- Make entry `n` of a stack's current list the current entry and go to it.
function M.jump(n: number, stack?: Stack): Entry
  local list = M.current(stack)
  if not list or #list.entries == 0 then
    paw.notify("no entries" .. (list and " in " .. list.title or ""), "warn")
    return nil
  end
  local at = math.max(1, math.min(#list.entries, n)) as integer
  list.idx = at
  local e = list.entries[at]
  M.go(e)
  say(e, list)
  api.ui_redraw()
  return e
end

--- Go `count` entries forward (back, when negative) from the current entry.
--- The first `]q` goes to the first entry. It stops at the ends, as Neovim does.
function M.step(count: integer, stack?: Stack): Entry
  local list = M.current(stack)
  if not list or #list.entries == 0 then
    paw.notify("no entries" .. (list and " in " .. list.title or ""), "warn")
    return nil
  end
  local at = list.idx
  if at == 0 then
    at = count > 0 and 0 or #list.entries + 1
  end
  local to = at + count
  if (count > 0 and at >= #list.entries) or (count < 0 and at <= 1) then
    paw.notify(count > 0 and "no more entries: this is the last" or "no more entries: this is the first", "warn")
    return nil
  end
  return M.jump(to, stack)
end

--- Go to the list's first entry, or its last.
function M.first(stack?: Stack): Entry
  return M.jump(1, stack)
end
--- Go to the list's last entry.
function M.last(stack?: Stack): Entry
  return M.jump(math.huge, stack)
end

--- Go to an older list in the history (`count` back), or a newer one.
function M.older(count?: integer, stack?: Stack): List
  stack = stack or quickfix
  refresh()
  if #stack.lists == 0 then
    paw.notify("no lists", "warn")
    return nil
  end
  local to = stack.at - (count or 1)
  if to < 1 or to > #stack.lists then
    paw.notify((count or 1) > 0 and "no older list" or "no newer list", "warn")
    return nil
  end
  stack.at = to
  local list = stack.lists[to]
  paw.notify(
    string.format(
      "list %d of %d: %s, %d entr%s", to, #stack.lists, list.title, #list.entries, #list.entries == 1 and "y" or "ies"
    )
  )
  api.ui_redraw()
  return list
end

--- Go to a newer list in the history (`count` on).
function M.newer(count?: integer, stack?: Stack): List
  return M.older(-(count or 1), stack)
end

-- Counts and the status line ----------------------------------------------------------

--- How many entries of each level a list has: `{ error, warning, info, hint, total }`.
function M.count(list?: List): Count
  local out: Count = {error = 0, warning = 0, info = 0, hint = 0, total = 0}
  local by = out as {string: integer}
  for _, e in ipairs(list and list.entries or {}) do
    if e.level then
      by[e.level] = by[e.level] + 1
    end
    out.total = out.total + 1
  end
  return out
end

--- The part of the status line while the quickfix list has entries:
--- `qf 2/7 E2 W5`, with the position after you go to an entry. Nil when the
--- list is empty.
function M.status(): {contracts.Piece}
  local list = M.current()
  if not list or #list.entries == 0 then
    return nil
  end
  local n = M.count(list)
  local by = n as {string: integer}
  local pieces: {contracts.Piece} = {{"qf", "StatusDim"}}
  if list.idx > 0 then
    pieces[#pieces + 1] = {string.format(" %d/%d", list.idx, n.total), "StatusLine"}
  end
  local some = false
  for i, word in ipairs(LEVELS) do
    if by[word] > 0 then
      some = true
      pieces[#pieces + 1] = {
        " " .. ("EWIH"):sub(i, i) .. by[word], i == 1 and "StatusError" or i == 2 and "StatusWarn" or "StatusDim"
      }
    end
  end
  if not some and list.idx == 0 then
    pieces[#pieces + 1] = {" " .. n.total, "StatusLine"}
  end
  return pieces
end

-- Doing things over the entries ------------------------------------------------------------

--- Run a command line on each entry of the current list of a stack (`:cdo`),
--- all as one undo step. For each entry, the cursor goes to the entry
--- first. The command gets the address as `ctx.target`, and the whole
--- location as `ctx.location`. With `per_track`, it runs one time for each
--- track of the entries (`:cfdo`). Returns how many times it ran.
function M.cdo(line: string, opts?: CdoOptions): integer
  opts = opts or {}
  line = tostring(line or ""):match("^%s*:?(.-)%s*$")
  if line == "" then
    paw.notify("usage: cdo <command>, run on every entry", "warn")
    return nil
  end
  local list = M.current(opts.stack)
  if not list or #list.entries == 0 then
    paw.notify("no entries", "warn")
    return nil
  end
  local targets: {integer} = {}
  local seen: {string: boolean} = {}
  for i, e in ipairs(list.entries) do
    if opts.per_track then
      local track = e.address and A.track_of(e.address)
      local key = e.address and (track and tostring(track) or e.address) or ""
      if not seen[key] then
        seen[key] = true
        targets[#targets + 1] = i
      end
    else
      targets[#targets + 1] = i
    end
  end
  local done = 0
  local failed: string
  for _, i in ipairs(targets) do
    local e = list.entries[i]
    list.idx = i
    M.go(e)
    local ctx: EntryContext = {target = e.address, location = e.location, entry = e}
    local ok, err = pcall(commands.exec, line, ctx)
    if ok then
      done = done + 1
    else
      failed = failed or tostring(err)
    end
  end
  api.ui_redraw()
  if failed then
    paw.notify(string.format("ran on %d of %d: %s", done, #targets, failed), "error")
  end
  return done
end

--- Do the fixes of entries as one undo step: each entry with a fix in the
--- current list of a stack, or the given entries. Returns how many.
function M.fix(entries?: {Entry}, opts?: FixOptions): integer
  opts = opts or {}
  if not entries then
    local list = M.current(opts.stack)
    entries = list and list.entries or {}
  end
  local edits: {A.Change} = {}
  local rest: {Entry} = {}
  -- The change of a workspace edit that is the last of an entry's fix.
  local last_of: {A.Change: Entry} = {}
  for _, e in ipairs(entries) do
    local fix = e.fix
    if fix is FixSpec and fix.edit then
      for _, change in ipairs(fix.edit) do
        edits[#edits + 1] = change
      end
      if #fix.edit > 0 then
        last_of[edits[#edits]] = e
      end
    elseif fix then
      rest[#rest + 1] = e
    end
  end
  local n = 0
  api.undo_label(opts.label or "Fix")
  if #edits > 0 then
    local ok = A.edit(edits)
    if ok then
      for _, change in ipairs(edits) do
        if last_of[change] then
          n = n + 1
        end
      end
    else
      -- One that cannot be made does not hold the others back.
      for _, e in ipairs(entries) do
        local fix = e.fix
        if fix is FixSpec and fix.edit then
          local made, why = A.edit(fix.edit)
          if made then
            n = n + 1
          else
            paw.notify("a fix cannot be made: " .. tostring(why), "warn")
          end
        end
      end
    end
  end
  for _, e in ipairs(rest) do
    local ok, err = pcall(
      function(): string
        local fix = e.fix
        if fix is string then
          M.go(e)
          local ctx: EntryContext = {target = e.address, location = e.location, entry = e}
          commands.exec(fix, ctx)
        else
          fix.apply(e)
        end
      end
    )
    if ok then
      n = n + 1
    else
      paw.notify("a fix failed: " .. tostring(err), "warn")
    end
  end
  for _, e in ipairs(entries) do
    if e.fix then
      e.fixed = true
    end
  end
  api.ui_redraw()
  return n
end

--- The title of an entry's fix, or nil.
function M.fix_title(e: Entry): string
  local fix = e.fix
  if fix is string then
    return ":" .. fix
  end
  return fix and (fix.title or "Fix") or nil
end

-- Diagnostics -------------------------------------------------------------------------------

--- Diagnostics as entries (as `paw.diagnostic.get` takes `target` and `filter`).
function M.from_diagnostics(target?: DiagnosticModule.Target, filter?: DiagnosticModule.Filter): {Item}
  local out: {Item} = {}
  for _, d in ipairs(paw.diagnostic.get(target, filter)) do
    out[#out + 1] = {
      location = d.location,
      level = d.severity,
      source = d.source,
      -- A fix of a diagnostic that is a function gets the entry, not the diagnostic.
      text = (d.rule and (d.rule .. ": ") or "") .. d.message,
      fix = d.fixes[1] as FixSpec,
      data = {diagnostic = d},
    }
  end
  return out
end

--- Put diagnostics in a list, as `vim.diagnostic.setqflist`: `opts` has
--- `target` and `severity` (as `paw.diagnostic.get` takes them), `title`
--- ("Diagnostics"), `win` for a location list, `open` to open its window.
function M.diagnostics(opts?: DiagnosticModule.ListOptions): List
  opts = opts or {}
  local filter: DiagnosticModule.Filter = opts.severity and {severity = {min = opts.severity}} or nil
  local list = M.set(M.from_diagnostics(opts.target, filter), {title = opts.title or "Diagnostics", win = opts.win})
  local win = opts.win
  if opts.open then
    M.open({loc = win ~= nil, win = win is integer and win or nil})
  end
  return list
end

M.source(
  "diagnostic",
  function(): {Item}
    local least = opt.qf_diagnostics as string | boolean
    if least == false or least == "off" then
      return {}
    end
    return M.from_diagnostics(nil, {severity = {min = severity_of(least) or 2}})
  end
)
events.on(paw.diagnostic.changed, function() M.changed("diagnostic") end)
events.on(
  options.changed,
  function(e: options.Changed)
    if e.name == "qf_diagnostics" then
      M.changed("diagnostic")
    end
  end
)
-- A diagnostic goes with what it is about.
events.on(
  kernel.changed,
  function()
    if feeds.diagnostic then
      M.changed("diagnostic")
    end
  end
)

-- Renders --------------------------------------------------------------------------------

local render_opts: {string: RenderOptions} = {} -- by path: the options asked for
local renders: {string: {Item}} = {} -- by path: the entries
local function db(x: number): number
  return 20 * math.log10(math.max(x, 1e-9))
end
local function file_name(path: string): string
  return tostring(path):match("([^/]+)$") or tostring(path)
end

--- What a render is made again with.
local record Again
  loudness: number
  normalize: number
end

local function render_again(path: string, set: Again): FixSpec
  local change = {uri = A.render(path), set = set}
  return {
    title = "Render "
      .. file_name(path)
      .. " again"
      .. (
        set.loudness and string.format(" at %g LUFS", set.loudness)
        or set.normalize and string.format(" peaking at %g dB", set.normalize)
        or ""
      ),
    edit = {change as A.Change},
  }
end

local function render_problems(info: types.RenderResult): {Item}
  local path = info.path
  local out: {Item} = {}
  local uri = A.render(path)
  local peak = info.peak or 0
  if peak > 1 then
    local float = info.bits == 32
    out[#out + 1] = {
      address = uri,
      level = float and "warning" or "error",
      text = string.format(
        "%s goes over full scale (peak %+.1f dB)%s",
        file_name(path),
        db(peak),
        float and ": a 32-bit float file holds it, but it clips once converted" or ": it clips"
      ),
      fix = render_again(path, {normalize = -1}),
    }
  end
  if info.loudness and info.loudness > opt.render_loudest then
    out[#out + 1] = {
      address = uri,
      level = "warning",
      text = string.format(
        "%s is too loud: %.1f LUFS integrated, over %g", file_name(path), info.loudness, opt.render_loudest
      ),
      fix = render_again(path, {loudness = -14, normalize = -1}),
    }
  end
  for _, why in ipairs(info.left_out or {}) do
    out[#out + 1] = {address = uri, level = "warning", text = file_name(path) .. ": " .. why}
  end
  return out
end

local function render_feed()
  local all: {Item} = {}
  local paths: {string} = {}
  for path in pairs(renders) do
    paths[#paths + 1] = path
  end
  table.sort(paths)
  for _, path in ipairs(paths) do
    for _, e in ipairs(renders[path]) do
      all[#all + 1] = e
    end
  end
  M.feed("render", all)
end

events.on(
  render.before,
  function(e: render.Before)
    if e.path then
      render_opts[e.path] = e.opts as RenderOptions
    end
  end
)
local function rendered(info: types.RenderResult)
  if type(info) ~= "table" or not info.path then
    return
  end
  renders[info.path] = render_problems(info)
  render_feed()
end
events.on(kernel.render_done, rendered)
events.on(render.finished, rendered)
events.on(
  kernel.render_failed,
  function(e: kernel.RenderEnd)
    if not e.path then
      return
    end
    local path, opts = e.path, render_opts[e.path] or {}
    renders[path] = {
      {
        address = A.render(path),
        level = "error",
        text = "render of " .. file_name(path) .. " failed: " .. tostring(e.error),
        fix = {
          title = "Render " .. file_name(path) .. " again",
          apply = function()
            local again: RenderOptions = {}
            for k, v in pairs(opts) do
              again[k] = v
            end
            (again as {string: boolean}).background = true
            paw.render(path, again)
          end,
        },
      },
    }
    render_feed()
  end
)

-- Missing sound files ----------------------------------------------------------------------

local function project_dir(): string
  local path = (api.project_get as function(string): string)("path")
  return path and tostring(path):match("^(.*)/[^/]+$")
end

M.source(
  "media",
  function(): {Item}
    local missing = api.media_missing()
    if #missing == 0 then
      return {}
    end
    local wanted: {string: boolean} = {}
    for _, path in ipairs(missing) do
      wanted[tostring(path)] = true
    end
    local dir = project_dir()
    local fix: FixSpec = dir
      and {
        title = "Look for the missing files under the project's folder", apply = function() api.media_search(dir) end
      }
    local out: {Item} = {}
    local found: {string: boolean} = {}
    for _, id in ipairs(api.track_list()) do
      for _, c in ipairs(api.clip_list(id)) do
        if c.file and wanted[tostring(c.file)] then
          found[tostring(c.file)] = true
          out[#out + 1] = {
            address = A.clip(c.id),
            level = "error",
            fix = fix,
            text = string.format("%s plays %s, which is not there", c.name, file_name(c.file)),
          }
        end
      end
    end
    for _, path in ipairs(missing) do
      if not found[tostring(path)] then
        out[#out + 1] = {address = A.project(), level = "error", fix = fix, text = tostring(path) .. " is not there"}
      end
    end
    return out
  end
)
events.on(kernel.project_loaded, function() M.changed("media") end)
events.on(kernel.clip_added, function() M.changed("media") end)
events.on(
  kernel.changed,
  function()
    if feeds.media then
      M.changed("media")
    end
  end
)

-- Plugins ------------------------------------------------------------------------------------

local invalid: {integer: boolean} = {} -- devices that put out NaN or infinity, by id
-- What each device is, kept until an event says it changed: a track deleted
-- or put back asks about the devices of the others again.
local known: {integer: types.Device} = {}

M.source(
  "plugins",
  function(): {Item}
    local out: {Item} = {}
    local tracks = api.track_list()
    tracks[#tracks + 1] = 0
    for _, track in ipairs(tracks) do
      local ok, t = pcall(api.track_get, track)
      for _, id in ipairs(ok and t.devices or {}) do
        local okd, d = true, known[id]
        if not d then
          okd, d = pcall(api.device_get, id)
          known[id] = okd and d or nil
        end
        if okd then
          local uri = "paw://track/" .. track .. "/device/" .. id
          local restart: FixSpec = {
            title = "Start " .. d.name .. " again", apply = function() api.device_restart(id) end
          }
          if d.missing or d.status == "missing" then
            out[#out + 1] = {
              address = uri, level = "error", text = d.name .. " on " .. t.name .. " is not installed or did not load"
            }
          elseif d.stopped or d.status == "stopped" then
            out[#out + 1] = {
              address = uri,
              level = "error",
              fix = restart,
              text = string.format(
                "%s on %s stopped: %s", d.name, t.name, tostring(d.stopped or "it stopped answering")
              ),
            }
          elseif invalid[id] then
            out[#out + 1] = {
              address = uri,
              level = "warning",
              fix = restart,
              text = string.format(
                "%s on %s put out invalid numbers (NaN or infinity) and is silenced", d.name, t.name
              ),
            }
          end
        end
      end
    end
    return out
  end
)
events.on(
  kernel.device_invalid,
  function(e: kernel.DeviceTrouble) invalid[e.device] = true; known = {}; M.changed("plugins") end
)
events.on(kernel.device_stopped, function() known = {}; M.changed("plugins") end)
events.on(kernel.device_added, function() M.changed("plugins") end)
events.on(kernel.device_removed, function(e: kernel.Item) known[e.id] = nil; M.changed("plugins") end)
events.on(kernel.project_loaded, function() known = {}; M.changed("plugins") end)
events.on(
  kernel.device_ready, function(e: kernel.DeviceReady) invalid[e.id] = nil; known = {}; M.changed("plugins") end
)
events.on(
  kernel.device_changed,
  function()
    known = {}
    if feeds.plugins then
      M.changed("plugins")
    end
  end
)

-- Plugin files that could not be looked into: what a scan notes, at start
-- and after `:plugins.rescan` (the `plugins.scanned` event, `{ notes, name }`).
local scans: {Item} = {}
local plugins_scanned: events.Event<Scanned> = events.event("plugins.scanned")
events.on(
  plugins_scanned,
  function(e: Scanned)
    local name = e.name and tostring(e.name):lower()
    local kept: {Item} = {}
    for _, entry in ipairs(name and scans or {}) do
      if not entry.text:lower():find(name, 1, true) then
        kept[#kept + 1] = entry
      end
    end
    for _, note in ipairs(e.notes or {}) do
      local path = note:match("^(/[^:]+): ")
      local stem = path and file_name(path):gsub("%.[^.]+$", "")
      kept[#kept + 1] = {level = "warning", text = note, fix = stem and ("plugins.rescan " .. stem) or "plugins.rescan"}
    end
    scans = kept
    M.feed("plugin scan", scans)
  end
)

-- Another project: what was said of the last one's renders goes.
events.on(kernel.project_loaded, function() renders, render_opts, invalid = {}, {}, {}; render_feed() end)

-- The window ------------------------------------------------------------------------------

--- Open the window of the list and give it the keyboard. The quickfix list
--- opens along the bottom of the tab, the whole width (`opts.height` rows,
--- or `paw.opt.qf_height`). A location list opens below its window
--- (`opts.loc`, with `opts.win` the window, the current one by default). If
--- a window of the tab shows the list already, paw goes to it. Returns the window.
function M.open(opts?: OpenOptions): Win
  opts = opts or {}
  local L = layout()
  local target: integer | string = "quickfix"
  local from: Win = nil
  if opts.loc then
    local stack, win = M.loc_stack(opts.win, true)
    if not stack then
      return nil
    end
    target, from = win, L.get(win)
  end
  local buf = L.buf_create("qflist", target)
  for _, w in ipairs(L.windows()) do
    if w.view == "qflist" and w.buf == buf.id then
      L.enter(w)
      return w
    end
  end
  local height = tonumber(opts.height) or opt.qf_height
  local win: Win
  if from and from.view ~= "qflist" then
    local made = L.split({win = from, view = "qflist", buf = buf.id})
    if not made then
      return nil
    end
    win = made
    win.size, win.weight = height, nil
  else
    win = L.leaf("qflist", {buf = buf.id, size = height})
    local root = paw.ui.layout as {Win}
    root[#root + 1] = win
    L.tidy(root)
  end
  L.enter(win)
  api.ui_redraw()
  return win
end

--- Close the windows of the tab that show the quickfix list (`loc`: the
--- location list of the current window). Returns true if one closed.
function M.close(loc?: boolean): boolean
  local L = layout()
  local target: integer | string = "quickfix"
  if loc then
    local _, win = M.loc_stack(nil)
    target = win
  end
  local closed = false
  for _, w in ipairs(L.windows()) do
    local buf = w.view == "qflist" and L.buf_of(w)
    if buf and (buf.target or "quickfix") == target then
      closed = L.close(w) or closed
    end
  end
  return closed
end

-- Commands and keys -------------------------------------------------------------------------

local type Context = commands.Context
local type Result = commands.Result
local map = paw.keymap.set

-- The stack a command works on: the quickfix lists, or the current
-- window's location lists.
local function stack_for(loc: boolean, make?: boolean): Stack
  if not loc then
    return quickfix
  end
  local stack = M.loc_stack(nil, make)
  if not stack then
    paw.notify("no location list for this window: `:ldiag` makes one", "warn")
  end
  return stack
end

-- A command for the quickfix lists (`c<name>`) and one for the window's
-- location lists (`l<name>`); `%s` in the description names which. With
-- `make`, the location list is made when the window has none.
local function both(
  name: string, fn: function(Stack, Context, boolean), desc: string, opts?: commands.Options, make?: boolean
)
  for _, loc in ipairs({false, true}) do
    local given = opts or {}
    local spec: commands.Options = {
      raw = given.raw,
      complete = given.complete,
      label = given.label,
      range = given.range,
      ext = given.ext,
      desc = (desc:gsub("%%s", loc and "the window's location list" or "the quickfix list")),
    }
    commands.define(
      (loc and "l" or "c") .. name,
      function(ctx: Context): Result
        local stack = stack_for(loc, make)
        if stack then
          fn(stack, ctx, loc)
        end
      end,
      spec
    )
  end
end

local function arg_number(ctx: Context): number
  return tonumber(ctx.args[1])
end
local function count(ctx: Context): integer
  return (arg_number(ctx) or ctx.count or 1) as integer
end

both("next", function(s: Stack, ctx: Context) M.step(count(ctx), s) end, "Go to the next entry of %s (`]q`)")
both("previous", function(s: Stack, ctx: Context) M.step(-count(ctx), s) end, "Go to the entry before in %s (`[q`)")
both(
  "first",
  function(s: Stack, ctx: Context) M.jump(arg_number(ctx) or ctx.count or 1, s) end,
  "Go to the first entry of %s (`[Q`)"
)
both("last", function(s: Stack) M.last(s) end, "Go to the last entry of %s (`]Q`)")
commands.alias("cn", "cnext")
commands.alias("cprev", "cprevious")
commands.alias("cp", "cprevious")
commands.alias("cN", "cprevious")
commands.alias("lprev", "lprevious")
for _, loc in ipairs({false, true}) do
  commands.define(
    loc and "ll" or "cc",
    function(ctx: Context): Result
      local stack = stack_for(loc)
      if not stack then
        return
      end
      local list = M.current(stack)
      M.jump(arg_number(ctx) or ctx.count or (list and list.idx > 0 and list.idx) or 1, stack)
    end,
    {
      desc = "Go to entry n of "
        .. (loc and "the window's location list: `ll 3`" or "the quickfix list: `cc 3`; the current one without"),
    }
  )
end

both(
  "open",
  function(_: Stack, ctx: Context, loc: boolean) M.open({loc = loc, height = arg_number(ctx) or ctx.count}) end,
  "Open a window showing %s and go to it: `copen 15` rows high",
  nil,
  true
)
both("close", function(_: Stack, _: Context, loc: boolean) M.close(loc) end, "Close the window showing %s")
both(
  "window",
  function(s: Stack, ctx: Context, loc: boolean)
    local list = M.current(s)
    if list and #list.entries > 0 then
      M.open({loc = loc, height = arg_number(ctx) or ctx.count})
      return
    end
    M.close(loc)
  end,
  "Open the window of %s when it has entries, close it when it has none"
)
both("older", function(s: Stack, ctx: Context) M.older(count(ctx), s) end, "Go to the list before in the history of %s")
both("newer", function(s: Stack, ctx: Context) M.newer(count(ctx), s) end, "Go to the next list in the history of %s")
both(
  "history",
  function(s: Stack)
    refresh()
    if #s.lists == 0 then
      paw.notify("no lists", "warn")
      return
    end
    local lines: {string | contracts.PageLine} = {}
    for i, list in ipairs(s.lists) do
      local n = M.count(list)
      lines[#lines + 1] = string.format(
        "%s list %d of %d: %-20s %d entr%s%s",
        i == s.at and ">" or " ",
        i,
        #s.lists,
        list.title,
        n.total,
        n.total == 1 and "y" or "ies",
        (n.error + n.warning > 0) and string.format(" (E%d W%d)", n.error, n.warning) or ""
      )
    end
    lines[#lines + 1] = {text = "> the current one; `:colder` and `:cnewer` go between them", style = "Dim"}
    paw.ui.page("Lists", lines)
  end,
  "List the lists in the history of %s"
)
both(
  "do",
  function(s: Stack, ctx: Context) M.cdo(ctx.args[1] as string, {stack = s}) end,
  "Run a command on every entry of %s, the cursor on each, as one undo step: `cdo track.mute`",
  {raw = true, label = "Run a command on every entry"}
)
both(
  "fdo",
  function(s: Stack, ctx: Context) M.cdo(ctx.args[1] as string, {stack = s, per_track = true}) end,
  "Run a command once for every track the entries of %s are on, as one undo step: `cfdo track.solo`",
  {raw = true, label = "Run a command on every track of the entries"}
)
both(
  "fix",
  function(s: Stack, ctx: Context)
    local list = M.current(s)
    if not list or #list.entries == 0 then
      paw.notify("no entries", "warn")
      return
    end
    local entries: {Entry} = nil
    if ctx.args[1] == "." then
      entries = {list.entries[math.max(1, list.idx)]}
    end
    local n = M.fix(entries, {stack = s})
    paw.notify(n == 0 and "no entry has a fix" or string.format("%d fix%s made", n, n == 1 and "" or "es"))
  end,
  "Make the fixes the entries of %s have, as one undo step; `cfix .` the current entry's",
  {label = "Fix the entries"}
)

-- What the window shows: the piano roll its clip, the mixer and the device
-- panel the cursor's track, the arrange view everything.
local function shown_target(): DiagnosticModule.Target
  local view = paw.ui.focused
  if view == "pianoroll" then
    return (paw.ui.views:get("pianoroll") as Roll.PianoRoll).clip_id
  end
  if view == "mixer" or view == "devices" then
    local id = paw.cursor.track_id()
    return id and A.track(id) or nil
  end
  return nil
end
both(
  "diag",
  function(_: Stack, ctx: Context, loc: boolean)
    local word = ctx.args[1]
    local severity = word and severity_of(word as string | number) or nil
    local list = M.diagnostics({target = loc and shown_target() or nil, severity = severity, win = loc or nil})
    paw.notify(string.format("%d diagnostic%s in the list", #list.entries, #list.entries == 1 and "" or "s"))
  end,
  "Put the diagnostics in %s (the location list: those of what the window shows); `cdiag warning` only warnings and worse",
  {complete = function(): {string} return LEVELS end},
  true
)

map("]q", function(ctx: KeyContext) M.step(ctx.count or 1) end, {desc = "Next entry of the quickfix list", jump = true})
map(
  "[q",
  function(ctx: KeyContext) M.step(-(ctx.count or 1)) end,
  {desc = "Entry before in the quickfix list", jump = true}
)
map("]Q", function() M.last() end, {desc = "Last entry of the quickfix list", jump = true})
map("[Q", function() M.first() end, {desc = "First entry of the quickfix list", jump = true})
map("]l", "lnext", {desc = "Next entry of the window's location list", jump = true})
map("[l", "lprevious", {desc = "Entry before in the window's location list", jump = true})

return M
