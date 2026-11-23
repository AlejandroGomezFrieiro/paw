-- The piano roll: edit the notes of a MIDI clip, or of several at once (see
-- `paw.roll_clips`), with other tracks' notes shown behind them.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. The module
-- gives the view's type, the record `PianoRoll`, and its other types: a
-- module that reads the roll names them with
-- `local type Roll = require("paw.views.pianoroll")` (`Roll.PianoRoll`,
-- `Roll.Layer`) and takes the view from `paw.ui.views:get("pianoroll")`. The modules that draw on
-- the roll or act on it (paw/roll_draw.tl, paw/frontend.tl) name this one's
-- types, so this one declares only the part of them that it calls.
local api = require("paw.api")
local axis = require("paw.axis")
local type CursorModule = require("paw.cursor")
local events = require("paw.events")
local options = require("paw.options")
local util = require("paw.util")
local music = require("paw.music")
local statusline = require("paw.statusline")
local clips = require("paw.roll_clips")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type AttrModule = require("paw.attr")
local type DrawModule = require("paw.draw")
local type EditModule = require("paw.edit")
local type HarmonyModule = require("paw.harmony")
local type KeymapModule = require("paw.keymap")
local type LayoutModule = require("paw.layout")
local type MouseModule = require("paw.mouse")
local type TempoModule = require("paw.tempo")
local type UiModule = require("paw.ui")
local type VzoomModule = require("paw.vzoom")

local type Buf = contracts.Buf
local type Part = clips.Part
local opt = options.opt
local project_edits = api.project_get as function(key: string): integer

local KEYS = 5 -- columns for the note names on the left

-- Types ---------------------------------------------------------------------------

--- Where a window of the roll drew its parts last: the pitches shown
--- (`rows`) and the grid's lines (`lines`), the rows of a pitch (`per`),
--- the zoom, the columns of the keyboard (`keys`), the rows above the notes
--- (`head`) and of the velocity strip (`vel`), the beats shown (`span`),
--- and the time axis that placed the beats (`axis`, paw/axis.tl). The
--- pointer reads it to find what is under it.
local record Geometry
  rows: integer
  lines: integer
  per: integer
  zoom: number
  keys: integer
  head: integer
  vel: integer
  span: number
  axis: axis.Axis
end

--- What a layer of the roll gets (`view.layer`). `roll` and `ruler` are
--- cell buffers, `plane` the roll as a plane of beats along and pitches up
--- (see `buf:plane`), `clip` the active clip and `data` its fields,
--- `parts` every clip edited (paw/roll_clips.tl), `x(beat)` a column of the
--- roll, `row(pitch)` its first row (nil when off screen), `from` and `to`
--- the beats that show, `rows` the pitches shown, `per` the rows of a
--- pitch, and the note under the cursor (`under_place` in `under_part`).
local record Layer
  roll: Buf
  ruler: Buf
  plane: contracts.Plane
  clip: objects.Clip
  data: types.Clip
  parts: {Part}
  scroll: number
  from: number
  to: number
  top: integer
  rows: integer
  per: integer
  zoom: number
  axis: axis.Axis
  width: integer
  focused: boolean
  hue: DrawModule.Hue
  under_place: integer
  under_part: Part
  x: function(beat: number): integer
  row: function(pitch: integer): integer
end

--- A layer of the roll: `paint(layer)` draws it, from back to front by `order`.
local record LayerEntry
  name: string
  order: number
  paint: function(layer: Layer)
end

--- A switch that a module adds to the row of tools (`view:tool`): its
--- label, whether it is on, what the pointer over it says, and the name of
--- the `paw.frontend.act` function that a click calls with the clip.
local record Tool
  label: string
  on: boolean
  act: string
  tip: string
end

local record ToolEntry
  name: string
  fn: function(): Tool
end

--- A button of the row of tools: `name` names it for the pointer
--- (paw/views/pianoroll_mouse.tl), `menu` opens a menu, `act` is a
--- module's switch.
local record ToolButton
  name: string
  text: string
  tip: string
  on: boolean
  menu: boolean
  act: string
end

--- A scope of mappings whose keys come before the roll's while `active()`.
local record KeyScope
  name: string
  order: number
  active: function(): boolean
end

--- An entry that a module adds to one of the roll's lists (`view.rows`,
--- `view.band`, `view.describer`, `view.entering`): its name, and where it
--- goes among the others.
local interface Provided
  name: string
  order: number
end

--- What a module says about a row of the keyboard (`view.rows`): `label`
--- (and its `style`) on the keyboard edge instead of the pitch, `shade` the
--- style of the row.
local record RowLook
  label: string
  style: string
  shade: string
end
local record RowProvider is Provided
  fn: function(pitch: integer, track: integer): RowLook
end

--- What a band's `paint` gets besides its row: the clip and its fields,
--- the beats that show, the zoom and width, the lines of the ruler and the
--- column of a beat.
local record BandContext
  clip: objects.Clip
  data: types.Clip
  from: number
  to: number
  zoom: number
  width: integer
  lines: {DrawModule.RulerLine}
  x: function(beat: number): integer
end

--- A row of its own above the ruler (`view.band`): shown while
--- `active(clip)`, `title` on the keyboard edge, `paint(buf, ctx)` in it.
local record Band is Provided
  title: string
  active: function(clip: objects.Clip): boolean
  paint: function(buf: Buf, ctx: BandContext)
end

--- The lines `K` adds for a note (`view.describer`). With `articulation`
--- they say the note's articulation, in place of its attribute's words.
local record Described is {string | contracts.PageLine}
  articulation: boolean
end
local record Describer is Provided
  fn: function(note: types.Note, part: Part): Described
end

--- A change of a note the roll is about to enter (`view.entering`).
local record Enterer is Provided
  fn: function(note: objects.NoteInput, clip: objects.Clip)
end

--- What the strip under the notes shows: the velocities (`kind` nil) or a
--- controller, "bend" or "cc" with its `number`.
local record StripKind
  label: string
  short: string
  kind: string
  number: integer
end

--- The strip under the notes, which paw/views/pianoroll_strip.tl sets:
--- what it shows, and what it draws over the roll's velocity strip.
local record Strip
  shown: function(): StripKind
  draw: function(view: PianoRoll, buf: Buf)
end

--- A gesture of the pointer under way on the roll (`paw.mouse.grab`):
--- what it draws over the notes (`roll`) and over the strip under them
--- (`strip`), and the last drag (`d`).
local record Grab is MouseModule.Handlers
  roll: function(layer: Layer)
  strip: function(view: PianoRoll, buf: Buf)
  d: contracts.MouseEvent
end

--- The props of a note on the roll (paw/roles/notes.lua).
local record NoteMark is contracts.MarkProps
  label: string
  style: string
  color: string
  velocity: integer
  selected: boolean
  cursor: boolean
  pending: boolean
  ghost: boolean
  bend: number
  bend_at: number
end

--- What the pointer finds on a note, the start in the roll's beats.
local record NoteHit is contracts.HitAction
  place: integer
  pitch: integer
  start: number
  length: number
end

--- A button of the row of tools, as the pointer finds it.
local record ToolHit is contracts.HitAction
  name: string
  act: string
  tip: string
end

--- A chip that a layer marks: a click calls `paw.frontend.act[act](clip, arg)`.
local record ActHit is contracts.HitAction
  act: string
  arg: integer
  tip: string
end

local record ScrollHit is contracts.HitAction
  axis: string
end

--- The props of the roles that the roll marks besides its notes
--- (paw/roles/widgets.lua, paw/roles/notes.lua). paw.contracts gives the
--- ones that other views mark too.
local type ButtonMark = contracts.ButtonMark
local record KeyboardMark is contracts.MarkProps
  top: integer
  per: integer
  cursor: integer
  names: {{integer | string}}
  labels: {{integer | string}}
  sounding: {integer}
end
local type PlayheadMark = contracts.PlayheadMark
local record ScrollbarMark is contracts.MarkProps
  axis: string
  from: number
  span: number
  total: number
end

--- The payload of `pianoroll.opened`: the clip opened.
local record Opened
  clip: integer
end

--- A grid the row of tools offers: its name and its step in beats.
local type GridChoice = {string | number}

