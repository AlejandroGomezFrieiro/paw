-- Scopes: a view of a part of the song, as REAPER's subprojects let a large
-- project be worked on one section at a time, but with one project and one
-- undo tree. A scope is a set of tracks, a stretch of time, or both:
--
--   paw.scope.narrow("Strings")   -- a group and every track in it
--   paw.scope.narrow("Bridge")    -- a region: every track, in its time
--   paw.scope.enter({ kind = "range", tracks = { 3, 4 }, from = 64, to = 96 })
--   paw.scope.widen()             -- up one level; `widen(true)` up to the song
--   paw.scope.next(1)             -- the next scope beside this one (`]z`)
--   paw.scope.current()           -- the scope shown, or nil for the song
--   paw.scope.tracks()            -- the tracks it shows, in order
--   paw.scope.span()              -- its time, `from, to` in beats, or nil for all of it
--
-- A scope belongs to a window, as Vim's folds do: each window keeps its
-- scope stack (`win.scope`, each level naming its parent), so that a split
-- shows the song beside the bridge. A split starts with the scope of the
-- window it is split from. What a view shows while it draws is the scope
-- of the window it draws (`paw.ui.drawing_win`); everything else reads the
-- scope of the current window. The tab is named after the scope of its
-- current window. The project's screen (`screen.json`) keeps the stacks.
--
-- Scopes nest: a scope entered inside another is its child, and shows only
-- what both show (the strings in the bridge). What a scope shows is always
-- its own part intersected with its parent's, so that a group or a region
-- that changes changes the scopes made of it at once.
--
-- The scope is view state: entering and leaving change nothing in the
-- project and make no undo step. Entering, leaving and `]z` are jumps:
-- `<C-o>` comes back into the scope and to the place (paw/keymap.lua).
--
-- In a scope with time, bars count from 1 at its start (`scopebars`); the
-- loop is its time while its window is in front (`scopeloop`); the cursor
-- stays in it. What the tracks outside do is `paw.opt.scope_rest`: "play"
-- (the default), "mute", or "frozen": each part of the rest is rendered in
-- the background and played from its file, so that its devices rest (see
-- paw/freeze.lua). None of it touches the project.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local commands = require("paw.commands")
local type types = require("paw.types")
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

local type Scope = contracts.Scope
local type Kind = contracts.ScopeKind
local type Window = contracts.Window
local type Node = LayoutModule.Node

--- The loop that was set before a scope set its own.
local record Loop
  start: number
  stop: number
  enabled: boolean
end

--- A track, by its id or itself.
local type TrackRef = integer | contracts.TrackHandle

-- paw/routes.lua and paw/freeze.lua, still in Lua: the parts read here.
local record Routes
  reached: function(id: integer): {integer: boolean}
end
local type RenderOptions = {string: boolean | number | string}
local record Freeze
  state: function(id: integer): string
  render_opts: function(id: integer, opts: RenderOptions): RenderOptions
end
local record Frontend
  refresh: function()
end
--- The key mappings (paw/keymap.lua, in Lua): what this module calls of them.
local record Keymap
  push_jump: function()
end
--- What `paw.ui.input` takes.
local record InputOptions
  prompt: string
  text: string
  label: string
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
local paw = (_G as {string: Paw}).paw

--- An entry of the scope picker (`<leader>zz`): a scope to enter, or a
--- level of the window's stack to go back up to (`level`, nil `scope` for
--- the song).
local record Item
  scope: Scope
  level: boolean
  kind: string
  label: string
end

local record M
  type Scope = Scope
  type Kind = Kind
  type Item = Item
  source: contracts.PickSource<Item>
end

