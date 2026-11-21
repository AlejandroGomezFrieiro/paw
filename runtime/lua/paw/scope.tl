-- Scopes: a view of a part of the song, as REAPER's subprojects let a large
-- project be worked on one section at a time, but with one project and one
-- undo tree. A scope is a set of tracks, a stretch of time, or both:
--
--   paw.scope.narrow("Strings")   -- a group and every track in it
--   paw.scope.narrow("Bridge")    -- a region: every track, in its time
--   paw.scope.enter({ kind = "range", tracks = { 3, 4 }, from = 64, to = 96 })
--   paw.scope.widen()             -- up one level; at the first, back to the tab it came from
--   paw.scope.current()           -- the scope shown, or nil for the song
--   paw.scope.tracks()            -- the tracks it shows, in order
--   paw.scope.span()              -- its time, `from, to` in beats, or nil for all of it
--
-- Scopes nest: a scope entered inside another is its child, and shows only
-- what both show (the strings in the bridge). Each level names its parent
-- (`scope.parent`), and what a scope shows is always its own part
-- intersected with its parent's, so that a group or a region that changes
-- changes the scopes made of it at once.
--
-- The scope is view state: entering and leaving change nothing in the
-- project and make no undo step. In this version a tab keeps the scope of
-- its windows; every read goes through `current(win)`, so that a window can
-- keep its own later.
--
-- In a scope with time, bars count from 1 at its start (`scopebars`); the
-- loop is its time while it is shown (`scopeloop`); the cursor stays in it.
-- What the tracks outside do is `paw.opt.scope_rest`: "play" (the
-- default), "mute", or "frozen": each part of the rest is rendered in the
-- background and played from its file, so that its devices rest (see
-- paw/freeze.lua). None of it touches the project.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local commands = require("paw.commands")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type LayoutModule = require("paw.layout")
local type GroupsModule = require("paw.groups")
local type VcaModule = require("paw.vca")
local type CursorModule = require("paw.cursor")
local type MarkersModule = require("paw.markers")
local type TextbufModule = require("paw.textbuf")
local type UiModule = require("paw.ui")

--- What a scope is made from. A group or a region scope follows its source:
--- a track added to the group, or the region moved, changes the scope.
local enum Kind
  "group" "track" "tracks" "region" "range"
end

--- A scope: what a view shows of the song. `id` is the group, track or
--- region it is made of; `tracks` a fixed list ("tracks", "range"), nil for
--- every track of the parent; `from` and `to` its time in beats ("range"),
--- nil for all the time of the parent. `parent` is the scope it was entered
--- from (nil: the song).
local record Scope
  kind: Kind
  id: integer
  tracks: {integer}
  from: number
  to: number
  name: string
  parent: Scope
end

--- What a tab keeps: the scope its windows show, the tab it was narrowed
--- from, and the loop that was set before the scope set its own.
local record Loop
  start: number
  stop: number
  enabled: boolean
end
local record ScopedTab
  name: string
  scope: Scope
  from: LayoutModule.Tab
  loop_was: Loop
end

--- A track, by its id or itself.
local type TrackRef = integer | contracts.TrackHandle

-- paw/routes.lua and paw/freeze.lua, still in Lua: the parts read here.
local record Routes
  reached: function(id: integer): {integer:boolean}
end
local type RenderOptions = {string: boolean | number | string}
local record Freeze
  state: function(id: integer): string
  render_opts: function(id: integer, opts: RenderOptions): RenderOptions
end
local record Frontend
  refresh: function()
end
local record Paw is partial.Paw
  ui: UiModule
  layout: LayoutModule
  groups: GroupsModule
  vca: VcaModule
  cursor: CursorModule
  markers: MarkersModule
  textbuf: TextbufModule
  routes: Routes
  freeze: Freeze
  frontend: Frontend
  time: objects.Time
  transport: objects.Transport
  emit: function(name: string, payload: events.Payload)
  render: function(path: string, opts: RenderOptions)
end
local paw = (_G as {string:Paw}).paw

