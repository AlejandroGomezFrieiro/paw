-- What the parts of `paw.frontend` read of `paw`: the typed global, the
-- parts of the modules in Lua that they call, one field of the kernel's
-- tables read alone, and the small helpers that every gesture uses.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local type types = require("paw.types")
local type KeymapModule = require("paw.keymap")
local type KeybarModule = require("paw.keybar")
local type objects = require("paw.objects")
local type CanvasModule = require("paw.canvas")
local type EditModule = require("paw.edit")
local type MidifileModule = require("paw.midifile")
local type PanesModule = require("paw.panes")
local type RenderModule = require("paw.render")
local type StatuslineModule = require("paw.statusline")
local type TempoModule = require("paw.tempo")
local type CursorModule = require("paw.cursor")
local type DrawModule = require("paw.draw")
local type ExModule = require("paw.ex")
local type GroupsModule = require("paw.groups")
local type FoldsModule = require("paw.folds")
local type LanesModule = require("paw.lanes")
local type MarkersModule = require("paw.markers")
local type MediaModule = require("paw.media")
local type QfModule = require("paw.qf")
local type TakesModule = require("paw.takes")
local type TempolaneModule = require("paw.tempolane")
local type VcaModule = require("paw.vca")
local type RollClipsModule = require("paw.roll_clips")
local type Roll = require("paw.views.pianoroll")
local type MouseModule = require("paw.mouse")
local type NestModule = require("paw.nest")

local opt = options.opt

local type Region = EditModule.Region

--- A candidate of a prompt (paw/views/cmdline.lua).
local record Candidate
  label: string
  desc: string
end

--- A prompt being typed (`paw.views.cmdline.state`).
local record Prompt
  prompt: string
  before: string
  after: string
  selected: boolean
  matches: {Candidate}
  match: integer
  note: string
  note_level: string
  anchored: boolean
  history: string
  ghost: string
end

local record Message
  text: string
  level: string
  time: number
end

--- A hint of the keys that may follow (`paw.keymap.hints`).
local type Hint = KeymapModule.Hint

--- A value that this module passes on or copies, and never reads.
local record Value
end

local record RangeChoice
  name: string
  label: string
end

--- A point of a gesture: a beat and a height (a fraction, or a pitch).
local type Point = {number, number}

--- A clip of the piano roll as a gesture reaches it (paw/roll_clips.tl):
--- its id, its handle, how far it starts after the clip named, its start
--- and its length; with `notes` and `places` once its chosen notes are taken.
local record Part is RollClipsModule.Part
  notes: {types.Note}
  places: {integer}
end

-- What this module reads of `paw`, which paw/init.lua makes, and of the
-- modules in Lua that it calls: their parts that it uses.
--- The device panel of paw/views/devices.lua: its rows, and the one the keyboard is on.
local record RowDevice
  index: integer
  param_info: {types.ParamInfo}
end
local record DeviceRow
  device: RowDevice
  param: types.ParamInfo
end
local record DevicePanel
  row: integer
  rows: function(self: DevicePanel): {DeviceRow}
end
local record Views
  devices: DevicePanel
  pianoroll: Roll.PianoRoll
end
local record Rect
  name: string
  x: integer
  y: integer
  w: integer
  h: integer
end
local record Float
  name: string
  title: string
end
local record InputOptions
  prompt: string
  text: string
  complete: function(text: string): {{string: string}}
end
local record MouseEvent
  kind: string
  button: string
  x: integer
  y: integer
end
--- paw/ui.tl, with the views as this module reads them (wave 5 types the views).
local record Ui
  focused: string
  float: Float
  message: Message
  rects: {Rect}
  views: Views
  keybar: KeybarModule
  has_focus: boolean
  grabber: function()
  visible: function(name: string): boolean
  focus: function(name: string)
  hide: function(name: string)
  input: function(opts: InputOptions, done: function(text: string))
  mouse: function(event: MouseEvent)
end
--- A choice of an input, an output or an audio device (paw/audio.lua).
local record Choice
  group: string
  label: string
  checked: boolean
end
local record InputOf
  input: string
end
local record Audio
  levels: function(): {number}
  level: function(track: InputOf, levels?: {number}): number
  load: function(cpu?: number): number
  summary: function(): string
  label: function(track: types.Track): string
  choices: function(track: integer): {Choice}
  choose: function(track: integer, choice: Choice)
  engine_choices: function(): {Choice}
  choose_engine: function(choice: Choice)
end
local record AddOptions
  query: string
end
local record Fx
  card_params: function(device: types.Device): {types.ParamInfo}
  add: function(track: objects.Track, kind: string, opts: AddOptions): objects.Device
end
local record Params
  format: function(param: types.ParamInfo, value: number): string
  fraction: function(param: types.ParamInfo, value: number): number
  from_fraction: function(param: types.ParamInfo, fraction: number): number
end
--- An output pair of a device (`paw.routes.outputs`).
local record Output
  pair: integer
  name: string
  target: integer
  target_name: string
end
local record Source
  id: integer
  name: string
end
local record Routes
  sidechain_text: function(device: types.Device): string
  reaching: function(track: integer): {integer: boolean}
  peers: function(track: integer): {integer}
  outputs: function(device: integer): {Output}
  set_output: function(device: integer, pair: integer, target: integer)
  spread: function(device: integer)
  sidechain_sources: function(device: integer): {Source}
  set_sidechain: function(device: integer, track: integer, pre?: boolean)