local opt = options.opt
options.define(
  "scope_rest", "play", {values = {"play", "mute", "frozen"}}
) -- what the tracks outside a scope do: "play", "mute" or "frozen"
options.define(
  "scopebars", "both", {values = {"local", "song", "both"}}
) -- bar numbers in a scope with time: "local" (from 1 at its start), "song", or "both" (local, and the song's on a second ruler row)
options.define("scopeloop", true) -- entering a scope with time loops its time while its window is in front

--- The payload of `scope.changed`: the window, and the group of its scope if any.
local record Changed
  scope: integer
  win: integer
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
local record WinEvent
  win: integer
end
local win_enter: events.Event<WinEvent> = events.event("win.enter")
local render_done: events.Event<kernel.RenderEnd> = events.event("render.done")

local function L(): LayoutModule
  return paw.layout
end
local function groups(): GroupsModule
  return paw.groups
end
local function keymap(): Keymap
  return paw.keymap as Keymap
end

local function id_of(track: TrackRef): integer
  if track is contracts.TrackHandle then
    return track.id
  end
  return track
end

local function exists(id: integer): boolean
  return id ~= nil and (pcall(api.track_get, id))
end

local function name_of(id: integer): string
  return (api.track_get as function(integer, string): string)(id, "name")
end

--- A track's subproject, or nil for a track of the song (one field: quick).
local nest_field = api.track_get as function(id: integer, key: string): integer
local function nest_of(id: integer): integer
  local ok, nest = pcall(nest_field, id, "nest") as (boolean, integer)
  return ok and nest or nil
end

local nest_get = api.nest_get as function(id: integer, key: string): string | number
local function nest_exists(id: integer): boolean
  for _, other in ipairs(api.nest_list()) do
    if other == id then
      return true
    end
  end
  return false
end

local function region(id: integer): MarkersModule.Marker
  local m = paw.markers and paw.markers.find({id = id})
  if m and m.length then
    return m
  end
end

--- Whether the source of one level is still there.
local function valid(s: Scope): boolean
  if s.kind == "group" then
    return exists(s.id) and groups().is_group(s.id)
  end
  if s.kind == "track" then
    return exists(s.id)
  end
  if s.kind == "region" then
    return region(s.id) ~= nil
  end
  if s.kind == "nest" then
    return nest_exists(s.id)
  end
  return true
end

--- The views whose windows keep a scope stack of their own. A window of
--- another view (the mixer, the device panel, the piano roll) shows the
--- scope of the arrange window of its tab that had the keyboard last.
local own_views: {string: boolean} = {arrange = true}

--- The window that keeps the scope stack a window shows.
local function owner(w: Window): Window
  if not w or own_views[w.view] then
    return w
  end
  local u = paw.ui
  local order = {u.tab}
  for i = 1, #u.tabs do
    if i ~= u.tab then
      order[#order + 1] = i
    end
  end
  for _, i in ipairs(order) do
    local t = u.tabs[i]
    if t and L().find_id(t.layout, w.id) then
      local id = t.last and t.last.arrange
      local found: Window = id and L().find_id(t.layout, id)
      if not (found and found.view == "arrange") then
        found = L().find(t.layout, "arrange")
      end
      return found or w
    end
  end
  return w
end

--- The window whose scope is meant when reading: the one given, else the
--- one being drawn, else the current one; its stack's keeper.
local function window_of(win?: Window): Window
  return owner(win or paw.ui.drawing_win or L().current())
end

--- The window whose scope an action changes: the one given, else the
--- current one; its stack's keeper.
local function holder(win?: Window): Window
  return owner(win or L().current())
end

--- A level, or the first level above it whose source is still there.
local function live(s: Scope): Scope
  while s and not valid(s) do
    s = s.parent
  end
  return s
end

--- The scope a window shows, or nil for the song: the window given, else
--- the window being drawn, else the current one. A level whose group,
--- track or region is gone is left out.
function M.current(win?: Window): Scope
  local w = window_of(win)
  return w and live(w.scope)
end

--- The window of a tab that has the keyboard there.
local function tab_window(tab: LayoutModule.Tab): Window
  return tab.win and L().find_id(tab.layout, tab.win) or L().windows(tab.layout)[1]
end

--- The scope of a tab: that of its current window.
function M.of_tab(tab: LayoutModule.Tab): Scope
  local win = tab_window(tab)
  return win and M.current(win)
end

--- The innermost group of a scope's path (the current scope by default):
--- what a narrowed window's tracks are shown under. Nil when no level is a group.
function M.group(s?: Scope): integer
  s = s or M.current()
  while s do
    if s.kind == "group" and valid(s) then
      return s.id
    end
    s = s.parent
  end
end

--- Whether one level, alone, shows a track.
local function own_contains(s: Scope, id: integer): boolean
  if s.kind == "group" then
    local at, steps = id, 0
    while at and steps < 32 do
      if at == s.id then
        return true
      end
      at, steps = groups().of(at), steps + 1
    end
    return false
  elseif s.kind == "track" then
    return id == s.id
  elseif s.kind == "nest" then
    return nest_of(id) == s.id
  elseif s.tracks then
    for _, other in ipairs(s.tracks) do
      if other == id then
        return true
      end
    end
    return false
  end
  return true
end

--- A scope as given: a scope, a group's id, or nil for the current one.
local function resolve(s: Scope | integer): Scope
  if s is integer then
    return {kind = "group", id = s}
  end
  return s or M.current()
end

--- True if a scope (the current one by default; a group's id is a scope
--- of that group) shows a track: it and every level above it do. With no
--- scope, every track is inside.
function M.contains(track: TrackRef, s?: Scope | integer): boolean
  local scope = resolve(s)
  local id = id_of(track)
  while scope do
    if valid(scope) and not own_contains(scope, id) then
      return false
    end
    if scope.kind == "nest" and valid(scope) then
      -- A subproject's tracks are its own: the levels above it show the song's.
      return true
    end
    scope = scope.parent
  end
  -- The song shows its own tracks, not those of a subproject.
  return id == 0 or nest_of(id) == nil
end

--- The innermost subproject of a scope's path (the current scope by
--- default), or nil when the path is in the song: its tracks and its
--- timeline are what the window shows.
function M.nest(s?: Scope | integer): Scope
  local scope = resolve(s)
  while scope do
    if scope.kind == "nest" and valid(scope) then
      return scope
    end
    scope = scope.parent
  end
end

--- True if a scope, or one of the levels above it, limits the tracks.
function M.limits_tracks(s?: Scope | integer): boolean
  local scope = resolve(s)
  while scope do
    if scope.kind ~= "region" and not (scope.kind == "range" and not scope.tracks) then
      return true
    end
    scope = scope.parent
  end
  return false
end

--- Whether a level below the innermost subproject (or below the song)
--- limits the tracks: else the scope shows all of that place's tracks.
local function limits_inside(scope: Scope): boolean
  while scope and scope.kind ~= "nest" do
    if scope.kind ~= "region" and not (scope.kind == "range" and not scope.tracks) then
      return true
    end
    scope = scope.parent
  end
  return false
end

--- The tracks of a scope (the current one by default), in the order of the
--- track list. With no scope, or one that keeps every track, all tracks of
--- the song; in a subproject, its tracks.
function M.tracks(s?: Scope | integer): {integer}
  local scope = resolve(s)
  local nest = M.nest(scope)
  local list = nest and api.track_list({nest = nest.id}) or api.track_list()
  if not (scope and limits_inside(scope)) then
    return list
  end
  local out: {integer} = {}
  for _, id in ipairs(list) do
    if M.contains(id, scope) then
      out[#out + 1] = id
    end
  end
  return out
end

--- One level's own time, or nil for all of it.
local function own_span(s: Scope): number, number
  if s.kind == "nest" then
    local ok, length = pcall(nest_get, s.id, "length") as (boolean, number)
    if ok and length then
      return 0, length
    end
  elseif s.kind == "region" then
    local m = region(s.id)
    if m then
      return m.beat, m.beat + m.length
    end
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
    if scope.kind == "nest" and valid(scope) then
      -- A subproject's timeline is its own: the song's time above it is not.
      break
    end
    scope = scope.parent
  end
  if from then
    return from, math.max(from, to)
  end
end

--- The levels of a scope's path (the current one by default), from the
--- outermost to it.
function M.path(s?: Scope): {Scope}
  local out: {Scope} = {}
  local at = s or M.current()
  while at do
    if valid(at) then
      table.insert(out, 1, at)
    end
    at = at.parent
  end
  return out
end

--- The scopes one level inside a scope (the current one by default): for
--- a region scope, the regions one level inside its region (paw/markers.tl), in
--- order of time; for a group scope, its members (a group or a track), in
--- order. Each has that scope as its parent. Other kinds have none.
function M.children(s?: Scope): {Scope}
  local scope = s or M.current()
  local out: {Scope} = {}
  if scope and scope.kind == "region" and paw.markers then
    for _, m in ipairs(paw.markers.children(scope.id)) do
      out[#out + 1] = {kind = "region", id = m.id, name = m.name, parent = scope}
    end
  elseif scope and scope.kind == "group" and valid(scope) then
    for _, id in ipairs(groups().members(scope.id)) do
      local kind: Kind = groups().is_group(id) and "group" or "track"
      out[#out + 1] = {kind = kind, id = id, name = name_of(id), parent = scope}
    end
  end
  return out
end

--- The path in words: `Song › Bridge › Strings`; a subproject is marked
--- `⧉`: `Song › ⧉Ballad › Strings`.
function M.breadcrumb(s?: Scope): string
  local names = {"Song"}
  for _, level in ipairs(M.path(s)) do
    names[#names + 1] = (level.kind == "nest" and "⧉" or "") .. level.name
  end
  return table.concat(names, " › ")
end

--- What a subproject's clip places: where its start is in the song, and
--- the beat of the subproject that starts there.
local clip_field = api.clip_get as function(id: integer): types.Clip

--- The beats to add to a beat of the window to get the song's beat: in a
--- subproject, where the clip it was entered through places its beat 0
--- (the clip's start less its offset); else 0.
function M.song_offset(s?: Scope): number
  local nest = M.nest(s)
  if not (nest and nest.clip) then
    return 0
  end
  local ok, c = pcall(clip_field, nest.clip) as (boolean, types.Clip)
  if not (ok and c and c.nest == nest.id) then
    return 0
  end
  return c.start - (c.offset or 0)
end

--- The song's beat of a beat that the current scope shows.
function M.song_beat(beat: number, s?: Scope): number
  return beat + M.song_offset(s)
end

-- Bars --------------------------------------------------------------------------------

--- How many bars of the song come before the first bar of a scope (the
--- current one by default) when its bars are numbered from 1: 0 with no
--- time, or with `scopebars=song`. A scope's bars are the song's (its meter
--- map), counted from the bar its time starts in.
function M.bar_offset(s?: Scope): integer
  if opt.scopebars == "song" then
    return 0
  end
  local from = M.span(s)
  if not from then
    return 0
  end
  return paw.time.bar_of(from) - 1
end

--- The bar the current scope shows for a bar of the song.
function M.local_bar(song_bar: integer): integer
  return song_bar - M.bar_offset()
end

--- The bar of the song for a bar as the current scope shows it.
function M.song_bar(local_bar: integer): integer
  return local_bar + M.bar_offset()
end

--- A place as the scope numbers it: `bar.beat.hundredths`, as `paw.time.format`.
function M.format(beat: number): string
  local bar, b, frac = api.tempo_bbt(beat)
  local part = math.floor(frac * 100 + 0.5)
  if part >= 100 then
    part = 99
  end
  return string.format("%d.%d.%02d", bar + 1 - M.bar_offset(), b + 1, part)
end

-- Finding scopes ---------------------------------------------------------------------

--- A group by its id, its track, or its name (or part of it).
function M.find(which: TrackRef | string): integer
  if which == nil then
    return nil
  end
  local id: integer
  if which is string then
    id = math.tointeger(tonumber(which))
  else
    id = id_of(which)
  end
  if id then
    return groups().is_group(id) and id or nil
  end
  local wanted = (which as string):lower()
  local partial_match: integer
  for _, other in ipairs(api.track_list()) do
    if groups().is_group(other) then
      local name = name_of(other):lower()
      if name == wanted then
        return other
      end
      if not partial_match and name:find(wanted, 1, true) then
        partial_match = other
      end
    end
  end
  return partial_match
end

--- The group of a track when you narrow: the track itself if it is a group.
--- If not, the group that contains it.
function M.group_at(track: TrackRef): integer
  if not track then
    return nil
  end
  local id = id_of(track)
  if groups().is_group(id) then
    return id
  end
  return groups().of(id)
end

--- The scopes named with `:scope.name`, the latest last. View state: the
--- project's screen keeps them.
local named_scopes: {Scope} = {}

--- A scope by name: a named scope (`:scope.name`), else a group of that
--- name, else a region of that name, else a group or a region whose name
--- starts with it. A number is a group's id.
function M.named(which: string | integer): Scope
  if which is integer then
    return groups().is_group(which) and {kind = "group", id = which, name = name_of(which)} or nil
  end
  local wanted = (which as string):lower()
  for i = #named_scopes, 1, -1 do
    if named_scopes[i].name:lower() == wanted then
      return named_scopes[i]
    end
  end
  -- A path of regions, `Chorus 2/Verse A`, when names repeat.
  if wanted:find("/", 1, true) and paw.markers then
    local r = paw.markers.region(which as string)
    if r then
      return {kind = "region", id = r.id, name = r.name}
    end
  end
  -- Of two regions of one name, the one inside the current scope's time.
  local regions: {MarkersModule.Marker} = {}
  local later: {MarkersModule.Marker} = {}
  local from, to = M.span()
  for _, m in ipairs(paw.markers and paw.markers.regions() or {}) do
    if not from or (m.beat >= from - 1e-9 and m.beat + m.length <= to + 1e-9) then
      regions[#regions + 1] = m
    else
      later[#later + 1] = m
    end
  end
  for _, m in ipairs(later) do
    regions[#regions + 1] = m
  end
  for _, id in ipairs(api.track_list()) do
    if groups().is_group(id) and name_of(id):lower() == wanted then
      return {kind = "group", id = id, name = name_of(id)}
    end
  end
  for _, m in ipairs(regions) do
    if m.name:lower() == wanted then
      return {kind = "region", id = m.id, name = m.name}
    end
  end
  local g = M.find(which)
  if g then
    return {kind = "group", id = g, name = name_of(g)}
  end
  for _, m in ipairs(regions) do
    if m.name:lower():find(wanted, 1, true) == 1 then
      return {kind = "region", id = m.id, name = m.name}
    end
  end
end

--- The name a scope shows when it has none.
local function name_for(s: Scope): string
  if s.name then
    return s.name
  end
  if (s.kind == "group" or s.kind == "track") and exists(s.id) then
    return name_of(s.id)
  end
  if s.kind == "region" then
    local m = region(s.id)
    return m and m.name
  end
  if s.kind == "nest" then
    local ok, name = pcall(nest_get, s.id, "name") as (boolean, string)
    return ok and name or ("Subproject " .. tostring(s.id))
  end
  if s.from and s.to and paw.time then
    local a, b = paw.time.bar_of(s.from), paw.time.bar_of(math.max(s.from, s.to - 1e-6))
    return a == b and ("Bar " .. a) or string.format("Bars %d-%d", a, b)
  end
  return s.tracks and (#s.tracks .. " tracks") or "Range"
end

--- The scope of a subproject's clip (`znn` or `<CR>` on it enters it), or
--- nil when the clip places no subproject.
function M.of_clip(id: integer): Scope
  local ok, c = pcall(clip_field, id) as (boolean, types.Clip)
  if ok and c and c.nest then
    return {kind = "nest", id = c.nest, clip = id}
  end
end

--- The scope that `znn` enters at the cursor: the innermost not entered
--- yet. A subproject's clip at the cursor; in a region scope, the region
--- one level inside it at the cursor; else the group at the cursor (its
--- header or one of its tracks), else the track. Nil when the window shows
--- that track already.
function M.at_cursor(): Scope
  local clip = paw.cursor.clip()
  local nest = clip and M.of_clip(clip.id)
  if nest then
    return nest
  end
  local here = M.current()
  if here and here.kind == "region" and paw.markers then
    local path = paw.markers.path(paw.cursor.beat)
    for i, m in ipairs(path) do
      if m.id == here.id and path[i + 1] then
        return {kind = "region", id = path[i + 1].id}
      end
    end
  end
  local id = paw.cursor.track_id()
  if not id or id == 0 then
    return nil
  end
  local entered: {integer: boolean} = {}
  for _, level in ipairs(M.path()) do
    if level.kind == "group" or level.kind == "track" then
      entered[level.id] = true
    end
  end
  local g = M.group_at(id)
  if g and not entered[g] then
    return {kind = "group", id = g}
  end
  if here and here.kind == "track" and here.id == id then
    return nil
  end
  return {kind = "track", id = id}
end

--- The scope an operator's region covers (`zn{motion}`, `{Visual}zn`):
--- the region, group or track its text object names (`ar`, `ag`, `it`),
--- else a block of its tracks, with its time when it has some. Nil for the
--- whole of what the window shows (`ie`).
function M.of_region(r: contracts.Region): Scope
  if r.scope then
    return r.scope
  end
  if r.entire then
    return nil
  end
  local rows, ids = groups().rows(), {}
  for row = math.max(1, math.floor(r.r0)), math.floor(r.r1) do
    if rows[row] then
      ids[#ids + 1] = rows[row]
    end
  end
  if #ids == 0 then
    return nil
  end
  local from, to = math.min(r.c0, r.c1), math.max(r.c0, r.c1)
  if r.kind == "line" or to - from < 1e-9 then
    return {kind = "tracks", tracks = ids}
  end
  return {kind = "range", tracks = ids, from = from, to = to}
end

-- Entering and leaving -------------------------------------------------------------------

--- Put the cursor inside the current scope: on its first track when it is
--- on one outside, and in its time.
local function cursor_inside(s: Scope)
  if not s then
    return
  end
  local cursor = paw.cursor
  local at = cursor.track_id()
  if not (at and M.contains(at, s)) then
    local first = M.tracks(s)[1]
    if first then
      cursor.set_track(first)
    end
  end
  local from, to = M.span(s)
  if from and (cursor.beat < from or cursor.beat > to) then
    cursor.set_beat(from)
  end
end

--- The loop that was set before a scope with time set its own.
local loop_was: Loop

--- The loop is the time of the scope of the window in front (`scopeloop`);
--- out of it, the loop that was set before comes back.
local function sync_loop(s: Scope)
  local from, to: number, number
  if s then
    from, to = M.span(s)
    if from then
      local offset = M.song_offset(s)
      from, to = from + offset, to + offset
    end
  end
  local tr = paw.transport
  if from and to > from and opt.scopeloop then
    loop_was = loop_was or {start = tr.loop_start, stop = tr.loop_end, enabled = tr.loop_enabled}
    if not (tr.loop_start == from and tr.loop_end == to and tr.loop_enabled) then
      tr.loop_start, tr.loop_end, tr.loop_enabled = from, to, true
    end
  elseif loop_was then
    local was = loop_was
    loop_was = nil
    tr.loop_start, tr.loop_end, tr.loop_enabled = was.start, was.stop, was.enabled
  end
end

--- Show a scope in a window, in place of the one it shows.
local function set(win: Window, s: Scope)
  win.scope = s
  events.emit(changed, {scope = s and M.group(s) or nil, win = win.id})
  api.ui_redraw()
end

--- Before a window in front changes its scope: where the cursor is, with
--- the scope, goes on the jump list.
local function jump(win: Window)
  if win == holder() then
    keymap().push_jump()
  end
end

--- Why a scope inside another would show nothing, or nil.
local function empty_inside(s: Scope): string
  local tracks = M.tracks(s)
  if #tracks == 0 then
    return string.format("no track of %s is in %s", s.name, s.parent.name)
  end
  local from, to = M.span(s)
  if from and to <= from then
    return string.format("%s and %s have no time in common", s.name, s.parent.name)
  end
end

--- A new level from what `enter` takes, checked, with its name.
local function level(spec: Scope, parent: Scope): Scope
  assert(spec and spec.kind, "a scope has a kind")
  local s: Scope = {
    kind = spec.kind,
    id = spec.id,
    tracks = spec.tracks,
    from = spec.from,
    to = spec.to,
    name = spec.name,
    clip = spec.clip,
  }
  if not valid(s) then
    error("no " .. s.kind .. " " .. tostring(s.id), 0)
  end
  if s.kind == "range" and s.from and not (s.to and s.to > s.from) then
    error("a range ends after it starts", 0)
  end
  s.name = name_for(s)
  s.parent = parent
  -- A subproject shows its own tracks and time, whatever the parent shows.
  if parent and s.kind ~= "nest" then
    local why = empty_inside(s)
    if why then
      error(why, 0)
    end
  end
  return s
end

local function same_level(a: Scope, b: Scope): boolean
  if not (a and b) or a.kind ~= b.kind or a.id ~= b.id or a.from ~= b.from or a.to ~= b.to or a.clip ~= b.clip then
    return false
  end
  return table.concat(a.tracks or {}, ",") == table.concat(b.tracks or {}, ",")
end

--- Enter a scope (`{ kind, id, tracks, from, to, name }`) in a window (the
--- current one by default). In a window that shows a scope, it becomes its
--- child: it shows what both show, and an empty one is refused with the
--- reason. Changes nothing in the project; a jump. Returns the scope.
function M.enter(spec: Scope, win?: Window): Scope
  local w = holder(win)
  if not w then
    error("no window to show a scope in", 0)
  end
  local here = M.current(w)
  if here and same_level(here, spec) then
    return here
  end
  local s = level(spec, here)
  jump(w)
  set(w, s)
  return s
end

--- Narrow to a group or a region, by its id, its track or its name (see
--- `named`): `enter` of that scope in the current window. Returns the scope.
function M.narrow(which: TrackRef | string): Scope
  local s: Scope
  if which is string then
    s = M.named(which)
  elseif which ~= nil then
    local g = M.find(which)
    s = g and {kind = "group", id = g, name = name_of(g)} or nil
  end
  if not s then
    error(which == nil and "not in a group" or ("no group or region `" .. tostring(which) .. "`"), 0)
  end
  return M.enter(s)
end

--- Leave the scope of a window (the current one by default): up one level,
--- or with `top` to the song. False when it shows the song.
function M.widen(top?: boolean, win?: Window): boolean
  local w = holder(win)
  local s = w and M.current(w)
  if not s then
    return false
  end
  jump(w)
  set(w, (not top) and live(s.parent) or nil)
  return true
end

--- Show a scope in a window as it was (a jump back, `<C-o>`): no jump of
--- its own, no check. Nil is the song.
function M.restore(s: Scope, win?: Window)
  local w = holder(win)
  if w and w.scope ~= s then
    set(w, s)
  end
end

--- The scopes beside the current one, in order, and its place among them:
--- regions by time, groups with the same parent group, tracks of the
--- parent scope. Nil and the reason when it has none.
local function siblings(s: Scope): {Scope}, integer
  local out: {Scope} = {}
  local at: integer
  if s.kind == "region" then
    -- The regions of the same parent region (paw/markers.tl's tree).
    local parent = paw.markers.parent(s.id)
    for _, m in ipairs(paw.markers.children(parent and parent.id)) do
      out[#out + 1] = {kind = "region", id = m.id}
      if m.id == s.id then
        at = #out
      end
    end
  elseif s.kind == "group" then
    local parent = groups().of(s.id)
    for _, id in ipairs(api.track_list()) do
      if groups().is_group(id) and groups().of(id) == parent then
        out[#out + 1] = {kind = "group", id = id}
        if id == s.id then
          at = #out
        end
      end
    end
  elseif s.kind == "nest" then
    -- The clips of subprojects on the tracks of the parent, by time: the
    -- next block of this subproject, or the next subproject.
    local clips: {types.Clip} = {}
    for _, track in ipairs(M.tracks(s.parent)) do
      for _, c in ipairs(api.clip_list(track)) do
        if c.kind == "nest" then
          clips[#clips + 1] = c
        end
      end
    end
    table.sort(
      clips,
      function(a: types.Clip, b: types.Clip): boolean
        if a.start ~= b.start then
          return a.start < b.start
        end
        return a.id < b.id
      end
    )
    for _, c in ipairs(clips) do
      out[#out + 1] = {kind = "nest", id = c.nest, clip = c.id}
      if c.id == s.clip then
        at = #out
      end
    end
  elseif s.kind == "track" then
    for _, id in ipairs(M.tracks(s.parent or {kind = "range"})) do
      out[#out + 1] = {kind = "track", id = id}
      if id == s.id then
        at = #out
      end
    end
  end
  return out, at
end

--- The scope `n` places after the current one (before it, with a negative
--- `n`), beside it in the same parent: the next region, group or track; a
--- block's next stretch of the same length. Nil and the reason when there
--- is none.
function M.sibling(n: integer): Scope, string
  local s = M.current()
  if not s then
    return nil, "the song has nothing beside it: `zn` enters a scope"
  end
  if s.kind == "range" or s.kind == "tracks" then
    if not (s.from and s.to) then
      return nil, "a scope of tracks has no next: `zw` goes up"
    end
    local length = s.to - s.from
    local from = s.from + n * length
    if from < -1e-9 then
      return nil, "no stretch before " .. s.name
    end
    return {kind = s.kind, tracks = s.tracks, from = from, to = from + length}
  end
  local list, at = siblings(s)
  local found = at and list[at + n]
  if not found then
    return nil, string.format("no %s %s %s", s.kind, n > 0 and "after" or "before", s.name)
  end
  return found
end

--- Go to the scope `n` places beside the current one (`]z`, `3]z`, `[z`),
--- in the same parent. A jump. Returns the scope.
function M.next(n?: integer): Scope
  local s = M.current()
  local spec, why = M.sibling(n or 1)
  if not spec then
    error(why, 0)
  end
  local w = holder()
  local new = level(spec, live(s.parent))
  jump(w)
  set(w, new)
  return new
end

--- Open a scope (the one at the cursor by default) in a new window:
--- `how` is "split", "vsplit" or "tab". The new window starts with the
--- scope of the one it comes from, and enters this one inside it.
function M.open(how: string, spec?: Scope): Scope
  local from = holder()
  spec = spec or M.at_cursor() or M.current(from)
  if how == "tab" then
    L().tab_copy()
  else
    local win, why = L().split({win = from as Node, view = "arrange", vertical = how == "vsplit"})
    if not win then
      error(why, 0)
    end
  end
  local w = holder()
  if spec and not same_level(M.current(w), spec) then
    local ok, err = pcall(M.enter, spec, w) as (boolean, string)
    if not ok then
      -- Not inside the scope it came from: from the song.
      w.scope = nil
      M.enter(spec, w)
      paw.notify(tostring(err) .. ": opened from the song", "warn")
    end
  end
  return M.current(w)
end

--- Name the current scope, so that the picker and `:narrow` find it
--- again. View state, kept with the project's screen. Returns it.
function M.name(name: string, win?: Window): Scope
  local w = holder(win)
  local s = w and M.current(w)
  if not s then
    error("the song has its name: `zn` enters a scope to name", 0)
  end
  local named: Scope = {
    kind = s.kind, id = s.id, tracks = s.tracks, from = s.from, to = s.to, name = name, parent = s.parent
  }
  for i = #named_scopes, 1, -1 do
    if named_scopes[i].name == name then
      table.remove(named_scopes, i)
    end
  end
  named_scopes[#named_scopes + 1] = named
  set(w, named)
  return named
end

--- The named scopes, the latest last.
function M.names(): {Scope}
  return named_scopes
end

--- The named scopes as the project's screen keeps them (paw/layout.tl).
function M.saved_names(): {{types.SavedScope}}
  local out: {{types.SavedScope}} = {}
  for i, s in ipairs(named_scopes) do
    out[i] = L().scope_levels(s)
  end
  return out
end

-- A scope follows its group's or track's name. A track added in a scope of
-- a group goes into the group, so that it stays in sight (undo and opening
-- a project put tracks back where they were).
events.on(
  kernel.track_changed,
  function(event: kernel.TrackId)
    if not exists(event.id) then
      return
    end
    for _, tw in ipairs(L().all_windows()) do
      local s = tw.win.scope
      while s do
        if (s.kind == "group" or s.kind == "track") and s.id == event.id then
          s.name = name_of(event.id)
        end
        s = s.parent
      end
    end
  end
)
events.on(
  added,
  function(event: Added)
    if event.restored or not exists(event.id) then
      return
    end
    local g = M.group()
    if g and not M.contains(event.id) and not paw.vca.is_vca(event.id) then
      pcall(groups().add, event.id, g)
    end
  end
)

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
  hold: {integer: string}
end
local held: {integer: Held} = {}
local pending: {string: Pending} = {}
-- Edits since the start, by track: a part of the rest whose tracks are
-- edited is rendered again.
local gens: {integer: integer} = {}
local applied: Applied = {hold = {}} -- what the engine was last told
local made = 0 -- files rendered, for their names

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
  if not (scope and M.limits_tracks(scope)) then
    return {}
  end
  local inside: {integer: boolean} = {}
  for _, id in ipairs(M.tracks(scope)) do
    inside[id] = true
  end
  -- The scope's groups and wherever its sound goes carry it: they play live.
  local carries: {integer: boolean} = {}
  local lineage: {integer: boolean} = {}
  for id in pairs(inside) do
    for to in pairs(paw.routes.reached(id)) do
      carries[to] = true
    end
    local at = groups().of(id)
    while at and not inside[at] do
      lineage[at] = true
      at = groups().of(at)
    end
  end
  local function sounds(id: integer): boolean
    if #api.clip_list(id) > 0 then
      return true
    end
    for _, member in ipairs(groups().members(id)) do
      if sounds(member) then
        return true
      end
    end
    return false
  end
  local out: {integer} = {}
  for _, id in ipairs(api.track_list()) do
    local parent = groups().of(id)
    local top = parent == nil or lineage[parent]
    if
      top
      and not inside[id]
      and not lineage[id]
      and not carries[id]
      and not paw.vca.is_vca(id)
      and not paw.freeze.state(id)
      and sounds(id)
    then
      out[#out + 1] = id
    end
  end
  return out
end

local function gen_of(track: integer): integer
  -- A part's generation counts the edits of every track inside it.
  local n = gens[track] or 0
  for _, member in ipairs(groups().members(track)) do
    n = n + gen_of(member)
  end
  return n
end

--- Render a part of the rest in the background, unless it is being rendered.
local function render_part(id: integer)
  for _, p in pairs(pending) do
    if p.id == id then
      return
    end
  end
  made = made + 1
  local path = string.format("%s/%d-%d-%d.wav", held_dir(), api.env().pid, id, made)
  pending[path] = {id = id, gen = gen_of(id)}
  local ok, err = pcall(paw.render, path, paw.freeze.render_opts(id, {background = true})) as (boolean, string)
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
  if scope and not valid(scope) then
    scope = nil
  end
  applied.scope = scope
  local rest = opt.scope_rest
  local narrowed = scope and M.limits_tracks(scope)
  local tracks = narrowed and M.tracks(scope) or nil
  local audible = tracks and rest == "mute" and table.concat(tracks, ",") or nil
  if audible ~= applied.audible then
    api.engine_audible(audible and tracks or nil)
    applied.audible = audible
  end
  local want: {integer: string} = {}
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
      if exists(id) then
        pcall(api.engine_hold, id, nil)
      end
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
  for id in pairs(applied.hold) do
    out[#out + 1] = id
  end
  table.sort(out)
  return out
end

events.on(
  render_done,
  function(info: kernel.RenderEnd)
    local p = pending[info.path]
    if not p then
      return
    end
    pending[info.path] = nil
    local old = held[p.id]
    if old and old.file ~= info.path then
      os.remove(old.file)
    end
    held[p.id] = {file = info.path, gen = p.gen}
    M.apply(applied.scope)
  end
)
for _, ev in ipairs({kernel.render_failed, kernel.render_cancelled}) do
  events.on(
    ev,
    function(info: kernel.RenderEnd)
      if info.path then
        pending[info.path] = nil
      else
        pending = {}
      end
    end
  )
end

-- An edit to a track makes what was rendered of it out of date.
local function touched(event: kernel.Item)
  local id = event.track or event.id
  if not id then
    return
  end
  gens[id] = (gens[id] or 0) + 1
end
for _, ev in ipairs(
  {
    kernel.clip_added,
    kernel.clip_changed,
    kernel.clip_removed,
    kernel.device_added,
    kernel.device_changed,
    kernel.device_removed,
    kernel.lane_added,
    kernel.lane_changed,
    kernel.lane_removed,
  }
) do
  events.on(ev, touched)
end

--- Lists edited as text read what the window in front sees: read them again
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

--- What the rest of the program last followed: the scope of the window in
--- front (nil: the song, as at the start).
local followed: Scope

--- Everything that shows tracks catches up with the window in front when
--- its scope is another: lists edited as text, a graphical frontend's
--- state, the engine, the loop, the cursor.
local function follow(force?: boolean, win?: Window)
  local s = M.current(holder(win))
  if s == followed and not force then
    return
  end
  -- Into or out of a subproject, the cursor keeps its place in the song:
  -- its beat is now one of the other timeline.
  local function root(at: Scope): Scope
    return at and M.nest(at) or nil
  end
  local function offset(at: Scope): number
    return at and M.song_offset(at) or 0
  end
  if root(followed) ~= root(s) and paw.cursor.beat then
    local beat = paw.cursor.beat + offset(followed) - offset(s)
    paw.cursor.set_beat(math.max(0, beat))
  end
  followed = s
  cursor_inside(s)
  sync_loop(s)
  reread()
  paw.frontend.refresh()
  M.apply(s)
end
events.on(tab_enter, function() follow(false, tab_window(L().tab())) end)
-- The window entered, from the event: while it is entered, the focused
-- view is not yet its view.
events.on(win_enter, function(e: WinEvent) follow(false, (L().get(e.win))) end)
events.on(changed, function() follow(true) end)
events.on(
  option_changed,
  function(e: Option)
    if e.name == "scope_rest" then
      M.apply(M.current(holder()))
    elseif e.name == "scopeloop" then
      sync_loop(M.current(holder()))
    end
  end
)
-- Tracks that come, go or change places change what the rest is.
local function again()
  if applied.scope and opt.scope_rest ~= "play" then
    M.apply(applied.scope)
  end
end
events.on(kernel.track_added, again)
events.on(kernel.track_removed, again)
events.on(kernel.track_moved, again)
events.on(kernel.clip_added, again)
events.on(kernel.clip_removed, again)
-- Another project: nothing of the last one is held, and its named scopes
-- come back (paw/layout.tl gives the windows theirs).
events.on(
  kernel.project_loaded,
  function()
    held, pending, gens = {}, {}, {}
    loop_was, followed = nil, nil
    applied = {hold = {}}
    api.engine_audible(nil)
    for _, id in ipairs(api.engine_held()) do
      pcall(api.engine_hold, id, nil)
    end
    named_scopes = {}
    local screen = api.project_screen()
    for _, levels in ipairs(screen and screen.scopes or {}) do
      local s = L().scope_chain(levels)
      if s then
        named_scopes[#named_scopes + 1] = s
      end
    end
  end
)

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
  return opt.scopebars == "both" and M.span() ~= nil and (M.bar_offset() ~= 0 or M.song_offset() ~= 0)
end

local arrange = paw.ui.views.arrange as Arrange
if arrange and arrange.layers then
  arrange.ruler2.scope_bars = song_row
  -- Under each bar's local number, its number in the song. Layers draw in
  -- the order of their names: this one after the markers' bands, and
  -- clear of the names of markers and regions.
  arrange.layers.zz_scope_bars = function(_: Arrange, layer: Layer)
    if not (song_row() and layer.ruler2) then
      return
    end
    local row = layer.ruler2
    local taken: {{integer}} = {}
    for _, m in ipairs(paw.markers and paw.markers.list() or {}) do
      local x = layer.x(m.beat)
      taken[#taken + 1] = {x, x + api.str_width(paw.markers.label(m)) + 1}
    end
    local function clear(a: integer, b: integer): boolean
      for _, t in ipairs(taken) do
        if a < t[2] and b > t[1] then
          return false
        end
      end
      return true
    end
    local free = 0
    local offset = M.song_offset()
    for _, line in ipairs(paw.time.bars(layer.scroll, layer.scroll + layer.span)) do
      local x = layer.x(line.beat)
      local text = tostring(offset ~= 0 and paw.time.bar_of(line.beat + offset) or line.bar)
      if x >= free and x >= 0 and x < row.width and clear(x, x + #text + 1) then
        free = x + row:text(x, 0, text, "RulerTick") + 1
      end
    end
  end
end

-- The scope picker ---------------------------------------------------------------------

--- The entries of the scope picker: the levels of the window's stack (and
--- the song) to go up to, the named scopes, the groups and the regions.
local function items(): {Item}
  local out: {Item} = {}
  local path = M.path()
  if #path > 0 then
    out[#out + 1] = {level = true, kind = "up", label = "Song"}
    for i = 1, #path - 1 do
      out[#out + 1] = {level = true, scope = path[i], kind = "up", label = M.breadcrumb(path[i])}
    end
  end
  for i = #named_scopes, 1, -1 do
    local s = named_scopes[i]
    if valid(s) then
      out[#out + 1] = {scope = s, kind = "named", label = s.name}
    end
  end
  for _, id in ipairs(api.track_list()) do
    if groups().is_group(id) then
      out[#out + 1] = {scope = {kind = "group", id = id}, kind = "group", label = name_of(id)}
    end
  end
  -- The subprojects, each by the first clip that places it in the song.
  local first: {integer: integer} = {}
  for _, track in ipairs(api.track_list()) do
    for _, c in ipairs(api.clip_list(track)) do
      if c.kind == "nest" and not first[c.nest] then
        first[c.nest] = c.id
      end
    end
  end
  for _, id in ipairs(api.nest_list()) do
    local scope: Scope = {kind = "nest", id = id, clip = first[id]}
    out[#out + 1] = {scope = scope, kind = "nest", label = name_for(scope)}
  end
  -- The regions as their tree: each one indented under its parent.
  for _, node in ipairs(paw.markers and paw.markers.walk() or {}) do
    local m = node.region
    local indent = string.rep("  ", node.depth - 1)
    out[#out + 1] = {scope = {kind = "region", id = m.id}, kind = "region", label = indent .. paw.markers.label(m)}
  end
  return out
end

--- Go to a picker's entry: up the stack to a level, or into a scope (from
--- the song when it is not inside the one shown).
local function choose(item: Item)
  paw.ui.focus("arrange")
  if item.level then
    jump(holder())
    set(holder(), item.scope)
  else
    local ok, err = pcall(M.enter, item.scope) as (boolean, string)
    if not ok then
      local w = holder()
      jump(w)
      w.scope = nil
      ok, err = pcall(M.enter, item.scope) as (boolean, string)
      if not ok then
        paw.notify(tostring(err), "warn")
        return
      end
    end
  end
  paw.notify(M.breadcrumb())
end

M.source = {
  desc = "Enter a scope: a level of this window's, a named scope, a group, a subproject, a region",
  title = "Scopes",
  empty = "No scope to enter: make a group, a region or a subproject, or name a scope with `:scope.name`.",
  items = items,
  format = function(item: Item): string return string.format("%-7s %s", item.kind, item.label) end,
  primary = function(item: Item): string return item.label end,
  search = function(item: Item): string return item.label end,
  on_choose = choose,
}

-- Commands -----------------------------------------------------------------------------

local function scope_names(): {string}
  local out: {string} = {}
  for _, s in ipairs(named_scopes) do
    out[#out + 1] = s.name
  end
  for _, id in ipairs(api.track_list()) do
    if groups().is_group(id) then
      out[#out + 1] = name_of(id)
    end
  end
  for _, m in ipairs(paw.markers and paw.markers.regions() or {}) do
    if m.name ~= "" then
      out[#out + 1] = m.name
    end
  end
  return out
end

--- What a scope shows, in words: its path, its tracks and its bars.
function M.describe(s?: Scope): string
  s = s or M.current()
  local from, to = M.span(s)
  local bars = from and string.format(", bars %d-%d", paw.time.bar_of(from), paw.time.bar_of(math.max(from, to - 1e-6)))
    or ""
  return string.format("%s: %d tracks%s", M.breadcrumb(s), #M.tracks(s), bars)
end

--- A step that changes the scope of a window.
local type Step = function(): Scope

--- Run a step and say what came of it, or why it did not.
local function say(fn: Step, hint?: string)
  local ok, err = pcall(fn) as (boolean, string)
  if not ok then
    paw.notify(tostring(err), "warn")
    return
  end
  paw.notify(M.describe() .. (hint or ""))
end

commands.define(
  "narrow",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local which = ctx.args[1]
    local s: Scope
    if which == nil or which == true then
      s = M.at_cursor()
      if not s then
        paw.notify("nothing smaller to enter at the cursor: `:narrow` takes a group or a region by name", "warn")
        return
      end
    else
      s = M.named(table.concat(ctx.args as {string}, " "))
      if not s then
        paw.notify("no group or region `" .. tostring(which) .. "`", "warn")
        return
      end
    end
    say(function(): Scope return M.enter(s) end, " · `zw` goes back")
  end,
  {
    desc = "Show only a group's tracks or a region's time in this window: `narrow Strings`, `narrow Bridge`; alone, the innermost scope at the cursor (as `znn`). Inside a scope, the new one is inside it",
    complete = scope_names,
  }
)

local function widen(top: boolean)
  if not M.widen(top) then
    paw.notify("this window shows the whole song", "warn")
    return
  end
  local s = M.current()
  paw.notify(s and M.breadcrumb(s) or "the whole song")
end
commands.define(
  "widen", function(): contracts.CommandResult widen(false) end, {desc = "Up one level of scope in this window"}
)
commands.define(
  "widen!",
  function(): contracts.CommandResult widen(true) end,
  {desc = "Leave every level of scope: this window shows the whole song"}
)

for _, dir in ipairs(
  {
    {"scope.next", 1, "The next scope beside this one: the next region, group or track, or a block's next stretch"},
    {"scope.prev", -1, "The scope before this one, beside it"},
  }
) do
  local name, sign, desc = dir[1] as string, dir[2] as integer, dir[3] as string
  commands.define(
    name,
    function(ctx: contracts.CommandContext): contracts.CommandResult
      local n = (ctx.count or math.tointeger(tonumber(ctx.args[1])) or 1) * sign
      say(function(): Scope return M.next(n) end)
    end,
    {desc = desc}
  )
end

for _, how in ipairs({{"split", "split"}, {"vsplit", "vertical split"}, {"tab", "tab"}}) do
  commands.define(
    "scope." .. how[1],
    function(ctx: contracts.CommandContext): contracts.CommandResult
      local spec: Scope
      if ctx.args[1] then
        spec = M.named(table.concat(ctx.args as {string}, " "))
        if not spec then
          paw.notify("no scope `" .. tostring(ctx.args[1]) .. "`", "warn")
          return
        end
      end
      say(function(): Scope return M.open(how[1], spec) end)
    end,
    {
      desc = "The scope at the cursor, or one by name, in a new " .. how[2] .. ": `scope." .. how[1] .. " Bridge`",
      complete = scope_names,
    }
  )
end

--- Name the current scope.
local function name_it(name: string)
  local ok, err = pcall(M.name, name) as (boolean, string)
  if not ok then
    paw.notify(tostring(err), "warn")
    return
  end
  paw.notify("named " .. M.breadcrumb() .. " · `:scope.list` finds it")
end
commands.define(
  "scope.name",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local name = table.concat(ctx.args as {string}, " "):match("^%s*(.-)%s*$")
    if name ~= "" then
      name_it(name)
      return
    end
    local s = M.current()
    if not s then
      paw.notify("the song has its name: `zn` enters a scope to name", "warn")
      return
    end
    (paw.ui.input as function(InputOptions, function(string)))(
      {prompt = "Scope name: ", text = s.name, label = "Name the scope"},
      function(text: string)
        if text and text ~= "" then
          name_it(text)
        end
      end
    )
  end,
  {
    desc = "Name the scope of this window, so that the picker and `:narrow` find it: `scope.name Strings in bridge`; alone, it asks",
  }
)
commands.define(
  "scope.list",
  function(): contracts.CommandResult commands.run("pick", {"scopes"}) end,
  {desc = "Choose a scope to enter, or a level to go up to, in a picker"}
)

return M