local record M
  type Scope = Scope
  type Kind = Kind
end

local opt = options.opt
options.define("scope_rest", "play", { values = { "play", "mute", "frozen" } }) -- what the tracks outside a scope do: "play", "mute" or "frozen"
options.define("scopebars", "both", { values = { "local", "song", "both" } }) -- bar numbers in a scope with time: "local" (from 1 at its start), "song", or "both" (local, and the song's on a second ruler row)
options.define("scopeloop", true) -- entering a scope with time loops its time

--- The payload of `scope.changed`: the group of the scope, if any.
local record Changed
  scope: integer
end
local changed: events.Event<Changed> = events.event("scope.changed")
--- `track.added`, which says whether undo or a load put the track back.
local record Added
  id: integer
  restored: boolean
end
local added: events.Event<Added> = events.event("track.added")
local record Option
  name: string
end
local option_changed: events.Event<Option> = events.event("option.changed")
local tab_enter: events.Event<events.Payload> = events.event("tab.enter")
local render_done: events.Event<kernel.RenderEnd> = events.event("render.done")

local function L(): LayoutModule return paw.layout end
local function groups(): GroupsModule return paw.groups end

local function id_of(track: TrackRef): integer
  if track is contracts.TrackHandle then return track.id end
  return track
end

local function exists(id: integer): boolean return id ~= nil and (pcall(api.track_get, id)) end

local function name_of(id: integer): string return (api.track_get as function(integer, string): string)(id, "name") end

local function region(id: integer): MarkersModule.Marker
  local m = paw.markers and paw.markers.find({ id = id })
  if m and m.length then return m end
end

--- Whether the source of one level is still there.
local function valid(s: Scope): boolean
  if s.kind == "group" then return exists(s.id) and groups().is_group(s.id) end
  if s.kind == "track" then return exists(s.id) end
  if s.kind == "region" then return region(s.id) ~= nil end
  return true
end

--- The tab that holds a window (the current tab without one).
local function tab_of(win?: LayoutModule.Node): ScopedTab
  if win then
    for _, tw in ipairs(L().all_windows()) do
      if tw.win == win then return paw.ui.tabs[tw.tab] as ScopedTab end
    end
  end
  return L().tab() as ScopedTab
end

--- The scope a window shows (the current window's by default), or nil for
--- the song. A level whose group, track or region is gone is left out.
function M.current(win?: LayoutModule.Node): Scope
  local t = tab_of(win)
  local s = t and t.scope
  while s and not valid(s) do s = s.parent end
  return s
end

--- The scope of a tab, for the frontends that draw each tab.
function M.of_tab(tab: LayoutModule.Tab): Scope
  local s = (tab as ScopedTab).scope
  while s and not valid(s) do s = s.parent end
  return s
end

--- The innermost group of a scope's path (the current scope by default):
--- what a narrowed tab's tracks are shown under. Nil when no level is a group.
function M.group(s?: Scope): integer
  s = s or M.current()
  while s do
    if s.kind == "group" and valid(s) then return s.id end
    s = s.parent
  end
end

--- Whether one level, alone, shows a track.
local function own_contains(s: Scope, id: integer): boolean
  if s.kind == "group" then
    local at, steps = id, 0
    while at and steps < 32 do
      if at == s.id then return true end
      at, steps = groups().of(at), steps + 1
    end
    return false
  elseif s.kind == "track" then
    return id == s.id
  elseif s.tracks then
    for _, other in ipairs(s.tracks) do
      if other == id then return true end
    end
    return false
  end
  return true
end

--- A scope as given: a scope, a group's id, or nil for the current one.
local function resolve(s: Scope | integer): Scope
  if s is integer then return { kind = "group", id = s } end
  return s or M.current()
end

--- True if a scope (the current one by default; a group's id is a scope
--- of that group) shows a track: it and every level above it do. With no
--- scope, every track is inside.
function M.contains(track: TrackRef, s?: Scope | integer): boolean
  local scope = resolve(s)
  local id = id_of(track)
  while scope do
    if valid(scope) and not own_contains(scope, id) then return false end
    scope = scope.parent
  end
  return true
end

--- True if a scope, or one of the levels above it, limits the tracks.
function M.limits_tracks(s?: Scope | integer): boolean
  local scope = resolve(s)
  while scope do
    if scope.kind ~= "region" and not (scope.kind == "range" and not scope.tracks) then return true end
    scope = scope.parent
  end
  return false
end

--- The tracks of a scope (the current one by default), in the order of the
--- track list. With no scope, or one that keeps every track, all tracks.
function M.tracks(s?: Scope | integer): {integer}
  local scope = resolve(s)
  local list = api.track_list()
  if not (scope and M.limits_tracks(scope)) then return list end
  local out: {integer} = {}
  for _, id in ipairs(list) do
    if M.contains(id, scope) then out[#out + 1] = id end
  end
  return out
end

--- One level's own time, or nil for all of it.
local function own_span(s: Scope): number, number
  if s.kind == "region" then
    local m = region(s.id)
    if m then return m.beat, m.beat + m.length end
  elseif s.from and s.to then
    return s.from, s.to
  end
end

--- The time a scope shows (the current one by default): `from, to` in
--- beats, its own time intersected with its parent's. Nil when it shows all
--- of the song's time. `from` is `to` when the times do not meet.
function M.span(s?: Scope | integer): number, number
  local scope = resolve(s)
  local from, to: number, number = nil, nil
  while scope do
    local a, b = own_span(scope)
    if a and valid(scope) then
      from = from and math.max(from, a) or a
      to = to and math.min(to, b) or b
    end
    scope = scope.parent
  end
  if from then return from, math.max(from, to) end
end

--- The levels of a scope's path, from the outermost to it.
function M.path(s?: Scope): {Scope}
  local out: {Scope} = {}
  local at = s or M.current()
  while at do
    if valid(at) then table.insert(out, 1, at) end
    at = at.parent
  end
  return out
end

--- The path in words: `Song › Bridge › Strings`.
function M.breadcrumb(s?: Scope): string
  local names = { "Song" }
  for _, level in ipairs(M.path(s)) do names[#names + 1] = level.name end
  return table.concat(names, " › ")
end

-- Bars --------------------------------------------------------------------------------

--- How many bars of the song come before the first bar of a scope (the
--- current one by default) when its bars are numbered from 1: 0 with no
--- time, or with `scopebars=song`. A scope's bars are the song's (its meter
--- map), counted from the bar its time starts in.
function M.bar_offset(s?: Scope): integer
  if opt.scopebars == "song" then return 0 end
  local from = M.span(s)
  if not from then return 0 end
  return paw.time.bar_of(from) - 1
end

--- The bar the current scope shows for a bar of the song.
function M.local_bar(song_bar: integer): integer return song_bar - M.bar_offset() end

--- The bar of the song for a bar as the current scope shows it.
function M.song_bar(local_bar: integer): integer return local_bar + M.bar_offset() end

--- A place as the scope numbers it: `bar.beat.hundredths`, as `paw.time.format`.
function M.format(beat: number): string
  local bar, b, frac = api.tempo_bbt(beat)
  local part = math.floor(frac * 100 + 0.5)
  if part >= 100 then part = 99 end
  return string.format("%d.%d.%02d", bar + 1 - M.bar_offset(), b + 1, part)
end

-- Entering and leaving -------------------------------------------------------------------

--- A group by its id, its track, or its name (or part of it).
function M.find(which: TrackRef | string): integer
  if which == nil then return nil end
  local id: integer
  if which is string then
    id = math.tointeger(tonumber(which))
  else
    id = id_of(which)
  end
  if id then return groups().is_group(id) and id or nil end
  local wanted = (which as string):lower()
  local partial_match: integer
  for _, other in ipairs(api.track_list()) do
    if groups().is_group(other) then
      local name = name_of(other):lower()
      if name == wanted then return other end
      if not partial_match and name:find(wanted, 1, true) then partial_match = other end
    end
  end
  return partial_match
end

--- The group of a track when you narrow: the track itself if it is a group.
--- If not, the group that contains it.
function M.group_at(track: TrackRef): integer
  if not track then return nil end
  local id = id_of(track)
  if groups().is_group(id) then return id end
  return groups().of(id)
end

--- A scope by name: a group of that name, else a region of that name, else
--- a group or a region whose name starts with it. A number is a group's id.
function M.named(which: string | integer): Scope
  if which is integer then
    return groups().is_group(which) and { kind = "group", id = which, name = name_of(which) } or nil
  end
  local wanted = (which as string):lower()
  local regions = paw.markers and paw.markers.regions() or {}
  for _, id in ipairs(api.track_list()) do
    if groups().is_group(id) and name_of(id):lower() == wanted then return { kind = "group", id = id, name = name_of(id) } end
  end
  for _, m in ipairs(regions) do
    if m.name:lower() == wanted then return { kind = "region", id = m.id, name = m.name } end
  end
  local g = M.find(which)
  if g then return { kind = "group", id = g, name = name_of(g) } end
  for _, m in ipairs(regions) do
    if m.name:lower():find(wanted, 1, true) == 1 then return { kind = "region", id = m.id, name = m.name } end
  end
end

--- The name a scope shows when it has none.
local function name_for(s: Scope): string
  if s.name then return s.name end
  if (s.kind == "group" or s.kind == "track") and exists(s.id) then return name_of(s.id) end
  if s.kind == "region" then
    local m = region(s.id)
    return m and m.name
  end
  return s.kind == "tracks" and (#s.tracks .. " tracks") or "Range"
end

local function same(a: Scope, b: Scope): boolean
  if a == b then return true end
  if not (a and b) then return false end
  if a.kind ~= b.kind or a.id ~= b.id or a.from ~= b.from or a.to ~= b.to then return false end
  if table.concat(a.tracks or {}, ",") ~= table.concat(b.tracks or {}, ",") then return false end
  return same(a.parent, b.parent)
end

--- Put the cursor inside the current scope: on its first track when it is
--- on one outside, and in its time.
local function cursor_inside()
  local s = M.current()
  if not s then return end
  local cursor = paw.cursor
  local at = cursor.track_id()
  if not (at and M.contains(at)) then
    local first = M.tracks()[1]
    if first then cursor.set_track(first) end
  end
  local from, to = M.span()
  if from and (cursor.beat < from or cursor.beat > to) then cursor.set_beat(from) end
end

--- The loop of a scope with time, while its tab is in front (`scopeloop`):
--- what was set before is kept, to come back when the scope is left.
local function loop_in(t: ScopedTab)
  local from, to = M.span(t.scope)
  if not (from and to > from and opt.scopeloop) then return end
  local tr = paw.transport
  t.loop_was = t.loop_was or { start = tr.loop_start, stop = tr.loop_end, enabled = tr.loop_enabled }
  tr.loop_start, tr.loop_end, tr.loop_enabled = from, to, true
end

local function loop_out(t: ScopedTab)
  local was = t.loop_was
  if not was then return end
  t.loop_was = nil
  local tr = paw.transport
  tr.loop_start, tr.loop_end, tr.loop_enabled = was.start, was.stop, was.enabled
end

--- Show a scope in the current tab, in place of the one it shows.
local function show(t: ScopedTab, s: Scope)
  loop_out(t)
  t.scope = s
  t.name = s and s.name or nil
  if not s then t.from = nil end
  loop_in(t)
  events.emit(changed, { scope = M.group(s) })
  cursor_inside()
  api.ui_redraw()
end

--- Why a scope inside another would show nothing, or nil.
local function empty_inside(s: Scope): string
  local tracks = M.tracks(s)
  if #tracks == 0 then return string.format("no track of %s is in %s", s.name, s.parent.name) end
  local from, to = M.span(s)
  if from and to <= from then return string.format("%s and %s have no time in common", s.name, s.parent.name) end
end

--- Enter a scope (`{ kind, id, tracks, from, to, name }`). In a tab that
--- shows a scope, it becomes its child, in the same tab: it shows what both
--- show. In a tab that shows the song, a tab of its own opens after it, or
--- the tab that shows the same scope comes to the front. Changes nothing in
--- the project. Returns the scope.
function M.enter(spec: Scope): Scope
  assert(spec and spec.kind, "a scope has a kind")
  local s: Scope = {
    kind = spec.kind, id = spec.id, tracks = spec.tracks, from = spec.from, to = spec.to, name = spec.name,
  }
  if not valid(s) then error("no " .. s.kind .. " " .. tostring(s.id), 0) end
  if s.kind == "range" and s.from and not (s.to and s.to > s.from) then error("a range ends after it starts", 0) end
  s.name = name_for(s)
  local t = L().tab() as ScopedTab
  local here = M.current()
  -- A tab that shows this scope at its first level comes to the front.
  local function shown_in_tab(): boolean
    for i, other in ipairs(paw.ui.tabs) do
      if same(M.of_tab(other), s) then
        L().tab_go(i)
        return true
      end
    end
    return false
  end
  if here then
    if here.kind == s.kind and here.id ~= nil and here.id == s.id then return here end
    s.parent = here
    local why = empty_inside(s)
    if why then
      s.parent = nil
      if shown_in_tab() then return s end
      error(why, 0)
    end
    show(t, s)
    return s
  end
  if shown_in_tab() then return s end
  local from = t as LayoutModule.Tab
  local nt = L().tab_copy(s.name) as ScopedTab
  nt.from = from
  show(nt, s)
  return s
end

--- Narrow to a group or a region, by its id, its track or its name (see
--- `named`): `enter` of that scope. Returns the tab it shows in.
function M.narrow(which: TrackRef | string): LayoutModule.Tab
  local s: Scope
  if which is string then
    s = M.named(which)
  elseif which ~= nil then
    local g = M.find(which)
    s = g and { kind = "group", id = g, name = name_of(g) } or nil
  end
  if not s then error(which == nil and "not in a group" or ("no group or region `" .. tostring(which) .. "`"), 0) end
  M.enter(s)
  return L().tab()
end

--- Leave the scope of the current tab: up one level, or with `top` to the
--- song. Leaving the first level closes the tab and shows the tab it was
--- narrowed from again; when it is the last tab, it stays, wide. False when
--- the tab shows the song.
function M.widen(top?: boolean): boolean
  local u = paw.ui
  local t = L().tab() as ScopedTab
  local s = M.current()
  if not s then return false end
  if s.parent and not top then
    show(t, s.parent)
    return true
  end
  local back = t.from
  loop_out(t)
  if not L().tab_close(u.tab) then
    show(t, nil)
  elseif back then
    for i, other in ipairs(u.tabs) do
      if other == back then L().tab_go(i) end
    end
  end
  api.ui_redraw()
  return true
end

-- A tab follows its scope's name. A tab whose scope is taken away is wide again.
events.on(kernel.track_changed, function(event: kernel.TrackId)
  for _, tab in ipairs(paw.ui.tabs) do
    local s = (tab as ScopedTab).scope
    if s and s.kind ~= "region" and s.kind ~= "range" and s.id == event.id and exists(event.id) then
      s.name = name_of(event.id)
      tab.name = s.name
    end
  end
end)
events.on(kernel.track_removed, function(event: kernel.TrackId)
  for _, tab in ipairs(paw.ui.tabs) do
    local t = tab as ScopedTab
    if t.scope and not M.of_tab(tab) then t.scope, t.from, t.name = nil, nil, nil end
    if t.scope and t.scope.kind == "group" and t.scope.id == event.id then t.name = nil end
  end
end)

-- A track added in a scope of a group goes into the group, so that it stays
-- in sight (undo and opening a project put tracks back where they were).
events.on(added, function(event: Added)
  if event.restored or not exists(event.id) then return end
  local g = M.group()
  if g and not M.contains(event.id) and not paw.vca.is_vca(event.id) then
    pcall(groups().add, event.id, g)
  end
end)

-- The rest of the song ---------------------------------------------------------------

--- A part of the rest rendered in the background: its file, and the
--- generation of the edits it was made from.
local record Held
  file: string
  gen: integer
end
local record Pending
  id: integer
  gen: integer
end
local record Applied
  scope: Scope
  audible: string
  hold: {integer:string}
end
local held: {integer:Held} = {}
local pending: {string:Pending} = {}
-- Edits since the start, by track: a part of the rest whose tracks are
-- edited is rendered again.
local gens: {integer:integer} = {}
local applied: Applied = { hold = {} }  -- what the engine was last told
local made = 0      -- files rendered, for their names

local function held_dir(): string
  local dir = api.env().data_dir .. "/paw/held"
  pcall(api.fs_mkdir, dir)
  return dir
end

--- The parts of the rest of the song that paw can freeze for a scope. These
--- are the tracks outside it at the top of their branch (a whole group, not
--- its members). They are not the tracks that the sound of the scope goes
--- through (its groups, and a bus that its sends reach). They are not empty.
function M.rest_parts(s?: Scope | integer): {integer}
  local scope = resolve(s)
  if not (scope and M.limits_tracks(scope)) then return {} end
  local inside: {integer:boolean} = {}
  for _, id in ipairs(M.tracks(scope)) do inside[id] = true end
  -- The scope's groups and wherever its sound goes carry it: they play live.
  local carries: {integer:boolean} = {}
  local lineage: {integer:boolean} = {}
  for id in pairs(inside) do
    for to in pairs(paw.routes.reached(id)) do carries[to] = true end
    local at = groups().of(id)
    while at and not inside[at] do
      lineage[at] = true
      at = groups().of(at)
    end
  end
  local function sounds(id: integer): boolean
    if #api.clip_list(id) > 0 then return true end
    for _, member in ipairs(groups().members(id)) do
      if sounds(member) then return true end
    end
    return false
  end
  local out: {integer} = {}
  for _, id in ipairs(api.track_list()) do
    local parent = groups().of(id)
    local top = parent == nil or lineage[parent]
    if top and not inside[id] and not lineage[id] and not carries[id] and not paw.vca.is_vca(id)
      and not paw.freeze.state(id) and sounds(id) then
      out[#out + 1] = id
    end
  end
  return out
end

local function gen_of(track: integer): integer
  -- A part's generation counts the edits of every track inside it.
  local n = gens[track] or 0
  for _, member in ipairs(groups().members(track)) do n = n + gen_of(member) end
  return n
end

--- Render a part of the rest in the background, unless it is being rendered.
local function render_part(id: integer)
  for _, p in pairs(pending) do
    if p.id == id then return end
  end
  made = made + 1
  local path = string.format("%s/%d-%d-%d.wav", held_dir(), api.env().pid, id, made)
  pending[path] = { id = id, gen = gen_of(id) }
  local ok, err = pcall(paw.render, path, paw.freeze.render_opts(id, { background = true })) as (boolean, string)
  if not ok then
    pending[path] = nil
    paw.notify("could not freeze " .. name_of(id) .. " for the scope: " .. tostring(err), "warn")
  end
end

--- Tell the engine what the rest of the song does for a scope. This is the
--- scope of the tab in front, which the last seat to change tabs (a
--- terminal or a window) selected.
function M.apply(s?: Scope | integer)
  local scope: Scope = s is integer and resolve(s) or s as Scope
  if scope and not valid(scope) then scope = nil end
  applied.scope = scope
  local rest = opt.scope_rest
  local narrowed = scope and M.limits_tracks(scope)
  local tracks = narrowed and M.tracks(scope) or nil
  local audible = tracks and rest == "mute" and table.concat(tracks, ",") or nil
  if audible ~= applied.audible then
    api.engine_audible(audible and tracks or nil)
    applied.audible = audible
  end
  local want: {integer:string} = {}
  if narrowed and rest == "frozen" then
    for _, id in ipairs(M.rest_parts(scope)) do
      local h = held[id]
      if h and h.gen == gen_of(id) then
        want[id] = h.file
      else
        render_part(id)
      end
    end
  end
  for id, file in pairs(applied.hold) do
    if want[id] ~= file then
      if exists(id) then pcall(api.engine_hold, id, nil) end
      applied.hold[id] = nil
    end
  end
  for id, file in pairs(want) do
    if applied.hold[id] ~= file then
      api.engine_hold(id, file)
      applied.hold[id] = file
    end
  end
end

--- The parts of the rest the engine plays from files now.
function M.held(): {integer}
  local out: {integer} = {}
  for id in pairs(applied.hold) do out[#out + 1] = id end
  table.sort(out)
  return out
end

events.on(render_done, function(info: kernel.RenderEnd)
  local p = pending[info.path]
  if not p then return end
  pending[info.path] = nil
  local old = held[p.id]
  if old and old.file ~= info.path then os.remove(old.file) end
  held[p.id] = { file = info.path, gen = p.gen }
  M.apply(applied.scope)
end)
for _, ev in ipairs({ kernel.render_failed, kernel.render_cancelled }) do
  events.on(ev, function(info: kernel.RenderEnd)
    if info.path then pending[info.path] = nil else pending = {} end
  end)
end

-- An edit to a track makes what was rendered of it out of date.
local function touched(event: kernel.Item)
  local id = event.track or event.id
  if not id then return end
  gens[id] = (gens[id] or 0) + 1
end
for _, ev in ipairs({ kernel.clip_added, kernel.clip_changed, kernel.clip_removed, kernel.device_added, kernel.device_changed,
    kernel.device_removed, kernel.lane_added, kernel.lane_changed, kernel.lane_removed }) do
  events.on(ev, touched)
end

--- Lists edited as text read what the tab in front sees: read them again
--- (one with changes not written is marked as behind instead).
local function reread()
  for _, buf in pairs(L().buffers) do
    local tb = buf as TextbufModule.TextBuffer
    if tb.type == "textbuf" and tb.state and tb.state.kind then
      tb.state.seen = nil
      paw.textbuf.sync(tb)
    end
  end
end

--- Everything that shows tracks catches up with the tab in front: lists
--- edited as text, a graphical frontend's state, the engine, the loop.
local function follow()
  cursor_inside()
  reread()
  paw.frontend.refresh()
  M.apply(M.current())
end
events.on(tab_enter, function()
  -- The loop is the scope's while its tab is in front.
  for _, tab in ipairs(paw.ui.tabs) do
    if tab ~= L().tab() then loop_out(tab as ScopedTab) end
  end
  loop_in(L().tab() as ScopedTab)
  follow()
end)
events.on(changed, follow)
events.on(option_changed, function(e: Option)
  if e.name == "scope_rest" then M.apply(M.current()) end
end)
-- Tracks that come, go or change places change what the rest is.
local function again()
  if applied.scope and opt.scope_rest ~= "play" then M.apply(applied.scope) end
end
events.on(kernel.track_added, again)
events.on(kernel.track_removed, again)
events.on(kernel.track_moved, again)
events.on(kernel.clip_added, again)
events.on(kernel.clip_removed, again)
-- Another project: nothing of the last one is held.
events.on(kernel.project_loaded, function()
  held, pending, gens = {}, {}, {}
  for _, tab in ipairs(paw.ui.tabs) do
    local t = tab as ScopedTab
    t.scope, t.loop_was = nil, nil
  end
  applied = { hold = {} }
  api.engine_audible(nil)
  for _, id in ipairs(api.engine_held()) do pcall(api.engine_hold, id, nil) end
end)

--- The time the cursor stays in: the current scope's.
paw.cursor.bounds = function(): number, number return M.span() end

-- The song's bars on the ruler's second row -------------------------------------------

--- What a layer of the arrange view gets (paw/views/arrange.lua).
local record Layer
  ruler2: contracts.Buf
  x: function(beat: number): integer
  scroll: number
  span: number
end
local record Arrange
  layers: {string: function(view: Arrange, layer: Layer)}
  ruler2: {string: function(view: Arrange): boolean}
end

--- Whether the ruler shows the song's bars under the scope's: in a scope
--- with time, with `scopebars=both`.
local function song_row(): boolean
  return opt.scopebars == "both" and M.span() ~= nil and M.bar_offset() ~= 0
end

local arrange = paw.ui.views.arrange as Arrange
if arrange and arrange.layers then
  arrange.ruler2.scope_bars = song_row
  -- Under each bar's local number, its number in the song. Layers draw in
  -- the order of their names: this one after the markers' bands, and
  -- clear of the names of markers and regions.
  arrange.layers.zz_scope_bars = function(_: Arrange, layer: Layer)
    if not (song_row() and layer.ruler2) then return end
    local row = layer.ruler2
    local taken: {{integer}} = {}
    for _, m in ipairs(paw.markers and paw.markers.list() or {}) do
      local x = layer.x(m.beat)
      taken[#taken + 1] = { x, x + api.str_width(paw.markers.label(m)) + 1 }
    end
    local function clear(a: integer, b: integer): boolean
      for _, t in ipairs(taken) do
        if a < t[2] and b > t[1] then return false end
      end
      return true
    end
    local free = 0
    for _, line in ipairs(paw.time.bars(layer.scroll, layer.scroll + layer.span)) do
      local x = layer.x(line.beat)
      local text = tostring(line.bar)
      if x >= free and x >= 0 and x < row.width and clear(x, x + #text + 1) then
        free = x + row:text(x, 0, text, "RulerTick") + 1
      end
    end
  end
end

-- Commands -----------------------------------------------------------------------------

local function scope_names(): {string}
  local out: {string} = {}
  for _, id in ipairs(api.track_list()) do
    if groups().is_group(id) then out[#out + 1] = name_of(id) end
  end
  for _, m in ipairs(paw.markers and paw.markers.regions() or {}) do
    if m.name ~= "" then out[#out + 1] = m.name end
  end
  return out
end

commands.define("narrow", function(ctx: contracts.CommandContext): contracts.CommandResult
  local which = ctx.args[1]
  local s: Scope
  if which == nil or which == true then
    local g = M.group_at(paw.cursor.track_id())
    if not g then
      paw.notify("not in a group: `:narrow` takes a group or a region by name", "warn")
      return
    end
    s = { kind = "group", id = g, name = name_of(g) }
  else
    s = M.named(table.concat(ctx.args as {string}, " "))
    if not s then
      paw.notify("no group or region `" .. tostring(which) .. "`", "warn")
      return
    end
  end
  local ok, err = pcall(function() M.enter(s) end) as (boolean, string)
  if not ok then
    paw.notify(tostring(err), "warn")
    return
  end
  local from, to = M.span()
  local bars = from and string.format(", bars %d-%d", paw.time.bar_of(from), paw.time.bar_of(math.max(from, to - 1e-6))) or ""
  paw.notify(string.format("%s: %d tracks%s · `:widen` or `zw` goes back", M.breadcrumb(), #M.tracks(), bars))
end, { desc = "Show only a group's tracks or a region's time: `narrow Strings`, `narrow Bridge`; alone, the group at the cursor. Inside a scope, the new one is inside it", complete = scope_names })

local function widen(top: boolean)
  if not M.widen(top) then
    paw.notify("this tab shows the whole song", "warn")
    return
  end
  local s = M.current()
  paw.notify(s and M.breadcrumb(s) or "the whole song")
end
commands.define("widen", function(): contracts.CommandResult widen(false) end,
  { desc = "Up one level of scope; at the first, close the narrowed tab and go back to the one it was narrowed from" })
commands.define("widen!", function(): contracts.CommandResult widen(true) end,
  { desc = "Leave every level of scope: show the whole song" })

return M