--- The piano roll: the view, and what each window of it keeps (the active
--- clip, the cursor's `pitch` and `beat`, the pitch at the top, the scroll
--- in beats, the note length, the clips edited with the active one).
--- Beats count from the start of the active clip.
local record PianoRoll is contracts.View, clips.Window
  -- Each window's own (`window_state`).
  pitch: integer
  top: integer
  seen_jump: integer
  geometry: Geometry
  length: number
  --- Zoom in to fit the clips at the next draw: the pointer opened them.
  fit_next: boolean
  --- The rows above the notes at the last draw.
  head: integer

  -- What modules add.
  tools: {ToolEntry}
  key_scopes: {KeyScope}
  layers: {LayerEntry}
  row_providers: {RowProvider}
  bands: {Band}
  describers: {Describer}
  enterers: {Enterer}
  grids: {GridChoice}
  strip: Strip

  clip: function(self: PianoRoll): objects.Clip
  play_beat: function(self: PianoRoll): number
  parts: function(self: PianoRoll): {Part}
  note_at: function(self: PianoRoll, pitch: integer, beat: number): types.Note, integer, Part
  toolbar_rows: function(h: integer, w: integer): integer
  tools_in_title: function(w: integer): boolean
  keys_width: function(w: integer): integer
  head_rows: function(h: integer, w: integer): integer
  tool: function(self: PianoRoll, name: string, fn: function(): Tool)
  toolbar: function(self: PianoRoll): {Tool}
  key_scope: function(self: PianoRoll, name: string, order: number, active: function(): boolean)
  layer: function(name: string, order: number, paint: function(layer: Layer))
  rows: function(name: string, fn: function(pitch: integer, track: integer): RowLook)
  band: function(name: string, order: number, spec: Band)
  describer: function(name: string, fn: function(note: types.Note, part: Part): Described)
  entering: function(name: string, fn: function(note: objects.NoteInput, clip: objects.Clip))
  row_look: function(pitch: integer, track: integer): RowLook
  active_bands: function(clip: objects.Clip): {Band}
  new_note: function(clip: objects.Clip, note: objects.NoteInput): objects.NoteInput
  draw_tools: function(self: PianoRoll, buf: Buf, clip: objects.Clip, ctx: contracts.RenderContext)
  title_tools: function(self: PianoRoll, buf: Buf, measure?: boolean): integer
  velocity_rows: function(h: integer): integer
  audition: function(self: PianoRoll, pitch?: integer)
  span: function(self: PianoRoll): number, number
  move: function(self: PianoRoll, dbeat: number, dpitch: integer)
  set: function(self: PianoRoll, pitch?: integer, beat?: number)
  ordered: function(self: PianoRoll): {clips.Note}
  to_note: function(self: PianoRoll, dir: integer, count?: integer)
  to_note_end: function(self: PianoRoll, count?: integer)
  to_bar: function(self: PianoRoll, n: integer)
  to_edge: function(self: PianoRoll, dir: integer)
  to_extreme: function(self: PianoRoll, dir: integer)
  paste: function(self: PianoRoll, value: EditModule.Yanked, before?: boolean, count?: integer)
  step_length: function(self: PianoRoll): number
  set_step: function(self: PianoRoll, length?: number)
  toggle_note: function(self: PianoRoll)
  change: function(self: PianoRoll, fn: function(note: types.Note)): boolean
  --- Bring the cursor along when the pointer scrolls (paw/views/pianoroll_mouse.tl).
  follow: function(self: PianoRoll)
end

--- The module: the roll's types, the event it sends, and the view.
local record M
  type PianoRoll = PianoRoll
  type Geometry = Geometry
  type Layer = Layer
  type Tool = Tool
  type RowLook = RowLook
  type Band = Band
  type BandContext = BandContext
  type Described = Described
  type StripKind = StripKind
  type Strip = Strip
  type Grab = Grab
  type NoteMark = NoteMark
  type NoteHit = NoteHit
  type ToolHit = ToolHit
  type ActHit = ActHit
  type Opened = Opened
  type GridChoice = GridChoice
  --- The event `pianoroll.opened`: the piano roll opened a clip.
  opened: events.Event<Opened>
  --- The view, as `paw.ui.views:get("pianoroll")` gives it.
  view: PianoRoll
end
M.opened = events.event("pianoroll.opened")

-- What this module reads of the modules that draw on the roll and act on
-- it: they name this module's types, so it cannot name theirs.
local record RollDraw
  hidden: function(clip: integer): {integer: boolean}
  controls_of: function(clip: objects.Clip): {types.Control}
  bend_of: function(controls: {types.Control}, note: types.Note): number, number
  stepping: function(): boolean
  status: function(): string
  label: function(): string
end
local record Frontend
  chosen_notes: function(clip: integer): {integer}
  chosen_text: function(clip: integer): string
end

local record Paw is partial.Paw
  ui: UiModule
  cursor: CursorModule
  draw: DrawModule
  keymap: KeymapModule
  harmony: HarmonyModule
  layout: LayoutModule
  tempo: TempoModule
  vzoom: VzoomModule
  attr: AttrModule
  edit: EditModule
  time: objects.Time
  clip: function(id: integer): objects.Clip
  roll_clips: clips
  roll_draw: RollDraw
  frontend: Frontend
end
local paw = (_G as {string: Paw}).paw
paw.roll_clips = clips

local view: PianoRoll = {
  pitch = 60, -- cursor row
  beat = 0, -- cursor column, in beats from the start of the active clip
  top = 72, -- pitch of the first row
  scroll = 0, -- beat at the left edge
  -- Each window of the roll has its own clip, cursor and scroll: two
  -- windows show two clips, or one clip twice. Each window has an instance
  -- that holds them (paw/layout.tl), and each seat its own instances.
  -- `edited` and `context_shown` are the state of paw/roll_clips.tl: the
  -- clips edited with the active one, and the toggles of the tracks shown
  -- behind them.
  window_state = {
    "clip_id",
    "pitch",
    "beat",
    "top",
    "scroll",
    "seen_jump",
    "geometry",
    "length",
    "edited",
    "context_shown",
  },
  window_fresh = {"geometry"},
  window_instances = true,
}

-- The clip -------------------------------------------------------------------------

--- True if the clip `id` is there (not undone or deleted).
local function exists(id: integer): boolean
  return id and pcall(api.clip_get, id)
end

function view:clip(): objects.Clip
  if exists(self.clip_id) then
    return paw.clip(self.clip_id)
  end
  self.clip_id = nil
end

--- Where play starts from this view: the cursor, as a beat of the song.
function view:play_beat(): number
  local clip = self:clip()
  if clip then
    return clip.start + self.beat
  end
end

--- The clips being edited, the active one first: `{ id, clip, offset, ... }`
--- each (see `paw.roll_clips.parts`).
function view:parts(): {Part}
  return clips.parts()
end

--- Open `clip` in this window: the cursor at its start, on its first note.
local function open(self: PianoRoll, clip: objects.Clip)
  self.clip_id, self.beat, self.scroll = clip.id, 0, 0
  -- A fit asked for by the pointer is for the clip it opened, not this one.
  self.fit_next = nil
  clips.only()
  local notes = clip:notes()
  self.pitch = notes[1] and notes[1].pitch or 60
  self.top = nil
end

--- Open a MIDI clip in the piano roll, alone.
function view:edit(clip: objects.Clip)
  if clip.kind ~= "midi" then
    return paw.notify("only MIDI clips open in the piano roll", "warn")
  end
  open(self, clip)
  paw.ui.focus("pianoroll")
  events.emit(M.opened, {clip = clip.id})
end

--- Open the clip a window's name gives (`:e roll://riff`, `:vs roll://7`):
--- by its name, its number or its address.
function view:open_target(target: string): boolean, string
  local clip = paw.layout.clip_named(target)
  if not clip then
    return false, "no clip `" .. tostring(target) .. "`"
  end
  if clip.kind ~= "midi" then
    return false, "only MIDI clips open in the piano roll"
  end
  open(self, clip)
  events.emit(M.opened, {clip = clip.id})
end

--- What a saved layout keeps of the window: the number of its clip, if
--- the clip is there (not undone or deleted).
function view:window_target(): string | integer
  if exists(self.clip_id) then
    return self.clip_id
  end
end

