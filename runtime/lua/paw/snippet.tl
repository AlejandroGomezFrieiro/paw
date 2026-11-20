-- `paw.snippet`: named music made from its context, written at the cursor
-- of the piano roll or over a selection, with choices to step through
-- afterwards. As `vim.snippet` or LuaSnip, for notes.
--
--   paw.snippet.add({
--     name = "dominant", desc = "the dominant seventh of the next chord, up to it",
--     views = { "pianoroll" },
--     expand = function(ctx)
--       local target = ctx.harmony.next(ctx.at)
--       if not target then return nil, "no chord after the cursor" end
--       local root = (target.root + 7) % 12
--       return {
--         notes = ctx:chord(ctx.harmony.tones(root, "7"), ctx.at, target.at),
--         choices = { { name = "voicing", values = { "smooth", "close", "drop2", "open" } } },
--       }
--     end,
--   })
--
-- `expand(ctx)` returns `{ notes, choices, remove }` or nil and a reason.
-- Notes are a note set in project beats: `{ pitch, start, length, velocity }`
-- (velocity 1..127, `paw.opt.velocity` when left out). `remove` lists notes
-- of `ctx.selection` the snippet replaces. Each choice is `{ name, values }`
-- and optionally `apply(result, value)` returning the notes; without it the
-- snippet is expanded again with `ctx.values[name]` set to the value chosen.
--
-- Expanding writes the notes as one undo step and makes the snippet active:
-- `<Tab>` and `<S-Tab>` go from choice to choice, `<C-n>` and `<C-p>` step
-- the current one (rewriting the notes within the same undo step), `<C-y>`,
-- `<Esc>` or the cursor leaving the snippet's span ends it.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local seats = require("paw.seats")
local limit = require("paw.limit")
local util = require("paw.util")
local music = require("paw.music")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")
local type objects = require("paw.objects")
local type HarmonyModule = require("paw.harmony")
local type EditModule = require("paw.edit")
local type AuditionModule = require("paw.audition")
local type CompleteModule = require("paw.complete")
local type DrawModule = require("paw.draw")

--- A note of a snippet, in project beats: `start` (or `at`), and in the
--- context the note's `place` in the clip (from 1).
local record Note
  pitch: integer
  start: number
  at: number
  length: number
  velocity: integer
  meta: types.Meta
  attr: types.NoteAttr
  place: integer
end

--- A value of a choice.
local type Value = string | number

--- A choice of a snippet: its name and values, and optionally `apply`,
--- which gives the notes for a value (else the snippet runs again).
local record Choice
  name: string
  values: {Value}
  apply: function(result: Expansion, value: Value): {Note}
end

--- What `expand` gives: the notes, the choices, and the notes of the
--- selection that it replaces.
local record Expansion
  notes: {Note}
  choices: {Choice}
  remove: {Note}
end

--- Where a source of snippets is: an extension or the user's configuration.
local enum Origin
  "extension" "config"
end

--- A stretch of the project, in beats.
local record Span
  from: number
  to: number
end