end
local record Stretch
  badge: function(clip: types.Clip): string
  repeats: function(clip: types.Clip): {number}
  file_seconds: function(clip: types.Clip, beats: number, at?: number): number
  sounding: function(clip: types.Clip, notes: {types.Note}, limit?: integer): {types.Note}
  lead: function(clip: types.Clip): number
  move_content: function(id: integer, by: number)
  to: function(id: integer, length: number)
  fit: function(id: integer, from: number, to: number)
  reset: function(id: integer)
  warp_add: function(id: integer, beat: number)
  warp_move: function(id: integer, index: integer, beat: number)
  warp_remove: function(id: integer, index: integer)
end
local record Controls
  select: function(clip: integer, place: integer, mode: string)
  select_box: function(
    clip: integer, kind: string, number: integer, beat0: number, low: number, beat1: number, high: number, mode?: string
  ): integer
  clear: function(clip: integer)
  move: function(clip: integer, dbeat: number, dfraction: number, free: boolean): integer
  remove: function(clip: integer): integer
  line: function(
    clip: integer, kind: string, number: integer, beat0: number, f0: number, beat1: number, f1: number, free: boolean
  ): integer
end
local record MixerRowInfo
  kind: string
  index: integer
  field: string
end
local record MixerRows
  current: function(): MixerRowInfo, integer
end
local record Menu
  shown: function(): Value, integer
end
local record Cmdline
  state: function(): Prompt
end
local record Learn
  learning: Value
  target_name: function(target: Value): string
end
local record Help
  topic_of: function(view: string): string
end
local record Loading
  toggle: function(device: objects.Device)
end
local record RecentModule
  menu: function(): {RangeChoice}
  open: function(path: string)
end
local record Autosave
  discard: boolean
end
local record Files
  here: function(): string
  project_path: function(name: string): string
end
local record TrackKinds
  describe: function(track: integer): string
end
local record FileOptions
  title: string
  directory: boolean
  on_choose: function(path: string)
end
local record Pick
  file: function(opts: FileOptions)
end
local record ImportOptions
  track: integer
  start: number
end
--- `paw.remote`, as far as this module reads it: how many turns had input.
local record RemoteTouches
  touches: integer
end
local record Paw
  nest: NestModule
  keymap: KeymapModule
  ui: Ui
  audio: Audio
  fx: Fx
  params: Params
  routes: Routes
  stretch: Stretch
  roll_clips: RollClipsModule
  controls: Controls
  ex: ExModule
  mouse: MouseModule
  panes: PanesModule
  learn: Learn
  help: Help
  loading: Loading
  recent: RecentModule
  autosave: Autosave
  files: Files
  track_kinds: TrackKinds
  pick: Pick
  canvas: CanvasModule
  cursor: CursorModule
  draw: DrawModule
  edit: EditModule
  groups: GroupsModule
  folds: FoldsModule
  lanes: LanesModule
  markers: MarkersModule
  media: MediaModule
  midifile: MidifileModule
  qf: QfModule
  statusline: StatuslineModule
  takes: TakesModule
  tempo: TempoModule
  tempolane: TempolaneModule
  vca: VcaModule
  time: objects.Time
  transport: objects.Transport
  project: objects.Project
  remote: RemoteTouches
  clip: function(id: integer): objects.Clip
  track: function(which: number | string): objects.Track
  device: function(id: integer): objects.Device
  restore_clip: function(snap: objects.ClipSnapshot, track: integer | objects.Track): objects.Clip
  is_audio_file: function(path: string): boolean
  import_audio: function(path: string, opts: ImportOptions): objects.Clip
  notify: function(text: string, level?: string)
end
local paw = (_G as {string: Paw}).paw

-- One field of the kernel's tables, read alone: quicker than the whole
-- table where the state is made, which runs for every frame.
local track_text = api.track_get as function(id: integer, key: string): string
local track_flag = api.track_get as function(id: integer, key: string): boolean
local track_number = api.track_get as function(id: integer, key: string): number
local project_text = api.project_get as function(key: string): string

local function render_module(): RenderModule
  return require("paw.render")
end

local function snap(beat: number): number
  return math.max(0, paw.cursor.snap(beat))
end

local function note_snap(beat: number): number
  local grid = opt.note_grid
  return math.max(0, math.floor(beat / grid + 0.5) * grid)
end

--- Give the arrange view the keyboard, unless a window is open over it.
local function to_arrange()
  if paw.keymap.mode == "x" then
    paw.keymap.set_mode("n")
  end
  if not paw.ui.float and paw.ui.focused ~= "arrange" then
    paw.ui.focus("arrange")
  end
end

local function by_beat(a: Point, b: Point): boolean
  return a[1] < b[1]
end

local record Host
  type Candidate = Candidate
  type Prompt = Prompt
  type Message = Message
  type Hint = Hint
  type Value = Value
  type RangeChoice = RangeChoice
  type Point = Point
  type Part = Part
  type Rect = Rect
  type Choice = Choice
  type MixerRows = MixerRows
  type Menu = Menu
  type Cmdline = Cmdline
  type Region = Region
  paw: Paw
  track_text: function(id: integer, key: string): string
  track_flag: function(id: integer, key: string): boolean
  track_number: function(id: integer, key: string): number
  project_text: function(key: string): string
  render_module: function(): RenderModule
  snap: function(beat: number): number
  note_snap: function(beat: number): number
  to_arrange: function()
  by_beat: function(a: Point, b: Point): boolean
end

Host.paw = paw
Host.track_text = track_text
Host.track_flag = track_flag
Host.track_number = track_number
Host.project_text = project_text
Host.render_module = render_module
Host.snap = snap
Host.note_snap = note_snap
Host.to_arrange = to_arrange
Host.by_beat = by_beat

return Host