--- Shown beside a view that has a clip open (the notation view), the roll
--- takes that clip, as the arrange view's clip is taken: the window that
--- had the keyboard says which.
function view:on_show()
  local other = paw.ui.views:get(paw.ui.focused) as PianoRoll
  if not other or other == self or type(other.clip) ~= "function" then
    return
  end
  local clip = other:clip()
  if not clip or clip.kind ~= "midi" or clip.id == self.clip_id then
    return
  end
  self.clip_id, self.beat, self.scroll, self.top = clip.id, 0, 0, nil
  local notes = clip:notes()
  self.pitch = notes[1] and notes[1].pitch or 60
  clips.only()
end

--- The time this view shows, for windows bound in time (`timebind`): the
--- project's beat at the left edge, columns per beat, and beats shown.
--- The roll counts beats from the active clip's start.
function view:time_axis(_ctx?: contracts.RenderContext): number, number, number
  local clip = self:clip()
  if not clip then
    return nil
  end
  return clip.start + self.scroll, opt.note_zoom, self.geometry and self.geometry.span
end

function view:set_time_axis(left: number, zoom: number, _ctx?: contracts.RenderContext)
  local clip = self:clip()
  if not clip then
    return
  end
  -- As far left as the earliest clip edited starts, as the roll scrolls.
  local lo = clips.span()
  self.scroll = math.max(math.min(0, math.floor(lo or 0)), left - clip.start)
  if zoom and opt.note_zoom ~= zoom then
    opt.note_zoom = zoom
  end
end