--- What `M.context` takes: where the snippet starts (project beats), how
--- many times, the values of its choices, and the selection (a region, or
--- false for none; the visual selection's when nil).
local record ContextOptions
  at: number
  count: integer
  values: {string:Value}
  selection: contracts.Region | boolean
end

--- The context of an expansion in the piano roll: `expand(ctx)` reads it.
local record Ctx
  view: string
  clip: objects.Clip
  clip_id: integer
  track: objects.Track
  track_id: integer
  at: number
  pitch: integer
  start: number
  harmony: HarmonyModule
  grid: number
  count: integer
  opt: options.Opt
  range: HarmonyModule.Range
  velocity: integer
  values: {string:Value}
  notes: {Note}
  key: HarmonyModule.Key
  selected_region: contracts.Region
  selection: {Note}
  region: Span
end

--- A snippet (`paw.snippet.add`): its name, what it says it does, the
--- views it is offered in, what it writes, its choices, `count = true`
--- when it takes the count itself, and where it comes from.
local record Spec
  name: string
  desc: string
  views: {string}
  expand: function(ctx: Ctx): Expansion, string
  choices: {Choice}
  count: boolean
  source: Origin
end

--- What a snippet would write: its notes, what it replaces, its choices
--- and its context.
local record Run
  notes: {Note}
  remove: {Note}
  choices: {Choice}
  ctx: Ctx
end

--- The snippet being edited.
local record Active
  name: string
  spec: Spec
  opts: ContextOptions
  clip: integer
  start: number
  length: number
  before: {types.Note}
  undo_before: integer
  choices: {Choice}
  index: {string:integer}
  current: integer
  notes: {Note}
  span: Span
  edits: integer
end

--- What a snippet would write in the open picker's context, made once.
local record Previewed
  result: Run
  why: string
end

--- The open picker's context, and what each snippet would write there.
local record Previewing
  opts: ContextOptions
  results: {string:Previewed}
end

--- What each seat has of its own.
local record SeatState
  active: Active
  previewing: Previewing
  from_visual: contracts.Region
end

--- What `paw.snippet.pick` takes: the selection, the count, and the text
--- typed in already.
local record PickOptions
  selection: contracts.Region
  count: integer
  query: string
end

--- A note to draw: its pitch, and where it is in the clip's beats.
local record Mark
  pitch: integer
  start: number
  length: number
end

--- The active snippet, for drawing (`paw.snippet.marks`).
local record Marks
  name: string
  notes: {Mark}
  from: number
  to: number
  label: string
end

--- The payload of `snippet.expanded`.
local record Expanded
  name: string
  clip: integer
end

--- The payload of `snippet.finished`.
local record Finished
  name: string
end

--- The payload of `mode.changed`.
local record ModeChanged
  mode: string
  old: string
end

--- What `Ctx:voice` takes: the beats it leads from and into, the pitches
--- before and after it (found when nil), how many, the style, the range,
--- and the bass.
local record VoiceOptions
  from: number
  to: number
  prev: {number}
  next: {number}
  count: integer
  style: string
  low: integer
  high: integer
  bass: integer
end

--- What `Ctx:chord` takes: the pitches (voiced when nil), the velocity,
--- and the options of `Ctx:voice`.
local record ChordOptions
  pitches: {integer}
  velocity: integer
  style: string
  prev: {number}
  next: {number}
  bass: integer
  count: integer
end

-- What this module reads of the modules that are still in Lua.

--- What a layer of the piano roll gets (paw/views/pianoroll.lua).
local record Layer
  clip: types.Clip
  roll: contracts.Buf
  rows: integer
  x: function(beat: number): integer
  row: function(pitch: integer): integer
end

--- The piano roll, as far as this module reads it.
local record Roll
  beat: number
  pitch: integer
  clip: function(self: Roll): objects.Clip
end

--- What `paw.pick.state()` gives, as far as this module reads it.
local record PickState
  title: string
  item: Spec
end

local record Paw is partial.Paw
  ui: UiModule
  harmony: HarmonyModule
  edit: EditModule
  audition: AuditionModule
  complete: CompleteModule
  time: objects.Time
  clip: function(id: integer): objects.Clip
  draw: DrawModule
end
local paw = (_G as {string:Paw}).paw
local opt = options.opt

local record M
  type Note = Note
  type Value = Value
  type Choice = Choice
  type Expansion = Expansion
  type Origin = Origin
  type ContextOptions = ContextOptions
  type Ctx = Ctx
  type Spec = Spec
  type Run = Run
  type Active = Active
  type PickOptions = PickOptions
  type Marks = Marks
  --- The snippets, by name.
  list: {string:Spec}
  --- Where the snippets that `load_dir` loads now come from.
  loading: Origin
  --- The open picker's context and what each snippet would write there.
  previewing: Previewing
  --- Snippets as a source of suggestions (`paw.complete`).
  source: CompleteModule.Source
  --- The event `snippet.expanded`.
  expanded: events.Event<Expanded>
  --- The event `snippet.finished`.
  finished: events.Event<Finished>
  finish: function()
end
M.list = {}
M.expanded = events.event("snippet.expanded")
M.finished = events.event("snippet.finished")

local harmony = paw.harmony

local RANK: {Origin:integer} = { extension = 1, config = 2 }

--- A copy of a table with the same fields.
local record Opaque
end
local function shallow<T>(t: T): T
  local out: {string:Opaque} = {}
  for k, v in pairs(t as {string:Opaque}) do out[k] = v end
  return out as T
end

--- Add a snippet, or replace one of the same name. A snippet from an
--- extension never replaces one from the user's configuration.
function M.add(spec: Spec): Spec
  assert(spec is Spec and type(spec.name) == "string" and type(spec.expand) == "function",
    "usage: paw.snippet.add({ name = ..., expand = function(ctx) ... end })")
  local source: Origin = spec.source or M.loading or (paw.ext.current and "extension") or "config"
  local old = M.list[spec.name]
  if old and RANK[old.source] > RANK[source] then return old end
  local entry = shallow(spec)
  entry.source, entry.desc, entry.views = source, spec.desc or "", spec.views or { "pianoroll" }
  M.list[spec.name] = entry
  return entry
end

--- Remove a snippet.
function M.remove(name: string)
  M.list[name] = nil
end

--- The snippet of a name, or nil.
function M.get(name: string): Spec
  return M.list[name]
end

--- The snippets offered in `view` (the focused one when nil), by name.
function M.offered(view?: string): {Spec}
  view = view or paw.ui.focused
  local out: {Spec} = {}
  for _, s in pairs(M.list) do
    for _, v in ipairs(s.views) do
      if v == view then out[#out + 1] = s break end
    end
  end
  table.sort(out, function(a: Spec, b: Spec): boolean return a.name < b.name end)
  return out
end

--- What a file of snippets gives: a snippet, or a list of them.
local record Loaded
  {Spec}
  name: string
end

--- Load every `*.lua` file of a directory: each calls `paw.snippet.add` or
--- returns a list of snippets. `source` is "config" or "extension".
function M.load_dir(dir: string, source: Origin)
  local ok, entries = pcall(api.read_dir, dir)
  if not ok then return end
  table.sort(entries, function(a: types.DirEntry, b: types.DirEntry): boolean return a.name < b.name end)
  for _, entry in ipairs(entries) do
    if not entry.is_dir and entry.name:match("%.lua$") then
      local path = dir .. "/" .. entry.name
      M.loading = source
      local chunk, err = loadfile(path)
      local done = false
      local result: Loaded | string = err as string
      if chunk then
        local ran, value = xpcall(limit.untrusted(chunk as function(): Loaded), debug.traceback)
        done, result = ran, value as Loaded | string
      end
      if done and result is Loaded then
        for _, spec in ipairs(result.name and { result as Spec } or result as {Spec}) do M.add(spec) end
      elseif not done then
        paw.notify("snippets " .. path .. ": " .. tostring(result), "error")
      end
      M.loading = nil
    end
  end
end

-- The context ----------------------------------------------------------------------

local ctx_mt: metatable<Ctx> = { __index = Ctx }

--- The notes of this clip that sound together, as pitches: the chord that
--- starts last before `beat` (the cursor's), or nil.
function Ctx:before(beat?: number): {number}
  beat = beat or self.at
  local best: number = nil
  local out: {number} = {}
  for _, n in ipairs(self.notes) do
    if n.start < beat - 1e-9 and (not best or n.start > best + 1e-6) then best = n.start end
  end
  if not best then return nil end
  for _, n in ipairs(self.notes) do
    if math.abs(n.start - best) < 1 / 16 then out[#out + 1] = n.pitch end
  end
  table.sort(out)
  return out
end

--- The pitches of the first chord of this clip starting at `beat`, or
--- within a beat after it.
function Ctx:after(beat?: number): {number}
  beat = beat or self.at
  local best: number = nil
  local out: {number} = {}
  for _, n in ipairs(self.notes) do
    if n.start >= beat - 1e-9 and n.start < beat + 1 and (not best or n.start < best - 1e-6) then best = n.start end
  end
  if not best then return nil end
  for _, n in ipairs(self.notes) do
    if math.abs(n.start - best) < 1 / 16 then out[#out + 1] = n.pitch end
  end
  table.sort(out)
  return out
end

--- The pitches other pitched tracks play inside this track's range at
--- `beat` (sounding just before it with `before`), or nil: what to lead
--- from or into when this clip has nothing there.
function Ctx:around(beat: number, before?: boolean): {number}
  local out: {number} = {}
  for _, n in ipairs(self.harmony.notes()) do
    local inside = n.pitch >= self.range.low and n.pitch <= self.range.high and n.clip ~= self.clip_id
    local sounding = before and (n.start < beat - 1e-9 and n.start + n.length >= beat - 1e-9)
      or (not before and math.abs(n.start - beat) < 1 / 16)
    if inside and sounding then out[#out + 1] = n.pitch end
  end
  table.sort(out)
  return #out > 0 and out or nil
end

--- Pitches for a chord (pitch classes, root first) in the track's range,
--- led from what this clip plays before `opts.from` (the cursor) and into
--- what it plays at `opts.to`; where it plays nothing, from and into what
--- the other tracks play in its range. Options as
--- `paw.harmony.voice.voice`; the style is the `voicing` choice when there
--- is one.
function Ctx:voice(tones: {integer}, opts?: VoiceOptions): {integer}
  opts = opts or {}
  local from = opts.from or self.at
  local prev = opts.prev
  if prev == nil then prev = self:before(from) or self:around(from, true) end
  local nxt = opts.next
  if nxt == nil and opts.to then nxt = self:after(opts.to) or self:around(opts.to, false) end
  local count = opts.count or math.max(math.min(#tones, 4), prev and math.min(#prev, 4) or 0, 3)
  return harmony.voice.voice(tones, {
    low = opts.low or self.range.low, high = opts.high or self.range.high,
    style = opts.style or self.values.voicing as string, prev = prev, next = nxt, count = count, bass = opts.bass,
    center = self.pitch,
  })
end

--- A chord as notes from `from` to `to` (project beats), voiced by `voice`.
function Ctx:chord(tones: {integer}, from: number, to: number, opts?: ChordOptions): {Note}, {integer}
  opts = opts or {}
  local pitches = opts.pitches or self:voice(tones, { from = from, to = to, style = opts.style, prev = opts.prev, next = opts.next, bass = opts.bass, count = opts.count })
  local out: {Note} = {}
  for _, p in ipairs(pitches or {}) do
    out[#out + 1] = { pitch = p, start = from, length = to - from, velocity = opts.velocity or self.velocity }
  end
  return out, pitches
end

--- Where the snippet should end when nothing says: the next chord's start,
--- else the end of the bar after the cursor.
function Ctx:until_next(): number, HarmonyModule.Chord
  local nxt = self.harmony.next(self.at)
  if nxt then return nxt.at, nxt end
  return paw.time.bar_ceil(self.at + 1e-9)
end

--- The context of an expansion in the piano roll, or nil and why not.
--- `opts`: `at` (project beats, the cursor's when nil), `count`, `values`,
--- `selection` (a region; the visual selection's when nil).
function M.context(opts?: ContextOptions): Ctx, string
  opts = opts or {}
  local roll = paw.ui.views.pianoroll as Roll
  local clip = roll and roll:clip()
  if not clip then return nil, "open a MIDI clip in the piano roll" end
  local c = clip:get()
  local notes: {Note} = {}
  local clip_notes = clip:notes()
  for i, n in ipairs(clip_notes) do
    notes[i] = { pitch = n.pitch, start = c.start + n.start, length = n.length, velocity = n.velocity, place = i }
  end
  local ctx: Ctx = setmetatable({
    view = "pianoroll", clip = clip, clip_id = c.id, track = clip:track(), track_id = c.track,
    at = opts.at or (c.start + roll.beat), pitch = roll.pitch, start = c.start,
    harmony = harmony, grid = opt.note_grid, count = opts.count or 1, opt = opt,
    range = harmony.range(c.track), velocity = opt.velocity, values = opts.values or {}, notes = notes,
  } as Ctx, ctx_mt)
  ctx.key = harmony.key(ctx.at)
  local region = opts.selection
  if region == nil and paw.ui.focused == "pianoroll" then region = paw.keymap.selection() end
  if region is contracts.Region then
    ctx.selected_region = region
    local found, places = paw.edit.roll.notes(clip, region as EditModule.Region)
    ctx.selection = {}
    for i, n in ipairs(found) do
      ctx.selection[i] = { pitch = n.pitch, start = c.start + n.start, length = n.length, velocity = n.velocity, place = places[i] }
    end
    ctx.region = { from = c.start + region.c0, to = c.start + region.c1 }
  end
  return ctx
end

-- Expanding ----------------------------------------------------------------------------

--- The value of each choice: its current one, else its first.
local function chosen(choices: {Choice}, index: {string:integer}): {string:Value}
  local values: {string:Value} = {}
  for _, choice in ipairs(choices or {}) do
    values[choice.name] = choice.values[(index[choice.name] or 1)]
    if values[choice.name] == nil then values[choice.name] = choice.values[1] end
    index[choice.name] = index[choice.name] or 1
  end
  return values
end

--- Run a snippet: its notes (project beats), its choices and what it
--- replaces, repeated `count` times one after another unless it takes the
--- count itself (`count = true`). Nil and a reason when it has nothing.
local function run(spec: Spec, opts: ContextOptions, index: {string:integer}): Run, string
  local ctx, why = M.context(opts)
  if not ctx then return nil, why end
  local times = spec.count and 1 or (opts.count or 1)
  local all: {Note} = {}
  local remove: {Note} = {}
  local choices: {Choice} = nil
  local at = ctx.at
  for k = 1, times do
    local c: Ctx
    if k == 1 then
      c = ctx
    else
      local next_opts = shallow(opts)
      next_opts.at, next_opts.selection = at, false
      c = M.context(next_opts)
    end
    if k > 1 then c.count = 1 end
    c.values = chosen(choices or spec.choices, index)
    local ok, result, reason = xpcall(spec.expand, debug.traceback, c)
    if not ok then return nil, tostring(result) end
    if not result then
      if k == 1 then return nil, reason or "nothing to write here" end
      break
    end
    if k == 1 then
      choices = result.choices or spec.choices
      local values = chosen(choices, index)
      -- First run: the choices were not known yet; run again with them.
      local again = false
      for name, v in pairs(values) do
        if c.values[name] ~= v then again = true end
      end
      if again then
        c.values = values
        local fine, second = xpcall(spec.expand, debug.traceback, c)
        if not fine then return nil, tostring(second) end
        result = second or result
      end
    end
    local notes = result.notes or {}
    for _, choice in ipairs(choices or {}) do
      if choice.apply then notes = choice.apply(result, c.values[choice.name]) or notes end
    end
    local finish = at
    for _, n in ipairs(notes) do
      all[#all + 1] = n
      finish = math.max(finish, (n.start or n.at) + n.length)
    end
    for _, n in ipairs(result.remove or {}) do remove[#remove + 1] = n end
    if finish <= at + 1e-9 then break end
    at = finish
  end
  if #all == 0 and #remove == 0 then return nil, "nothing to write here" end
  return { notes = all, remove = remove, choices = choices or {}, ctx = ctx }
end

--- What a snippet would write here, but does not write: `{ notes,
--- choices, ctx }` or nil and why.
function M.preview(name: string, opts?: ContextOptions): Run, string
  local spec = M.list[name]
  if not spec then return nil, "no snippet " .. tostring(name) end
  return run(spec, opts or {}, {})
end

local active: Active       -- the snippet being edited: see `expand`
M.previewing = nil         -- the open picker's context and what each snippet would write there
local from_visual: contracts.Region  -- the selection the command line was opened over, for `:snippet`
-- All three are what one person is in the middle of: each seat has its own.
seats.keep("snippet",
  function(): SeatState return { active = active, previewing = M.previewing, from_visual = from_visual } end,
  function(s: SeatState) active, M.previewing, from_visual = s.active, s.previewing, s.from_visual end,
  function(): SeatState return {} end)

local project_edits = api.project_get as function(key: string): integer

--- Write `result` into its clip in place of what the clip held before.
local function write(state: Active, result: Run)
  local clip = paw.clip(state.clip)
  local start = state.start
  local removed: {integer:boolean} = {}
  for _, n in ipairs(result.remove) do
    if n.place then removed[n.place] = true end
  end
  local list: {types.Note} = {}
  for i, n in ipairs(state.before) do
    if not removed[i] then list[#list + 1] = n end
  end
  local finish = 0.0
  for _, n in ipairs(result.notes) do
    local s = (n.start or n.at) - start
    if s >= -1e-9 then
      list[#list + 1] = { pitch = n.pitch, start = math.max(0, s), length = n.length, velocity = n.velocity or opt.velocity, meta = n.meta, attr = n.attr }
      finish = math.max(finish, s + n.length)
    end
  end
  local length = state.length
  if finish > length + 1e-9 then length = paw.time.bar_ceil(start + finish - 1e-9) - start end
  if math.abs(clip.length - length) > 1e-9 then clip.length = length end
  api.clip_set_notes(state.clip, list)
  state.notes, state.span = result.notes, { from = result.ctx.at, to = result.ctx.at }
  for _, n in ipairs(result.notes) do
    state.span.from = math.min(state.span.from, n.start or n.at)
    state.span.to = math.max(state.span.to, (n.start or n.at) + n.length)
  end
  for _, n in ipairs(result.remove) do
    state.span.from = math.min(state.span.from, n.start)
    state.span.to = math.max(state.span.to, n.start + n.length)
  end
  state.edits = project_edits("edits")
end

local function describe(state: Active): string
  local choice = state.choices[state.current]
  local parts = { state.name }
  if choice then
    parts[#parts + 1] = string.format("%s: %s (%d/%d)", choice.name, tostring(choice.values[state.index[choice.name]]),
      state.index[choice.name], #choice.values)
  elseif #state.choices > 0 then
    parts[#parts + 1] = "Tab: " .. state.choices[1].name
  end
  return table.concat(parts, " · ")
end

--- Expand a snippet at the cursor of the piano roll (or over its
--- selection): `opts` `count`, `at`, `values` (a choice's value by name).
--- Returns the active snippet, or nil and why nothing was written.
function M.expand(name: string, opts?: ContextOptions): Active, string
  opts = opts or {}
  local spec = M.list[name]
  if not spec then return nil, "no snippet " .. tostring(name) end
  M.finish()
  local index: {string:integer} = {}
  for k, v in pairs(opts.values or {}) do
    for _, choice in ipairs(spec.choices or {}) do
      if choice.name == k then
        for i, value in ipairs(choice.values) do
          if value == v then index[k] = i end
        end
      end
    end
  end
  local result, why = run(spec, opts, index)
  if not result then return nil, why end
  local clip = result.ctx.clip
  local c = clip:get()
  -- Leave visual mode: the selection is what the snippet worked on.
  if paw.keymap.mode == "x" then paw.keymap.set_mode("n") end
  api.undo_label("snippet " .. name)
  local before = api.clip_notes(c.id)
  local state: Active = {
    name = name, spec = spec, opts = { count = opts.count, at = result.ctx.at, selection = result.ctx.selected_region or false },
    clip = c.id, start = c.start, length = c.length, before = before, undo_before = api.undo_current(),
    choices = result.choices, index = index, current = 0,
  }
  write(state, result)
  active = state
  events.emit(M.expanded, { name = name, clip = c.id })
  paw.notify(describe(state))
  api.ui_redraw()
  return state
end

--- The active snippet, or nil. A snippet ends when the project changed
--- other than through it, or the piano roll's cursor left its span.
function M.active(): Active
  if not active then return nil end
  local roll = paw.ui.views.pianoroll as Roll
  local clip = roll and roll:clip()
  local stale = project_edits("edits") ~= active.edits or not pcall(api.clip_get, active.clip)
  local away = not clip or clip.id ~= active.clip
    or clip.start + roll.beat < active.span.from - 1e-9 or clip.start + roll.beat > active.span.to + 1e-9
  if stale or away then M.finish() end
  return active
end

--- Stop the active snippet, and keep the notes that it wrote.
function M.finish()
  if not active then return end
  local name = active.name
  active = nil
  events.emit(M.finished, { name = name })
  api.ui_redraw()
end

--- Rewrite the active snippet with its choices as they are now, joining
--- the undo step that wrote it. It runs again on the clip as it was
--- before, so that it sees what it saw the first time.
local function rewrite(state: Active)
  -- Stepped in the same turn as it was written (keys typed at once, a
  -- script), the step is still open: there is nothing to join.
  if api.undo_current() ~= state.undo_before then api.undo_join(api.undo_current()) end
  local clip = paw.clip(state.clip)
  api.clip_set_notes(state.clip, state.before)
  if math.abs(clip.length - state.length) > 1e-9 then clip.length = state.length end
  local result, why = run(state.spec, state.opts, state.index)
  if not result then
    paw.notify(why, "warn")
    M.finish()
    return
  end
  write(state, result)
end

--- The notes a snippet wrote, as text to compare.
local function signature(notes: {Note}): string
  local out: {string} = {}
  for i, n in ipairs(notes or {}) do out[i] = string.format("%d@%.6f+%.6f", n.pitch, n.start or n.at, n.length) end
  table.sort(out)
  return table.concat(out, " ")
end

--- Go to the next choice (`dir` 1) or the previous choice (-1). False when
--- no snippet is active. Then the key can do its usual action.
function M.jump(dir?: integer): boolean
  local state = M.active()
  if not state then return false end
  local n = #state.choices
  if n == 0 then
    paw.notify(state.name .. " has no choices")
    return true
  end
  state.current = (state.current - 1 + (dir or 1)) % n + 1
  paw.notify(describe(state))
  api.ui_redraw()
  return true
end

--- Step the current choice (the first when none is) to its next value
--- (`dir` 1) or the one before (-1), and rewrite the notes.
function M.step(dir?: integer): boolean
  local state = M.active()
  if not state then return false end
  if #state.choices == 0 then
    paw.notify(state.name .. " has no choices")
    return true
  end
  if state.current == 0 then state.current = 1 end
  local choice = state.choices[state.current]
  -- Values that would write the same notes (a smooth voicing that is the
  -- close one here) are passed over.
  local was = signature(state.notes)
  for _ = 1, #choice.values - 1 do
    local i = state.index[choice.name] or 1
    state.index[choice.name] = (i - 1 + (dir or 1)) % #choice.values + 1
    rewrite(state)
    if not active or signature(state.notes) ~= was then break end
  end
  paw.notify(describe(state))
  api.ui_redraw()
  return true
end

--- The active snippet's notes and span in the clip's beats, for drawing:
--- `{ name, notes, from, to, label }`, or nil.
function M.marks(clip_id: integer): Marks
  local state = M.active()
  if not state or state.clip ~= clip_id then return nil end
  local notes: {Mark} = {}
  for i, n in ipairs(state.notes) do
    notes[i] = { pitch = n.pitch, start = (n.start or n.at) - state.start, length = n.length }
  end
  return { name = state.name, notes = notes, from = state.span.from - state.start, to = state.span.to - state.start, label = describe(state) }
end

-- The picker -------------------------------------------------------------------------

local function note_names(notes: {Note}): string
  local pitches: {integer} = {}
  local seen: {integer:boolean} = {}
  for _, n in ipairs(notes) do
    if not seen[n.pitch] then
      seen[n.pitch] = true
      pitches[#pitches + 1] = n.pitch
    end
  end
  table.sort(pitches)
  local out: {string} = {}
  for i, p in ipairs(pitches) do out[i] = music.name(p) end
  return table.concat(out, " ")
end

--- What snippet `name` would write in the open picker's context, made once:
--- `{ result, why }`.
local function previewed(name: string): Previewed
  local p = M.previewing
  if not p.results[name] then
    local result, why = run(M.list[name], p.opts, {})
    p.results[name] = { result = result, why = why }
  end
  return p.results[name]
end

--- The notes of a snippet that start together.
local record Group
  at: number
  notes: {Note}
end

--- Lines that tell what a snippet would write here.
function M.describe_preview(spec: Spec, opts?: ContextOptions, result?: Run, why?: string): {string | contracts.PageLine}, Run
  local lines: {string | contracts.PageLine} = { { text = spec.name, style = "Title" }, spec.desc ~= "" and spec.desc or nil }
  if result == nil and why == nil then result, why = run(spec, opts or {}, {}) end
  if not result then
    lines[#lines + 1] = ""
    lines[#lines + 1] = { text = why or "nothing to write here", style = "Comment" }
    return lines, nil
  end
  lines[#lines + 1] = ""
  -- The notes, a chord at a time.
  local groups: {string:Group} = {}
  local order: {Group} = {}
  for _, n in ipairs(result.notes) do
    local s = n.start or n.at
    local key = string.format("%.4f", s)
    if not groups[key] then
      groups[key] = { at = s, notes = {} }
      order[#order + 1] = groups[key]
    end
    table.insert(groups[key].notes, n)
  end
  table.sort(order, function(a: Group, b: Group): boolean return a.at < b.at end)
  for i, g in ipairs(order) do
    if i > 8 then
      lines[#lines + 1] = string.format("… and %d more", #order - 8)
      break
    end
    lines[#lines + 1] = string.format("%-8s %s", paw.time.format(g.at), note_names(g.notes))
  end
  if #result.choices > 0 then
    lines[#lines + 1] = ""
    for _, choice in ipairs(result.choices) do
      lines[#lines + 1] = { text = choice.name .. ": " .. table.concat(choice.values as {string}, ", "), style = "Comment" }
    end
  end
  return lines, result
end

--- The picker that opens (paw/pick.lua).
local record Picker
end

--- Open the picker of the snippets of the focused view. Enter expands the
--- selected snippet `count` times.
function M.pick(opts?: PickOptions): Picker
  opts = opts or {}
  local view = paw.ui.focused
  local items = M.offered(view)
  -- The context is the cursor's now, before the picker takes the keys.
  local region = opts.selection or (view == "pianoroll" and paw.keymap.selection()) or nil
  local run_opts: ContextOptions = { count = opts.count, selection = region or false }
  -- What each snippet would write here, made once while the picker is open:
  -- its pane and the ghosts in the roll both show it.
  M.previewing = { opts = run_opts, results = {} }
  local source: contracts.PickSource<Spec> = {
    title = "Snippets",
    items = items,
    -- Above the piano roll, so that its ghosts show under it.
    top = true,
    height = 16,
    query = opts.query,
    format = function(s: Spec): string return string.format("%-12s %s", s.name, s.desc) end,
    primary = function(s: Spec): string return s.name end,
    empty = "No snippets here. Load extensions/snippets, or add your own with paw.snippet.add.",
    preview = function(s: Spec): {string | contracts.PageLine}
      local found = M.previewing and previewed(s.name)
      return (M.describe_preview(s, run_opts, found and found.result or nil, found and found.why or nil))
    end,
    -- Its notes through the clip's track, with what every other pitched
    -- track plays over the same beats (the harmony it was written for),
    -- once; nothing is written until it is chosen.
    audition_key = "snippets",
    audition = function(s: Spec): string
      local found = M.previewing and previewed(s.name)
      local result = found and found.result
      if not result or #result.notes == 0 then return found and found.why or "nothing to write here" end
      local ctx = result.ctx
      local from, to = math.huge, -math.huge
      for _, n in ipairs(result.notes) do
        local at = n.start or n.at
        from, to = math.min(from, at), math.max(to, at + n.length)
      end
      local gone: {string:boolean} = {}
      for _, n in ipairs(result.remove) do
        if n.place then gone[ctx.clip_id .. ":" .. n.place] = true end
      end
      local notes: {AuditionModule.PhraseNote} = {}
      for _, n in ipairs(result.notes) do
        notes[#notes + 1] = { pitch = n.pitch, start = (n.start or n.at) - from, length = n.length, velocity = n.velocity or ctx.velocity, track = ctx.track_id }
      end
      for _, n in ipairs(harmony.notes()) do
        if n.start < to and n.start + n.length > from and n.start >= from - 1e-9 then
          local place: integer
          if n.clip == ctx.clip_id then
            for i, c in ipairs(ctx.notes) do
              if c.pitch == n.pitch and math.abs(c.start - n.start) < 1e-9 then place = c.place or i end
            end
          end
          if not (place and gone[n.clip .. ":" .. place]) then
            notes[#notes + 1] = { pitch = n.pitch, start = n.start - from, length = n.length, velocity = n.velocity, track = n.track }
          end
        end
      end
      paw.audition.phrase(ctx.track_id, notes, { length = to - from, at = from, loop = false })
      return s.name .. " · " .. paw.time.format(from)
    end,
    on_choose = function(s: Spec)
      M.previewing = nil
      local _, why = M.expand(s.name, run_opts)
      if why then paw.notify(why, "warn") end
    end,
    on_cancel = function() M.previewing = nil end,
  }
  return (paw.pick.open as function(contracts.PickSource<Spec>): Picker)(source)
end

--- The notes that the snippet under the selection of the picker would
--- write, in the beats of the clip, to draw them. Nil when no picker of
--- snippets is open.
function M.preview_marks(clip_id: integer): {Mark}
  local state = M.previewing and paw.pick.state() as PickState
  local item = state and state.title == "Snippets" and state.item
  local found = item and previewed(item.name)
  local result = found and found.result
  if not result or result.ctx.clip_id ~= clip_id then return nil end
  local out: {Mark} = {}
  for i, n in ipairs(result.notes) do out[i] = { pitch = n.pitch, start = (n.start or n.at) - result.ctx.start, length = n.length } end
  return out
end

--- Paint the snippet layer of the piano roll (order 40, see
--- `views/pianoroll.lua`). It marks the notes of the active snippet, and
--- shows its range along the bottom with the items of Tab and `<C-n>`. It
--- shows the notes that the picker would write as ghosts.
function M.paint(p: Layer)
  local roll, glyphs = p.roll, paw.draw.g
  for _, n in ipairs(M.preview_marks(p.clip.id) or {}) do
    local row = p.row(n.pitch)
    if row then
      local x0 = p.x(n.start)
      local w = math.max(1, p.x(n.start + n.length) - x0)
      roll:fill(x0, row, w, 1, " ", "SnippetGhost")
      roll:text(x0, row, glyphs.clip_start, "SnippetGhost")
      if w >= 4 then roll:text(x0 + 1, row, music.name(n.pitch):sub(1, w - 1), "SnippetGhost") end
    end
  end
  local m = M.marks(p.clip.id)
  if not m then return end
  for _, n in ipairs(m.notes) do
    local row = p.row(n.pitch)
    if row then
      local x0 = p.x(n.start)
      local w = math.max(1, p.x(n.start + n.length) - x0)
      roll:fill(x0, row, w, 1, " ", "SnippetNote")
      roll:text(x0, row, glyphs.clip_start, "SnippetNote")
      if w >= 4 then roll:text(x0 + 1, row, music.name(n.pitch):sub(1, w - 1), "SnippetNote") end
    end
  end
  local width = roll.width
  local x0, x1 = math.max(0, p.x(m.from)), math.min(width, p.x(m.to))
  if x1 > x0 then
    -- The span along the bottom row, and what it is doing, running on
    -- past it when the span is short.
    local label = " " .. m.label .. " "
    roll:fill(x0, p.rows - 1, x1 - x0, 1, " ", "SnippetSpan")
    roll:text(x0, p.rows - 1, util.fit(label, math.min(api.str_width(label), width - x0)), "SnippetSpan")
  end
end

--- Snippets as a source of suggestions (`paw.complete`): on `<C-Space>`,
--- each snippet of the piano roll that has something to write at the
--- suggestion's place is offered, its notes as the ghost. Taking one
--- writes its notes as they are; its choices are for `<C-s>`. Not asked
--- after an idle pause: a snippet is chosen, not guessed.
M.source = {
  name = "snippets", priority = 10, views = { "pianoroll" }, auto = false,
  complete = function(ctx: CompleteModule.Context, done: function(items: {CompleteModule.ItemInput}))
    local items: {CompleteModule.ItemInput} = {}
    for _, spec in ipairs(M.offered("pianoroll")) do
      local ok, result = pcall(run, spec, { at = ctx.start + ctx.at, selection = false } as ContextOptions, {} as {string:integer})
      if ok and result and #result.notes > 0 then
        local notes: {CompleteModule.NoteInput} = {}
        local remove: {integer} = {}
        for i, n in ipairs(result.notes) do
          notes[i] = { pitch = n.pitch, start = (n.start or n.at) - ctx.start, length = n.length, velocity = n.velocity }
        end
        for _, n in ipairs(result.remove) do remove[#remove + 1] = n.place end
        items[#items + 1] = { label = spec.name, detail = spec.desc, notes = notes, remove = #remove > 0 and remove or nil }
      end
    end
    done(items)
  end,
}

local startup: events.Event<kernel.Nothing> = events.event("startup")
local escape: events.Event<kernel.Nothing> = events.event("escape")
local mode_changed: events.Event<ModeChanged> = events.event("mode.changed")

events.on(startup, function()
  if paw.complete then paw.complete.register(M.source) end
end)

events.on(escape, function() M.finish() end)
-- Another project (or a new one): nothing of this one's snippet is left.
events.on(kernel.project_loaded, function() M.finish() end)
events.on(mode_changed, function(e: ModeChanged)
  if e.old == "i" and e.mode == "n" then M.finish() end
  -- `:` typed over a selection: the command works on it.
  if e.mode == "c" then from_visual = e.old == "x" and paw.ui.focused == "pianoroll" and paw.keymap.selection() or nil end
end)

--- The selection the command line was opened over, once: what
--- `:snippet` works on.
function M.take_cmdline_selection(): contracts.Region
  local region = from_visual
  from_visual = nil
  return region
end

return M
