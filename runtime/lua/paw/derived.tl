-- One graph for the data that paw derives from the project (the design
-- `derived.md`, part 4): the chord reading first, more consumers later.
--
-- A node kind (`M.node(spec)`) makes values from the project. Each value
-- (an entry) records what it read while it was made: the sources (a
-- track's fields, a track's clips, the tempo, an option), and the other
-- entries. An edit marks its sources dirty (the kernel's events say which),
-- and the entries that read them, and those that read these, become stale:
-- at the next read, or in the next slice of the job, not in the event
-- handler.
-- A job in slices (`derived`, paw.slices) makes again what is stale, the
-- entries that someone waits for first, and nothing more:
--
--  - an entry whose sources and entries did not change is fresh again;
--  - an entry with `inputs` compares them first: the same inputs, the same
--    value (an early cutoff on the key);
--  - a value made again that is the `same` as before tells no one (an
--    early cutoff on the value);
--  - an `eager` entry (a track, the track list) is made again before the
--    entries that read it learn of the change: they are marked stale only
--    when its value changed, and with `touched` only over that time.
--
-- A slice stops before each entry that it makes, at any depth: an entry
-- that reads thousands of others does not hold a key for all of them.
--
-- A consumer reads a value as it stands (`node:get(key)`: the value, and
-- whether it is fresh), or waits for it (`node:get(key, true)`, for a
-- command and for tests). After each slice, `derived.changed` names the
-- kinds whose values changed.
--
-- The views tell what they show as they draw (`visible`): the entries
-- there come before the rest, and after each frame the kernel gets the
-- same ranges for its bakes (`api.view_ranges_set`).
--
-- The module is internal for now: extensions get it when it is public.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local slices = require("paw.slices")
local type contracts = require("paw.contracts")
local type types = require("paw.types")

--- How a kind of node is made. They are made the same way: the kind tells
--- `:checkhealth derived` what to expect.
---  - memo: one call, short (about 1 ms at most), when it is read stale.
---  - sliced: one call that can stop between slices (`ctx:pause()`).
---  - family: one entry for each key of many (each track and window).
---  - join: an entry that adds up a family's entries.
local enum Kind
  "memo"
  "sliced"
  "family"
  "join"
end

-- An entry's state: fresh; maybe stale (an entry it read is stale);
-- stale (a source it read changed, or an entry it read has a new value);
-- never made.
local FRESH, MAYBE, DIRTY, NEW = 0, 1, 2, 3

-- The order in which the job makes what waits, as the bake scheduler has
-- it: what plays next, what shows, the rest. The `eager` entries come
-- before all: until they are made, the entries that read them do not know
-- that they are stale.
local EAGER, PLAYING, VISIBLE, BACKGROUND = 0, 1, 2, 3

--- A value of an entry, its key or its inputs, as the graph keeps them: the
--- graph never reads it. `Node<K, V, I>` gives it back with its type.
local record Value
end

--- A node's counts, as `:checkhealth derived` and the tests read them.
local record Stats
  name: string
  kind: Kind
  values: integer
  bytes: integer
  limit: integer
  made: integer
  hits: integer
  dropped: integer
end

--- What `derived.changed` says: the kinds whose values changed.
local record Changed
  names: {string}
end

--- The job while it runs: what it makes, how far it is (0 to 1), and the
--- milliseconds since it started.
local record Progress
  label: string
  fraction: number
  ms: number
end

local record M
  type Kind = Kind
  type Stats = Stats
  type Changed = Changed
  type Progress = Progress
  --- After a slice of the job: the kinds of node whose values changed.
  changed: events.Event<Changed>
  progress: function(after?: number): Progress

  --- What an entry reads while it is made: through this, the graph
  --- records what it depends on.
  record Ctx
    --- The value of another node's entry, made first if it is stale.
    get: function<K, V, I>(self: Ctx, node: Node<K, V, I>, key: K): V
    --- Record a source by its name: `track:<id>:<field>`,
    --- `track:<id>:clips`, `tracks`, `tempo`, `option:<name>`,
    --- `clip:<id>`, `device:<id>`.
    source: function(self: Ctx, name: string)
    --- A track, and the fields of it that the entry reads.
    track: function(self: Ctx, id: integer, fields: {string}): types.Track
    --- The clips of a track (any change of one, or of their list).
    clips: function(self: Ctx, track: integer): {types.Clip}
    --- The tracks, in order.
    tracks: function(self: Ctx): {integer}
    --- The tempo map's stamp (`project_get("tempo_stamp")`).
    tempo: function(self: Ctx): integer
    --- An option that the entry reads (it reads the value from `paw.opt`).
    option: function(self: Ctx, name: string)
    --- Stop here if the slice's time is up: the work goes on at the next slice.
    pause: function(self: Ctx)
  end

  --- How a kind of node is made. `K` is the key of an entry, `V` its value
  --- and `I` its inputs.
  record Spec<K, V, I>
    name: string
    kind: Kind
    --- What the status line says while the job makes it (`chords`).
    label: string
    --- Make the value of `key`; `old` is the value before, or nil, and
    --- `inputs` what `inputs` gave.
    make: function(ctx: Ctx, key: K, old: V, inputs: I): V
    --- What the value is made of, quicker to make than the value: the
    --- same inputs give the same value, and the entry is fresh again.
    inputs: function(ctx: Ctx, key: K, old: V): I
    same_inputs: function(a: I, b: I): boolean
    --- Whether two values are the same: then the entries that read it
    --- stay fresh.
    same: function(a: V, b: V): boolean
    --- Keep the value before the last change, with its inputs: inputs that
    --- come back (an undo, an unmute) give it back without a make. Only
    --- for a node whose `make` reads nothing that `inputs` does not.
    undo: boolean
    --- The key as a number or a text, when it is not one already.
    id: function(key: K): string
    --- Where in the song the value is, in beats: for its priority, and
    --- for `touched`.
    span: function(key: K): number, number
    --- Where in the song a new value differs from the old one, in beats:
    --- of the entries that read it, those with a `span` elsewhere stay
    --- as they are. Nil: everywhere.
    touched: function(old: V, new: V): number, number
    --- Make a stale entry again first, before the entries that read it
    --- know: they are marked stale only when its value changed (and with
    --- `touched`, only those over the time that changed). For a node that
    --- is quick to make and that many entries read: a change of a track
    --- does not mark every window of the song.
    eager: boolean
    --- About how many bytes a value takes.
    bytes: function(v: V): integer
    --- The bytes of all values (with `bytes`), or how many values: past
    --- it, the values no other value reads go, the oldest first.
    limit: integer
  end

  --- A kind of node, as a consumer has it.
  record Node<K, V, I>
    spec: Spec<K, V, I>
    --- The value of `key` as it stands, and whether it is fresh. A stale
    --- value comes first in the job. With `latest`, it is made now.
    get: function(self: Node<K, V, I>, key: K, latest?: boolean): V, boolean
    --- Keep the value of `key` fresh: the job makes it after each change.
    want: function(self: Node<K, V, I>, key: K)
    --- Stop keeping the value of `key` fresh: it goes when the node is past
    --- its limit and no other value reads it.
    unwant: function(self: Node<K, V, I>, key: K)
    --- Whether the value of `key` is fresh.
    fresh: function(self: Node<K, V, I>, key: K): boolean
    --- Forget every value of the node: they are made again from nothing.
    reset: function(self: Node<K, V, I>)
    --- Goes up each time a value of the node changes.
    revision: function(self: Node<K, V, I>): integer
    stats: function(self: Node<K, V, I>): Stats
  end
end

local type Ctx = M.Ctx
local type AnySpec = M.Spec<Value, Value, Value>

--- One kind of node, as the graph keeps it.
local record Core
  spec: AnySpec
  entries: {Value: Entry}
  orphans: {Entry} -- entries that no entry reads, the oldest first
  count: integer
  bytes: integer
  revision: integer
  made: integer
  hits: integer
  dropped: integer
end

--- One value of a node, with what it was made from.
local record Entry
  core: Core
  key: Value
  value: Value
  state: integer
  inputs: Value
  deps: {Entry} -- the entries it read
  user: Entry -- an entry that reads it
  users: {Entry: boolean} -- the others
  -- Only some entries have these:
  sources: {string} -- the sources it read
  prev_inputs: Value -- the value before (`spec.undo`)
  prev_value: Value
  wanted: boolean -- kept fresh (`node:want`)
  raised: boolean -- read while stale: it is wanted soon
end

local cores: {Core} = {}
local by_source: {string: {Entry: boolean}} = {} -- who read each source
local queue: {Entry: boolean} = {} -- what the job makes, stale and wanted
-- Stale entries of an `eager` node: the job makes them first, and only then
-- do the entries that read them learn of the change (`went_stale`). An
-- entry is in it from when it goes stale until it is fresh or goes.
local eager: {Entry: boolean} = {}
local pending: {string: boolean} = {} -- sources marked and not yet applied (`apply_pending`)
local changed_names: {string: boolean} = {} -- kinds whose values changed
local current: Entry -- the entry being made, which records what it reads
local pass: thread -- the pass under way
local until_ms: number -- when the slice under way ends (nil: never)
local edits_seen: integer
local tempo_seen: integer
local started: number -- when the job started
local done, todo = 0, 0 -- entries made fresh, and made stale, since then
local label: string -- what the job makes now
local ranges: {string: types.ViewRange} = {} -- what each window shows, in beats
local told_ranges = "" -- the ranges the kernel has, as `range_text` writes them

-- Entries that read an entry -------------------------------------------------------------

local function each_user(e: Entry, fn: function(Entry))
  if e.user then
    fn(e.user)
  end
  if e.users then
    for u in pairs(e.users) do
      fn(u)
    end
  end
end

local function held(e: Entry): boolean
  return e.user ~= nil or (e.users ~= nil and next(e.users) ~= nil)
end

--- `u` reads `d`.
local function link(d: Entry, u: Entry)
  if d.user ~= u and not (d.users and d.users[u]) then
    if not d.user then
      d.user = u
    else
      d.users = d.users or {}
      d.users[u] = true
    end
  end
  local deps = u.deps
  if deps[#deps] ~= d then
    deps[#deps + 1] = d
  end
end

local function unlink(d: Entry, u: Entry)
  if d.user == u then
    d.user = nil
  elseif d.users then
    d.users[u] = nil
  end
  if not held(d) and not d.wanted then
    local orphans = d.core.orphans
    orphans[#orphans + 1] = d
  end
end

--- Forget what `e` read: it goes.
local function forget(e: Entry)
  for i_d = 1, #e.deps do
    local d = e.deps[i_d]
    unlink(d, e)
  end
  e.deps = {}
  if e.sources then
    for i_name = 1, #e.sources do
      local name = e.sources[i_name]
      local set = by_source[name]
      if set then
        set[e] = nil
      end
    end
    e.sources = nil
  end
end

--- `e` was made again, and read `e.deps` and `e.sources`: forget what it
--- read before (`deps`, `sources`) and does not read now.
local function settle(e: Entry, deps: {Entry}, sources: {string})
  local now = e.deps
  local same = #deps == #now
  if same then
    for i = 1, #now do
      if deps[i] ~= now[i] then
        same = false
        break
      end
    end
  end
  if not same then
    local kept: {Entry: boolean} = {}
    for i_d = 1, #now do
      local d = now[i_d]
      kept[d] = true
    end
    for i_d = 1, #deps do
      local d = deps[i_d]
      if not kept[d] then
        unlink(d, e)
      end
    end
  end
  if sources then
    local read: {string: boolean} = {}
    for _, name in ipairs(e.sources or {}) do
      read[name] = true
    end
    for i_name = 1, #sources do
      local name = sources[i_name]
      if not read[name] then
        local set = by_source[name]
        if set then
          set[e] = nil
        end
      end
    end
  end
end

-- Stale and fresh ------------------------------------------------------------------------

local schedule: function()

--- `e` is no longer fresh: what reads it may be stale too, and the job
--- makes it if it is wanted.
local function went_stale(e: Entry)
  todo = todo + 1
  if e.core.spec.eager then
    -- The entries that read it are not marked: when it is made again,
    -- `remake` marks them if its value changed.
    eager[e] = true
    queue[e] = true
    schedule()
    return
  end
  if e.wanted or e.raised then
    queue[e] = true
    schedule()
  end
  local u = e.user
  if u and u.state == FRESH then
    u.state = MAYBE
    went_stale(u)
  end
  if e.users then
    for v in pairs(e.users) do
      if v.state == FRESH then
        v.state = MAYBE
        went_stale(v)
      end
    end
  end
end

local function set_fresh(e: Entry)
  e.state = FRESH
  e.raised = nil
  eager[e] = nil
  done = done + 1
end

--- Source `name` changed: the entries that read it are stale, and so are
--- the entries that read these, at any depth.
local function stale_source(name: string)
  local set = by_source[name]
  if not set then
    return
  end
  for e in pairs(set) do
    local was = e.state
    if was ~= DIRTY and was ~= NEW then
      e.state = DIRTY
      if was == FRESH then
        went_stale(e)
      end
    end
  end
end

--- Source `name` changed. The entries that read it become stale later: at
--- the next read of a value, or in the next slice of the job. An event
--- handler only notes the name, because one source can have thousands of
--- entries that read it (the track list: every window of the chord
--- reading). While a pass is under way, the names wait for its end.
local function mark(name: string)
  if by_source[name] then
    pending[name] = true
    schedule()
  end
end

--- Make stale what the sources marked since the last time read.
local function apply_pending()
  if next(pending) == nil then
    return
  end
  local names = pending
  pending = {}
  for name in pairs(names) do
    stale_source(name)
  end
end

--- Before a value is read as it stands: the sources marked since are
--- applied, unless a pass is under way (they wait for its end, as in
--- `M.run`).
local function before_read()
  if not pass then
    apply_pending()
  end
end

-- Making values --------------------------------------------------------------------------

local ctx: Ctx = {}

local function entry_of(core: Core, key: Value): Entry
  local spec = core.spec
  local id = spec.id and (spec.id(key) as Value) or key
  local e = core.entries[id]
  if not e then
    e = {core = core, key = key, state = NEW, deps = {}}
    core.entries[id] = e
    core.count = core.count + 1
    todo = todo + 1
    core.orphans[#core.orphans + 1] = e
  end
  return e
end

local ensure: function(e: Entry)

--- An entry that `u` read has a new value: `u` is made again.
local function push(u: Entry)
  local was = u.state
  if was == NEW then
    return
  end
  u.state = DIRTY
  if was == FRESH then
    went_stale(u)
  end
end

--- Push the entries that read `e` and whose `span` meets `from` to `to`,
--- and those that have none.
local function push_over(e: Entry, from: number, to: number)
  local function near(u: Entry)
    local span = u.core.spec.span
    if not span then
      push(u)
    else
      local a, b = span(u.key)
      if a <= to and b >= from then
        push(u)
      end
    end
  end
  if e.user then
    near(e.user)
  end
  if e.users then
    for u in pairs(e.users) do
      near(u)
    end
  end
end

--- Make `e` again: compare its inputs first, then make it.
local function remake(e: Entry)
  -- A slice whose time is up stops before each make, at any depth: one
  -- entry that reads thousands of others does not make all of them in
  -- one slice.
  ctx:pause()
  local core = e.core
  local spec = core.spec
  local saved = current
  local deps, sources = e.deps, e.sources
  e.deps, e.sources = {}, nil
  current = e
  local inputs: Value
  if spec.inputs then
    inputs = spec.inputs(ctx, e.key, e.value)
    if e.state ~= NEW then
      if spec.same_inputs(inputs, e.inputs) then
        current = saved
        settle(e, deps, sources)
        core.hits = core.hits + 1
        set_fresh(e)
        return
      end
      if e.prev_inputs ~= nil and spec.same_inputs(inputs, e.prev_inputs) then
        -- What it was before the last change: an undo.
        current = saved
        settle(e, deps, sources)
        e.prev_inputs, e.prev_value, e.inputs, e.value = e.inputs, e.value, e.prev_inputs, e.prev_value
        core.hits = core.hits + 1
        core.revision = core.revision + 1
        changed_names[spec.name] = true
        each_user(e, push)
        set_fresh(e)
        return
      end
    end
  end
  local value = spec.make(ctx, e.key, e.value, inputs)
  current = saved
  settle(e, deps, sources)
  core.made = core.made + 1
  local first = e.state == NEW
  if first or not (spec.same and spec.same(e.value, value)) then
    if spec.bytes then
      core.bytes = core.bytes + spec.bytes(value) - (e.value ~= nil and spec.bytes(e.value) or 0)
    end
    if spec.undo and not first then
      e.prev_inputs, e.prev_value = e.inputs, e.value
    end
    local from, to: number, number
    if spec.touched and not first then
      from, to = spec.touched(e.value, value)
    end
    e.value = value
    core.revision = core.revision + 1
    changed_names[spec.name] = true
    if from then
      -- Only the entries over the time the change touched read it again.
      push_over(e, from, to)
    else
      each_user(e, push)
    end
  end
  e.inputs = inputs
  set_fresh(e)
end

ensure = function(e: Entry)
  local state = e.state
  if state == FRESH then
    return
  end
  if state == MAYBE then
    -- Fresh again if none of the entries it read has a new value: a new
    -- value marks it stale (`remake`).
    for i_d = 1, #e.deps do
      local d = e.deps[i_d]
      ensure(d)
      if e.state ~= MAYBE then
        break
      end
    end
    if e.state == MAYBE then
      e.core.hits = e.core.hits + 1
      set_fresh(e)
      return
    end
  end
  remake(e)
end

function ctx:get<K, V, I>(node: M.Node<K, V, I>, key: K): V
  local e = entry_of((node as {string: Core}).core, key as Value)
  ensure(e)
  if current then
    link(e, current)
  end
  return e.value as V
end

function ctx:source(name: string)
  local e = current
  if not e then
    return
  end
  local set = by_source[name]
  if not set then
    set = {}
    by_source[name] = set
  end
  set[e] = true
  local list = e.sources
  if not list then
    e.sources = {name}
    return
  end
  for i_other = 1, #list do
    local other = list[i_other]
    if other == name then
      return
    end
  end
  list[#list + 1] = name
end

function ctx:track(id: integer, fields: {string}): types.Track
  for i_f = 1, #fields do
    local f = fields[i_f]
    self:source("track:" .. id .. ":" .. f)
  end
  local ok, t = pcall(api.track_get, id)
  return ok and t or nil
end

function ctx:clips(track: integer): {types.Clip}
  self:source("track:" .. track .. ":clips")
  local ok, list = pcall(api.clip_list, track)
  return ok and list or {}
end

function ctx:tracks(): {integer}
  self:source("tracks")
  return api.track_list()
end

local project_int = api.project_get as function(string): integer

function ctx:tempo(): integer
  self:source("tempo")
  return project_int("tempo_stamp")
end

function ctx:option(name: string)
  self:source("option:" .. name)
end

function ctx:pause()
  if until_ms and pass and coroutine.running() == pass and api.now() >= until_ms then
    local e = current
    current = nil
    coroutine.yield()
    current = e
  end
end

-- The job -------------------------------------------------------------------------------

local function priority(e: Entry): integer
  if eager[e] then
    return EAGER
  end
  local spec = e.core.spec
  local best = e.raised and VISIBLE or BACKGROUND
  if spec.span then
    local from, to = spec.span(e.key)
    local t = api.transport_get()
    local ahead = 10 * t.tempo / 60 -- about 10 s, in beats
    if from < t.position + ahead and to > t.position then
      return PLAYING
    end
    for _, r in pairs(ranges) do
      if from < r.to and to > r.from then
        best = VISIBLE
      end
    end
  end
  return best
end

--- The next entry to make: the stale one wanted most.
local function next_wanted(): Entry
  local best: Entry
  local best_p = math.huge
  for e in pairs(queue) do
    if e.state == FRESH or e.core.entries == nil then
      queue[e] = nil
    else
      local p = priority(e)
      if p < best_p then
        best, best_p = e, p
        if p == EAGER then
          break
        end
      end
    end
  end
  return best
end

local function run_pass()
  while true do
    local e = next_wanted()
    if not e then
      return
    end
    label = e.core.spec.label or e.core.spec.name
    ensure(e)
    queue[e] = nil
  end
end

--- Make the `eager` entries now (outside a pass): then each entry that one
--- of them changed is marked stale.
local function make_eager()
  while true do
    local e = next(eager)
    if not e then
      return
    end
    ensure(e)
    eager[e] = nil
  end
end

--- Make what is stale and wanted, for about `budget` milliseconds (all of
--- it when nil). True when nothing waits.
function M.run(budget?: number): boolean
  local outer = until_ms
  until_ms = budget and api.now() + budget or nil
  while true do
    if not pass then
      apply_pending()
      if next(queue) == nil then
        until_ms = outer
        return true
      end
      pass = coroutine.create(run_pass)
    end
    local ok, err = coroutine.resume(pass)
    if not ok then
      pass, current, until_ms = nil, nil, outer
      error(tostring(err), 0)
    end
    if coroutine.status(pass) ~= "dead" then
      until_ms = outer
      return false
    end
    pass = nil
    if until_ms and api.now() >= until_ms then
      apply_pending()
      until_ms = outer
      return next(queue) == nil
    end
  end
end

--- Whether the job has work: what is stale and wanted, or a pass under way.
function M.busy(): boolean
  return pass ~= nil or next(queue) ~= nil or next(pending) ~= nil
end

local SLICE = 4 -- milliseconds at a time, so that a key comes in between

-- Drop the values no one reads, the oldest first, from the nodes over their limit.
local function drop(e: Entry)
  local core = e.core
  local spec = core.spec
  local id = spec.id and (spec.id(e.key) as Value) or e.key
  if core.entries[id] ~= e then
    return
  end
  forget(e)
  core.entries[id] = nil
  core.count = core.count - 1
  core.dropped = core.dropped + 1
  if spec.bytes then
    if e.value ~= nil then
      core.bytes = core.bytes - spec.bytes(e.value)
    end
  end
  queue[e] = nil
  eager[e] = nil
end

local function over(core: Core): boolean
  local limit = core.spec.limit
  if not limit then
    return false
  end
  return (core.spec.bytes and core.bytes or core.count) > limit
end

local function sweep()
  for i_core = 1, #cores do
    local core = cores[i_core]
    if over(core) then
      local kept: {Entry} = {}
      for i_e = 1, #core.orphans do
        local e = core.orphans[i_e]
        if not held(e) and not e.wanted and e.state == FRESH and over(core) then
          drop(e)
        elseif held(e) == false and not e.wanted then
          kept[#kept + 1] = e
        end
      end
      core.orphans = kept
    elseif #core.orphans > 2 * core.count + 64 then
      -- Entries that are read again are no orphans: the list keeps only the others.
      local kept: {Entry} = {}
      for i_e = 1, #core.orphans do
        local e = core.orphans[i_e]
        if not held(e) and not e.wanted then
          kept[#kept + 1] = e
        end
      end
      core.orphans = kept
    end
  end
end

--- Tell who listens which kinds changed.
local function tell()
  if next(changed_names) == nil then
    return
  end
  local names: {string} = {}
  for name in pairs(changed_names) do
    names[#names + 1] = name
  end
  table.sort(names)
  changed_names = {}
  events.emit(M.changed, {names = names} as Changed)
end

local shown = false -- the status line shows the job

local function slice(ms: number): boolean
  local ok = M.run(ms)
  sweep()
  tell()
  if ok then
    started, label, done, todo = nil, nil, 0, 0
  end
  -- The status line shows a job that runs for more than a second.
  if shown or M.progress() then
    shown = not ok
    api.ui_redraw()
  end
  return ok
end

schedule = function()
  if slices.job("derived") then
    return
  end
  started = started or api.now()
  slices.run("derived", slice, {ms = SLICE, after = 30})
end

-- Nodes ---------------------------------------------------------------------------------

--- A new kind of node.
function M.node<K, V, I>(spec: M.Spec<K, V, I>): M.Node<K, V, I>
  local core: Core = {
    spec = spec as AnySpec,
    entries = {},
    orphans = {},
    count = 0,
    bytes = 0,
    revision = 0,
    made = 0,
    hits = 0,
    dropped = 0,
  }
  cores[#cores + 1] = core
  local node: M.Node<K, V, I> = {spec = spec}
  (node as {string: Core}).core = core
  function node:get(key: K, latest?: boolean): V, boolean
    if latest and pass and coroutine.running() == pass then
      -- Read from inside the pass: as `ctx:get` does.
      local e = entry_of(core, key as Value)
      ensure(e)
      return e.value as V, true
    elseif latest then
      -- Finish the pass under way, then what the edits since asked for.
      if pass then
        M.run()
      end
      local edits = project_int("edits")
      if edits ~= edits_seen then
        -- Edits whose events have not come yet: look at every source again.
        edits_seen = edits
        for name in pairs(by_source) do
          pending[name] = true
        end
      end
      apply_pending()
      local e = entry_of(core, key as Value)
      local outer = until_ms
      until_ms = nil
      make_eager()
      ensure(e)
      until_ms = outer
      if next(changed_names) then
        schedule()
      end
      return e.value as V, true
    end
    before_read()
    local e = entry_of(core, key as Value)
    if e.state ~= FRESH then
      e.raised = true
      queue[e] = true
      schedule()
    end
    return e.value as V, e.state == FRESH and next(eager) == nil
  end
  function node:want(key: K)
    before_read()
    local e = entry_of(core, key as Value)
    e.wanted = true
    if e.state ~= FRESH then
      queue[e] = true
      schedule()
    end
  end
  function node:unwant(key: K)
    local id = spec.id and (spec.id(key) as Value) or key as Value
    local e = core.entries[id]
    if e and e.wanted then
      e.wanted = nil
      if not held(e) then
        core.orphans[#core.orphans + 1] = e
      end
    end
  end
  function node:fresh(key: K): boolean
    local id = spec.id and (spec.id(key) as Value) or key as Value
    before_read()
    local e = core.entries[id]
    return e ~= nil and e.state == FRESH and not pass and next(eager) == nil
  end
  function node:reset()
    if pass then
      pass, current = nil, nil
    end
    local wanted: {Value} = {}
    for _, e in pairs(core.entries) do
      if e.wanted then
        wanted[#wanted + 1] = e.key
      end
      each_user(e, push)
      forget(e)
      queue[e] = nil
      eager[e] = nil
    end
    core.entries, core.orphans, core.count, core.bytes = {}, {}, 0, 0
    core.revision = core.revision + 1
    for i_key = 1, #wanted do
      local key = wanted[i_key]
      node:want(key as K)
    end
  end
  function node:revision(): integer
    return core.revision
  end
  function node:stats(): Stats
    return {
      name = spec.name,
      kind = spec.kind,
      values = core.count,
      bytes = core.bytes,
      limit = spec.limit,
      made = core.made,
      hits = core.hits,
      dropped = core.dropped,
    }
  end
  return node
end

--- The counts of every node, by name.
function M.stats(): {Stats}
  local out: {Stats} = {}
  for i_core = 1, #cores do
    local core = cores[i_core]
    local spec = core.spec
    out[#out + 1] = {
      name = spec.name,
      kind = spec.kind,
      values = core.count,
      bytes = core.bytes,
      limit = spec.limit,
      made = core.made,
      hits = core.hits,
      dropped = core.dropped,
    }
  end
  table.sort(out, function(a: Stats, b: Stats): boolean return a.name < b.name end)
  return out
end

--- Forget every value: the wanted ones are made again from nothing.
function M.reset()
  pass, current = nil, nil
  slices.stop("derived")
  by_source, queue, pending, changed_names, eager = {}, {}, {}, {}, {}
  started, label, done, todo = nil, nil, 0, 0
  for i_core = 1, #cores do
    local core = cores[i_core]
    local wanted: {Value} = {}
    for _, e in pairs(core.entries) do
      if e.wanted then
        wanted[#wanted + 1] = e.key
      end
    end
    core.entries, core.orphans, core.count, core.bytes = {}, {}, 0, 0
    core.revision = core.revision + 1
    for i_key = 1, #wanted do
      local key = wanted[i_key]
      local e = entry_of(core, key)
      e.wanted = true
      queue[e] = true
    end
  end
  edits_seen = project_int("edits")
  tempo_seen = project_int("tempo_stamp")
  if next(queue) then
    schedule()
  end
end

--- A window shows the song from `from` to `to` (beats), on `tracks`
--- (all when nil): what is there comes before the rest, here and in the
--- bakes. A view tells it each time it draws; nil `from` forgets the window.
function M.visible(window: string, from?: number, to?: number, tracks?: {integer})
  ranges[window] = from and {from = from, to = to, tracks = tracks} or nil
end

--- A frame starts: the windows that tell their range while it is drawn
--- (`visible`) are all that show.
function M.frame_start()
  ranges = {}
end

local function range_text(r: types.ViewRange): string
  return string.format("%.17g:%.17g:%s", r.from, r.to, r.tracks and table.concat(r.tracks, ",") or "*")
end

--- A frame ends: the kernel gets what the windows show when it changed,
--- for the bake scheduler (`api.view_ranges_set`).
function M.frame_end()
  local list: {types.ViewRange} = {}
  local texts: {string} = {}
  for _, r in pairs(ranges) do
    list[#list + 1] = r
    texts[#texts + 1] = range_text(r)
  end
  table.sort(texts)
  local text = table.concat(texts, ";")
  if text ~= told_ranges then
    told_ranges = text
    api.view_ranges_set(list)
  end
end

--- The job while it has run for `after` milliseconds (1000) or more: what
--- it makes and how far it is. Nil when it does not run.
function M.progress(after?: number): Progress
  if not started or not M.busy() then
    return nil
  end
  local ms = api.now() - started
  if ms < (after or 1000) then
    return nil
  end
  return {label = label or "derived", fraction = todo > 0 and math.min(1, done / todo) or 0, ms = ms}
end

--- `:checkhealth derived`: each kind of node, its values and its limit.
function M.health(h: contracts.Health)
  local job = slices.job("derived")
  if job then
    h.info(string.format("the job runs: %d slices, the longest %.1f ms", job.slices, job.longest))
  else
    h.ok("nothing waits to be made")
  end
  -- What the bakes take as shown, as the kernel has it.
  for _, r in ipairs(api.view_ranges()) do
    local tracks = r.tracks and (#r.tracks .. " tracks") or "all tracks"
    h.info(string.format("a window shows beats %.0f to %.0f, %s: what is there comes first", r.from, r.to, tracks))
  end
  for _, s in ipairs(M.stats()) do
    local amount: string
    for i_core = 1, #cores do
      local core = cores[i_core]
      if core.spec.name == s.name then
        amount = core.spec.bytes and string.format("%.1f MB", s.bytes / 1048576) or string.format("%d values", s.values)
        if s.limit then
          amount = amount
            .. " of "
            .. (core.spec.bytes and string.format("%.0f MB", s.limit / 1048576) or tostring(s.limit))
        end
      end
    end
    local text = string.format(
      "%s (%s): %d values, %s; made %d, fresh again %d, dropped %d",
      s.name,
      s.kind,
      s.values,
      amount,
      s.made,
      s.hits,
      s.dropped
    )
    if s.limit and (s.bytes > s.limit or (s.bytes == 0 and s.values > s.limit)) then
      h.warn(text, "past its limit: the values that no other value reads go first")
    else
      h.ok(text)
    end
  end
end

M.changed = events.event("derived.changed") as events.Event<Changed>

-- What the kernel says changed: the sources ----------------------------------------------

events.on(
  kernel.track_changed,
  function(e: kernel.TrackChange)
    for i_f = 1, #e.fields do
      local f = e.fields[i_f]
      mark("track:" .. e.id .. ":" .. f)
    end
  end
)
for _, event in ipairs({kernel.track_added, kernel.track_removed}) do
  events.on(event, function(_: kernel.TrackId) mark("tracks") end)
end
events.on(kernel.track_moved, function() mark("tracks") end)
for _, event in ipairs({kernel.clip_added, kernel.clip_changed, kernel.clip_removed}) do
  events.on(event, function(e: kernel.Item) mark("clip:" .. e.id) end)
end
for _, event in ipairs({kernel.device_added, kernel.device_changed, kernel.device_removed}) do
  events.on(event, function(e: kernel.Item) mark("device:" .. e.id) end)
end
events.on(
  kernel.project_changed,
  function()
    local stamp = project_int("tempo_stamp")
    if stamp ~= tempo_seen then
      tempo_seen = stamp
      mark("tempo")
    end
  end
)
local record OptionChanged
  name: string
end
events.on(
  events.event("option.changed") as events.Event<OptionChanged>,
  function(e: OptionChanged) mark("option:" .. e.name) end
)
events.on(kernel.changed, function() edits_seen = project_int("edits") end)
events.on(kernel.project_loaded, function() M.reset() end)

return M