--- The note under the cursor in any of the clips edited, the active one's
--- first: the note (its start in the roll's beats), its place among its
--- clip's notes, and its part.
function view:note_at(pitch: integer, beat: number): types.Note, integer, Part
  if not self:clip() or pitch < 0 or pitch > 127 then
    return
  end
  return clips.note_at(pitch, beat)
end

-- Its parts' sizes -------------------------------------------------------------------

--- Whether a panel `h` rows tall has a row of tools under its title.
--- (A panel `w` wide enough has them in its title row instead.)
function view.toolbar_rows(h: integer, w: integer): integer
  return not view.tools_in_title(w) and h >= 20 and 1 or 0
end

--- Whether a panel `w` columns wide has its tools in its title row.
function view.tools_in_title(w: integer): boolean
  return (w or 0) >= 140
end

--- Columns for the keyboard on the left of a panel `w` wide.
function view.keys_width(w: integer): integer
  return (w or 0) >= 100 and 8 or KEYS
end

--- Rows above the notes on a panel `h` rows tall and `w` wide: the panel's
--- title, the tools when they are not in it and there is room, the chord
--- symbols when `paw.opt.chords` asks for them and there is room, then the
--- ruler.
function view.head_rows(h: integer, w: integer): integer
  return 2 + view.toolbar_rows(h, w) + ((opt.chords and h >= 12) and 1 or 0)
end

--- Rows for the velocity lane on a panel `h` rows tall.
function view.velocity_rows(h: integer): integer
  return h >= 30 and 5 or h >= 16 and 3 or 0
end

-- What modules add -------------------------------------------------------------------

--- Remove the entry `name` of `list`.
local function drop<T>(list: {T}, name: string, name_of: function(T): string)
  for i = #list, 1, -1 do
    if name_of(list[i]) == name then
      table.remove(list, i)
    end
  end
end

-- Switches a module adds to the piano roll's row of tools: `fn()` returns
-- `{ label, on, tip, act }` (`act` names the `paw.frontend.act` function a
-- click calls, given the clip), or nil to show none for now.
view.tools = {}

function view:tool(name: string, fn: function(): Tool)
  drop(self.tools, name, function(t: ToolEntry): string return t.name end)
  if fn then
    self.tools[#self.tools + 1] = {name = name, fn = fn}
  end
end

function view:toolbar(): {Tool}
  local out: {Tool} = {}
  for _, tool in ipairs(self.tools) do
    local ok, t = pcall(tool.fn) as (boolean, Tool)
    if ok and t is Tool then
      out[#out + 1] = t
    end
  end
  return out
end

-- Keys that hold for a while: a module whose state takes keys of its own
-- (a suggestion showing, a snippet being filled in) names a scope of
-- mappings and says when it is on; while it is, its keys come before the
-- piano roll's, earlier entries first (`paw.keymap` looks here through
-- `subscope`).
--
--   paw.ui.views:get("pianoroll"):key_scope("pianoroll.complete", 50, function() return shown ~= nil end)
view.key_scopes = {}

function view:key_scope(name: string, order: number, active: function(): boolean)
  drop(self.key_scopes, name, function(s: KeyScope): string return s.name end)
  if not active then
    return
  end
  self.key_scopes[#self.key_scopes + 1] = {name = name, order = order, active = active}
  table.sort(self.key_scopes, function(a: KeyScope, b: KeyScope): boolean return a.order < b.order end)
end

function view:subscope(): string | {string}
  local out: {string} = {}
  for _, scope in ipairs(view.key_scopes) do
    local ok, on = pcall(scope.active) as (boolean, boolean)
    if ok and on then
      out[#out + 1] = scope.name
    end
  end
  return #out > 0 and out or nil
end

-- Layers that modules draw over the roll, from back to front by `order`:
-- other tracks' notes ("context", 10), the notes of the clips edited
-- ("notes", 20), diagnostics 30, the notes insert mode is drawing
-- ("draw", 35), a snippet's marks 40, suggestions 50; the
-- selection and the cursor last of all.
view.layers = {}

--- Draw `paint(p)` as a layer of the roll, replacing one of the same name
--- (nil removes it). `p` holds `roll` and `ruler` (cell buffers), `plane`
--- (the roll as a plane of beats along and pitches up, see `buf:plane`:
--- what is marked there a window paints where it is, between cells),
--- `clip` (the active one), `data` (its fields), `parts` (every clip
--- edited, see `paw.roll_clips`), `x(beat)` (a column of the roll) and
--- `axis` (the roll's time axis, paw/axis.tl, which gives it),
--- `row(pitch)` (its first row, nil when off screen), `scroll`, `from`
--- and `to` (the beats that show), `zoom`, `top`, `rows` (the pitches
--- shown), `per` (the rows of a pitch: the window's vertical zoom),
--- `width`, `focused` and `hue`. Beats are the roll's: the active clip's. Both frontends show
--- what a layer draws. A chip that does something is a hit region,
--- `p.roll:hit(x, y, w, 1, { kind = "act", act = name, arg = arg, tip = text })`:
--- a click calls `paw.frontend.act[name](clip, arg)`, and `tip` is what the
--- pointer over it says. A failing layer is skipped.
function view.layer(name: string, order: number, paint: function(layer: Layer))
  drop(view.layers, name, function(l: LayerEntry): string return l.name end)
  if paint then
    view.layers[#view.layers + 1] = {name = name, order = order, paint = paint}
  end
  table.sort(view.layers, function(a: LayerEntry, b: LayerEntry): boolean return a.order < b.order end)
  api.ui_redraw()
end

local function paint_layers(p: Layer)
  for _, layer in ipairs(view.layers) do
    local ok, err = pcall(layer.paint, p) as (boolean, string)
    if not ok then
      api.log("piano roll layer " .. layer.name .. ": " .. tostring(err))
    end
  end
end

-- What modules say about rows and notes, for an instrument whose keys mean
-- more than pitches (keyswitches, a playable range, drum pieces):
--
--   view.rows(name, fn)      fn(pitch, track) -> { label, style, shade } or nil:
--                            `label` (and its `style`) on the keyboard edge
--                            instead of the pitch, `shade` the row's style
--   view.band(name, order, spec)  a row of its own above the ruler while
--                            `spec.active(clip)`: `spec.title` on the
--                            keyboard edge, `spec.paint(buf, L)` in it
--   view.describer(name, fn) fn(note, part) -> lines `K` adds for a note;
--                            with `articulation = true` in the table they
--                            say the note's articulation for the roll
--   view.entering(name, fn)  fn(note, clip) changes a note the roll is
--                            about to enter (keys, insert mode, the mouse)
-- The first provider with something to say about a row wins. nil removes one.
view.row_providers, view.bands, view.describers, view.enterers = {}, {}, {}, {}

--- Put `entry` in `list` as `name` (nil removes it), in the order of `order`.
local function provide<T is Provided>(list: {T}, name: string, entry: T)
  drop(list, name, function(e: T): string return e.name end)
  if entry then
    entry.name = name
    list[#list + 1] = entry
  end
  table.sort(list, function(a: T, b: T): boolean return (a.order or 0) < (b.order or 0) end)
  api.ui_redraw()
end

function view.rows(name: string, fn: function(pitch: integer, track: integer): RowLook)
  provide(view.row_providers, name, fn and {fn = fn} as RowProvider)
end

function view.band(name: string, order: number, spec: Band)
  -- A copy, with the order given here.
  local band: Band = spec and {title = spec.title, active = spec.active, paint = spec.paint, order = order}
  provide(view.bands, name, band)
end

function view.describer(name: string, fn: function(note: types.Note, part: Part): Described)
  provide(view.describers, name, fn and {fn = fn} as Describer)
end

function view.entering(name: string, fn: function(note: objects.NoteInput, clip: objects.Clip))
  provide(view.enterers, name, fn and {fn = fn} as Enterer)
end

--- What the modules say about a row of a track, or nil.
function view.row_look(pitch: integer, track: integer): RowLook
  for _, p in ipairs(view.row_providers) do
    local ok, look = pcall(p.fn, pitch, track) as (boolean, RowLook)
    if ok and look then
      return look
    end
  end
end

--- The bands shown over a clip.
function view.active_bands(clip: objects.Clip): {Band}
  local out: {Band} = {}
  for _, band in ipairs(view.bands) do
    local ok, on = pcall(band.active, clip) as (boolean, boolean)
    if ok and on then
      out[#out + 1] = band
    end
  end
  return out
end

--- A note about to be entered in `clip`, as the modules want it.
function view.new_note(clip: objects.Clip, note: objects.NoteInput): objects.NoteInput
  for _, e in ipairs(view.enterers) do
    local ok, err = pcall(e.fn, note, clip) as (boolean, string)
    if not ok then
      api.log("piano roll entering " .. e.name .. ": " .. tostring(err))
    end
  end
  return note
end

-- The layers of the roll's own ---------------------------------------------------------

-- Other tracks' notes, behind the clips' own: each a dashed line on a
-- faint shade of its track's colour, without a name; the clips' own notes
-- are solid and named.
view.layer(
  "context",
  10,
  function(L: Layer)
    local glyph = opt.ascii and "-" or "╌"
    for _, n in ipairs(clips.context()) do
      local row = L.row(n.pitch)
      if row and n.start < L.to and n.start + n.length > L.from then
        local x0, x1 = L.axis:range(n.start, n.start + n.length)
        L.roll:fill(x0, row, x1 - x0, L.per, glyph, paw.draw.hue(n.color).body)
      end
    end
  end
)

-- The notes of the clips being edited: each a note on the roll's plane,
-- and what the pointer finds there.
view.layer(
  "notes",
  20,
  function(L: Layer)
    -- A selection that names its notes (`viv`) shows on them.
    local selection = paw.ui.focused == "pianoroll" and paw.keymap.selection()
    local named = selection and selection.notes
    for i, part in ipairs(L.parts) do
      local colour = paw.draw.track_colour(api.track_get(part.track))
      local hue = i == 1 and L.hue or paw.draw.hue(colour)
      local chosen: {integer: boolean} = {}
      for _, place in ipairs(paw.frontend.chosen_notes(part.id)) do
        chosen[place] = true
      end
      local shown, places = part.clip:notes(
        {from = L.from - part.offset, to = L.to - part.offset, low = math.max(0, L.top - L.rows + 1), high = L.top}
      )
      -- The notes insert mode's pencil holds show where it has them; each
      -- note's own bend shows on it.
      local held = paw.roll_draw.hidden(part.id) or {}
      local controls = #shown > 0 and paw.roll_draw.controls_of(part.clip) or {}
      local ids: {integer: boolean} = named and named[part.id] or {}
      for k, note in ipairs(shown) do
        if not held[note.id] then
          local place, start = places[k], note.start + part.offset
          local at_cursor = L.under_part and L.under_part.id == part.id and place == L.under_place
          if ids[note.id] then
            chosen[place] = true
          end
          local style = at_cursor and "NoteCursor"
            or ids[note.id] and "Visual"
            or chosen[place] and hue.title_cur
            or paw.draw.note_style(hue, note.velocity)
          -- Long enough notes say which they are, or the articulation
          -- (MIDI 2.0 attribute) they carry.
          local said = note.attr and paw.attr.describe(note.attr)
          local bend, bend_at = paw.roll_draw.bend_of(controls, note)
          local hit: NoteHit = {
            kind = "note",
            clip = part.id,
            place = place,
            pitch = note.pitch,
            start = start,
            length = note.length,
          }
          local mark: NoteMark = {
            label = said and said.tag or music.name(note.pitch),
            style = style,
            color = colour,
            velocity = note.velocity,
            selected = chosen[place] or nil,
            cursor = at_cursor or nil,
            key = "note:" .. part.id .. ":" .. place,
            bend = bend,
            bend_at = bend_at,
            hit = hit,
          }
          L.plane:mark("note", start, note.pitch, note.length, 1, mark)
        end
      end
    end
  end
)

-- The row of tools -------------------------------------------------------------------

-- The grids the row of tools offers, as `:grid` takes them.
view.grids = {
  {"1/1", 4},
  {"1/2", 2},
  {"1/4", 1},
  {"1/8", 0.5},
  {"1/16", 0.25},
  {"1/32", 0.125},
  {"1/8 triplet", 1 / 3},
  {"1/16 triplet", 1 / 6},
}

--- The tools the pointer reaches without keys, in order: `{ name, text,
--- tip, on, menu, act }` each (`menu` for one that opens a menu).
local function tool_list(self: PianoRoll, titled: boolean): {ToolButton}
  local grid_text = statusline.grid_text
  local list: {ToolButton} = {
    {
      name = "tracks",
      text = "Tracks",
      tip = "the tracks whose notes show behind these, and the clips edited together (also :roll.tracks)",
    },
    {
      name = "grid",
      text = "Grid " .. grid_text(opt.note_grid),
      menu = true,
      tip = "the grid notes snap to and the lines it draws (also :grid)",
    },
    {
      name = "snap",
      text = "Snap",
      on = opt.note_snap,
      tip = "snap to the grid: notes land on it (Shift while dragging leaves it)",
    },
    {
      name = "length",
      text = "Note " .. grid_text(self:step_length()),
      menu = true,
      tip = "the length a click gives a note; drawing a note sets it",
    },
    {
      name = "quantize",
      text = "Quantize",
      tip = "the chosen notes, or all of them, start on the grid (also :notes.quantize)",
    },
    {
      name = "step",
      text = "Step",
      on = paw.roll_draw.stepping(),
      tip = "step input (I): notes played on a MIDI keyboard go in at the cursor, one undo step; Esc writes them",
    },
    {
      name = "list",
      text = "List",
      tip = "the event list: every note and controller move of the clip, a row each (also E)",
    },
  }
  for _, t in ipairs(self:toolbar()) do
    list[#list + 1] = {name = "layer", act = t.act, text = t.label, on = t.on, tip = t.tip}
  end
  list[#list + 1] = {
    name = "zoom_out", text = "-", tip = "zoom out in time (Ctrl and the wheel zoom where the pointer is)"
  }
  list[#list + 1] = {name = "zoom_in", text = "+", tip = "zoom in in time"}
  if titled then
    list[#list + 1] = {
      name = "window",
      text = "Window",
      tip = "the piano roll in a window of its own, in a graphical frontend (also :view.window)",
    }
    list[#list + 1] = {name = "close", text = "x", tip = "close the piano roll"}
  end
  return list
end

--- The tools as buttons on a row of `buf` from column `x`; each a button
--- whose hit region names it (paw/views/pianoroll_mouse.tl). Returns the
--- columns they take; with `measure`, draws nothing.
local function place_tools(buf: Buf, list: {ToolButton}, x: integer, measure?: boolean): integer
  local from = x
  local caret = opt.ascii and "v" or "▾"
  for _, t in ipairs(list) do
    local text = " " .. t.text .. (t.menu and " " .. caret or "") .. " "
    local w = api.str_width(text)
    if x + w > buf.width then
      break
    end
    if not measure then
      local hit: ToolHit = {kind = "tool", name = t.name, act = t.act, tip = t.tip}
      local mark: ButtonMark = {
        text = text,
        on = t.on or nil,
        menu = t.menu or nil,
        style = "TrackInfo",
        on_style = "TitleBarFocus",
        label = t.text,
        hit = hit,
      }
      buf:mark("button", x, 0, w, 1, mark)
    end
    x = x + w + 1
  end
  return x - from
end

--- What the pointer has chosen, or what insert mode is doing: said where
--- the tools are.
local function said_now(clip: objects.Clip, ctx: contracts.RenderContext): string
  return ctx.focused and paw.keymap.mode == "i" and paw.roll_draw.status() or paw.frontend.chosen_text(clip.id)
end

--- The tools under the title, on a row of their own (`buf`), where the
--- panel is not wide enough for them in its title: then what the pointer
--- has chosen, or what insert mode is doing.
function view.draw_tools(self: PianoRoll, buf: Buf, clip: objects.Clip, ctx: contracts.RenderContext)
  buf:fill(0, 0, buf.width, 1, " ", "Ruler")
  local x = 1 + place_tools(buf, tool_list(self, false), 1)
  local said = said_now(clip, ctx)
  if said and said ~= "" and buf.width - x > 6 then
    buf:text(x + 1, 0, util.fit(said, buf.width - x - 2), "RulerChordEdge")
  end
end

--- The tools at the right end of the title row (`buf`, the row): the
--- columns they take, from the right edge; with `measure`, draws nothing.
function view.title_tools(self: PianoRoll, buf: Buf, measure?: boolean): integer
  local list = tool_list(self, true)
  local w = place_tools(buf, list, 0, true)
  local x = math.max(0, buf.width - w)
  if not measure then
    place_tools(buf, list, x)
  end
  return w
end

-- Drawing -----------------------------------------------------------------------------

--- What a draw of the roll works out before it draws: the sizes of its
--- parts (as `Geometry`), whether its tools are in the title row, the row
--- of the chord symbols, the bands, the columns of the grid (`tw`) and of
--- the scroll bar, the grid step, and the stretch the clips cover.
local record Frame
  w: integer
  h: integer
  geometry: Geometry
  tools: integer
  titled: boolean
  chords_row: integer
  bands: {Band}
  bar: integer
  tw: integer
  grid: number
  lo: number
  hi: number
end

--- The sizes of the parts of a roll drawn in `buf`.
local function frame_of(buf: Buf, clip: objects.Clip): Frame
  local w, h = buf.width, buf.height
  local lo, hi = clips.span()
  local titled = view.tools_in_title(w)
  local tools = view.toolbar_rows(h, w)
  local keys = view.keys_width(w)
  -- With room to spare, the notes' velocities get a few rows of their own.
  local vel = view.velocity_rows(h)
  local bands = h >= 12 and view.active_bands(clip) or {}
  local head = view.head_rows(h, w) + #bands
  -- A wide roll has a scroll bar through the pitches in a column of its own.
  local bar = titled and 1 or 0
  -- The grid's lines, and the keys on them: a key is `per` lines tall
  -- with the window's vertical zoom (paw/vzoom.tl).
  local per = paw.vzoom.key_rows()
  local grid_h, tw = h - head - vel, w - keys - bar
  return {
    w = w,
    h = h,
    geometry = {
      rows = math.max(1, math.floor(grid_h / per)),
      lines = grid_h,
      per = per,
      zoom = opt.note_zoom,
      keys = keys,
      head = head,
      vel = vel,
    },
    tools = tools,
    titled = titled,
    chords_row = opt.chords and h >= 12 and 1 + tools or nil,
    bands = bands,
    bar = bar,
    tw = tw,
    grid = opt.note_grid,
    lo = lo,
    hi = hi,
  }
end

--- Opened by the pointer (`fit_next`), zoomed in as far as the clips and
--- a bar after them fill the width, never out.
local function fit_zoom(self: PianoRoll, f: Frame, c: types.Clip)
  if not self.fit_next then
    return
  end
  self.fit_next = nil
  local fit = math.floor(f.tw / (f.hi - math.min(0, f.lo) + paw.time.bar_ceil(c.start + 1) - c.start) * 4) / 4
  if fit > f.geometry.zoom then
    f.geometry.zoom = math.min(64, fit)
    opt.note_zoom = f.geometry.zoom
  end
end

--- Keep the cursor on screen: the pitches and, unless another window
--- leads this one's time (`timebind`), the beats.
local function keep_cursor(self: PianoRoll, f: Frame, ctx: contracts.RenderContext)
  local g = f.geometry
  local rows, span, zoom = g.rows, g.span, g.zoom
  if not self.top then
    self.top = self.pitch + math.floor(rows / 2)
  end
  if self.pitch > self.top then
    self.top = self.pitch
  end
  if self.pitch <= self.top - rows then
    self.top = self.pitch + rows - 1
  end
  self.top = math.floor(util.clamp(self.top, rows - 1, 127))
  local jumped = paw.keymap.jump_serial ~= self.seen_jump
  self.seen_jump = paw.keymap.jump_serial
  if not ctx.follower then
    local to = paw.draw.jump_scroll(axis.new(self.scroll, zoom), self.beat, span, jumped)
    if to then
      self.scroll = math.floor(to)
    elseif self.beat < self.scroll then
      self.scroll = math.floor(self.beat)
    elseif self.beat >= self.scroll + span - f.grid then
      self.scroll = math.ceil(self.beat - span + 1)
    end
  end
  self.scroll = math.max(math.min(0, math.floor(f.lo)), self.scroll)
end

--- Title: the active clip in its track's colour, the track and how many
--- clips are edited, where the cursor is and the chord sounding there; on
--- the right what the keys will enter. A wide panel has its tools at the
--- right of the title row, and says there what is chosen or what insert
--- mode is doing, as the row of tools does where they have a row of its own.
local function draw_title(
  self: PianoRoll, buf: Buf, f: Frame, clip: objects.Clip, c: types.Clip, ctx: contracts.RenderContext, chord: string
)
  local w = f.w
  local track = api.track_get(c.track)
  local parts = #clips.ids()
  local grid_text = statusline.grid_text
  local right = string.format("grid %s  len %s  vel %d", grid_text(f.grid), grid_text(self:step_length()), opt.velocity)
  local place = music.name(self.pitch) .. "  " .. paw.time.format(c.start + self.beat)
  local title_row = buf:sub(0, 0, w, 1)
  local reserve = f.titled and self:title_tools(title_row, true) or 0
  if f.titled then
    right = said_now(clip, ctx)
  end
  paw.ui.titlebar(
    buf,
    {
      pill = {c.name, paw.draw.track_hue(track).pill},
      focused = ctx.focused,
      name = parts > 1 and string.format("%s  +%d clip%s", track.name, parts - 1, parts == 2 and "" or "s")
        or track.name,
      context = chord and place .. "  " .. chord or place,
      right = (f.titled or w >= 90) and right ~= "" and right or nil,
      reserve = reserve,
    }
  )
  if ctx.focused and paw.keymap.mode == "i" and not f.titled then
    local text = " " .. paw.roll_draw.label() .. " "
    buf:text(math.max(0, w - api.str_width(text) - 1), 0, text, "RulerInsert")
  end
  if f.titled then
    self:title_tools(title_row)
  end
  if f.tools > 0 then
    self:draw_tools(buf:sub(0, 1, w, 1), clip, ctx)
  end
end

--- The rows over the grid: the ruler (bars as the project counts them,
--- beats in between) and above it the chords that sound, read over every
--- pitched track, with the key, and the bands. Returns the lines of the
--- ruler.
local function draw_ruler(
  self: PianoRoll, buf: Buf, f: Frame, clip: objects.Clip, c: types.Clip
): {DrawModule.RulerLine}
  local g = f.geometry
  local w, head, keys, tw, ax, span = f.w, g.head, g.keys, f.tw, g.axis, g.span
  buf:fill(0, head - 1, w, 1, " ", "Ruler")
  buf:hit(0, head - 1, w, 1, {kind = "ruler"})
  local ruler = buf:sub(keys, head - 1, tw, 1)
  if f.chords_row then
    local row = f.chords_row
    buf:fill(0, row, w, 1, " ", "Ruler")
    local key = paw.harmony.key(c.start + self.scroll, true)
    buf:text(0, row, (key.name:gsub(" major", ""):gsub(" minor", "m")):sub(1, keys - 1), "RulerChordEdge")
    paw.harmony.draw(buf:sub(keys, row, tw, 1), ax, span, c.start)
  end
  local lines = paw.draw.beats(ruler, ax, span, c.start)
  local bands = f.bands
  for i, band in ipairs(bands) do
    local y = head - 1 - #bands + i - 1
    buf:fill(0, y, w, 1, " ", "Ruler")
    buf:text(0, y, util.fit(band.title or band.name, keys - 1), "RulerChordEdge")
    local ok, err = pcall(
      band.paint,
      buf:sub(keys, y, tw, 1),
      {
        clip = clip,
        data = c,
        from = self.scroll,
        to = self.scroll + span,
        zoom = ax.zoom,
        width = tw,
        lines = lines,
        x = function(beat: number): integer return ax:x_of(beat) end,
      } as BandContext
    ) as (boolean, string)
    if not ok then
      api.log("piano roll band " .. band.name .. ": " .. tostring(err))
    end
  end
  return lines
end

--- Steps between the beats when zoomed in far enough to see them. They are
--- the same on every row: one line of text, drawn row by row. Nil when
--- they do not show.
local function steps_line(f: Frame, lines: {DrawModule.RulerLine}): string
  local ax, grid, tw = f.geometry.axis, f.grid, f.tw
  if not (ax:cells(1) >= 8 and grid < 1) then
    return nil
  end
  local cells: {string} = {}
  for i = 1, tw do
    cells[i] = " "
  end
  for _, line in ipairs(lines) do
    for k = 1, math.floor(1 / grid + 0.5) - 1 do
      local x = ax:x_of(line.beat + k * grid)
      if x >= 0 and x < tw then
        cells[x + 1] = paw.draw.g.step
      end
    end
  end
  return table.concat(cells)
end

--- The grid's rows, the lines of the beats and bars on them, and the
--- keyboard down the left: what the track's instrument calls its keys (a
--- drum, a keyswitch) is written on them, and the pitches `sounding` at the
--- cursor are lit.
local function draw_rows(
  self: PianoRoll, buf: Buf, roll: Buf, f: Frame, c: types.Clip, lines: {DrawModule.RulerLine}, sounding: {integer}
)
  local g = f.geometry
  local tw, per = f.tw, g.per
  local glyphs = paw.draw.g
  local steps = steps_line(f, lines)
  local key_names = paw.plugins.key_names(c.track)
  local start_x, end_x = g.axis:x_of(f.lo), g.axis:x_of(f.hi)
  local names, labels: {{integer | string}}, {{integer | string}} = {}, {}
  for row = 0, g.rows * per - 1 do
    local pitch = self.top - math.floor(row / per)
    local black = music.is_black(pitch)
    local look = view.row_look(pitch, c.track) or {}
    if row % per == 0 and key_names[pitch] then
      names[#names + 1] = {pitch, key_names[pitch]}
    end
    if row % per == 0 and look.label then
      labels[#labels + 1] = {pitch, look.label, look.style}
    end
    roll:fill(0, row, tw, 1, " ", look.shade or (black and "RollRowBlack" or "RollRow"))
    if steps then
      roll:text(0, row, steps, black and "RollStepBlack" or "RollStep")
    end
    for _, line in ipairs(lines) do
      roll:text(line.x, row, line.bar and glyphs.bar or glyphs.beat, line.bar and "RollBar" or "RollBeat")
    end
    -- Before and past the clips, the grid goes on, shaded.
    local outside = black and "RollOutsideBlack" or "RollOutside"
    if start_x > 0 then
      roll:fill(0, row, math.min(tw, start_x), 1, nil, outside)
    end
    if end_x < tw then
      roll:fill(math.max(0, end_x), row, tw, 1, nil, outside)
    end
  end
  local keyboard: KeyboardMark = {
    top = self.top,
    per = per,
    cursor = self.pitch,
    names = names,
    labels = labels,
    sounding = sounding,
    hit = {kind = "keys"},
  }
  buf:mark("keyboard", 0, g.head, g.keys, g.lines, keyboard)
end

--- The playhead is a thin line on the beat's left edge, under the notes,
--- with a cap on the ruler: one that starts where it stands is drawn
--- whole, from where it starts. A window moves it as the song plays.
local function draw_playhead(self: PianoRoll, buf: Buf, f: Frame, c: types.Clip)
  local g = f.geometry
  local playhead: PlayheadMark = {
    at = api.transport_get().position,
    from = c.start + self.scroll,
    per = g.zoom,
    lo = c.start + f.lo,
    hi = c.start + f.hi,
    bind = "position",
  }
  buf:mark("playhead", g.keys, g.head - 1, f.tw, g.lines + 1, playhead)
end

--- How hard each note on screen is played, along the bottom, with a button
--- at its left that chooses what the strip shows.
local function draw_velocities(self: PianoRoll, buf: Buf, f: Frame, L: Layer, lines: {DrawModule.RulerLine})
  local g = f.geometry
  local vel, keys, tw, top = g.vel, g.keys, f.tw, g.head + g.lines
  local glyphs = paw.draw.g
  local lane = buf:sub(keys, top, tw, vel)
  buf:fill(0, top, f.w, vel, " ", "VelocityLane")
  buf:hit(0, top, f.w, vel, {kind = "velocity"})
  -- What it shows, which a click on it chooses.
  local shown = self.strip and self.strip.shown() or {label = "Velocity", short = "vel"}
  local button: ButtonMark = {
    text = " " .. shown.short .. " " .. (opt.ascii and "v" or "▾"),
    menu = true,
    style = "VelocityLane",
    label = shown.label,
    hit = {kind = "velocity"},
  }
  buf:mark("button", 0, top + vel - 1, keys, 1, button)
  for _, line in ipairs(lines) do
    if line.bar then
      lane:fill(line.x, 0, 1, vel, glyphs.bar, "RollBar")
    end
  end
  for i, part in ipairs(L.parts) do
    local fg = i == 1 and L.hue.fg or paw.draw.track_hue(api.track_get(part.track)).fg
    local all, places = part.clip:notes({from = self.scroll - part.offset, to = self.scroll + g.span - part.offset})
    for k, note in ipairs(all) do
      local x0 = g.axis:x_of(note.start + part.offset)
      local level = note.velocity / 127 * vel * 8
      local at_cursor = L.under_part and L.under_part.id == part.id and places[k] == L.under_place
      for row = 0, vel - 1 do
        local amount = level - (vel - 1 - row) * 8
        if amount >= 1 then
          lane:text(x0, row, glyphs.eighths[math.min(8, math.floor(amount))], at_cursor and "Bright" or fg)
        end
      end
      if at_cursor then
        lane:text(x0 + 1, 0, tostring(note.velocity), "Bright")
      end
    end
  end
end

--- The selection of visual mode (a stretch of time, a block, or whole
--- pitches), and the cursor: on a note, the note shows it, unless a
--- selection or insert mode is under way.
local function draw_cursor(self: PianoRoll, roll: Buf, f: Frame, ctx: contracts.RenderContext, under_place: integer)
  local g = f.geometry
  local rows, per, ax, tw = g.rows, g.per, g.axis, f.tw
  local selection = ctx.focused and paw.keymap.selection()
  -- One that names its notes shows on the notes themselves.
  if selection and not selection.notes then
    local x0 = math.max(0, ax:x_of(selection.c0))
    local x1 = math.min(tw, ax:x_of(selection.c1))
    local y0, y1 = math.max(0, self.top - selection.r1), math.min(rows - 1, self.top - selection.r0)
    if selection.kind == "line" then
      x0, x1 = 0, tw
    elseif selection.kind == "char" then
      y0, y1 = 0, rows - 1
    end
    if x1 > x0 and y1 >= y0 then
      roll:fill(x0, y0 * per, x1 - x0, (y1 - y0 + 1) * per, nil, "Visual")
    end
  end
  local inserting = ctx.focused and paw.keymap.mode == "i"
  local cx, after = ax:range(self.beat, self.beat + f.grid)
  local cw = after - cx
  if not under_place or selection or inserting then
    roll:fill(cx, (self.top - self.pitch) * per, cw, per, nil, inserting and "InsertCursor" or "RollCursor")
  end
end

--- Where the view is among the pitches, down its right side.
local function draw_scrollbar(self: PianoRoll, buf: Buf, f: Frame)
  local g = f.geometry
  local x = g.keys + f.tw
  buf:fill(x, g.head, 1, g.lines, " ", "RollRowBlack")
  local hit: ScrollHit = {kind = "scrollbar", axis = "y"}
  local bar: ScrollbarMark = {axis = "y", from = 127 - self.top, span = g.rows, total = 128, hit = hit}
  buf:mark("scrollbar", x, g.head, 1, g.lines, bar)
end

--- The roll with no clip open: how to open one.
local function draw_empty(buf: Buf, ctx: contracts.RenderContext)
  paw.ui.titlebar(buf, {name = "Piano roll", focused = ctx.focused})
  buf:text(2, 2, "No clip open.", "Empty")
  local lead = "Put the cursor on a MIDI clip in the arrange view and press "
  buf:text(2, 3, lead, "Empty")
  buf:text(2 + #lead, 3, "Enter", "EmptyKey")
end

--- Draw the roll of the active clip, part by part.
local function draw_roll(self: PianoRoll, buf: Buf, clip: objects.Clip, ctx: contracts.RenderContext)
  local c = clip:get()
  local f = frame_of(buf, clip)
  local g = f.geometry
  fit_zoom(self, f, c)
  g.span = axis.new(self.scroll, g.zoom):beats(f.tw)
  self.head = g.head
  keep_cursor(self, f, ctx)
  -- The roll's axis, at the scroll it has now: every row draws on it.
  g.axis = axis.new(self.scroll, g.zoom)
  self.geometry = g

  local sounding, chord = clips.sounding(self.beat)
  draw_title(self, buf, f, clip, c, ctx, chord)
  local lines = draw_ruler(self, buf, f, clip, c)
  local roll = buf:sub(g.keys, g.head, f.tw, g.lines)
  draw_rows(self, buf, roll, f, c, lines, sounding)
  draw_playhead(self, buf, f, c)

  -- The grid as a plane: beats along from the left edge, a row a pitch
  -- down from the top. What the layers mark on it a window paints where
  -- it is; a press on its empty part is on the grid.
  local plane = buf:plane(
    g.keys,
    g.head,
    f.tw,
    g.lines,
    {
      key = "roll",
      hit = {kind = "grid"},
      x = {domain = "beat", from = self.scroll, per = g.zoom},
      y = {domain = "pitch", from = self.top + 1, per = -g.per},
    }
  )

  -- The layers, back to front. Only what is on screen crosses over from the core.
  local _, under_place, under_part = self:note_at(self.pitch, self.beat)
  local scroll, top, rows, per = self.scroll, self.top, g.rows, g.per
  local ax = g.axis
  local L: Layer = {
    roll = roll,
    ruler = buf:sub(g.keys, g.head - 1, f.tw, 1),
    plane = plane,
    clip = clip,
    data = c,
    scroll = scroll,
    from = scroll,
    to = scroll + g.span,
    top = top,
    rows = rows,
    per = per,
    zoom = ax.zoom,
    axis = ax,
    width = f.tw,
    focused = ctx.focused,
    parts = clips.parts(),
    hue = paw.draw.track_hue(api.track_get(c.track)),
    under_place = under_place,
    under_part = under_part,
    x = function(beat: number): integer return ax:x_of(beat) end,
    row = function(pitch: integer): integer
      local row = top - pitch
      return row >= 0 and row < rows and row * per or nil
    end,
  }
  paint_layers(L)

  if g.vel > 0 then
    draw_velocities(self, buf, f, L, lines)
  end
  draw_cursor(self, roll, f, ctx, under_place)
  if f.bar > 0 then
    draw_scrollbar(self, buf, f)
  end
end

function view:render(buf: Buf, ctx: contracts.RenderContext)
  local self = self as PianoRoll
  buf:fill(0, 0, buf.width, buf.height, " ", "Normal")
  local clip = self:clip()
  if clip then
    draw_roll(self, buf, clip, ctx)
  else
    draw_empty(buf, ctx)
  end
  -- The strip under the notes draws over their velocities.
  if self.strip then
    self.strip.draw(self, buf)
  end
end

--- What a window of the roll shows besides what events announce (the
--- screen keeps the window while it is the same): its clip, its cursor,
--- its scroll, and whether a jump or another window moves its time.
function view:stamp(ctx: contracts.RenderContext): string
  local self = self as PianoRoll
  return table.concat(
    {
      tostring(self.clip_id),
      self.pitch,
      self.beat,
      tostring(self.top),
      self.scroll,
      tostring(self.length),
      tostring(self.fit_next),
      tostring(self.seen_jump == paw.keymap.jump_serial),
      tostring(ctx.follower),
    } as {string | number},
    " "
  )
end

-- The cursor ---------------------------------------------------------------------------

--- Play the pitch under the cursor on the track of the clip it is in.
function view:audition(pitch?: integer)
  local part = clips.target(self.beat)
  if part then
    part.clip:track():play_note(pitch or self.pitch, opt.velocity, 180)
  end
end

--- How far the cursor can go: the stretch of the clips edited.
function view:span(): number, number
  return clips.span()
end

function view:move(dbeat: number, dpitch: integer)
  if not self:clip() then
    return
  end
  -- One step past the last is allowed, so that a selection can reach the end.
  local lo, hi = self:span()
  -- Whole steps of the grid count from its lines, so that no sum of
  -- steps drifts off them (paw/cursor.tl `step`).
  local grid = opt.note_grid
  local steps = math.floor(dbeat / grid + 0.5)
  local to = math.abs(dbeat - steps * grid) < grid * 1e-6 and paw.cursor.step(self.beat, steps, grid)
    or self.beat + dbeat
  self.beat = util.clamp(to, lo, hi)
  local pitch = math.floor(util.clamp(self.pitch + dpitch, 0, 127))
  if pitch ~= self.pitch then
    self.pitch = pitch
    self:audition()
  end
  api.ui_redraw()
end

--- Put the cursor somewhere without sounding the pitch; nil leaves that
--- part of it where it is. Unlike `move` it can sit right at the end of the
--- clip, where a selection or a deletion may need to reach.
function view:set(pitch?: integer, beat?: number)
  if not self:clip() then
    return
  end
  if pitch then
    self.pitch = math.floor(util.clamp(pitch, 0, 127))
  end
  if beat then
    local lo, hi = self:span()
    self.beat = util.clamp(beat, lo, hi)
  end
  api.ui_redraw()
end

--- The notes of the clips edited in the order they start, lower pitches
--- first within a chord, their starts in the roll's beats.
function view:ordered(): {clips.Note}
  if not self:clip() then
    return {}
  end
  -- One clip's are in the order the core keeps them in.
  return clips.notes()
end

--- Go to the next (`dir` 1) or previous (-1) note, wherever its pitch is.
function view:to_note(dir: integer, count?: integer)
  local notes = self:ordered()
  for _ = 1, count or 1 do
    local found: clips.Note
    if dir > 0 then
      for _, n in ipairs(notes) do
        if n.start > self.beat + 1e-9 then
          found = n
          break
        end
      end
    else
      for i = #notes, 1, -1 do
        if notes[i].start < self.beat - 1e-9 then
          found = notes[i]
          break
        end
      end
    end
    if not found then
      -- Past the last note there is the end of the clips; before the first, their start.
      if dir > 0 then
        self:to_edge(-1)
      else
        self:set(nil, (self:span()))
      end
      return
    end
    self:set(found.pitch, found.start)
  end
end

--- Go to where the note under the cursor ends, or else the next one to end.
function view:to_note_end(count?: integer)
  for _ = 1, count or 1 do
    local best: clips.Note
    for _, n in ipairs(self:ordered()) do
      local finish = n.start + n.length
      if finish > self.beat + 1e-9 and (not best or finish < best.start + best.length) then
        best = n
      end
    end
    if not best then
      return
    end
    self:set(best.pitch, best.start + best.length)
  end
end

--- Go `n` bars on, or back with a negative `n`, to where a bar starts.
function view:to_bar(n: integer)
  local clip = self:clip()
  if not clip then
    return
  end
  local at = clip.start + self.beat
  local bar = paw.time.bar_of(at)
  local to = n > 0 and bar + n or bar + n + (paw.tempo.is_bar_line(at) and 0 or 1)
  self:set(nil, paw.time.bar_start(math.max(1, to)) - clip.start)
end

--- Go to the first note (`dir` 1) or to the end of the clips (-1).
function view:to_edge(dir: integer)
  if not self:clip() then
    return
  end
  local lo, hi = self:span()
  if dir < 0 then
    return self:set(nil, hi)
  end
  local first = self:ordered()[1]
  if first then
    self:set(first.pitch, first.start)
  else
    self:set(nil, lo)
  end
end

--- Go to the pitch of the highest (`dir` 1) or lowest (-1) note.
function view:to_extreme(dir: integer)
  local best: integer
  for _, n in ipairs(self:ordered()) do
    if not best or (n.pitch - best) * dir > 0 then
      best = n.pitch
    end
  end
  if best then
    self:set(best, nil)
  end
end

-- Editing ------------------------------------------------------------------------------

--- Where the last paste left the cursor (`clip` and `beat`), where it
--- ended, and the project's edits then.
local record LastPaste
  clip: integer
  beat: number
  finish: number
  edits: integer
end
local last_paste: LastPaste

--- Paste yanked notes `count` times one after another: after the note under
--- the cursor, or right at the cursor with `before`. Notes yanked from
--- clips that are edited now go back into them; the rest go into the clip
--- at the cursor.
function view:paste(value: EditModule.Yanked, before?: boolean, count?: integer)
  local clip = self:clip()
  if not clip then
    return
  end
  local at = self.beat
  if not before then
    local edits = project_edits("edits")
    if last_paste and last_paste.clip == clip.id and last_paste.beat == at and last_paste.edits == edits then
      -- Pasting again right after a paste carries on where that one ended.
      at = last_paste.finish
    else
      local note = self:note_at(self.pitch, self.beat)
      if note then
        at = note.start + note.length
      end
    end
  end
  local start = at
  for _ = 1, count or 1 do
    start = at
    local parts = clips.parts()
    -- Several clips go as their list, one as the clip itself.
    local target = #parts > 1 and parts as EditModule.Target or clip as EditModule.Target
    local finish = paw.edit.roll.paste(target, value, self.pitch, at, clips.target(at, parts) as EditModule.Part)
    if not finish then
      return
    end
    at = finish
  end
  self:set(nil, start)
  last_paste = {clip = clip.id, beat = self.beat, finish = at, edits = project_edits("edits")}
end

-- The note length: what a click gives a note, and the step of step input.

--- How long a new note is: the note length, or a grid step when it is unset.
function view:step_length(): number
  return self.length or opt.note_grid
end

function view:set_step(length?: number)
  self.length = length
  api.ui_redraw()
end

-- What modal editing works on: rows are pitches, which count upwards.
view.grid = {
  down = -1,
  get = function(): number, number return view.pitch, view.beat end,
  set = function(row: number, col: number) view:set(row as integer, col) end,
  step = function(): number return opt.note_grid end,
  -- A selection takes in the note under its far end, as Vim's takes in the
  -- character under the cursor.
  extent = function(row: number, col: number): number
    local note = view:note_at(row as integer, col)
    if note then
      return note.start + note.length
    end
  end,
  -- Notes by the name of their pitch: `c` finds every C and C sharp, `c4` one key.
  search = function(text: string): {contracts.GridHit}
    local wanted = text:lower()
    local hits: {contracts.GridHit} = {}
    for _, n in ipairs(view:ordered()) do
      if music.name(n.pitch):lower():find(wanted, 1, true) == 1 then
        hits[#hits + 1] = {row = n.pitch, col = n.start}
      end
    end
    return hits
  end,
}

--- Add a note at the cursor, or remove the one that is there.
function view:toggle_note()
  if not self:clip() then
    return
  end
  local _, place, part = self:note_at(self.pitch, self.beat)
  if place then
    part.clip:remove_note(place)
  else
    part = clips.target(self.beat)
    part.clip:add_note(
      view.new_note(
        part.clip, {pitch = self.pitch, start = self.beat - part.offset, length = self.length or opt.note_grid}
      )
    )
    self:audition()
  end
end

--- The lines that `K` says of a note's own bend, the key's name and the
--- chord that the note starts in.
local function describe_more(lines: contracts.Description, note: types.Note, part: Part)
  -- The note as its own clip has it: its start in that clip's beats.
  local own = note
  if part.offset ~= 0 then
    own = {
      start = note.start - part.offset,
      length = note.length,
      pitch = note.pitch,
      velocity = note.velocity,
      id = note.id,
      meta = note.meta,
      attr = note.attr,
    }
  end
  local bend, bend_at = paw.roll_draw.bend_of(paw.roll_draw.controls_of(part.clip), own)
  if bend then
    lines[#lines + 1] = string.format(
      "  bends %s %g semitone%s by its end, from %d%% of it (its own pitch bend)",
      bend > 0 and "up" or "down",
      math.abs(bend),
      math.abs(bend) == 1 and "" or "s",
      math.floor(bend_at * 100 + 0.5)
    )
  end
  local key = paw.plugins.key_names(part.track)[note.pitch]
  if key then
    lines[#lines + 1] = "  the instrument calls this key " .. key
  end
  -- The chord the note starts in, as paw.harmony reads it. After an edit,
  -- the reading is made again in slices: until then, K says so.
  if not paw.harmony.fresh() then
    lines[#lines + 1] = "  the chord here: reading"
  else
    local chord = paw.harmony.at(part.clip:get().start + own.start, true)
    if chord then
      lines[#lines + 1] = "  the chord here: " .. chord.name
    end
  end
end

--- What `K` shows before the track: the note under the cursor.
function view:describe(): contracts.Description
  local self = self as PianoRoll
  local note, _, part = self:note_at(self.pitch, self.beat)
  if not note then
    return nil
  end
  local lines: contracts.Description = {
    {text = "Note  " .. music.name(note.pitch), style = "Title"},
    string.format("  from beat %g, %g beats long, velocity %d", note.start, note.length, note.velocity),
  }
  -- A describer that says the articulation (an articulation map's name for
  -- it) says it instead of the attribute's plain words.
  local more: {string | contracts.PageLine} = {}
  local said = false
  for _, d in ipairs(view.describers) do
    local ok, got = pcall(d.fn, note, part) as (boolean, Described)
    if ok and got is Described then
      said = said or got.articulation == true
      for _, line in ipairs(got) do
        more[#more + 1] = line
      end
    end
  end
  local attr = not said and note.attr and paw.attr.describe(note.attr)
  if attr then
    lines[#lines + 1] = "  articulation: " .. attr.text
  end
  describe_more(lines, note, part)
  for _, line in ipairs(more) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ""
  return lines
end

--- Change the note under the cursor with `fn(note)`, the note's start in
--- its own clip's beats, which it does not leave. Returns whether there was one.
function view:change(fn: function(note: types.Note)): boolean
  local _, place, part = self:note_at(self.pitch, self.beat)
  if not place then
    return false
  end
  local note = part.clip:note(place)
  fn(note)
  part.clip:set_note(
    place,
    {
      start = note.start,
      length = note.length,
      pitch = note.pitch,
      velocity = note.velocity,
      meta = note.meta or {},
      attr = note.attr or false,
    }
  )
  return true
end

-- Its title row has buttons of its own (`view.title_tools`): a graphical
-- frontend shows it rather than a title of its own over it (paw/panes.tl).
view.titled = true
-- What moves on its own as the song plays is the playhead: a frontend that
-- paints it with the live values needs no new scene of the roll for it.
view.live_roles = {"playhead"}
-- From here on, `view` is the proxy that `paw.ui.view` gives: the code
-- above reads `view.pitch` in the window that drew or acted last.
view = paw.ui.view("pianoroll", view)
M.view = view
return M
