-- What a graphical frontend needs to draw the project, in one call.
--
-- A frontend polls `paw.frontend.state(known)` many times a second. The
-- answer always holds what moves on its own (transport position, meters). The
-- project itself is only included when it has changed since revision `known`,
-- so an idle project costs almost nothing to watch. Waveforms are a separate
-- call, `paw.frontend.peaks(clip)`, made only when a clip's `waveform` changes.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local seats = require("paw.seats")
local util = require("paw.util")
local commands = require("paw.commands")
local type types = require("paw.types")
local type objects = require("paw.objects")
local type CanvasModule = require("paw.canvas")
local type CursorModule = require("paw.cursor")
local type DrawModule = require("paw.draw")
local type EditModule = require("paw.edit")
local type GroupsModule = require("paw.groups")
local type LanesModule = require("paw.lanes")
local type MarkersModule = require("paw.markers")
local type MediaModule = require("paw.media")
local type MidifileModule = require("paw.midifile")
local type QfModule = require("paw.qf")
local type RenderModule = require("paw.render")
local type StatuslineModule = require("paw.statusline")
local type TakesModule = require("paw.takes")
local type TempoModule = require("paw.tempo")
local type TempolaneModule = require("paw.tempolane")
local type VcaModule = require("paw.vca")
local type MouseModule = require("paw.mouse")
local type PanesModule = require("paw.panes")

local opt = options.opt

local type Region = EditModule.Region

-- What the state holds -----------------------------------------------------------

--- A device of the selected track, for its card (`state.devices`).
local record ParamState
  key: string
  name: string
  text: string
  value: number
  min: number
  max: number
  default: number
end
local record DeviceState
  id: integer
  name: string
  format: string
  bypass: boolean
  params: {ParamState}
  more: integer
  wet: number
  gain: number
  editor: string
  stopped: string
  preset: string
  status: string
  keyed: boolean
  sidechain: string
  pairs: integer
  routed: integer
end

--- An entry of a menu of an extension's (`paw.frontend.menus`): a command
--- line or a function given the clip or track and the beat that was clicked.
local record MenuEntry
  label: string
  command: string
  run: function(target: integer, beat: number)
  only: string
end

--- The entries of the menus as the state gives them.
local record MenuLabel
  label: string
  only: string
end

--- An entry of a band under the ruler, as an extension gives it.
local record BandEntry
  beat: number
  length: number
  name: string
  color: string
  command: string
  run: function(entry: BandEntry)
  hint: string
end

--- A band of an extension: its entries.
local type Band = function(): {BandEntry}

--- An entry of a band, as the state gives it.
local record BandState
  row: integer
  band: integer
  index: integer
  beat: number
  length: number
  name: string
  color: string
  active: boolean
  hint: string
end
local record Bands
  rows: integer
  entries: {BandState}
end

--- A candidate of a prompt (paw/views/cmdline.lua).
local record Candidate
  label: string
  desc: string
end

--- The candidates of a prompt that show (`M.completions`).
local record Completions
  total: integer
  chosen: integer
  items: {Candidate}
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

--- A prompt as the state gives it: its candidates are those that show.
local record PromptState
  prompt: string
  before: string
  after: string
  selected: boolean
  matches: Completions
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

local record KeyHint
  key: string
  desc: string
end

--- What an Ex line being typed would act on.
local record ExClip
  id: integer
  count: integer
  notes: boolean
end
local record ExState
  from: number
  to: number
  tracks: {integer}
  clips: {ExClip}
  current: integer
end

local record MixerRow
  track: integer
  kind: string
  index: integer
  field: string
end

local record QfState
  text: string
  level: integer
end

--- A hint of the keys that may follow (`paw.keymap.hints`).
local record Hint
  key: string
  desc: string
  more: integer
end
local record Hints
  title: string
  items: {Hint}
end

--- A value that this module passes on or copies, and never reads.
local record Value
end

--- Where the keyboard is (`modal()`).
local record Modal
  mode: string
  pending: string
  recording: string
  name: string
  focused: string
  mixer: boolean
  float: string
  menu: integer
  hint: string
  pointer: string
  selection: Region
  render: types.RenderStatus
  learning: string
  prompt: PromptState
  message: Message
  keys: {KeyHint}
  ex: ExState
  mixer_row: MixerRow
  statusline: StatuslineModule.Line
  qf: QfState
  hints: Hints
  clip: integer
  panes: PanesModule.State
  windows: {CanvasModule.WindowInfo}
  views: {CanvasModule.Openable}
  menus: {string:{MenuLabel}}
  device: integer
  param: integer
end

local record TempoLane
  lo: number
  hi: number
  points: {types.TempoPoint}
end

local record MarkerState
  id: integer
  beat: number
  name: string
  length: number
end

local record Line
  beat: number
  bar: integer
  index: integer
  next: number
  label: string
  place: string
end

--- What changes only with the project (`state.project`).
local record ProjectState
  name: string
  modified: boolean
  tempo: number
  bar: number
  length: number
  signature: string
  loop_enabled: boolean
  loop_start: number
  loop_end: number
  metronome: boolean
  backend: string
  sample_rate: integer
  punch_enabled: boolean
  punch_start: number
  punch_end: number
  count_in: integer
  pre_roll: integer
  pre_roll_seconds: number
  grid: number
  note_grid: number
  threads: integer
  xruns: integer
  engine: string
  marks: {TempoModule.Mark}
  tempo_lane: TempoLane
  markers: {MarkerState}
  bands: Bands
  lines: {Line}
end

local record LaneState
  id: integer
  target: types.LaneTarget
  device: integer
  param: string
  enabled: boolean
  min: number
  max: number
  points: {types.LanePoint}
  lo: number
  hi: number
  name: string
end

local record Send
  name: string
  level: number
end

local record TrackState
  id: integer
  name: string
  volume: number
  pan: number
  mute: boolean
  solo: boolean
  armed: boolean
  master: boolean
  lanes: {LaneState}
  input: string
  monitor: boolean
  input_label: string
  color: string
  chain: string
  kind: string
  output: string
  sends: {Send}
  depth: integer
  group: boolean
  folded: boolean
  members: integer
  vca: boolean
  vcas: string
  height: number
  automation: string
  lane_rows: {integer}
  take_rows: integer
end

--- A take of a clip as its take lane shows it (`M.take_rows`).
local record TakeRow
  name: string
  key: string
end

local record ClipState
  take_rows: {TakeRow}
  id: integer
  track: integer
  start: number
  length: number
  name: string
  midi: boolean
  muted: boolean
  takes: integer
  take: integer
  selected: boolean
  fade_in: number
  fade_out: number
  gain: number
  offline: boolean
  stamp: string
  waveform: string
  loop: boolean
  notches: {number}
  warps: {number}
end

--- A track that a track can play into or send to.
local record Target
  id: integer
  name: string
end
local record SendState
  target: integer
  name: string
  level: number
  pre: boolean
end
--- Where a track's sound goes (`M.routing`).
local record Routing
  output: string
  output_id: integer
  targets: {Target}
  sends: {SendState}
  master: boolean
end

--- What `paw.frontend.state` gives a frontend.
local record State
  revision: integer
  playing: boolean
  recording: boolean
  position: number
  counting: integer
  time: string
  clock: string
  tempo: number
  signature: string
  cpu: number
  levels: {number}
  inputs: {number}
  modal: Modal
  armed: boolean
  xruns: integer
  late_blocks: integer
  midi_dropped: integer
  record_dropped: integer
  devices_stopped: integer
  window_fps: number | string
  window_cache: boolean | string
  project: ProjectState
  selected: integer
  cursor: number
  tracks: {TrackState}
  clips: {ClipState}
  devices: {DeviceState}
  routing: Routing
  kinds: {string}
end

--- The float as text (`M.float`).
local record FloatText
  title: string
  lines: {string}
end

--- What the window said of its OpenGL (`M.window_renderer`).
local record Renderer
  renderer: string
  version: string
  software: boolean
  cause: string
end

--- What the window needs for the desktop's file dialogs (`M.dialog_info`).
local record DialogInfo
  native: boolean
  dir: string
  name: string
  render: {string}
end

--- What paw would lose if it closed now (`M.closing`).
local record Closing
  modified: boolean
  name: string
  path: string
end

local record RangeChoice
  name: string
  label: string
end
--- The start values of the render dialog (`M.render_dialog`).
local record RenderDialog
  path: string
  ranges: {RangeChoice}
  sample_rate: integer
  formats: {string:boolean}
  tags: types.RenderTags
end

--- An entry of a menu: what it says, and whether it is checked.
local record Check
  label: string
  checked: boolean
end
local record InputMenu
  audio: {Check}
  midi: {Check}
  channel: {Check}
  midi_out: {Check}
  midi_out_channel: {Check}
  midi_out_form: {Check}
  monitor: boolean
end
local record EngineMenu
  info: {Check}
  output: {Check}
  input: {Check}
  block: {Check}
  rate: {Check}
  backend: {Check}
end
--- An output pair of a device and where it can play (`M.outputs_menu`).
local record PairMenu
  label: string
  choices: {Check}
end

--- How the window was left (`M.layout_get`): its own data, which it reads.
local record WindowLayout
end

--- What the render dialog of the window gives `act.render`.
local record RenderRequest
  path: string
  range: string
  format: string
  quality: string
  bits: number
  tail: number
  normalize: number
  dither: boolean
  mono: boolean
  stems: boolean
  tags: types.RenderTags
end

--- What `act.drop` did.
local record Dropped
  open: string
  clips: {integer}
  refused: integer
end

--- A point of a gesture: a beat and a height (a fraction, or a pitch).
local type Point = {number, number}

--- A clip of the piano roll as a gesture reaches it: its id, its handle,
--- how far it starts after the clip named, its start and its length; with
--- `notes` and `places` once its chosen notes are taken.
local record Part
  id: integer
  clip: objects.Clip
  offset: number
  start: number
  length: number
  track: integer
  name: string
  notes: {types.Note}
  places: {integer}
end

-- What this module reads of `paw`, which paw/init.lua makes, and of the
-- modules in Lua that it calls: their parts that it uses.
--- paw/keymap.lua: the mode, the selection and the keys typed.
local record Visual
  kind: string
  row: number
  col: number
  view: string
  region: function(): Region
end
local record Keymap
  mode: string
  visual: Visual
  pending: function(): string
  recording: function(): string
  selection: function(): Region
  set_mode: function(mode: string)
  hints: function(): {Hint}, string
  feed: function(keys: string)
  visual_start: function(kind: string)
end
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
--- The piano roll of paw/views/pianoroll.lua.
local record Roll
  fit_next: boolean
  beat: number
  pitch: integer
  clip: function(self: Roll): objects.Clip
  edit: function(self: Roll, clip: objects.Clip)
  step_length: function(self: Roll): number
  set_step: function(self: Roll, length: number)
  step: function(self: Roll, n: integer)
  starting_here: function(self: Roll, clip: objects.Clip, pitch: integer): {integer}
  new_note: function(clip: objects.Clip, note: objects.NoteInput): objects.NoteInput
end
local record Views
  devices: DevicePanel
  pianoroll: Roll
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
local record Keybar
  entries: function(): {{string}}
end
local record InputOptions
  prompt: string
  text: string
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
  keybar: Keybar
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
  reaching: function(track: integer): {integer:boolean}
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
local record Behind
  clip: integer
end
local record RollTrack
  id: integer
  on: boolean
end
local record RollClips
  active: function(): integer
  editable: function(clip: integer): boolean
  parts: function(): {Part}
  offset: function(clip: integer): number
  target: function(beat: number): Part
  context_at: function(pitch: integer, beat: number): Behind
  activate: function(clip: integer)
  toggle: function(clip: integer)
  tracks: function(): {RollTrack}
  show_track: function(track: integer, on: boolean)
  open: function(ids: {integer}, active: integer)
end
local record Controls
  select: function(clip: integer, place: integer, mode: string)
  select_box: function(clip: integer, kind: string, number: integer, beat0: number, low: number, beat1: number, high: number, mode?: string): integer
  clear: function(clip: integer)
  move: function(clip: integer, dbeat: number, dfraction: number, free: boolean): integer
  remove: function(clip: integer): integer
  line: function(clip: integer, kind: string, number: integer, beat0: number, f0: number, beat1: number, f1: number, free: boolean): integer
end
--- What an Ex line being typed acts on (`paw.ex.shown`, paw/ex.lua).
local record ShownCurrentClip
  id: integer
end
local record ShownCurrent
  clip: ShownCurrentClip
end
local record Shown
  from: number
  to: number
  tracks: {integer:boolean}
  clips: {integer:integer}
  notes: {integer:Value}
  current: ShownCurrent
end
local record Ex
  shown: function(): Shown
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
local record Saved
  pick_dir: string
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
  keymap: Keymap
  ui: Ui
  audio: Audio
  fx: Fx
  params: Params
  routes: Routes
  stretch: Stretch
  roll_clips: RollClips
  controls: Controls
  ex: Ex
  mouse: MouseModule
  panes: PanesModule
  learn: Learn
  help: Help
  loading: Loading
  recent: RecentModule
  autosave: Autosave
  state: Saved
  track_kinds: TrackKinds
  pick: Pick
  canvas: CanvasModule
  cursor: CursorModule
  draw: DrawModule
  edit: EditModule
  groups: GroupsModule
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
local paw = (_G as {string:Paw}).paw

-- One field of the kernel's tables, read alone: quicker than the whole
-- table where the state is made, which runs for every frame.
local track_text = api.track_get as function(id: integer, key: string): string
local track_flag = api.track_get as function(id: integer, key: string): boolean
local track_number = api.track_get as function(id: integer, key: string): number
local project_text = api.project_get as function(key: string): string

local function render_module(): RenderModule return require("paw.render") end

--- The pointer's gestures (`paw.frontend.act`): each is a function of the
--- frontend's arguments. Other modules add their own.
local record Act
  clear_clip_selection: function()
  select: function(track: integer, beat?: number)
  select_clip: function(id: integer, beat?: number, mode?: string)
  select_clips_box: function(row0: integer, beat0: number, row1: integer, beat1: number, mode?: string): integer
  select_all_clips: function()
  move_clip: function(id: integer, start: number, track?: integer, copy?: boolean): integer
  drag_clips: function(id: integer, dbeat: number, drows?: number, copy?: boolean, free?: boolean): {integer}
  trim_clips: function(id: integer, edge: string, dbeat: number, free?: boolean, slip?: boolean): {integer}
  stretch_clips: function(id: integer, dbeat: number): {integer}
  stretch_clip: function(id: integer, what: string)
  warp_add: function(id: integer, beat: number)
  warp_move: function(id: integer, index: integer, beat: number, free?: boolean)
  warp_remove: function(id: integer, index: integer)
  set_fade: function(id: integer, which: string, beats: number)
  set_clip_gain: function(id: integer, db: number)
  resize_clip: function(id: integer, length: number)
  tempo_mark: function(action: string, kind: string, beat: number, to?: number)
  tempo_lane: function(on?: boolean): boolean
  tempo_point_add: function(beat: number, fraction: number)
  tempo_point_move: function(beat: number, to: number, fraction: number)
  tempo_point_remove: function(beat: number)
  tempo_point_ramp: function(beat: number): boolean
  tempo_draw: function(points: {Point})
  add_clip: function(track: integer, beat: number): integer
  open_clip: function(id: integer)
  record: function()
  close_roll: function()
  clip_command: function(id: integer, beat: number, line: string)
  menu_target: function(id: integer, beat?: number)
  track_command: function(id: integer, line: string)
  toggle_offline: function(id: integer)
  restart_device: function(id: integer)
  menu: function(kind: string, index: integer, target?: integer, beat?: number)
  band: function(band: integer, index: integer)
  set_loop: function(from: number, to: number)
  float_pointer: function(kind: string, line: integer, col?: integer)
  split_clips: function(): boolean
  glue_clips: function()
  menu_split: function(id: integer)
  menu_glue: function(id: integer)
  set_loop_edge: function(edge: string, beat: number)
  set_punch_edge: function(edge: string, beat: number, free?: boolean)
  set_punch: function(from: number, to: number)
  take_lanes: function(track: integer): boolean
  comp: function(track: integer, take: integer, from: number, to: number, free?: boolean): integer
  take_click: function(track: integer, take: integer, beat: number): integer
  ruler_click: function(beat: number)
  select_range: function(row0: integer, beat0: number, row1: integer, beat1: number)
  focus: function(on: boolean)
  keys: function(keys: string)
  set_volume: function(track: integer, db: number)
  hold: function(track: integer, target: string, device: integer, param: string, on: boolean)
  leave: function(how: string, what: string)
  chosen: function(kind: string, path: string)
  drop: function(paths: {string}, row?: integer, beat?: number): Dropped
  hide_lane_rows: function(lane: integer)
  lane_rows: function(track: integer): boolean
  render: function(o: RenderRequest)
  set_output: function(track: integer, target?: integer)
  add_send: function(track: integer, target: integer, level?: number)
  set_send: function(track: integer, index: integer, level?: number, pre?: boolean)
  remove_send: function(track: integer, index: integer)
  route_pair: function(device: integer, pair: integer, index: integer)
  spread_outputs: function(device: integer)
  choose_sidechain: function(device: integer, index: integer)
  set_pan: function(track: integer, pan: number)
  toggle: function(track: integer, flag: string)
  choose_input: function(track: integer, group: string, index: integer)
  choose_engine: function(group: string, index: integer)
  pick_device: function(track: integer, index: integer)
  rename_track: function(track: integer, name: string)
  color_track: function(track: integer, colour: string)
  move_track: function(track: integer, index: integer)
  set_track_height: function(track: integer, share: number)
  set_flag: function(track: integer, flag: string, on: boolean)
  sweep_flag: function(row0: integer, row1: integer, flag: string, on: boolean)
  fold: function(track: integer)
  add_note: function(clip: integer, pitch: integer, start: number, length?: number, free?: boolean): integer
  context_click: function(clip: integer, beat: number, pitch: number)
  roll_activate: function(_: integer, id: number)
  roll_toggle_clip: function(_: integer, id: number)
  roll_show_track: function(_: integer, id: number)
  select_note: function(clip: integer, index: integer, mode?: string)
  select_notes_box: function(clip: integer, beat0: number, pitch0: number, beat1: number, pitch1: number, mode?: string): integer
  select_all_notes: function(clip: integer)
  clear_note_selection: function()
  drag_notes: function(clip: integer, index: integer, dbeat: number, dpitch?: number, copy?: boolean, free?: boolean)
  stretch_notes: function(clip: integer, index: integer, dstart?: number, dlength?: number, free?: boolean): boolean
  remove_note: function(clip: integer, index: integer)
  remove_chosen_notes: function(clip: integer): boolean
  move_note: function(clip: integer, index: integer, start: number, pitch: integer): integer
  resize_note: function(clip: integer, index: integer, length: number)
  set_velocity: function(clip: integer, index: integer, velocity: number): integer
  audition: function(clip: integer, pitch: integer)
  erase_notes: function(clip: integer, points: {Point}): integer
  select_pitches: function(clip: integer, low: number, high: number, mode?: string): integer
  draw_velocities: function(clip: integer, points: {Point}, reach?: number): integer
  set_note_length: function(length?: number)
  toggle_note_snap: function()
  quantize_notes: function(clip: integer, strength?: number): integer
  toggle_step_input: function()
  roll_seek: function(clip: integer, beat: number)
  lane: function(track: integer, target: types.LaneTarget, device?: integer, param?: string): integer
  add_point: function(lane: integer, beat: number, fraction: number)
  move_point: function(lane: integer, index: integer, beat: number, fraction: number)
  draw_lane: function(lane: integer, points: {Point})
  toggle_lane: function(lane: integer)
  clear_lane: function(lane: integer)
  draw_controls: function(clip: integer, kind: types.ControlType, number: integer, points: {Point})
  clear_controls: function(clip: integer, kind: types.ControlType, number: integer)
  select_control: function(clip: integer, place: integer, mode: integer | string)
  select_controls: function(clip: integer, kind: string, number: integer, beat0: number, low: number, beat1: number, high: number, mode: integer | string): integer
  select_all_controls: function(clip: integer, kind: string, number: integer): integer
  clear_control_selection: function(clip: integer)
  move_controls: function(clip: integer, dbeat: number, dfraction: number, free?: boolean | integer): integer
  remove_chosen_controls: function(clip: integer): integer
  line_controls: function(clip: integer, kind: string, number: integer, beat0: number, f0: number, beat1: number, f1: number, free?: boolean | integer): integer
  open_event_list: function(clip: integer)
  remove_point: function(lane: integer, index: integer)
  set_param: function(device: integer, key: string, fraction: number)
  reset_param: function(device: integer, key: string)
  toggle_bypass: function(device: integer)
  add_device: function(kind: string, query?: string): integer
  move_device: function(device: integer, by: integer)
end

local record M
  type State = State
  type Modal = Modal
  type ProjectState = ProjectState
  type TrackState = TrackState
  type ClipState = ClipState
  type DeviceState = DeviceState
  type Routing = Routing
  type Line = Line
  type MenuEntry = MenuEntry
  type BandEntry = BandEntry
  type Band = Band
  type Bands = Bands
  type Act = Act
  type Part = Part
  type Point = Point
  type Renderer = Renderer
  type WindowLayout = WindowLayout
  type RenderRequest = RenderRequest
  --- The state's revision: a frontend asks for what changed after it.
  revision: integer
  --- How many parameters a device's card shows.
  max_params: integer
  --- The points of a waveform when a frontend does not say.
  peak_points: integer
  --- How many notes the picture inside a clip shows at most.
  preview_notes: integer
  --- When a frontend last asked for the state (`paw.api.now`).
  polled: number
  --- What extensions add to the frontend's right-click menus, by kind:
  --- `clip`, `track` and `timeline`.
  menus: {string:{MenuEntry}}
  --- Bands of extensions under the ruler.
  bands: {Band}
  --- The pointer's gestures.
  act: Act
  chosen_clips: function(): {integer}
  routing: function(track: integer): Routing
  render_dialog: function(): RenderDialog
  --- Editors of extensions for clips: given a clip, true if it opened it.
  openers: {function(clip: objects.Clip): boolean}
  --- What the window said of the OpenGL that draws it.
  window_renderer: Renderer
  --- What to do about a window that draws on the processor, by cause.
  software_advice: {string:string}
  --- Another file for the window's layout than the state folder's (tests).
  layout_path: string
end

M.revision, M.max_params, M.peak_points, M.preview_notes = 0, 16, 128, 2000

local function bump() M.revision = M.revision + 1 end
for _, name in ipairs({ "changed", "transport.changed", "cursor.changed", "project.loaded", "engine.started", "option.changed", "lanes.changed" }) do
  local event: events.Event<events.Payload> = events.event(name)
  events.on(event, bump)
end

-- Values as text in their unit, and sliders on a log scale for frequencies
-- and times: see `paw.params`.
--- A parameter's value as text in its unit (see `paw.params.format`).
function M.format_value(param: types.ParamInfo, value: number): string return paw.params.format(param, value) end
local format_value = M.format_value

local function device_state(id: integer): DeviceState
  local d = api.device_get(id)
  local params: {ParamState} = {}
  -- The device's own parameters, those the user chose to show first (see
  -- `paw.fx.card_params`); the host's wet/dry mix and gain are on the header.
  local own = paw.fx.card_params(d)
  for i = 1, math.min(M.max_params, #own) do
    local p = own[i]
    local value = d.params[p.key]
    params[i] = {
      key = p.key, name = p.name, text = format_value(p, value),
      -- Sliders work on 0..1 whatever the parameter's own range is.
      value = paw.params.fraction(p, value),
      min = p.min, max = p.max,
      -- Where the slider rests, for a double click.
      default = paw.params.fraction(p, p.default),
    }
  end
  local meta = d.meta as {string:string}
  return {
    id = d.id, name = d.name, format = d.format, bypass = d.bypass, params = params,
    more = #own - #params,
    -- The wet share, 0 to 1, and the output gain in dB.
    wet = (d.params.fx_wet or 100) / 100, gain = d.params.fx_gain or 0,
    -- "open", "closed", or "" for a device with no window of its own.
    editor = d.editor or "",
    -- Why a plugin has stopped working, or "".
    stopped = d.stopped or (d.missing and "it is not installed or did not load") or "",
    -- The preset last loaded or saved, or "".
    preset = type(d.meta) == "table" and meta.preset or "",
    -- "running", "loading", "stopped", "offline" or "missing".
    status = d.status or "running",
    -- Whether it can listen to a side-chain, and the track it listens to
    -- ("" for its own input); `sidechain_menu` lists the choices.
    keyed = (d.ports and d.ports.sidechain) or d.sidechain ~= nil,
    sidechain = paw.routes.sidechain_text(d) or "",
    -- How many output pairs it has (1 for most), and how many of the
    -- further ones play somewhere; `outputs_menu` routes them.
    pairs = math.max(1, #(d.ports and d.ports.outputs or {})) as integer,
    routed = (function(): integer
      local n = 0
      for _ in pairs(d.outputs or {}) do n = n + 1 end
      return n
    end)(),
  }
end

--- What extensions add to the frontend's right-click menus: on a clip, on a
--- track's header, on an empty stretch of the timeline.
---
---   table.insert(paw.frontend.menus.clip, { label = "Open as notation", command = "notation.open", only = "midi" })
---   table.insert(paw.frontend.menus.timeline, { label = "New drum track", run = function(track, beat) ... end })
---
--- `command` is a command line and `run` a function given the clip or track
--- and the beat that was clicked; either runs with the cursor put there
--- first. `only` keeps a clip's entry to "midi" or "audio" clips.
M.menus = { clip = {}, track = {}, timeline = {} }

local function menus(): {string:{MenuLabel}}
  local out: {string:{MenuLabel}} = {}
  for kind, entries in pairs(M.menus) do
    local list: {MenuLabel} = {}
    for i, entry in ipairs(entries) do list[i] = { label = entry.label, only = entry.only or "" } end
    out[kind] = list
  end
  return out
end

--- Bands of their own under the frontend's ruler, from extensions, under
--- the one for markers: each a function that returns the band's entries,
--- `{ beat, length, name, color, command }` each (`length` 0 for a flag,
--- `color` `#rrggbb` or nil for the window's own, `command` a command line,
--- or `run` a function, for a click on it, and `hint`, what the status line
--- says over it).
---
---   table.insert(paw.frontend.bands, function()
---     return { { beat = 0, length = 16, name = "Intro", command = "section.goto 1" } }
---   end)
---
--- A band with no entries takes no room. They are asked again whenever the
--- project, the cursor or the transport changes; after a change of its own
--- (a measurement that has ended) an extension calls `paw.frontend.refresh()`.
M.bands = {}

--- Make the frontend get the state of the project again, when nothing in the
--- project changed. This is for data that an extension adds to the state.
function M.refresh()
  M.revision = M.revision + 1
  api.ui_redraw()
end

local function band_entries(index: integer): {BandEntry}
  local fn = M.bands[index]
  local ok, entries = pcall(fn)
  if not ok then
    paw.notify("a band of the window's ruler failed: " .. tostring(entries), "error")
    return {}
  end
  return type(entries) == "table" and entries as {BandEntry} or {}
end

--- The bands that have entries, as rows from 0 below the marker band:
--- `{ rows, entries }`. Each entry has its `row`, its `band` and `index`
--- (for `act.band`), `beat`, `length`, `name`, `color`, `active` and `hint`.
function M.band_state(): Bands
  local out: {BandState} = {}
  local rows = 0
  for i in ipairs(M.bands) do
    local entries = band_entries(i)
    if #entries > 0 then
      for j, e in ipairs(entries) do
        out[#out + 1] = {
          row = rows, band = i, index = j, beat = tonumber(e.beat) or 0, length = tonumber(e.length) or 0,
          name = tostring(e.name or ""), color = e.color or "", active = e.command ~= nil or e.run ~= nil,
          hint = tostring(e.hint or e.name or ""),
        }
      end
      rows = rows + 1
    end
  end
  return { rows = rows, entries = out }
end

--- The candidates of a prompt, as the terminal shows them above the line.
--- These are the candidates in view around the selected one, as
--- `{ label, desc }`. `chosen` is the place of the selected candidate among
--- them (0 for none).
function M.completions(prompt: Prompt): Completions
  local all = prompt.matches
  if not all or #all == 0 then return nil end
  local rows = 10
  local first = math.max(1, math.min((prompt.match or 0) - rows + 1, #all - rows + 1))
  local list: Completions = { total = #all, chosen = (prompt.match or 0) > 0 and prompt.match - first + 1 or 0, items = {} }
  for i = first, math.min(#all, first + rows - 1) do
    local c = all[i]
    list.items[#list.items + 1] = { label = c.label, desc = c.desc and (c.desc:match("^[^\n]*"):gsub(":? `.*$", "")) or "" }
  end
  return list
end

--- A track's sends as `{ name, level }`, the level in dB.
function M.send_list(track: types.Track): {Send}
  local out: {Send} = {}
  for i, send in ipairs(track.sends or {}) do
    local ok, to = pcall(api.track_get, send.target)
    out[i] = { name = ok and (to as types.Track).name or "?", level = send.level }
  end
  return out
end

local mode_names: {string:string} = { n = "NORMAL", c = "COMMAND", i = "INSERT", o = "PENDING" }
local visual_names: {string:string} = { v = "VISUAL", V = "V-LINE", b = "V-BLOCK", clips = "CLIPS" }

--- Where the keyboard is: the mode, what is half typed, the prompt or the
--- message, the selection, and the cursors of the panels. Small, and sent
--- every time, because a key press changes it without changing the project.
local function modal(): Modal
  local keymap, ui = paw.keymap, paw.ui
  local hint, pointer = paw.mouse.hint_text()
  local _, menu_count = ((require as function(string): Menu)("paw.menu")).shown()
  local out: Modal = {
    mode = keymap.mode, pending = keymap.pending(), recording = keymap.recording() or "",
    name = keymap.mode == "x" and keymap.visual and visual_names[keymap.visual.kind]
      or mode_names[keymap.mode] or keymap.mode:upper(),
    focused = ui.focused, mixer = ui.visible("mixer"),
    float = ui.float and (ui.float.title or ui.float.name) or nil,
    -- A menu the kernel opened (a right click in a pane drawn from its
    -- scene), by how many were: the window shows it (`paw.frontend.menu("shown")`).
    menu = menu_count,
    -- What the pointer is over in a pane drawn from its scene, or what its
    -- drag will do (`paw.mouse.hint`), for the status line.
    hint = hint,
    -- The shape of the pointer there, if it has one ("resize_h", "resize_v").
    pointer = pointer,
    selection = keymap.selection(),
    -- A render in the background: { path, fraction, seconds, cancelling, stage }.
    render = api.render_status(),
    -- What `:learn` is waiting to bind a controller to, in words.
    learning = paw.learn and paw.learn.learning and paw.learn.target_name(paw.learn.learning) or nil,
  }
  -- Chosen clips are told one by one, with the clips (`selected`).
  if out.selection then out.selection.clips = nil end
  local prompt = ((require as function(string): Cmdline)("paw.views.cmdline")).state()
  if prompt then
    local shown = prompt as PromptState
    shown.matches = M.completions(prompt)
    out.prompt = shown
  elseif ui.message then
    out.message = { text = ui.message.text:match("^[^\n]*"), level = ui.message.level, time = ui.message.time }
  elseif opt.keybar and keymap.pending() == "" then
    -- With nothing to say, the keys worth knowing here, as the terminal's
    -- bottom line shows them.
    out.keys = {}
    for i, entry in ipairs(ui.keybar.entries()) do out.keys[i] = { key = entry[1], desc = entry[2] } end
    local topic = paw.help and paw.help.topic_of(ui.focused)
    if topic then out.keys[#out.keys + 1] = { key = ":help " .. topic, desc = "the manual" } end
  end
  -- What an Ex line being typed would act on: the stretch of time, the
  -- tracks, and the clips that match with how many matches each holds.
  local shown = paw.ex and paw.ex.shown()
  if shown then
    out.ex = { from = shown.from, to = shown.to, tracks = {}, clips = {}, current = shown.current and shown.current.clip and shown.current.clip.id }
    for id in pairs(shown.tracks or {}) do out.ex.tracks[#out.ex.tracks + 1] = id end
    for id, n in pairs(shown.clips or {}) do out.ex.clips[#out.ex.clips + 1] = { id = id, count = n, notes = shown.notes[id] ~= nil } end
  end
  -- The row of a strip the keyboard is on in the mixer.
  if out.mixer and ui.focused == "mixer" then
    local row, id = ((require as function(string): MixerRows)("paw.mixer_rows")).current()
    if row then out.mixer_row = { track = id, kind = row.kind, index = row.index or 0, field = row.field or "" } end
  end
  -- The status line when it was set up (`paw.statusline.setup`): the
  -- pieces of each side as `{ text, style }`, for a window that draws it.
  if paw.statusline.customized() then out.statusline = paw.statusline.frontend() end
  local qf = paw.qf and paw.qf.status()
  if qf then
    local text: {string} = {}
    local worst = 0
    for _, piece in ipairs(qf) do
      text[#text + 1] = piece[1] as string
      worst = math.max(worst, piece[2] == "StatusError" and 2 or piece[2] == "StatusWarn" and 1 or 0)
    end
    out.qf = { text = table.concat(text), level = worst }
  end
  if opt.hints then
    local hints, title = keymap.hints()
    if hints then out.hints = { title = title, items = hints } end
  end
  local under = paw.cursor.clip()
  out.clip = ui.focused == "arrange" and under and under.id or nil
  -- The tabs and windows, as panes of the main area.
  out.panes = paw.panes.state()
  -- Views in windows of their own.
  out.windows = paw.canvas.windows()
  -- Views that can be opened in one, for the views menu.
  out.views = paw.canvas.openable()
  out.menus = menus()
  if ui.focused == "devices" then
    -- The row the keyboard is on, as a device of the track and one of its
    -- parameters (0 for the device's own line).
    local panel = ui.views.devices
    local rows = panel:rows()
    panel.row = util.clamp(panel.row, 1, math.max(1, #rows)) as integer
    local row = rows[panel.row]
    if row then
      out.device, out.param = row.device.index, 0
      for i, p in ipairs(row.device.param_info) do
        if row.param and p.key == row.param.key then out.param = i end
      end
    end
  end
  return out
end

--- The float that is open (help, a list, a picker), drawn as text `width`
--- columns wide: its title and its lines. Nil when there is none.
function M.float(width: integer, height: integer): FloatText
  if not paw.ui.float then return nil end
  local lines = api.ui_snapshot(width, height)
  local rect: Rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == paw.ui.float.name then rect = r end
  end
  if not rect then return nil end
  local out: {string} = {}
  for y = rect.y, rect.y + rect.h - 1 do
    local cells: {string} = {}
    for ch in (lines[y + 1] or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do cells[#cells + 1] = ch end
    out[#out + 1] = table.concat(cells, "", rect.x + 1, math.min(#cells, rect.x + rect.w))
  end
  return { title = paw.ui.float.title or paw.ui.float.name, lines = out }
end

--- The stretch of a lane's range that is worth drawing it over: a fader's
--- travel for volume, the whole range for anything else.
function M.lane_span(lane: types.Lane): number, number
  if lane.target == "volume" then return -60, 6 end
  return lane.min, lane.max
end

--- What a lane moves, in words: `Volume`, `Pan`, `Synth · cutoff`.
function M.lane_name(lane: types.Lane): string
  if lane.target == "volume" then return "Volume" end
  if lane.target == "pan" then return "Pan" end
  local ok, got = pcall(api.device_get, lane.device)
  if not ok then return tostring(lane.param) end
  local device = got as types.Device
  for _, p in ipairs(device.param_info) do
    if p.key == lane.param then return device.name .. " · " .. p.name end
  end
  return device.name .. " · " .. tostring(lane.param)
end

--- The takes of a clip as its take lanes show them: `{ name, key }` each.
--- `key` changes exactly when the sound of the take changes. Nil for a clip
--- without takes, which has nothing in the lanes.
function M.take_rows(clip: types.Clip): {TakeRow}
  local takes = paw.takes.of(clip)
  if not takes then return nil end
  local out: {TakeRow} = {}
  local seconds = clip.kind == "audio" and paw.stretch.file_seconds(clip, clip.length) or 0
  for i, entry in ipairs(takes.list) do
    local key: string
    if clip.kind == "audio" then
      local c = paw.takes.content(clip, i)
      key = string.format("%s|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%s|%s|%.17g|%.17g", c.file, c.offset, c.gain, clip.length,
        seconds, clip.stretch, clip.pitch, tostring(clip.stretching), tostring(clip.loop), clip.loop_start, clip.loop_length or 0)
    else
      key = string.format("%s|%d|%d|%d|%.17g|%s|%.17g|%.17g", tostring(clip.stamp), takes.active, i, #(entry.notes or {}),
        clip.length, tostring(clip.loop), clip.loop_start, clip.loop_length or 0)
    end
    out[i] = { name = entry.name or ("take " .. i), key = key }
  end
  return out
end

--- What take `take` of a clip plays, for the picture in its take lane. For
--- sound, this is a waveform as `M.peaks` gives it, at `points` points. For
--- MIDI, it is the notes as `M.preview` gives them. It repeats as a looped
--- clip repeats. The waveform of the take that plays is the waveform of the
--- clip, stretched. The waveform of a different take is its file, made
--- shorter or longer in time as the clip stretches it.
function M.take_preview(id: integer, take: integer, points?: number): {number}
  local ok, got = pcall(api.clip_get, id)
  if not ok then return {} end
  local clip = got as types.Clip
  local c = paw.takes.content(clip, take)
  local flat: {number} = {}
  if clip.kind == "audio" then
    local n = util.clamp(math.floor(points or M.peak_points), 8, 4096) as integer
    local takes = paw.takes.of(clip)
    if takes and take == takes.active then
      local fetched, peaks = pcall(api.clip_peaks, id, n)
      for i, p in ipairs(fetched and peaks as {types.Peak} or {}) do
        flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1], p[2], p[3]
      end
      return flat
    end
    local seconds = paw.stretch.file_seconds(clip, clip.length)
    local fetched: boolean
    local peaks: {types.Peak}
    if clip.loop and clip.loop_length then
      -- One repeat's worth, laid along the clip as it repeats.
      local period = paw.stretch.file_seconds(clip, clip.loop_length)
      local lead = clip.loop_start / clip.loop_length * period
      local per = util.clamp(math.ceil(n * period / seconds), 1, 4096) as integer
      local fetched_one, one = pcall(api.media_peaks, c.file, math.max(0, c.offset + lead), period, per)
      fetched = fetched_one
      local repeat_peaks = one as {types.Peak}
      if fetched and #repeat_peaks > 0 then
        peaks = {}
        for i = 1, n do
          local at = (i - 0.5) * seconds / n
          local phase = ((at - lead) % period) / period
          peaks[i] = repeat_peaks[math.min(#repeat_peaks, math.floor(phase * #repeat_peaks) + 1)]
        end
      end
    else
      local fetched_all, all = pcall(api.media_peaks, c.file, c.offset, seconds, n)
      fetched, peaks = fetched_all, all as {types.Peak}
    end
    local gain = 10 ^ ((c.gain or 0) / 20)
    for i, p in ipairs(fetched and peaks or {}) do
      flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1] * gain, p[2] * gain, p[3] * gain
    end
    return flat
  end
  local i = 0
  for _, n in ipairs(paw.stretch.sounding(clip, c.notes, M.preview_notes)) do
    if i >= M.preview_notes then break end
    if n.start >= 0 and n.start < clip.length then
      i = i + 1
      flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = n.start, n.length, n.pitch
    end
  end
  return flat
end

--- What changes exactly when what a clip shows inside does: its notes and
--- controller moves (fetch `M.preview` again then), or its waveform (fetch
--- `M.peaks` again then). Nil for a MIDI clip with no notes yet.
function M.content_key(clip: types.Clip): string
  local repeats = clip.loop and string.format("|%.17g|%.17g", clip.loop_start, clip.loop_length) or ""
  -- Its warp markers change its waveform.
  for _, m in ipairs(clip.warp or {}) do repeats = repeats .. string.format("|%.17g:%.17g", m.source, m.target) end
  if clip.kind == "audio" then
    return string.format("%s|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%s%s", clip.file, clip.offset, clip.length, clip.gain,
      paw.time.seconds(clip.length, clip.start), clip.stretch, clip.pitch, tostring(clip.stretching), repeats)
  end
  return clip.stamp and string.format("%.0f|%.0f|%.17g%s", clip.stamp, clip.control_stamp or 0, clip.length, repeats) or nil
end

--- A MIDI clip's notes for the small picture inside it: one flat list
--- { start1, length1, pitch1, start2, ... }, at most `M.preview_notes` notes.
--- Fetched when the clip's `stamp` in `state` changes.
function M.preview(id: integer): {number}
  local flat: {number} = {}
  local ok, got = pcall(api.clip_notes, id)
  local notes = got as {types.Note}
  local c: types.Clip = ok and api.clip_get(id) or { length = 0 }
  local length = c.length
  -- A looped clip shows its notes over and over, as they sound.
  if ok then notes = paw.stretch.sounding(c, notes, M.preview_notes) end
  local i = 0
  for _, n in ipairs(ok and notes or {}) do
    if i >= M.preview_notes then break end
    -- Notes hidden by a trim of the clip's edges are not drawn.
    if n.start >= 0 and n.start < length then
      i = i + 1
      flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = n.start, n.length, n.pitch
    end
  end
  return flat
end

--- What a track is in VCA terms, for a strip: a VCA's members by name, a
--- member's VCAs by name, joined by commas.
function M.vca_words(id: integer): string
  local names: {string} = {}
  local list = paw.vca.is_vca(id) and paw.vca.members(id) or paw.vca.of(id)
  for i, other in ipairs(list) do names[i] = track_text(other, "name") end
  return table.concat(names, ", ")
end

--- The parts of the state that are kept while nothing changes them.
local record Kept
  key: string
  ids: {integer}
  modal: Modal
end

-- What the state's parts that only a turn with input, an edit or a redraw
-- can change were made for (`still_key`), by seat: the drawn tracks and
-- the modal state. While the song plays and nobody types, they are kept.
local kept: {integer:Kept} = {}

--- What those parts depend on: the project's revision, the redraws, the
--- input that came (`paw.remote.touches`), the seat and the keys typed.
--- A render in the background changes the modal state on its own.
local function still_key(): string
  if api.render_status() then return nil end
  local keymap = paw.keymap
  return table.concat({ M.revision, api.ui_redraws(), paw.remote and paw.remote.touches or 0, seats.current,
    keymap.mode, keymap.pending() } as {string | number}, ":")
end

--- The data that paw sends to a graphical frontend: transport, tracks,
--- clips, devices and the modal state, as plain data. `known` is a list of
--- the data that the frontend has already.
function M.state(known: integer): State
  M.polled = api.now() -- someone is looking: see `paw.fx.interactive`
  local t, e = api.transport_get(), api.engine_get()
  local key = still_key()
  local seat = seats.current
  local same = key and kept[seat] and kept[seat].key == key and kept[seat]
  -- The tracks that are drawn: those folded away into a group are left out.
  local ids = same and same.ids
  if not ids then
    ids = paw.groups.rows()
    ids[#ids + 1] = 0 -- the master track goes last
  end
  -- Both sides of every track's meter, one after the other.
  local levels: {number} = {}
  for i, id in ipairs(ids) do
    levels[2 * i - 1], levels[2 * i] = api.track_meter(id)
  end
  -- What arrives at each track's audio input, armed or not: 0 without one.
  local inputs: {number} = {}
  local device_levels = paw.audio.levels()
  for i, id in ipairs(ids) do
    inputs[i] = id ~= 0 and paw.audio.level({ input = track_text(id, "input") }, device_levels) or 0
  end
  local num, den = paw.tempo.signature_at(t.position)
  local out: State = {
    revision = M.revision, playing = t.playing, recording = t.take ~= nil, position = t.position,
    -- Beats of a count-in still to be counted before the take starts; 0 for none.
    counting = t.counting or 0,
    time = paw.time.format(t.position), clock = paw.time.clock(t.position),
    -- The tempo and signature where the playhead is.
    tempo = math.floor(paw.tempo.at(t.position) * 100 + 0.5) / 100, signature = num .. "/" .. den,
    cpu = paw.audio.load(e.cpu), levels = levels, inputs = inputs, modal = same and same.modal or modal(), armed = t.recording,
    -- What went wrong while playing (see `:engine.status`).
    xruns = e.xruns, late_blocks = e.late_blocks, midi_dropped = e.midi_dropped,
    record_dropped = e.record_dropped, devices_stopped = e.devices_stopped,
    -- How often the window draws while the song plays (`paw.opt.window_fps`).
    window_fps = opt.window_fps,
    window_cache = opt.window_cache,
  }
  if key and not same then kept[seat] = { key = key, ids = ids, modal = out.modal } end
  if known == M.revision then return out end

  local p = api.project_get()
  local project: ProjectState = {
    name = p.name, modified = p.modified, tempo = out.tempo, bar = paw.time.bar(), length = p.length,
    signature = out.signature, loop_enabled = t.loop_enabled, loop_start = t.loop_start,
    loop_end = t.loop_end, metronome = t.metronome, backend = e.backend, sample_rate = e.sample_rate,
    -- Recording only between two points, and the bars counted before a take.
    punch_enabled = t.punch_enabled, punch_start = t.punch_start, punch_end = t.punch_end,
    count_in = t.count_in, pre_roll = t.pre_roll, pre_roll_seconds = t.pre_roll_seconds,
    grid = opt.grid, note_grid = opt.note_grid, threads = e.threads, xruns = e.xruns,
    -- The engine in a few words: backend, output device, sample rate.
    engine = paw.audio.summary(),
  }
  out.project = project
  -- Bar and beat lines from the tempo map, well past the end and the last
  -- change, and the tempo and signature changes to flag on the ruler.
  project.marks = paw.tempo.marks(0, math.huge)
  -- The tempo lane under the ruler, when it is shown: the whole map, and the
  -- tempos at the bottom and the top of the row.
  if paw.tempolane.shown() then
    local lo, hi = paw.tempolane.range()
    project.tempo_lane = { lo = lo, hi = hi, points = paw.tempo.points() }
  end
  -- Markers and regions (`paw.markers`): { id, beat, name, length } each.
  project.markers = {}
  for i, m in ipairs(paw.markers and paw.markers.list() or {}) do
    project.markers[i] = { id = m.id, beat = m.beat, name = paw.markers.label(m), length = m.length or 0 }
  end
  -- Extensions' bands under it (`M.bands`).
  project.bands = M.band_state()
  local last = math.max(p.length or 0, t.loop_end or 0)
  for _, mark in ipairs(project.marks) do last = math.max(last, mark.beat) end
  local stop = paw.time.bar_start(paw.time.bar_of(last) + 17)
  project.lines = {}
  local lines = paw.tempo.lines(0, stop)
  for i, line in ipairs(lines) do
    local next_beat = lines[i + 1] and lines[i + 1].beat or line.beat + (line.beat - (lines[i - 1] and lines[i - 1].beat or line.beat - 1))
    project.lines[i] = {
      beat = line.beat, bar = line.bar, index = line.index, next = next_beat,
      label = line.index == 0 and tostring(line.bar) or "", place = line.bar .. "." .. (line.index + 1),
    }
  end
  out.selected = paw.cursor.track_id() or -1
  out.cursor = paw.cursor.beat
  out.tracks, out.clips, out.devices = {}, {}, {}
  local chosen_set: {integer:boolean} = {}
  for _, id in ipairs(M.chosen_clips()) do chosen_set[id] = true end
  for i, id in ipairs(ids) do
    local track = api.track_get(id)
    -- What the track's sound goes through, in a few words.
    local chain: {string} = {}
    for j, device in ipairs(track.devices or {}) do chain[j] = api.device_get(device).name end
    local to: types.Track
    if track.output then
      local ok, got = pcall(api.track_get, track.output)
      to = ok and got as types.Track or nil
    end
    local row: TrackState = {
      id = id, name = track.name, volume = track.volume, pan = track.pan, mute = track.mute,
      solo = track.solo, armed = track.armed, master = track.master, lanes = {},
      input = track.input, monitor = track.monitor,
      -- What the track takes in, in words (`UR22mkII · 1/2`), or nil.
      input_label = not track.master and paw.audio.label(track) or nil,
      -- The colour everything of the track's is drawn in, as in the terminal.
      color = paw.draw.track_colour(track, i), chain = table.concat(chain, " › "),
      -- Its kind, in a few words ("Vocal track · Kitane"), or nil.
      kind = id ~= 0 and paw.track_kinds.describe(id) or nil,
      output = to and to.name or nil,
      -- Its sends, for the mixer's strip: `{ name, level }` in dB each.
      sends = M.send_list(track),
      -- Groups: how many groups the track is inside, whether it is one,
      -- whether it is folded, and how many tracks it holds.
      depth = id ~= 0 and paw.groups.depth(id) or 0,
      group = id ~= 0 and paw.groups.is_group(id) or false,
      folded = id ~= 0 and paw.groups.folded(id) or false,
      members = id ~= 0 and #paw.groups.members(id) or 0,
      -- VCAs: whether it is one, and the names of the tracks under it, or
      -- of the VCAs a track is under, in a few words.
      vca = id ~= 0 and paw.vca.is_vca(id) or false,
      vcas = id ~= 0 and M.vca_words(id) or "",
      -- How tall it is drawn, as a share of the zoom's height.
      height = track.height or 1,
      -- "read", "touch", "latch", "write" or "off".
      automation = track.automation or "read",
      -- The lanes shown as rows of their own under the track, by id.
      lane_rows = {},
      -- How many take lanes it shows under its clips, above those rows.
      take_rows = id ~= 0 and paw.takes.lane_count(id) or 0,
    }
    out.tracks[i] = row
    for j, lane in ipairs(id ~= 0 and paw.lanes.shown(id) or {}) do row.lane_rows[j] = lane.id end
    -- Points are in the target's own units; `min` and `max` give its range,
    -- `lo` and `hi` the part of it a frontend draws the lane over, and
    -- `name` says what the lane moves.
    for j, lane in ipairs(api.lane_list(id)) do
      local lo, hi = M.lane_span(lane)
      row.lanes[j] = {
        id = lane.id, target = lane.target, device = lane.device, param = lane.param,
        enabled = lane.enabled, min = lane.min, max = lane.max, points = api.lane_points(lane.id),
        lo = lo, hi = hi, name = M.lane_name(lane),
      }
    end
    local take_lanes = row.take_rows > 0
    for _, clip in ipairs(api.clip_list(id)) do
      -- Stretched, shifted, looped, or being stretched: in a few characters.
      local mark = paw.stretch.badge(clip)
      local notches = paw.stretch.repeats(clip)
      -- Its warp markers, in beats from its start.
      local warps: {number} = {}
      for j, m in ipairs(clip.warp or {}) do warps[j] = m.beat - clip.start end
      local content = M.content_key(clip)
      local takes, take = paw.takes.count(clip)
      out.clips[#out.clips + 1] = {
        -- In take lanes: each take's name, and what changes exactly when
        -- its picture does (fetch `M.take_preview` again then).
        take_rows = take_lanes and M.take_rows(clip) or nil,
        id = clip.id, track = i - 1, start = clip.start, length = clip.length,
        name = (clip.offline and "offline · " or "") .. (mark and mark .. " · " or "") .. clip.name,
        midi = clip.kind == "midi", muted = clip.muted,
        -- How many takes it has (1 without others), and which plays.
        takes = takes, take = take,
        -- Chosen with the pointer (`M.chosen_clips`).
        selected = chosen_set[clip.id] or false,
        -- An audio clip's fades, in beats, and its gain in dB.
        fade_in = clip.fade_in, fade_out = clip.fade_out, gain = clip.gain,
        -- Its file is missing: silent until relinked. The name says so too.
        offline = clip.offline or nil,
        -- Changes exactly when the clip's notes or controller moves do:
        -- fetch `M.preview` (and the piano roll's clip) again then.
        stamp = clip.kind ~= "audio" and content or nil,
        -- Changes exactly when the clip's waveform does: fetch `M.peaks` again then.
        waveform = clip.kind == "audio" and content or nil,
        -- Whether it loops, and where its repeats begin, in beats from its start.
        loop = clip.loop or nil, notches = notches, warps = warps,
      }
    end
  end
  if out.selected >= 0 then
    for i, id in ipairs(api.track_get(out.selected).devices) do out.devices[i] = device_state(id) end
    out.routing = M.routing(out.selected)
  end
  if known < 0 then
    out.kinds = {}
    for i, info in ipairs(api.device_types()) do out.kinds[i] = info.kind end
  end
  return out
end

--- Save the project under a new name: choose the directory from a list,
--- then type the file's name. `after` runs once it is saved.
function M.save_as(after?: function())
  paw.pick.file({
    title = "Save the project in",
    directory = true,
    on_choose = function(dir: string)
      local p = api.project_get()
      -- A project is a folder: its name is the folder's.
      local name = p.path and (p.path:gsub("/project%.toml$", ""):gsub("%.json$", ""):match("([^/]+)$"))
        or (p.name ~= "" and p.name or "song")
      paw.ui.input({ prompt = "Folder name: ", text = name }, function(typed: string)
        if typed == "" then return end
        local saved, note = paw.project.write(dir .. "/" .. typed)
        paw.notify(note and (note .. ": " .. saved) or ("saved " .. saved))
        if after then after() end
      end)
    end,
  })
end

options.define("native_dialogs", true) -- the window opens the desktop's file dialogs, not the kernel's list
-- Frames a second the window draws while the song plays (the playhead, the
-- meters): "auto" is 30 on a graphics card and 15 on the processor. Keys,
-- the pointer and edits are drawn at once all the same.
options.define("window_fps", "auto", { type = { "number", "string" }, min = 1, max = 60, values = { "auto" } })
-- The window keeps what does not move in a pane as textures, and paints a
-- part again only when it changes: true, false, or "auto" (on).
options.define("window_cache", "auto", { type = { "boolean", "string" }, values = { "auto", true, false } })

--- What the graphical window said of the OpenGL that draws it when it
--- started: `{ renderer, version, software, cause }`, or nil before a
--- window started. `cause` tells why a window draws on the processor:
--- "asked", "libgl", "no-card" or "driver".
M.window_renderer = nil

--- What to do about a window that draws on the processor, by cause, the
--- likely cause first. `:checkhealth window` gives all of them.
M.software_advice = {
  asked = "PAW_GUI_RENDERER=software or --renderer software asks for the processor: unset the variable and leave out the option",
  libgl = "LIBGL_ALWAYS_SOFTWARE is set: unset it",
  driver = "the OpenGL driver of the graphics card is missing (on NixOS, set hardware.graphics.enable = true; elsewhere install Mesa's drivers), "
    .. "or the X server gives no DRI3 (over SSH, VNC or Xvfb): start the window on the computer's own screen",
  ["no-card"] = "no graphics card was found (/dev/dri has no render node): on this computer the window can only draw on the processor; "
    .. "a lower paw.opt.window_fps costs less",
}

--- The window tells which OpenGL renderer draws it (see
--- `paw.frontend.window_renderer`). One that draws on the processor is
--- told once, in a line that says what to do.
function M.window_renderer_set(info: Renderer)
  M.window_renderer = info
  if type(info) == "table" and info.software then
    local advice = M.software_advice[info.cause] or M.software_advice.driver
    paw.notify("The window draws on the processor (" .. tostring(info.renderer):match("^%S+") .. "), which costs CPU while a song plays: "
      .. advice .. ". See :checkhealth window.", "warn")
  end
end

--- The data that the window needs to open the file dialog of the desktop.
--- `native` tells if it must use that dialog (the option). When it is off,
--- the dialogs are those of the kernel. `dir` is the folder to start in. It
--- is the folder of the last selected file, or of the project, or home, as
--- in the list picker. `name` is the file name of the project, for
--- "Save as". `render` is the file endings that a render can write.
function M.dialog_info(): DialogInfo
  local p = api.project_get()
  local dir = paw.state.pick_dir or (p.path and p.path:match("^(.*)/[^/]+$")) or os.getenv("HOME") or "/"
  local name = p.path and p.path:match("([^/]+)$") or ((p.name ~= "" and p.name or "song") .. ".json")
  -- What a render can write: wav and flac, and the lossy formats ffmpeg can make.
  local render: {string} = { "wav", "flac" }
  for ext, available in pairs(M.render_dialog().formats) do
    if available then render[#render + 1] = ext end
  end
  table.sort(render)
  return { native = opt.native_dialogs and true or false, dir = dir, name = name, render = render }
end

--- Tells if paw would lose data if it closes now: { modified, name, path }.
function M.closing(): Closing
  local p = api.project_get()
  return { modified = paw.project.unsaved(), name = p.name, path = p.path }
end

--- The start values of the render dialog. These are the file that a render
--- would write, and the ranges that paw can render (`{ name, label }`: the
--- song, the loop, the selection, each region). They are also the sample
--- rate of the engine, and the lossy formats that ffmpeg can make here
--- (`formats`: `{ mp3 = true, ogg = false, ... }`).
function M.render_dialog(): RenderDialog
  local t = api.transport_get()
  local ranges: {RangeChoice} = { { name = "song", label = "The whole song" } }
  if t.loop_end > t.loop_start then
    ranges[#ranges + 1] = { name = "loop", label = string.format("The loop (%s – %s)", paw.time.format(t.loop_start), paw.time.format(t.loop_end)) }
  end
  local sel = paw.keymap.selection()
  if sel and sel.c0 and sel.c1 and sel.c1 > sel.c0 then ranges[#ranges + 1] = { name = "selection", label = "The selection" } end
  for _, r in ipairs(paw.markers.regions()) do
    ranges[#ranges + 1] = { name = "region:" .. r.id, label = "Region “" .. paw.markers.label(r) .. "”" }
  end
  -- A project with no file yet renders to where a file was last chosen, or home.
  local path = render_module().default_path()
  if not path:find("/", 1, true) then path = (paw.state.pick_dir or os.getenv("HOME") or ".") .. "/" .. path end
  local formats: {string:boolean} = {}
  for _, f in ipairs(api.render_formats(opt.ffmpeg)) do
    if f.lossy then formats[f.extensions[1]] = f.available end
  end
  return {
    path = path, ranges = ranges, sample_rate = api.engine_get().sample_rate, formats = formats,
    tags = render_module().tags(),
  }
end

--- The menu of the input of a track: the choices of `paw.audio.choices`
--- under their headings, `audio`, `midi` and `channel`. It also gives the
--- MIDI output of the track: `midi_out`, `midi_out_channel` and
--- `midi_out_form`. Each is a list of `{ label, checked }`.
--- `act.choose_input` takes one by heading and place.
function M.input_menu(track: integer): InputMenu
  local out: InputMenu = {
    audio = {}, midi = {}, channel = {}, midi_out = {}, midi_out_channel = {}, midi_out_form = {},
    monitor = track_flag(track, "monitor"),
  }
  local lists = out as {string:{Check}}
  for _, choice in ipairs(paw.audio.choices(track)) do
    local list = lists[choice.group]
    list[#list + 1] = { label = choice.label, checked = choice.checked }
  end
  return out
end

--- The recent projects the File menu lists: `{ label, path }` each.
function M.recent_menu(): {RangeChoice}
  return paw.recent.menu()
end

local function layout_file(): string return M.layout_path or api.env().state_dir .. "/window.json" end

--- How the window was left (its size, the zoom, the heights of rows and of
--- the piano roll, if the mixer shows): a table, empty when nothing
--- was kept. It belongs to the machine, so it is kept here, where a window
--- attached to this kernel finds it too. (`M.layout_path` names another
--- file, for tests.)
function M.layout_get(): WindowLayout
  local handle = io.open(layout_file(), "rb")
  if not handle then return {} end
  local text = handle:read("*a")
  handle:close()
  local ok, data = pcall(api.json_decode, text)
  return ok and type(data) == "table" and data as WindowLayout or {}
end

--- Keep the window's layout (see `layout_get`).
function M.layout_set(layout: WindowLayout)
  local file = layout_file()
  pcall(api.fs_mkdir, (file:match("^(.*)/[^/]*$") or "."))
  local handle = io.open(file .. ".tmp", "wb")
  if not handle then return end
  handle:write(api.json_encode(layout, true))
  handle:close()
  os.rename(file .. ".tmp", file)
end

--- The menu where the audio devices are chosen: `info` (lines to show),
--- `output`, `input`, `block`, `rate` and `backend`, each a list of
--- `{ label, checked }`.
--- `act.choose_engine` takes one by heading and place.
function M.engine_menu(): EngineMenu
  local out: EngineMenu = { info = {}, output = {}, input = {}, block = {}, rate = {}, backend = {} }
  local ok, got = pcall(paw.audio.engine_choices)
  if not ok then
    out.info[1] = { label = tostring(got):match("[^\n]*"), checked = false }
    return out
  end
  local lists = out as {string:{Check}}
  for _, choice in ipairs(got as {Choice}) do
    local list = lists[choice.group]
    list[#list + 1] = { label = choice.label, checked = choice.checked }
  end
  return out
end

--- The waveform of an audio clip at `points` points (`M.peak_points`
--- without), as one flat list { min1, max1, rms1, min2, max2, rms2, ... }.
--- It gives how far the wave goes each way and how loud it is, which is its
--- body. It is not in `state`, which paw sends again each time the cursor
--- moves. So a frontend gets each waveform only one time for each width.
function M.peaks(clip: integer, points?: number): {number}
  local flat: {number} = {}
  local n = util.clamp(math.floor(points or M.peak_points), 8, 4096) as integer
  for i, p in ipairs(api.clip_peaks(clip, n)) do
    flat[3 * i - 2], flat[3 * i - 1], flat[3 * i] = p[1], p[2], p[3]
  end
  return flat
end

-- What a pointer does ---------------------------------------------------------
--
-- A frontend sends gestures here (`paw.frontend.act.move_clip(id, 8, track)`)
-- instead of spelling out what they mean, so that every frontend means the
-- same by a drag or a double click, and the suite can test it. Beats snap to
-- the grid here. Notes and points are named by their place, from 1.

local A: Act = {}
M.act = A
M.openers = {}

local function snap(beat: number): number return math.max(0, paw.cursor.snap(beat)) end

local function note_snap(beat: number): number
  local grid = opt.note_grid
  return math.max(0, math.floor(beat / grid + 0.5) * grid)
end

--- Give the arrange view the keyboard, unless a window is open over it.
local function to_arrange()
  if paw.keymap.mode == "x" then paw.keymap.set_mode("n") end
  if not paw.ui.float and paw.ui.focused ~= "arrange" then paw.ui.focus("arrange") end
end

-- Clips chosen with the pointer -----------------------------------------------
--
-- A click chooses a clip, Ctrl and a click adds or takes one away, Shift and
-- a click takes in the clips between it and the last one chosen, a box drawn
-- with the right button takes in what it touches. Gestures on a chosen clip
-- act on all of them. So do the keys: two or more chosen clips (or any chosen
-- with a modifier or a box) are visual mode's selection, of the kind "clips",
-- which every operator acts on (`d`, `x`, `y`, `>`, `gc`...) and Esc lets go
-- of; one clip chosen with a plain click is the clip under the cursor, which
-- `x` already deletes, and is let go of when the cursor leaves it.

--- The clips chosen with the pointer, and the one a Shift click counts from.
local record Picked
  set: {integer:boolean}
  anchor: integer
end
--- The clips chosen before the last plain click, and when.
local record Recent
  set: {integer:boolean}
  at: number
end

local picked: Picked = { set = {}, anchor = nil }
local recently_chosen: Recent -- the clips chosen before the last plain click: { set, at }
-- A gesture is choosing: the cursor and mode it moves keep the choice.
local pointing = false
-- Each window and terminal chooses clips of its own.
seats.keep("frontend.picked", function(): Picked return picked end, function(p: Picked) picked = p end,
  function(): Picked return { set = {}, anchor = nil } end)
seats.keep("frontend.recently_chosen", function(): Recent return recently_chosen end,
  function(r: Recent) recently_chosen = r end, function(): Recent return nil end)

--- The ids of the chosen clips, in order.
function M.chosen_clips(): {integer}
  local keymap = paw.keymap
  -- Another kind of selection is open: that is what the keys act on.
  if keymap.mode == "x" and not (keymap.visual and keymap.visual.region) then return {} end
  local out: {integer} = {}
  for id in pairs(picked.set) do
    if pcall(api.clip_get, id) then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

--- Where each drawn track is, by id: its row from 1.
local function row_index(): {integer:integer}
  local rows: {integer:integer} = {}
  for i, id in ipairs(paw.groups.rows()) do rows[id] = i end
  return rows
end

--- The chosen clips as a region for the operators: the rows and the stretch
--- they span, and `clips`, the set of them.
local function clip_region(): Region
  local rows = row_index()
  local set: {integer:boolean} = {}
  local r0, r1, c0, c1 = math.huge, -math.huge, math.huge, -math.huge
  for _, id in ipairs(M.chosen_clips()) do
    local c = api.clip_get(id)
    local row = rows[c.track]
    if row then
      set[id] = true
      r0, r1 = math.min(r0, row), math.max(r1, row)
      c0, c1 = math.min(c0, c.start), math.max(c1, c.start + c.length)
    end
  end
  if not next(set) then return nil end
  return { kind = "clips", clips = set, r0 = r0, r1 = r1, c0 = c0, c1 = c1 }
end

local function changed()
  M.revision = M.revision + 1
  api.ui_redraw()
end

--- Choose a set of clips (`{ [id] = true }`); with `visual` they become
--- visual mode's selection.
local function choose_clips(set: {integer:boolean}, anchor: integer, visual: boolean)
  picked = { set = set, anchor = anchor or picked.anchor }
  local keymap = paw.keymap
  pointing = true
  if visual and next(set) and clip_region() then
    if not paw.ui.float and paw.ui.focused ~= "arrange" then paw.ui.focus("arrange") end
    local region = clip_region()
    keymap.visual = { kind = "clips", row = region.r0, col = region.c0, view = paw.ui.focused, region = clip_region }
    if keymap.mode ~= "x" then keymap.set_mode("x") end
  elseif keymap.mode == "x" then
    keymap.set_mode("n")
  end
  pointing = false
  changed()
end

--- The payload of `mode.changed` (paw/keymap.lua).
local record ModeChanged
  mode: string
  old: string
end
local mode_changed: events.Event<ModeChanged> = events.event("mode.changed")

events.on(mode_changed, function(e: ModeChanged)
  if not pointing and e.old == "x" and next(picked.set) then
    picked.set = {}
    changed()
  end
end)
local cursor_changed: events.Event<events.Payload> = events.event("cursor.changed")
events.on(cursor_changed, function()
  if pointing or paw.keymap.mode == "x" or not next(picked.set) then return end
  local under = paw.cursor.clip()
  if not (under and picked.set[under.id]) then
    picked.set = {}
    changed()
  end
end)

--- Let go of the chosen clips.
function A.clear_clip_selection()
  if next(picked.set) then choose_clips({}, nil, false) end
end

--- Put the cursor on a track at a beat: a click on a lane or a header. A
--- click on a lane (one with a beat) lets go of the chosen clips.
function A.select(track: integer, beat?: number)
  pointing = true
  to_arrange()
  if track ~= 0 then paw.cursor.set_track(track) end
  if beat then paw.cursor.set_beat(snap(beat)) end
  pointing = false
  if beat and next(picked.set) then
    picked.set = {}
    changed()
  end
end

--- Put the cursor in a clip where it was clicked, on the grid but inside
--- the clip, so that the keys act on it.
local function cursor_into(id: integer, beat?: number)
  local c = api.clip_get(id)
  pointing = true
  to_arrange()
  paw.cursor.set_track(c.track)
  beat = snap(beat or c.start)
  if beat < c.start or beat >= c.start + c.length then beat = c.start end
  paw.cursor.set_beat(beat)
  pointing = false
end

--- The clips on drawn rows `row0` to `row1` reaching into beats `from` to `to`.
local function clips_in(row0: integer, row1: integer, from: number, to: number): {integer}
  local rows = paw.groups.rows()
  local out: {integer} = {}
  for row = math.max(1, math.min(row0, row1)), math.min(#rows, math.max(row0, row1)) do
    for _, c in ipairs(api.clip_list(rows[row])) do
      if c.start < to - 1e-9 and c.start + c.length > from + 1e-9 then out[#out + 1] = c.id end
    end
  end
  return out
end

--- A click on a clip: the cursor goes there, and `mode` says what happens
--- to the chosen clips: "only" (or nil) the clip alone, "toggle" (Ctrl) in
--- or out, "add" (Shift) the clips from the last one chosen to this one: on
--- one track those that start between them, across tracks those in the
--- rectangle the two span.
function A.select_clip(id: integer, beat?: number, mode?: string)
  cursor_into(id, beat)
  mode = mode or "only"
  if mode == "only" then
    -- What was chosen before, for a double click that follows.
    recently_chosen = { set = {}, at = api.now() }
    for _, other in ipairs(M.chosen_clips()) do recently_chosen.set[other] = true end
    return choose_clips({ [id] = true }, id, false)
  end
  local set: {integer:boolean} = {}
  for _, other in ipairs(M.chosen_clips()) do set[other] = true end
  if mode == "toggle" then
    set[id] = not set[id] or nil
    return choose_clips(set, set[id] and id or picked.anchor, true)
  end
  local anchor = picked.anchor and set[picked.anchor] and pcall(api.clip_get, picked.anchor) and api.clip_get(picked.anchor)
  local c = api.clip_get(id)
  if not anchor then
    set[id] = true
    return choose_clips(set, id, true)
  end
  local rows = row_index()
  local from, to = math.min(anchor.start, c.start), math.max(anchor.start, c.start)
  if anchor.track == c.track then
    for _, other in ipairs(api.clip_list(c.track)) do
      if other.start >= from - 1e-9 and other.start <= to + 1e-9 then set[other.id] = true end
    end
  else
    to = math.max(anchor.start + anchor.length, c.start + c.length)
    for _, other in ipairs(clips_in(rows[anchor.track] or 1, rows[c.track] or 1, from, to)) do set[other] = true end
  end
  set[id] = true
  choose_clips(set, anchor.id, true)
end

--- A box drawn with the right button over the timeline, from row `row0`
--- at `beat0` to `row1` at `beat1` (rows of drawn tracks, from 1): the
--- clips it touches are chosen. `mode` as for `select_clip`: "add" keeps
--- those chosen already, "toggle" turns the ones it touches over.
function A.select_clips_box(row0: integer, beat0: number, row1: integer, beat1: number, mode?: string): integer
  local set: {integer:boolean} = {}
  if mode == "add" or mode == "toggle" then
    for _, id in ipairs(M.chosen_clips()) do set[id] = true end
  end
  local touched = clips_in(row0, row1, math.min(beat0, beat1), math.max(beat0, beat1))
  for _, id in ipairs(touched) do
    if mode == "toggle" and set[id] then set[id] = nil else set[id] = true end
  end
  choose_clips(set, touched[1] or picked.anchor, true)
  local count = 0
  for _ in pairs(set) do count = count + 1 end
  return count
end

--- Choose a set of clips (`{ [id] = true }`), as visual mode's selection:
--- what `:select` does.
function M.choose_clips(set: {integer:boolean}) choose_clips(set, nil, true) end

--- Every clip on the timeline, chosen.
function A.select_all_clips()
  local set: {integer:boolean} = {}
  for _, track in ipairs(paw.groups.rows()) do
    for _, c in ipairs(api.clip_list(track)) do set[c.id] = true end
  end
  choose_clips(set, nil, true)
end

--- A clip's snapshot moved to `start`.
local function snapshot_at(clip: objects.Clip, start: number): objects.ClipSnapshot
  local taken = clip:snapshot()
  local out: objects.ClipSnapshot = {}
  for k, v in pairs(taken as {string:Value}) do (out as {string:Value})[k] = v end
  out.start = start
  return out
end

--- Drop a clip somewhere else: at `start`, on `track` if given. With `copy`
--- the clip stays and a copy is dropped.
function A.move_clip(id: integer, start: number, track?: integer, copy?: boolean): integer
  local clip = paw.clip(id)
  start = snap(start)
  track = track and track ~= 0 and track or clip:get().track
  if copy then
    local made = paw.restore_clip(snapshot_at(clip, start), track)
    return made.id
  end
  api.clip_set(id, { start = start })
  if track ~= api.clip_get(id).track then api.clip_set(id, { track = track }) end
  return id
end

--- The clips a gesture on clip `id` acts on: all the chosen ones if it is
--- one of them, else that clip alone, which is then the chosen one.
local function grabbed_clips(id: integer): {integer}
  local ids = M.chosen_clips()
  for _, other in ipairs(ids) do
    if other == id then return ids end
  end
  choose_clips({ [id] = true }, id, false)
  return { id }
end

--- Drag clips: the one at `id` and, if it is chosen, the others chosen with
--- it, by `dbeat` beats and `drows` rows of drawn tracks, keeping their
--- places to one another. Snapping is relative: the clips move by whole
--- grid steps, so the grabbed clip keeps its distance from the grid line
--- before it, which is none if it started on one. `free` (Shift) moves them
--- by exactly `dbeat`. With `copy` (Ctrl) they stay and copies are dropped,
--- which are then the chosen clips. Nothing goes before the start or off
--- the tracks. One undo step, as one call. Returns the ids of what moved.
function A.drag_clips(id: integer, dbeat: number, drows?: number, copy?: boolean, free?: boolean): {integer}
  local ids = grabbed_clips(id)
  local by = free and dbeat or util.round(dbeat, opt.grid)
  local rows_by = math.floor((drows or 0) + 0.5)
  local rows, list = row_index(), paw.groups.rows()
  local clips: {types.Clip} = {}
  for i, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    clips[i] = c
    by = math.max(by, -c.start)
    local row = rows[c.track]
    if row then rows_by = util.clamp(rows_by, 1 - row, #list - row) as integer end
  end
  if math.abs(by) < 1e-9 and rows_by == 0 and not copy then return ids end
  local out: {integer} = {}
  for i, c in ipairs(clips) do
    local row = rows[c.track]
    local track = row and list[row + rows_by] or c.track
    if copy then
      local made = paw.restore_clip(snapshot_at(paw.clip(c.id), c.start + by), track)
      out[i] = made.id
    else
      api.clip_set(c.id, { start = c.start + by })
      if track ~= c.track then api.clip_set(c.id, { track = track }) end
      out[i] = c.id
    end
  end
  if copy then
    local set: {integer:boolean} = {}
    for _, cid in ipairs(out) do set[cid] = true end
    choose_clips(set, out[1], #out > 1)
  end
  return out
end

--- Move what plays inside a MIDI clip by `by` beats: its notes and its
--- controller moves. What goes before the clip's start keeps a place below
--- 0, where it is not played or drawn, and comes back when the start is
--- dragged out over it again.
local function shift_content(id: integer, by: number)
  local notes = api.clip_notes(id)
  for _, n in ipairs(notes) do n.start = n.start + by end
  api.clip_set_notes(id, notes)
  local c = api.clip_get(id)
  if c.control_count > 0 then
    local controls = api.clip_controls(id)
    for _, move in ipairs(controls) do move.start = move.start + by end
    api.clip_set_controls(id, controls)
  end
  -- The takes that are not playing stay lined up with the one that is.
  paw.takes.shift(id, by)
end

--- Beats in an audio clip's offset into its file.
--- How far before an audio clip's start its file begins, in beats of the
--- tempo map there (a negative number).
local function file_start(c: types.Clip): number
  return paw.time.to_beat(math.max(0, paw.time.to_seconds(c.start) - paw.stretch.lead(c))) - c.start
end

--- Drag an edge of a clip, and the same edge of the clips chosen with it:
--- `edge` is "start" or "end", `dbeat` how far it went. The grabbed clip's
--- edge lands on the grid unless `free` (Shift); the others change by as
--- much, each within what it can do. The start is trimmed without moving
--- what plays: an audio clip starts further into its file, a MIDI clip
--- hides the notes before its new start, which come back when it is
--- dragged out again. A clip is never shorter than a grid step (a 64th of
--- a beat when free). With `slip` (Alt) the edge stays and what plays
--- inside the clip moves instead. With Alt and Shift on the right edge,
--- the sound is stretched instead (`A.stretch_clips`). One undo step.
--- Returns the ids.
function A.trim_clips(id: integer, edge: string, dbeat: number, free?: boolean, slip?: boolean): {integer}
  if slip and free and edge == "end" then return A.stretch_clips(id, dbeat) end
  local ids = grabbed_clips(id)
  local held = api.clip_get(id)
  local least = free and 1 / 64 or opt.grid
  if slip then
    for _, cid in ipairs(ids) do
      local c = api.clip_get(cid)
      if c.loop then
        -- A looped clip's repeats turn round under it.
        paw.stretch.move_content(cid, -dbeat)
      elseif c.kind == "audio" then
        -- Later in the clip is earlier in the file, which has no time before 0.
        api.clip_set(cid, { offset = math.max(0, c.offset - paw.stretch.file_seconds(c, dbeat)) })
      else
        shift_content(cid, dbeat)
      end
    end
    return ids
  end
  local at = edge == "start" and held.start or held.start + held.length
  local by = (free and math.max(0, at + dbeat) or snap(at + dbeat)) - at
  if math.abs(by) < 1e-9 then return ids end
  for _, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    if edge == "start" then
      local d = math.min(by, c.length - least)
      d = math.max(d, -c.start)
      -- A looped clip turns its loop round instead of running out of file.
      if c.kind == "audio" and not c.loop then d = math.max(d, file_start(c)) end
      if math.abs(d) > 1e-9 then
        api.clip_set(cid, { start = c.start + d })
        api.clip_set(cid, { length = c.length - d })
        if c.loop then
          paw.stretch.move_content(cid, d)
        elseif c.kind == "audio" then
          api.clip_set(cid, { offset = math.max(0, c.offset + paw.stretch.file_seconds(c, d)) })
        else
          shift_content(cid, -d)
        end
        if c.kind == "audio" then
          api.clip_set(cid, { fade_in = math.min(c.fade_in, c.length - d) })
          api.clip_set(cid, { fade_out = math.min(c.fade_out, c.length - d) })
        end
      end
    else
      local length = math.max(least, c.length + by)
      api.clip_set(cid, { length = length })
      if c.kind == "audio" then
        api.clip_set(cid, { fade_in = math.min(c.fade_in, length) })
        api.clip_set(cid, { fade_out = math.min(c.fade_out, length) })
      end
    end
  end
  return ids
end

--- The right edge of an audio clip dragged with Alt and Shift: what it
--- plays is stretched to end where the edge lands on the grid, without
--- changing its pitch, and that of the audio clips chosen with it by as
--- many beats (`paw.stretch.to`). The stretched sound is made once the
--- edge is let go. One undo step. Returns the ids.
function A.stretch_clips(id: integer, dbeat: number): {integer}
  local ids = grabbed_clips(id)
  local held = api.clip_get(id)
  local at = held.start + held.length
  local by = snap(at + dbeat) - at
  if math.abs(by) < 1e-9 then return ids end
  for _, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    if c.kind == "audio" then
      local ok, err = pcall(paw.stretch.to, cid, math.max(opt.grid, c.length + by)) as (boolean, string)
      if not ok then paw.notify((tostring(err):gsub("^[^:]*:%d+: ", "")), "warn") end
    end
  end
  return ids
end

--- The clip menu's "Stretch to the selection", "Stretch to the loop" and
--- "Reset stretch" (`what` "selection", "loop" or "reset"), on audio clip
--- `id`: it is stretched to start and end where the time selection or the
--- loop does, or plays its file at its own speed again.
function A.stretch_clip(id: integer, what: string)
  local from, to: number, number
  if what == "selection" then
    local sel = paw.keymap.selection()
    -- Clips chosen with the pointer make a selection too: not one of time.
    if not (sel and not sel.clips and sel.c0 and sel.c1 and sel.c1 > sel.c0) then
      return paw.notify("select a stretch of time to stretch the clip to", "warn")
    end
    from, to = sel.c0, sel.c1
  elseif what == "loop" then
    local t = api.transport_get()
    if not (t.loop_end > t.loop_start) then return paw.notify("there is no loop to stretch the clip to", "warn") end
    from, to = t.loop_start, t.loop_end
  end
  local ok, err = pcall(function()
    if from then paw.stretch.fit(id, from, to) else paw.stretch.reset(id) end
  end) as (boolean, string)
  if not ok then paw.notify((tostring(err):gsub("^[^:]*:%d+: ", "")), "warn") end
end

--- Warp markers in the window (`paw.stretch.warp_add`): a double click on
--- an audio clip's top band puts one at `beat`; a marker's handle dragged
--- moves marker `index` to `beat` (on the grid unless `free`), stretching
--- the sound on either side of it; its menu takes it off. Each one undo
--- step; a refusal is said, not raised.
local function warp_run(f: function())
  local ok, err = pcall(f) as (boolean, string)
  if not ok then paw.notify((tostring(err):gsub("^[^:]*:%d+: ", ""):gsub("^runtime error: ", "")), "warn") end
end

function A.warp_add(id: integer, beat: number)
  warp_run(function() paw.stretch.warp_add(id, math.max(0, beat)) end)
end

function A.warp_move(id: integer, index: integer, beat: number, free?: boolean)
  local to = free and math.max(0, beat) or snap(beat)
  warp_run(function() paw.stretch.warp_move(id, index, to) end)
end

function A.warp_remove(id: integer, index: integer)
  warp_run(function() paw.stretch.warp_remove(id, index) end)
end

--- The handle at a top corner of an audio clip: its fade in (`which` "in")
--- or out ("out") is set to `beats`, and so is that of the audio clips
--- chosen with it, each no longer than the clip. One undo step.
function A.set_fade(id: integer, which: string, beats: number)
  for _, cid in ipairs(grabbed_clips(id)) do
    local c = api.clip_get(cid)
    if c.kind == "audio" then
      local fade = util.clamp(beats, 0, c.length)
      if which == "out" then api.clip_set(cid, { fade_out = fade }) else api.clip_set(cid, { fade_in = fade }) end
    end
  end
end

--- A drag on the top line of an audio clip: its gain, in dB, is set to
--- `db`, and that of the audio clips chosen with it changes by as much,
--- each between -60 and +24 dB. The waveform is drawn as loud as it plays.
function A.set_clip_gain(id: integer, db: number)
  local by = db - api.clip_get(id).gain
  for _, cid in ipairs(grabbed_clips(id)) do
    local c = api.clip_get(cid)
    if c.kind == "audio" then api.clip_set(cid, { gain = util.clamp(c.gain + by, -60, 24) }) end
  end
end

--- Drag a clip's right edge to a new length, never shorter than a grid step.
function A.resize_clip(id: integer, length: number)
  api.clip_set(id, { length = math.max(opt.grid, paw.cursor.snap(length)) })
end

--- A tempo (`kind` "tempo") or signature change flagged on the ruler at
--- `beat`: "move" it to beat `to` (on the grid; a signature to the bar
--- line nearest), "edit" its value through a prompt, or "remove" it.
function A.tempo_mark(action: string, kind: string, beat: number, to?: number)
  local map = api.tempo_points()
  local tempos, signatures = map.tempos, map.signatures
  local index: integer
  local beats: {number} = {}
  if kind == "tempo" then
    for i, p in ipairs(tempos) do beats[i] = p.beat end
  else
    for i, p in ipairs(signatures) do beats[i] = p.beat end
  end
  for i, b in ipairs(beats) do
    if math.abs(b - beat) < 1e-6 then index = i end
  end
  if not index or index == 1 then return end
  local was = beats[index]
  if action == "remove" then
    if kind == "tempo" then api.tempo_remove(was) else api.signature_remove(was) end
  elseif action == "move" then
    local moved: number
    if kind == "tempo" then
      local point = table.remove(tempos, index)
      point.beat = math.max(opt.grid, paw.cursor.snap(to))
      tempos[#tempos + 1] = point
      moved = point.beat
    else
      local point = table.remove(signatures, index)
      -- To the nearest bar line, so that the bars before it stay whole.
      local n = paw.time.bar_of(to)
      local a, b = paw.time.bar_start(n), paw.time.bar_start(n + 1)
      point.beat = math.max(paw.time.bar_start(2), (to - a < b - to) and a or b)
      signatures[#signatures + 1] = point
      moved = point.beat
    end
    if math.abs(moved - was) > 1e-9 then api.tempo_set_points(tempos, signatures) end
  elseif action == "edit" then
    local where = "bar " .. paw.time.bar_of(was)
    if kind == "tempo" then
      local point = tempos[index]
      paw.ui.input({ prompt = "tempo at " .. where .. ": ", text = string.format("%g", point.bpm) }, function(text: string)
        local bpm = tonumber(text)
        if bpm then api.tempo_set(point.beat, bpm) end
      end)
    else
      local point = signatures[index]
      paw.ui.input({ prompt = "signature at " .. where .. ": ", text = point.num .. "/" .. point.den }, function(text: string)
        local n, d = tostring(text):match("^%s*(%d+)%s*/%s*(%d+)%s*$")
        if n then api.signature_set(point.beat, tonumber(n) as integer, tonumber(d) as integer) end
      end)
    end
  end
end

-- The tempo lane under the ruler. A frontend names a height in it as a
-- fraction, 0 at the bottom, as for the automation lanes.

--- Show the tempo lane, or hide it.
function A.tempo_lane(on?: boolean): boolean
  if on == nil then return paw.tempolane.toggle() end
  paw.tempolane.show(on)
  return on
end

--- A click on the lane: a tempo change at the beat, on the grid.
function A.tempo_point_add(beat: number, fraction: number)
  paw.tempolane.add(snap(beat), paw.tempolane.bpm(fraction))
end

--- A change dragged to a beat and a height. The first change, the start's,
--- only changes its tempo.
function A.tempo_point_move(beat: number, to: number, fraction: number)
  paw.tempolane.move(beat, snap(to), paw.tempolane.bpm(fraction))
end

function A.tempo_point_remove(beat: number)
  paw.tempolane.remove(beat)
end

--- Make the change at `beat` ramp to the next, or hold again.
function A.tempo_point_ramp(beat: number): boolean
  return paw.tempolane.ramp(beat)
end

--- Draw over the lane with a pencil: `points` are `{ beat, fraction }`.
function A.tempo_draw(points: {Point})
  local out: {TempolaneModule.StrokePoint} = {}
  for i, p in ipairs(points) do out[i] = { snap(p[1]), paw.tempolane.bpm(p[2]) } end
  paw.tempolane.draw(out)
end

--- A double click on an empty lane: a clip of one bar in the bar clicked.
function A.add_clip(track: integer, beat: number): integer
  local start = paw.time.bar_floor(math.max(0, beat))
  local id = api.clip_add(track, { start = start, length = paw.time.bar(start) })
  A.select(track, api.clip_get(id).start)
  return id
end

--- Open a clip's notes; an audio clip has none to open. An extension that
--- has an editor of its own for some clips adds a function to
--- `paw.frontend.openers`, which is asked first: it gets the clip and
--- returns true if it has opened it.
function A.open_clip(id: integer)
  local clip = paw.clip(id)
  -- Opening one of several chosen clips edits them all. A double click's
  -- first click had chosen it alone a moment before.
  local before = recently_chosen and api.now() - recently_chosen.at < 1500 and recently_chosen.set
  if not (before and before[id]) then
    before = {}
    for _, other in ipairs(M.chosen_clips()) do before[other] = true end
  end
  local together: {integer} = {}
  if before[id] then
    for other in pairs(before) do
      local ok, c = pcall(api.clip_get, other)
      if ok and (c as types.Clip).kind == "midi" then together[#together + 1] = other end
    end
    table.sort(together)
  end
  A.select_clip(id, clip.start)
  for _, opener in ipairs(M.openers) do
    if opener(clip) then return end
  end
  if clip.kind ~= "midi" then return end
  -- Opened by the pointer, the roll shows the clips whole where it can.
  paw.ui.views.pianoroll.fit_next = true
  if #together > 1 then return paw.roll_clips.open(together, id) end
  paw.ui.views.pianoroll:edit(clip)
end

--- The record button. With nothing being recorded: arm the selected track
--- if no track is armed, then record from the playhead. Otherwise: end the
--- take and stop.
function A.record()
  local t = api.transport_get()
  if t.recording or t.take then
    paw.transport.recording = false
    if t.playing then paw.transport.stop() end
    return
  end
  local armed = false
  for _, id in ipairs(api.track_list()) do armed = armed or track_flag(id, "armed") end
  if not armed then
    local track = paw.cursor.track()
    if not track then
      return paw.notify("nothing to record on: select a track, or arm one with its R button", "warn")
    end
    track.armed = true
    paw.notify("recording on " .. track.name .. ": it was armed for you (its R button)")
  end
  paw.transport.record()
end

function A.close_roll()
  paw.ui.hide("pianoroll")
  to_arrange()
end

--- Run a command on a clip or a track that was not under the cursor: what
--- a context menu does. The cursor goes there first, as a click would put it.
function A.clip_command(id: integer, beat: number, line: string)
  A.menu_target(id, beat)
  commands.exec(line)
end

--- The cursor goes to the clip a menu was opened on; the chosen clips stay
--- chosen if it is one of them, else it is chosen alone.
function A.menu_target(id: integer, beat?: number)
  local among = false
  for _, other in ipairs(M.chosen_clips()) do among = among or other == id end
  if among then return cursor_into(id, beat) end
  A.select_clip(id, beat)
end

function A.track_command(id: integer, line: string)
  A.select(id)
  commands.exec(line)
end

--- Set a device offline, or back online.
function A.toggle_offline(id: integer)
  paw.loading.toggle(paw.device(id))
end

--- Start a plugin again that has stopped working.
function A.restart_device(id: integer)
  local ok, err = pcall(api.device_restart, id) as (boolean, string)
  if not ok then paw.notify(tostring(err):match("^[^\n]*"), "error") end
end

--- An entry an extension added to a menu (`paw.frontend.menus`), by its
--- place in the list: `target` is the clip or the track that was clicked.
--- The timeline's entries are also offered by the buttons that make a
--- track, which have no place to give: no track, or a beat below 0, leaves
--- the cursor where it is.
function A.menu(kind: string, index: integer, target?: integer, beat?: number)
  local entry = (M.menus[kind] or {})[index]
  if not entry then return end
  if beat and beat < 0 then beat = nil end
  if kind == "clip" then
    A.menu_target(target, beat)
  elseif target and target > 0 then
    A.select(target, beat)
  else
    to_arrange()
  end
  if entry.run then
    entry.run(target, beat)
  elseif entry.command then
    commands.exec(entry.command)
  end
end

--- A click on an entry of an extension's band under the ruler
--- (`paw.frontend.bands`), by the band's place in the list and the entry's
--- in what it returns: its command runs, in the arrange view.
function A.band(band: integer, index: integer)
  if not M.bands[band] then return end
  local entry = band_entries(band)[index]
  if not entry then return end
  to_arrange()
  if entry.run then
    entry.run(entry)
  elseif entry.command then
    commands.exec(entry.command)
  end
end

--- Drag along the ruler: loop that stretch. Too short a drag is a click,
--- which only moves the playhead.
function A.set_loop(from: number, to: number)
  from, to = snap(math.min(from, to)), snap(math.max(from, to))
  if to - from < opt.grid then return api.transport_seek(from) end
  paw.transport.loop_start, paw.transport.loop_end = from, to
  paw.transport.loop_enabled = true
end

--- The pointer on the floating window, drawn as the lines of `M.float`:
--- `kind` is "down" for a click, "scroll_up" or "scroll_down" for the
--- wheel; `line` and `col` count from 1. It goes where a click in the
--- terminal goes: in a picker a click on a row selects it, and a click on
--- the selected row (the second of a double click) chooses it.
function A.float_pointer(kind: string, line: integer, col?: integer)
  local float = paw.ui.float
  if not float then return end
  for _, r in ipairs(paw.ui.rects) do
    if r.name == float.name then
      return paw.ui.mouse({ kind = kind, button = "left", x = r.x + math.max(0, (col or 1) - 1), y = r.y + math.max(0, line - 1) })
    end
  end
end

local splitting = false

--- Split every chosen clip that the edit cursor is inside, there: what
--- `clip.split` (`S`, and the clip menu's "Split at the edit cursor") does
--- while clips are chosen. Both halves are chosen afterwards. Returns false
--- when no clip is chosen, for `clip.split` to split the clip under the
--- cursor instead.
function A.split_clips(): boolean
  local ids = M.chosen_clips()
  if splitting or #ids == 0 then return false end
  local beat, track, visual = paw.cursor.beat, paw.cursor.track_id(), paw.keymap.mode == "x"
  local set: {integer:boolean} = {}
  splitting, pointing = true, true
  local ok, err = pcall(function()
    for _, id in ipairs(ids) do
      set[id] = true
      local c = api.clip_get(id)
      if beat > c.start + 1e-9 and beat < c.start + c.length - 1e-9 then
        paw.cursor.set_track(c.track)
        commands.exec("clip.split")
        local right = paw.track(c.track):clip_at(beat)
        if right then set[right.id] = true end
      end
    end
  end) as (boolean, string)
  if track then paw.cursor.set_track(track) end
  splitting, pointing = false, false
  if not ok then error(err, 0) end
  choose_clips(set, ids[1], visual or #ids > 1)
  return true
end

--- Glue the chosen clips on each track into one clip, the gaps between
--- them included: what the clip menu's "Glue" and `J` on chosen clips do.
--- MIDI clips are joined; audio clips are glued into a new file
--- (`paw.media.glue`). A track whose chosen clips are of both kinds is left
--- as it is.
function A.glue_clips()
  local region = clip_region()
  if not region then return paw.notify("no clips chosen to glue", "warn") end
  local glued = false
  for _, track in ipairs(paw.edit.arrange.tracks(region)) do
    local audio: {integer} = {}
    local midi = 0
    for _, c in ipairs(api.clip_list(track)) do
      if region.clips[c.id] then
        if c.kind == "audio" then audio[#audio + 1] = c.id else midi = midi + 1 end
      end
    end
    local ok, done: boolean, boolean = true, false
    local why: string
    if #audio >= 2 and midi == 0 then
      local fine, result = pcall(paw.media.glue, audio)
      ok = fine
      if fine then
        local made = result as types.ClipGlued
        done = made and made.glued and made.glued > 1
      else
        why = tostring(result)
      end
    elseif midi >= 2 and #audio == 0 then
      local fine, result = pcall(paw.edit.arrange.join, track, region.c0, region.c1, region.clips)
      ok = fine
      if fine then done = result as boolean else why = tostring(result) end
    elseif #audio > 0 and midi > 0 then
      paw.notify("audio and MIDI clips cannot be glued together", "warn")
    end
    if not ok then return paw.notify(why:match("^[^\n]*"), "warn") end
    glued = glued or done
  end
  if not glued then paw.notify("glue takes two or more chosen clips of one kind on a track", "warn") end
  local left: {integer:boolean} = {}
  for _, id in ipairs(M.chosen_clips()) do left[id] = true end
  choose_clips(left, nil, false)
end

--- The clip menu's "Split at the edit cursor" and "Glue", opened on clip
--- `id`: on the chosen clips if it is one of them, else on it alone. The
--- edit cursor stays where it is.
function A.menu_split(id: integer)
  grabbed_clips(id)
  if not A.split_clips() then commands.exec("clip.split") end
end

function A.menu_glue(id: integer)
  grabbed_clips(id)
  A.glue_clips()
end

--- Drag an edge of the loop, "start" or "end", to a beat on the grid; it
--- stays at least a grid step long.
function A.set_loop_edge(edge: string, beat: number)
  local t = paw.transport
  beat = snap(beat)
  if edge == "start" then
    t.loop_start = math.min(beat, t.loop_end - opt.grid)
  else
    t.loop_end = math.max(beat, t.loop_start + opt.grid)
  end
end

--- Drag an edge of the punch range, "start" or "end", to a beat on the
--- grid (anywhere with `free`); it stays at least a grid step long.
function A.set_punch_edge(edge: string, beat: number, free?: boolean)
  local t = paw.transport
  beat = free and math.max(0, beat) or snap(beat)
  local least = free and 1 / 64 or opt.grid
  if edge == "start" then
    t.punch_start = math.min(beat, t.punch_end - least)
  else
    t.punch_end = math.max(beat, t.punch_start + least)
  end
end

--- Punch in and out between two beats, on the grid, and turn punching on.
function A.set_punch(from: number, to: number)
  from, to = snap(math.min(from, to)), snap(math.max(from, to))
  if to - from < opt.grid then return end
  paw.transport.punch_start, paw.transport.punch_end = from, to
  paw.transport.punch_enabled = true
end

--- Show a track's take lanes under its clips, or hide them. Returns
--- whether they show now.
function A.take_lanes(track: integer): boolean
  return paw.takes.toggle_lanes(track)
end

--- A drag across take lane `take` of a track, from beat `from` to `to`:
--- that take plays over the stretch (see `paw.takes.comp`). The ends land
--- on the grid unless `free` (Shift). A stretch shorter than a grid step is
--- a click, which chooses the take for the piece under the pointer. One
--- undo step. Returns how many pieces play the take now.
function A.comp(track: integer, take: integer, from: number, to: number, free?: boolean): integer
  local a, b = math.min(from, to), math.max(from, to)
  if not free then a, b = snap(a), snap(b) end
  a = math.max(0, a)
  if b - a < (free and 1 / 64 or opt.grid) - 1e-9 then
    return A.take_click(track, take, math.min(from, to)) and 1 or 0
  end
  local n = paw.takes.comp(track, take, a, b)
  if n > 0 then paw.cursor.set_track(track) end
  return n
end

--- A click on take lane `take` of a track: the piece under the pointer
--- plays that take. Returns its clip, or nil when there is none there.
function A.take_click(track: integer, take: integer, beat: number): integer
  local c = paw.takes.choose_at(track, take, beat)
  if c then
    pointing = true
    to_arrange()
    paw.cursor.set_track(track)
    pointing = false
  end
  return c and c.id or nil
end

--- A click on the ruler: the edit cursor goes to the beat, on the grid,
--- and the playhead with it.
function A.ruler_click(beat: number)
  beat = snap(beat)
  pointing = true
  paw.cursor.set_beat(beat)
  pointing = false
  api.transport_seek(beat)
end

--- Drag across empty lanes: select that stretch of time on those tracks,
--- as visual mode does, for the keys and the menu to act on. Rows are
--- places in the track list, from 1.
function A.select_range(row0: integer, beat0: number, row1: integer, beat1: number)
  local tracks = paw.groups.rows()
  if #tracks == 0 then return end
  to_arrange()
  local clamp = util.clamp
  paw.cursor.set_track(tracks[clamp(row0, 1, #tracks) as integer])
  paw.cursor.set_beat(snap(math.min(beat0, beat1)))
  paw.keymap.visual_start("v")
  paw.cursor.set_track(tracks[clamp(row1, 1, #tracks) as integer])
  paw.cursor.set_beat(snap(math.max(beat0, beat1)))
end

--- The payload of `ui.focus`.
local record Focus
  focused: boolean
end
local ui_focus: events.Event<Focus> = events.event("ui.focus")

--- Type keys as if at the keyboard: what a menu entry for an operator does
--- to a selection.
--- The window got the focus of the desktop (true), or lost it.
function A.focus(on: boolean)
  paw.ui.has_focus = on
  events.emit(ui_focus, { focused = on })
end

function A.keys(keys: string)
  -- Keys typed in the main window are not for a view in a window of its
  -- own, which sends its own (`paw.canvas.key`): they go to the window
  -- that had the keyboard before.
  if paw.canvas.open_views[paw.ui.focused] and not paw.ui.float and not paw.ui.grabber then
    paw.canvas.back(paw.ui.focused)
  end
  paw.keymap.feed(keys)
end

function A.set_volume(track: integer, db: number) api.track_set(track, { volume = util.fader_db(track_number(track, "volume"), db) }) end

--- A fader, a pan or a parameter is under the pointer (`on`), or let go:
--- in touch mode it writes automation for as long as it is held. `device`
--- and `param` name a parameter; 0 and "" for a fader or a pan.
function A.hold(track: integer, target: string, device: integer, param: string, on: boolean)
  if target ~= "param" then device, param = nil, nil end
  api.automation_hold(track, target, device, param, on)
end

--- Where a file was chosen is where the next choice starts.
local function remember_dir(path: string)
  paw.state.pick_dir = path:match("^(.*)/[^/]*$") or paw.state.pick_dir
end

--- Leave the project: `what` is "quit", "new" (an empty project),
--- "open" (another, chosen from a list) or "open:<path>" (that one, already
--- chosen: from the recent list, by the desktop's dialog, or dropped on the
--- window). `how` is "save" to save its
--- changes first (asking where, for a project with no file yet),
--- "discard" to throw them away, or "go" when there are none.
function A.leave(how: string, what: string)
  local function go()
    if what == "quit" then
      if how == "discard" then paw.autosave.discard = true end
      api.quit(0)
    elseif what == "new" then
      paw.project.new()
    elseif what:match("^open:") then
      remember_dir(what:sub(6))
      paw.recent.open(what:sub(6))
    else
      commands.exec("open")
    end
  end
  if how ~= "save" then return go() end
  if project_text("path") then
    paw.project.write()
    return go()
  end
  M.save_as(go)
end

--- A file chosen in the desktop's dialog, for what `kind` says: "import"
--- (a sound file on a new track, a MIDI file's tracks at the cursor) or
--- "saveas" (the project's new file).
function A.chosen(kind: string, path: string)
  remember_dir(path)
  if kind == "saveas" then
    local saved, note = paw.project.write(path)
    paw.notify(note and (note .. ": " .. saved) or ("saved " .. saved))
  else
    commands.run("import", { path })
  end
end

--- Files dropped on the window: sound files, MIDI files and projects. A
--- project (the first of them, when there are several) is not opened here,
--- for the window asks about unsaved changes first: its path is returned as
--- `open`. A MIDI file's tracks come in below the cursor's at `beat`, or
--- the edit cursor. Sound files go on the track at `row` (a place in the list of
--- drawn tracks, from 1) at `beat`, snapped, one after another; with no
--- track there (below the last, or where the window cannot tell) each gets
--- a track of its own, at `beat` or the edit cursor. Anything else is said
--- to be refused. Returns `{ open, clips, refused }`.
function A.drop(paths: {string}, row?: integer, beat?: number): Dropped
  local out: Dropped = { clips = {}, refused = 0 }
  local sounds, midis: {string}, {string} = {}, {}
  for _, path in ipairs(paths) do
    if paw.is_audio_file(path) then
      sounds[#sounds + 1] = path
    elseif paw.midifile.is_midi_file(path) then
      midis[#midis + 1] = path
    elseif path:lower():match("%.json$") or paw.project.is_folder(path) then
      out.open = out.open or path
    else
      out.refused = out.refused + 1
      paw.notify("cannot take " .. (path:match("([^/]+)$") or path) .. ": it is not a sound file, a MIDI file or a project", "warn")
    end
  end
  if out.open then return out end
  local rows = paw.groups.rows()
  local track = row and rows[row]
  local start = beat and snap(beat)
  for _, path in ipairs(midis) do
    local ok, got = pcall(paw.midifile.import, path, { start = start })
    if ok then
      local done = got as MidifileModule.Imported
      for _, clip in ipairs(done.clips) do out.clips[#out.clips + 1] = (clip as objects.Clip).id end
      paw.notify(string.format("dropped %s: %d notes on %d tracks", path:match("([^/]+)$") or path, done.notes, #done.tracks))
    else
      out.refused = out.refused + 1
      paw.notify("could not import " .. path .. ": " .. tostring(got), "error")
    end
  end
  for _, path in ipairs(sounds) do
    local ok, got = pcall(paw.import_audio, path, { track = track, start = start })
    if ok then
      local clip = got as objects.Clip
      out.clips[#out.clips + 1] = clip.id
      if track then start = clip.start + clip.length end
      paw.notify(string.format("dropped %s: %.1f beats on track “%s”", path:match("([^/]+)$") or path, clip.length, clip:track().name))
    else
      out.refused = out.refused + 1
      paw.notify("could not import " .. path .. ": " .. tostring(got), "error")
    end
  end
  return out
end

--- The lanes of a lane's track are no longer shown as rows.
function A.hide_lane_rows(lane: integer)
  paw.lanes.open(api.lane_get(lane).track, false)
end

--- Show a track's lanes as rows of their own under it, or hide them. A
--- track that has none yet gets one for its fader, to draw on.
function A.lane_rows(track: integer): boolean
  if not paw.lanes.is_open(track) and #api.lane_list(track) == 0 then A.lane(track, "volume") end
  return paw.lanes.toggle(track)
end

local lossy_formats: {string:string} = { flac = "flac", mp3 = "mp3", ogg = "ogg", opus = "opus" }

--- Render as the window's dialog says: `o.path`, `o.range` (a name from
--- `render_dialog`), `o.format` ("wav", "flac", "mp3", "ogg" or "opus"), `o.quality` (for those
--- three: "low" to "best"), `o.bits`, `o.tail`
--- seconds, `o.normalize` dB or nil, `o.dither`, `o.mono`, and `o.stems`
--- for a file per track in a directory named after the path. `o.tags`
--- (`title`, `artist`, ... as `paw.render.tags` has them, an empty one
--- taking it out) becomes the project's tags, which the files carry. It
--- runs in the background: the state's `modal.render` says how far it is.
function A.render(o: RenderRequest)
  local render = render_module()
  if o.tags then render.tags(o.tags) end
  local opts: RenderModule.Options = {
    tail = tonumber(o.tail), bits = tonumber(o.bits) as integer, dither = o.dither and true or nil,
    normalize = tonumber(o.normalize), channels = o.mono and 1 or nil, background = true,
  }
  local format = lossy_formats[o.format] or "wav"
  if format == "flac" and opts.bits == 32 then opts.bits = 24 end
  if format ~= "wav" and format ~= "flac" then opts.bits, opts.dither, opts.quality = nil, nil, o.quality end
  local range = o.range or "song"
  local region = range:match("^region:(%d+)$")
  if region then
    local r = paw.markers.find({ id = tonumber(region) as integer })
    if not r then error("that region is gone", 0) end
    opts.start, opts["end"] = r.beat, r.beat + r.length
  elseif range ~= "song" then
    opts.range = range
  end
  local path = util.expand_path(tostring(o.path or ""))
  if path == "" then error("render: name a file to write", 0) end
  local stem = path:gsub("%.[Ww][Aa][Vv]$", ""):gsub("%.[Ff][Ll][Aa][Cc]$", ""):gsub("%.[Mm][Pp]3$", "")
    :gsub("%.[Oo][Gg][Gg]$", ""):gsub("%.[Oo][Pp][Uu][Ss]$", "")
  if o.stems then
    opts.format = format
    local files = render.stems(stem .. " stems", opts)
    return paw.notify(string.format("rendering %d stem%s into %s", #files, #files == 1 and "" or "s", stem .. " stems"))
  end
  render.render(stem .. "." .. format, opts)
  paw.notify("rendering " .. (stem:match("([^/]+)$") or stem) .. "." .. format .. " · Esc cancels")
end

-- Where a track's sound goes.

--- Where a track's sound goes, for a frontend to show and change:
---   output   the name of the track it plays into ("Master" without one)
---   targets  the tracks it could play into or send to, `{ id, name }` each;
---            the master is first, with id 0
---   sends    `{ target, name, level, pre }` each, levels in dB
--- A track cannot play into itself or into a track that plays into it.
function M.routing(track: integer): Routing
  local t = api.track_get(track)
  local targets: {Target} = { { id = 0, name = "Master" } }
  -- Not a track whose sound reaches this one, by any route.
  local reaching = paw.routes.reaching(track)
  for _, id in ipairs(api.track_list()) do
    if id ~= track and not reaching[id] then targets[#targets + 1] = { id = id, name = track_text(id, "name") } end
  end
  local sends: {SendState} = {}
  for i, send in ipairs(t.sends or {}) do
    local ok, to = pcall(api.track_get, send.target)
    sends[i] = { target = send.target, name = ok and (to as types.Track).name or "?", level = send.level, pre = send.pre or false }
  end
  local ok, to = pcall(api.track_get, t.output or 0)
  return { output = t.output and ok and (to as types.Track).name or "Master", output_id = t.output or 0, targets = targets, sends = sends, master = t.master or false }
end

--- Play a track into another (`target` 0 or nil for the master).
function A.set_output(track: integer, target?: integer)
  if target and target ~= 0 then
    api.track_set(track, { output = target })
  else
    api.track_set(track, "output", nil)
  end
end

--- Send a track's sound to another as well, at `level` dB (`paw.opt.send_level` without).
function A.add_send(track: integer, target: integer, level?: number)
  local sends = api.track_get(track).sends
  for _, send in ipairs(sends) do
    if send.target == target then return end
  end
  sends[#sends + 1] = { target = target, level = level or opt.send_level }
  api.track_set(track, { sends = sends })
end

--- Change the send at `index` (from 1): `level` in dB, `pre` whether it is
--- taken ahead of the fader; nil leaves either as it is.
function A.set_send(track: integer, index: integer, level?: number, pre?: boolean)
  local sends = api.track_get(track).sends
  if not sends[index] then return end
  if level ~= nil then sends[index].level = util.fader_db(sends[index].level, level) end
  if pre ~= nil then sends[index].pre = pre and true or nil end
  api.track_set(track, { sends = sends })
end

function A.remove_send(track: integer, index: integer)
  local sends = api.track_get(track).sends
  if not sends[index] then return end
  table.remove(sends, index)
  api.track_set(track, { sends = sends })
end

--- The menu of the side-chain of a device: "None" first, then the tracks
--- that it can listen to. The last item tells if it takes the sound before
--- their fader. Each is `{ label, checked }`.
--- `act.choose_sidechain` takes one by place.
function M.sidechain_menu(device: integer): {Check}
  local d = api.device_get(device)
  local out: {Check} = { { label = "None: its own input", checked = d.sidechain == nil } }
  for _, source in ipairs(paw.routes.sidechain_sources(device)) do
    out[#out + 1] = { label = source.name, checked = source.id == d.sidechain }
  end
  out[#out + 1] = { label = "Before the fader", checked = d.sidechain_pre or false }
  return out
end

--- The menu of the other output pairs of a device. For each pair, it gives
--- `{ label, choices }`. The label names the pair and where it plays. The
--- choices (`{ label, checked }`) are "Nowhere" and the tracks that it can
--- play into. `act.route_pair` takes one. `act.spread_outputs` makes a
--- track for each pair that plays nowhere.
function M.outputs_menu(device: integer): {PairMenu}
  local out: {PairMenu} = {}
  local d = api.device_get(device)
  local reaching = paw.routes.reaching(d.track)
  for _, o in ipairs(paw.routes.outputs(device)) do
    if o.pair > 1 then
      local choices: {Check} = { { label = "Nowhere: not heard", checked = o.target == nil } }
      for _, id in ipairs(api.track_list()) do
        if id ~= d.track and not reaching[id] then
          choices[#choices + 1] = { label = track_text(id, "name"), checked = id == o.target }
        end
      end
      out[#out + 1] = { label = string.format("%d %s → %s", o.pair, o.name, o.target_name or "not heard"), choices = choices }
    end
  end
  return out
end

--- Route a device's output pair `pair` (from 2) to the `index`th choice of
--- its menu (`M.outputs_menu`): 1 for nowhere, then the tracks it lists.
function A.route_pair(device: integer, pair: integer, index: integer)
  if index == 1 then return paw.routes.set_output(device, pair, nil) end
  local d = api.device_get(device)
  local reaching = paw.routes.reaching(d.track)
  local n = 1
  for _, id in ipairs(api.track_list()) do
    if id ~= d.track and not reaching[id] then
      n = n + 1
      if n == index then return paw.routes.set_output(device, pair, id) end
    end
  end
end

function A.spread_outputs(device: integer) paw.routes.spread(device) end

--- Choose from a device's side-chain menu (`M.sidechain_menu`), by place
--- from 1: none, a track, or the last entry, which turns taking it before
--- the fader on or off.
function A.choose_sidechain(device: integer, index: integer)
  local d = api.device_get(device)
  local sources = paw.routes.sidechain_sources(device)
  if index == 1 then
    paw.routes.set_sidechain(device, nil)
  elseif sources[index - 1] then
    paw.routes.set_sidechain(device, sources[index - 1].id, d.sidechain_pre)
  elseif index == #sources + 2 and d.sidechain then
    api.device_set(device, { sidechain_pre = not d.sidechain_pre })
  end
end

function A.set_pan(track: integer, pan: number) api.track_set(track, { pan = util.clamp(pan, -1, 1) }) end

function A.toggle(track: integer, flag: string)
  local patch: {string:boolean} = { [flag] = not track_flag(track, flag) }
  api.track_set(track, patch as types.Track)
end

local function nth(list: {Choice}, group: string, index: integer): Choice
  local n = 0
  for _, choice in ipairs(list) do
    if choice.group == group then
      n = n + 1
      if n == index then return choice end
    end
  end
end

--- Choose a track's input from its menu (`M.input_menu`): the `index`th
--- entry, from 1, under the heading `group`.
function A.choose_input(track: integer, group: string, index: integer)
  local choice = nth(paw.audio.choices(track), group, index)
  if not choice then return end
  paw.audio.choose(track, choice)
  A.select(track)
end

--- Choose an audio device or a block size from `M.engine_menu`.
function A.choose_engine(group: string, index: integer)
  local choice = nth(paw.audio.engine_choices(), group, index)
  if choice then paw.audio.choose_engine(choice) end
end

--- A click on a device of a track's chain, as a mixer strip lists them: the
--- track becomes the cursor's and the device panel gets the keyboard, on
--- the `index`th device, from 1.
function A.pick_device(track: integer, index: integer)
  A.select(track)
  local panel = paw.ui.views.devices
  for row, entry in ipairs(panel:rows()) do
    if not entry.param and entry.device.index == index then panel.row = row end
  end
  paw.ui.focus("devices")
end

function A.rename_track(track: integer, name: string)
  name = name:match("^%s*(.-)%s*$")
  if name ~= "" then api.track_set(track, { name = name }) end
end

--- Give a track one of the theme's colours by name, any `#rrggbb`, or "none".
function A.color_track(track: integer, colour: string)
  A.track_command(track, "track.color " .. colour)
end

--- Drag a track's header to another place among the drawn rows, from 1.
--- It goes into the group of the track drawn above it where it lands (or
--- into that track, if it is an open group), and out of its own group if it
--- lands outside it. A group takes its tracks along.
function A.move_track(track: integer, index: integer)
  local groups = paw.groups
  -- The row is among the tracks that are drawn; the list may hold more.
  local rows = groups.rows()
  local target = rows[util.clamp(index, 1, #rows) as integer]
  for place, id in ipairs(api.track_list()) do
    if id == target then api.track_move(track, place) end
  end
  local above: integer
  rows = groups.rows()
  for i, id in ipairs(rows) do
    if id == track then above = rows[i - 1] end
  end
  local want: integer
  if above then
    want = groups.is_group(above) and not groups.folded(above) and above or groups.of(above)
  end
  if want ~= groups.of(track) then
    if want then
      -- A group cannot go inside itself; then it stays in its own group.
      pcall(groups.add, track, want)
    else
      while groups.of(track) do groups.remove(track, true) end
    end
  end
  if groups.is_group(track) then groups.gather(track) end
  local group = groups.of(track)
  if group then groups.gather(group) end
end

--- Drag a track's bottom edge: its height, as a share of the zoom's height
--- that every track has (`1` for that height, which is then not kept).
function A.set_track_height(track: integer, share: number)
  api.track_set(track, { height = share })
end

--- A press on one of a track's M, S or R buttons swept down across others:
--- each it crosses is set as the first was (`flag` is "mute", "solo" or
--- "armed").
function A.set_flag(track: integer, flag: string, on: boolean)
  if flag ~= "mute" and flag ~= "solo" and flag ~= "armed" then
    error("not a flag of a track: " .. tostring(flag), 2)
  end
  local patch: {string:boolean} = { [flag] = on and true or false }
  api.track_set(track, patch as types.Track)
end

--- The same, for the drawn tracks from row `row0` to `row1` (from 1, either
--- way round): where a sweep has gone so far.
function A.sweep_flag(row0: integer, row1: integer, flag: string, on: boolean)
  local rows = paw.groups.rows()
  for row = math.max(1, math.min(row0, row1)), math.min(#rows, math.max(row0, row1)) do
    A.set_flag(rows[row], flag, on)
  end
end

--- Fold a group away or open it: a click on its triangle.
function A.fold(track: integer)
  paw.groups.fold(track)
end

-- Notes, in the clips the piano roll has open. A gesture names a note by
-- its clip and its place there; where the roll edits several clips (see
-- `paw.roll_clips`), the chosen notes may be in any of them and a gesture
-- on one acts on all of them, each note staying in its own clip. Beats a
-- gesture gives are the roll's: from the start of the clip it names.

--- The notes chosen in a clip: their places, and the clip's stamp then.
local record Chosen
  places: {integer:boolean}
  stamp: integer
end

-- The notes chosen with the pointer: places in each clip, by clip id. They
-- are kept as long as the clip's notes are what the pointer's own edits
-- left; an edit made any other way (a key, an undo) forgets them, since
-- places move. Each window and terminal chooses notes of its own.
local chosen: {integer:Chosen} = {}
seats.keep("frontend.chosen", function(): {integer:Chosen} return chosen end, function(c: {integer:Chosen}) chosen = c end,
  function(): {integer:Chosen} return {} end)

local function stamp_of(clip: integer): integer
  local ok, data = pcall(api.clip_get, clip)
  return ok and (data as types.Clip).stamp or nil
end

--- Choose notes of `clip` by their places (`{ [place] = true }`), as the
--- pointer would: what `:select` does.
function M.choose_notes(clip: integer, places: {integer:boolean})
  chosen[clip] = next(places) and { places = places, stamp = stamp_of(clip) } or nil
  api.ui_redraw()
end

--- The places of the selected notes of `clip`, in order. None if the notes
--- of the clip changed after the selection.
function M.chosen_notes(clip: integer): {integer}
  local entry = chosen[clip]
  if not entry or entry.stamp ~= stamp_of(clip) then return {} end
  local out: {integer} = {}
  for place in pairs(entry.places) do out[#out + 1] = place end
  table.sort(out)
  return out
end

--- The clips a gesture on `clip` reaches, with how far each starts after
--- it (`offset`): every clip the roll edits when it is one of them, else
--- that clip alone.
local function parts_for(clip: integer): {Part}
  local rc = paw.roll_clips
  if rc.editable(clip) then
    local parts = rc.parts()
    -- Offsets count from the clip named, which is the active one when the
    -- gesture gives beats.
    local base = rc.offset(clip)
    for _, part in ipairs(parts) do part.offset = part.offset - base end
    return parts
  end
  local c = api.clip_get(clip)
  return { { id = clip, clip = paw.clip(clip), offset = 0, start = c.start, length = c.length } }
end

--- The chosen notes of the clips a gesture on `clip` reaches: clip id ->
--- places, and how many there are.
local function chosen_map(clip: integer): {integer:{integer}}, integer
  local map: {integer:{integer}} = {}
  local count = 0
  for _, part in ipairs(parts_for(clip)) do
    local places = M.chosen_notes(part.id)
    if #places > 0 then map[part.id], count = places, count + #places end
  end
  return map, count
end

--- Every chosen note of the clips the roll edits, as `{ clip, place }`.
function M.chosen_refs(): {{integer}}
  local out: {{integer}} = {}
  local active = paw.roll_clips.active()
  if not active then return out end
  for _, part in ipairs(parts_for(active)) do
    for _, place in ipairs(M.chosen_notes(part.id)) do out[#out + 1] = { part.id, place } end
  end
  return out
end

--- The chosen notes of `clip` (and of the clips edited with it) in words,
--- for a toolbar: `3 notes · 5.1.00 – 5.3.00`, or "" with none chosen.
function M.chosen_text(clip: integer): string
  local map, count = chosen_map(clip)
  if count == 0 then return "" end
  local first, last, clips = math.huge, -math.huge, 0
  for id, places in pairs(map) do
    local c = api.clip_get(id)
    local notes = api.clip_notes(id)
    clips = clips + 1
    for _, place in ipairs(places) do
      local n = notes[place]
      if n then first, last = math.min(first, c.start + n.start), math.max(last, c.start + n.start + n.length) end
    end
  end
  if first == math.huge then return "" end
  return string.format("%d note%s%s · %s – %s", count, count == 1 and "" or "s",
    clips > 1 and " in " .. clips .. " clips" or "", paw.time.format(first), paw.time.format(last))
end

--- Choose notes: `map` is clip id -> places, and replaces every choice.
local function choose_all(map: {integer:{integer}})
  chosen = {}
  for clip, places in pairs(map) do
    local set: {integer:boolean} = {}
    for _, place in ipairs(places) do set[place] = true end
    if next(set) then chosen[clip] = { places = set, stamp = stamp_of(clip) } end
  end
  api.ui_redraw()
end

local function choose(clip: integer, places: {integer})
  choose_all({ [clip] = places })
end

--- Where a note is wanted: its start and pitch.
local record Wanted
  start: number
  pitch: integer
end

--- Where notes are now, given what they are: `wanted` is a list of
--- `{ start, pitch }`.
local function places_of(clip: integer, wanted: {Wanted}): {integer}
  local notes = paw.clip(clip):notes()
  local out: {integer} = {}
  local used: {integer:boolean} = {}
  for _, want in ipairs(wanted) do
    for place, n in ipairs(notes) do
      if not used[place] and n.pitch == want.pitch and math.abs(n.start - want.start) < 1e-6 then
        out[#out + 1], used[place] = place, true
        break
      end
    end
  end
  return out
end

-- A gesture's beat on the grid, unless it is `free` (Shift held) or snap
-- is off in the piano roll (`paw.opt.note_snap`): then to the nearest of
-- 960 ticks a beat, as MIDI files count them.
local function snap_note(beat: number, free: boolean): number
  if free or not opt.note_snap then return math.max(0, math.floor(beat * 960 + 0.5) / 960) end
  return note_snap(beat)
end

--- A press and drag on the empty grid: a note from `start` for `length`,
--- which is then the one chosen note. `free` leaves it off the grid. A
--- click gives no length (nil, or 0 or less): the note is the piano roll's
--- note length (`set_note_length`); a drawn length becomes that length. A
--- click on a note shown behind the roll's own (another track's) makes its
--- clip the one the roll edits instead. With several clips edited the note
--- goes into the one at `start`, the active one first.
function A.add_note(clip: integer, pitch: integer, start: number, length?: number, free?: boolean): integer
  local rc = paw.roll_clips
  if (not length or length <= 0) and clip == rc.active() then
    local behind = rc.context_at(pitch, start)
    if behind then
      rc.activate(behind.clip)
      return nil
    end
  end
  local part = parts_for(clip)[1]
  if rc.editable(clip) then
    part = rc.target(start + rc.offset(clip))
    start = start + rc.offset(clip) - part.offset
  end
  local c = part.clip
  free = free or not opt.note_snap
  start = snap_note(start, free)
  if start >= c.length or c:note_at(pitch, start) then return end
  local roll = paw.ui.views.pianoroll
  if not length or length <= 0 then
    length = roll:step_length()
  else
    length = math.max(free and 1 / 64 or opt.note_grid, snap_note(length, free))
    roll:set_step(length)
  end
  local index = c:add_note(roll.new_note(c, { pitch = pitch, start = start, length = math.min(length, c.length - start), velocity = opt.velocity }))
  c:track():play_note(pitch, opt.velocity, 150)
  choose(part.id, { index })
  return index
end

--- Ctrl and a click on a note shown behind the roll's own: its clip is
--- edited too, or no longer. `beat` is the roll's.
function A.context_click(clip: integer, beat: number, pitch: number)
  local behind = paw.roll_clips.context_at(math.floor(pitch + 0.5), beat + paw.roll_clips.offset(clip))
  if behind then paw.roll_clips.toggle(behind.clip) end
end

--- The clips list of the roll's side panel: make one active, edit it too
--- (or no longer), show a track's notes behind the roll's or not.
function A.roll_activate(_: integer, id: number) paw.roll_clips.activate(math.floor(id)) end
function A.roll_toggle_clip(_: integer, id: number) paw.roll_clips.toggle(math.floor(id)) end
function A.roll_show_track(_: integer, id: number)
  local track = math.floor(id)
  for _, t in ipairs(paw.roll_clips.tracks()) do
    if t.id == track then return paw.roll_clips.show_track(track, not t.on) end
  end
end

--- Choose notes with a click: `mode` is "only" (the note alone), "add" or
--- "toggle" (Shift or Ctrl held).
function A.select_note(clip: integer, index: integer, mode?: string)
  if mode == "only" or mode == nil then return choose(clip, { index }) end
  local map = chosen_map(clip)
  local set: {integer:boolean} = {}
  for _, place in ipairs(map[clip] or {}) do set[place] = true end
  if mode == "toggle" and set[index] then set[index] = nil else set[index] = true end
  local out: {integer} = {}
  for place in pairs(set) do out[#out + 1] = place end
  map[clip] = out
  choose_all(map)
end

--- Choose the notes a box touches: from `beat0, pitch0` to `beat1, pitch1`,
--- in any order, in every clip the roll edits. `mode` as for `select_note`.
function A.select_notes_box(clip: integer, beat0: number, pitch0: number, beat1: number, pitch1: number, mode?: string): integer
  if beat0 > beat1 then beat0, beat1 = beat1, beat0 end
  if pitch0 > pitch1 then pitch0, pitch1 = pitch1, pitch0 end
  local map: {integer:{integer}} = (mode == "add" or mode == "toggle") and chosen_map(clip) or {}
  local count = 0
  for _, part in ipairs(parts_for(clip)) do
    local set: {integer:boolean} = {}
    for _, place in ipairs(map[part.id] or {}) do set[place] = true end
    local notes = part.clip:notes()
    for place, n in ipairs(notes) do
      local start = n.start + part.offset
      if n.start >= 0 and n.pitch >= pitch0 and n.pitch <= pitch1 and start < beat1 and start + n.length > beat0 then
        if mode == "toggle" and set[place] then set[place] = nil else set[place] = true end
      end
    end
    local out: {integer} = {}
    for place in pairs(set) do out[#out + 1] = place end
    map[part.id], count = out, count + #out
  end
  choose_all(map)
  return count
end

function A.select_all_notes(clip: integer)
  local map: {integer:{integer}} = {}
  for _, part in ipairs(parts_for(clip)) do
    local out: {integer} = {}
    local notes = part.clip:notes()
    for place, n in ipairs(notes) do
      -- Not those hidden by a trim of the clip's edges.
      if n.start >= 0 and n.start < part.length then out[#out + 1] = place end
    end
    map[part.id] = out
  end
  choose_all(map)
end

function A.clear_note_selection()
  if next(chosen) then choose_all({}) end
end

--- The notes a gesture on the note at `index` acts on: all the chosen ones
--- if it is one of them, else that note alone, which is then the chosen
--- one. Clip id -> places.
local function grabbed(clip: integer, index: integer): {integer:{integer}}
  local map = chosen_map(clip)
  for _, place in ipairs(map[clip] or {}) do
    if place == index then return map end
  end
  choose(clip, { index })
  return { [clip] = { index } }
end

--- The parts a map of chosen notes is in, each with its notes and places.
local function grabbed_parts(clip: integer, map: {integer:{integer}}): {Part}
  local out: {Part} = {}
  for _, part in ipairs(parts_for(clip)) do
    if map[part.id] then
      part.notes, part.places = part.clip:notes(), map[part.id]
      out[#out + 1] = part
    end
  end
  return out
end

--- A note with its fields laid over: a copy.
local function note_with(n: types.Note, start: number, pitch: integer): objects.NoteInput
  local out: objects.NoteInput = {}
  for k, v in pairs(n as {string:Value}) do (out as {string:Value})[k] = v end
  out.start, out.pitch = start, pitch
  return out
end

--- Drag notes: the one at `index` and, if it is chosen, the others chosen
--- with it, by `dbeat` and `dpitch`. The grabbed note lands on the grid
--- unless `free`; the rest keep their distance from it. With `copy` the
--- notes stay and copies are dropped. Each note stays in its own clip.
function A.drag_notes(clip: integer, index: integer, dbeat: number, dpitch?: number, copy?: boolean, free?: boolean)
  local held = paw.clip(clip):notes()[index]
  if not held then return end
  local parts = grabbed_parts(clip, grabbed(clip, index))
  local by = snap_note(held.start + dbeat, free) - held.start
  local up = math.floor((dpitch or 0) + 0.5)
  -- Nothing leaves its clip or the keyboard.
  for _, part in ipairs(parts) do
    for _, place in ipairs(part.places) do
      local n = part.notes[place]
      by = math.max(by, -n.start)
      by = math.min(by, part.length - n.start - math.min(n.length, opt.note_grid))
      up = util.clamp(up, -n.pitch, 127 - n.pitch) as integer
    end
  end
  if math.abs(by) < 1e-9 and up == 0 and not copy then return end
  local after: {integer:{Wanted}} = {}
  for _, part in ipairs(parts) do
    local wanted: {Wanted} = {}
    local set: {objects.NoteChangeInput} = {}
    local add: {objects.NoteInput} = {}
    for _, place in ipairs(part.places) do
      local n = part.notes[place]
      local moved: Wanted = { start = n.start + by, pitch = n.pitch + up }
      wanted[#wanted + 1] = moved
      if copy then
        add[#add + 1] = note_with(n, moved.start, moved.pitch)
      else
        set[#set + 1] = { index = place, start = moved.start, pitch = moved.pitch }
      end
    end
    part.clip:edit_notes({ set = set, add = add })
    after[part.id] = wanted
  end
  if up ~= 0 then paw.clip(clip):track():play_note(held.pitch + up, held.velocity, 120) end
  local map: {integer:{integer}} = {}
  for id, wanted in pairs(after) do map[id] = places_of(id, wanted) end
  choose_all(map)
end

--- Drag an end of the note at `index`, and the same end of the notes chosen
--- with it: `dstart` moves their starts (the ends stay), `dlength` their ends.
function A.stretch_notes(clip: integer, index: integer, dstart?: number, dlength?: number, free?: boolean): boolean
  local held = paw.clip(clip):notes()[index]
  if not held then return end
  local parts = grabbed_parts(clip, grabbed(clip, index))
  local least = (free or not opt.note_snap) and 1 / 64 or opt.note_grid
  -- The grabbed note's end lands on the grid; the others change by as much.
  if dstart and dstart ~= 0 then
    dstart = snap_note(held.start + dstart, free) - held.start
  else
    dstart = 0
  end
  if dlength and dlength ~= 0 then
    dlength = snap_note(held.start + held.length + dlength, free) - (held.start + held.length)
  else
    dlength = 0
  end
  local map: {integer:{integer}} = {}
  for _, part in ipairs(parts) do
    local wanted: {Wanted} = {}
    local set: {objects.NoteChangeInput} = {}
    for _, place in ipairs(part.places) do
      local n = part.notes[place]
      local stop = n.start + n.length
      local start = util.clamp(n.start + dstart, 0, stop - least)
      local length = math.max(least, math.min(stop + dlength, part.length) - start)
      wanted[#wanted + 1] = { start = start, pitch = n.pitch }
      set[#set + 1] = { index = place, start = start, length = length }
    end
    part.clip:edit_notes({ set = set })
    map[part.id] = places_of(part.id, wanted)
  end
  choose_all(map)
  return dlength ~= 0 or dstart ~= 0
end

--- Take a note away, and with it the others if it is one of the chosen.
function A.remove_note(clip: integer, index: integer)
  for _, part in ipairs(grabbed_parts(clip, grabbed(clip, index))) do
    part.clip:edit_notes({ remove = part.places })
  end
  choose_all({})
end

--- Take the chosen notes away: what Delete does in the piano roll.
function A.remove_chosen_notes(clip: integer): boolean
  local map, count = chosen_map(clip)
  if count == 0 then return false end
  for _, part in ipairs(grabbed_parts(clip, map)) do
    part.clip:edit_notes({ remove = part.places })
  end
  choose_all({})
  return true
end

-- One note at a time, as scripts and older frontends ask for it.
function A.move_note(clip: integer, index: integer, start: number, pitch: integer): integer
  pitch = util.clamp(pitch, 0, 127) as integer
  local c = paw.clip(clip)
  local before = c:notes()[index]
  local at = c:set_note(index, { start = note_snap(start), pitch = pitch })
  if before and before.pitch ~= pitch then c:track():play_note(pitch, before.velocity, 120) end
  return at
end

function A.resize_note(clip: integer, index: integer, length: number)
  paw.clip(clip):set_note(index, { length = math.max(opt.note_grid, note_snap(length)) })
end

--- How hard a note is played; with the note among the chosen, all of them.
function A.set_velocity(clip: integer, index: integer, velocity: number): integer
  local v = util.clamp(math.floor(velocity + 0.5), 1, 127) as integer
  local map = chosen_map(clip)
  local among = false
  for _, place in ipairs(map[clip] or {}) do among = among or place == index end
  if not among then return paw.clip(clip):set_note(index, { velocity = v }) end
  for _, part in ipairs(grabbed_parts(clip, map)) do
    local set: {objects.NoteChangeInput} = {}
    for i, place in ipairs(part.places) do set[i] = { index = place, velocity = v } end
    part.clip:edit_notes({ set = set })
  end
  choose_all(map)
end

--- Hear a pitch on the track of the clip that is open: a click on the keyboard.
function A.audition(clip: integer, pitch: integer)
  paw.clip(clip):track():play_note(util.clamp(pitch, 0, 127) as integer, opt.velocity, 250)
end

--- A note as `erase_notes` crosses it: where it shows in the roll.
local record Seen
  start: number
  length: number
  pitch: integer
  hidden: boolean
end

--- A drag with Alt held: take away every note the pointer crossed. `points`
--- are `{ beat, pitch }` as the pointer went; between two of them the path
--- is a straight line, so a quick stroke misses nothing it passed over.
function A.erase_notes(clip: integer, points: {Point}): integer
  local function crosses(n: Seen, b0: number, p0: number, b1: number, p1: number): boolean
    -- Walk the segment in steps finer than a note's height and a 64th.
    local steps = math.max(1, math.ceil(math.max(math.abs(p1 - p0) * 4, math.abs(b1 - b0) * 64)))
    for s = 0, steps do
      local t = s / steps
      local beat, pitch = b0 + (b1 - b0) * t, p0 + (p1 - p0) * t
      if not n.hidden and math.floor(pitch + 0.5) == n.pitch and beat >= n.start and beat < n.start + n.length then return true end
    end
    return false
  end
  local count = 0
  for _, part in ipairs(parts_for(clip)) do
    local hit: {integer} = {}
    local notes = part.clip:notes()
    for place, n in ipairs(notes) do
      -- Notes hidden by a trim of the clip's start are not there to cross.
      local seen: Seen = { start = n.start + part.offset, length = n.length, pitch = n.pitch, hidden = n.start < 0 }
      for i = 1, #points do
        local a, b = points[i], points[math.min(i + 1, #points)]
        if crosses(seen, a[1], a[2], b[1], b[2]) then
          hit[#hit + 1] = place
          break
        end
      end
    end
    if #hit > 0 then part.clip:edit_notes({ remove = hit }) end
    count = count + #hit
  end
  if count > 0 then choose_all({}) end
  return count
end

--- A drag with the right button down the keyboard: choose every note from
--- `low` to `high` (either way round). `mode` as for `select_note`.
function A.select_pitches(clip: integer, low: number, high: number, mode?: string): integer
  local from, to: number, number = 0, paw.clip(clip).length
  for _, part in ipairs(parts_for(clip)) do
    from, to = math.min(from, part.offset), math.max(to, part.offset + part.length)
  end
  return A.select_notes_box(clip, from - 1, low, to + 1, high, mode)
end

local function by_beat(a: Point, b: Point): boolean return a[1] < b[1] end

--- Draw over the velocity strip: `points` are `{ beat, fraction }` as the
--- pointer went (fraction 0 at the bottom, 1 at the top). Each note starting
--- within the stretch drawn over, or within `reach` beats of a click, takes
--- the height drawn above its start; with notes chosen, only those.
function A.draw_velocities(clip: integer, points: {Point}, reach?: number): integer
  if #points == 0 then return 0 end
  table.sort(points, by_beat)
  reach = reach or 0
  local from, to = points[1][1] - reach, points[#points][1] + reach
  local function height(beat: number): number
    if beat <= points[1][1] then return points[1][2] end
    for i = 2, #points do
      local a, b = points[i - 1], points[i]
      if beat <= b[1] then
        return b[1] > a[1] and a[2] + (b[2] - a[2]) * (beat - a[1]) / (b[1] - a[1]) or b[2]
      end
    end
    return points[#points][2]
  end
  local map, chosen_count = chosen_map(clip)
  local count = 0
  for _, part in ipairs(parts_for(clip)) do
    local only: {integer:boolean} = {}
    for _, place in ipairs(map[part.id] or {}) do only[place] = true end
    local set: {objects.NoteChangeInput} = {}
    local notes = part.clip:notes()
    for place, n in ipairs(notes) do
      local start = n.start + part.offset
      if (chosen_count == 0 or only[place]) and n.start >= 0 and start >= from - 1e-9 and start <= to + 1e-9 then
        set[#set + 1] = { index = place, velocity = util.clamp(math.floor(height(start) * 127 + 0.5), 1, 127) as integer }
      end
    end
    if #set > 0 then part.clip:edit_notes({ set = set }) end
    count = count + #set
  end
  if count > 0 and chosen_count > 0 then choose_all(map) end
  return count
end

--- The length a click on the grid gives a note, and that insert mode and
--- step input enter: the piano roll's note length. 0 or nil for one grid step.
function A.set_note_length(length?: number)
  paw.ui.views.pianoroll:set_step(length and length > 0 and length or nil)
end

--- The snap button: whether the pointer's notes land on the grid.
function A.toggle_note_snap()
  opt.note_snap = not opt.note_snap
end

--- Quantize: the chosen notes of `clip` (and of the clips edited with it),
--- or all of them with none chosen, start on the nearest step of the piano
--- roll's grid, keeping their lengths (a note that would leave its clip
--- stops at its end). `strength` from 0 to 1 moves them that part of the
--- way (1 without).
function A.quantize_notes(clip: integer, strength?: number): integer
  strength = util.clamp(strength or 1, 0, 1)
  local map, chosen_count = chosen_map(clip)
  local some = chosen_count > 0
  local count = 0
  local after: {integer:{Wanted}} = {}
  for _, part in ipairs(parts_for(clip)) do
    local notes = part.clip:notes()
    local places = map[part.id] or {}
    if not some then
      for place in ipairs(notes) do places[place] = place end
    end
    local set: {objects.NoteChangeInput} = {}
    local wanted: {Wanted} = {}
    for _, place in ipairs(places) do
      local n = notes[place]
      local start = math.max(0, math.min(n.start + (note_snap(n.start) - n.start) * strength, part.length - opt.note_grid))
      set[#set + 1] = { index = place, start = start, length = math.min(n.length, part.length - start) }
      wanted[#wanted + 1] = { start = start, pitch = n.pitch }
    end
    if #set > 0 then
      part.clip:edit_notes({ set = set })
      after[part.id] = wanted
    end
    count = count + #set
  end
  if count == 0 then return 0 end
  if some then
    local out: {integer:{integer}} = {}
    for id, wanted in pairs(after) do out[id] = places_of(id, wanted) end
    choose_all(out)
  end
  return count
end

-- Step input: with it on, the piano roll open and the transport stopped,
-- each note a MIDI keyboard plays is entered at the roll's cursor with the
-- roll's note length. Notes held together make a chord; the cursor steps
-- on when the last of them is let go.
local record Stepping
  on: boolean
  held: {integer:boolean}
  entered: boolean
end
local stepping: Stepping = { on = false, held = {}, entered = false }

--- True if step input (notes from a MIDI keyboard) is on.
function M.step_input(): boolean return stepping.on end

function A.toggle_step_input()
  stepping.on, stepping.held, stepping.entered = not stepping.on, {}, false
  paw.notify(stepping.on and "step input: play notes on a MIDI keyboard to enter them at the cursor" or "step input off")
  api.ui_redraw()
end

events.on(kernel.midi_in, function(event: types.MidiEvent)
  if not stepping.on or not paw.ui.visible("pianoroll") or api.transport_get().playing then return end
  local roll = paw.ui.views.pianoroll
  local clip = roll:clip()
  if not clip or not event.pitch then return end
  if event.type == "note_on" and (event.velocity or 0) > 0 then
    local length = roll:step_length()
    if roll.beat + length > clip.length + 1e-9 then
      clip.length = paw.time.bar_ceil(clip.start + roll.beat + length - 1e-9) - clip.start
    end
    clip:edit_notes({
      remove = roll:starting_here(clip, event.pitch),
      add = { { pitch = event.pitch, start = roll.beat, length = length, velocity = event.velocity as integer } },
    })
    roll.pitch = event.pitch
    stepping.held[event.pitch], stepping.entered = true, true
    api.ui_redraw()
  elseif event.type == "note_off" or event.type == "note_on" then
    stepping.held[event.pitch] = nil
    if stepping.entered and next(stepping.held) == nil then
      stepping.entered = false
      roll:step(1)
    end
  end
end)

--- A click on the piano roll's ruler: the playhead to that beat of the clip.
function A.roll_seek(clip: integer, beat: number)
  api.transport_seek(math.max(0, paw.clip(clip).start + math.max(0, beat)))
end

-- Automation. A lane is drawn over a stretch of its range (`lane_span`),
-- and a frontend names a height in it as a fraction, 0 at the bottom.

local function lane_value(lane: integer, fraction: number): number
  local lo, hi = M.lane_span(api.lane_get(lane))
  return lo + util.clamp(fraction, 0, 1) * (hi - lo)
end

--- The lane of a track for "volume", "pan", or a parameter (by key) of one
--- of its devices: the one there is, or a new one.
function A.lane(track: integer, target: types.LaneTarget, device?: integer, param?: string): integer
  for _, lane in ipairs(api.lane_list(track)) do
    if lane.target == target and (target ~= "param" or (lane.device == device and lane.param == param)) then
      return lane.id
    end
  end
  return api.lane_add(track, { target = target, device = device, param = param })
end

function A.add_point(lane: integer, beat: number, fraction: number)
  api.lane_add_point(lane, snap(beat), lane_value(lane, fraction))
end

function A.move_point(lane: integer, index: integer, beat: number, fraction: number)
  local points = api.lane_points(lane)
  table.remove(points, index)
  points[#points + 1] = { snap(beat), lane_value(lane, fraction) }
  api.lane_set_points(lane, points)
end

--- Draw over a lane with a pencil: `points` are `{ beat, fraction }` as
--- they were drawn. They replace what the lane held over the stretch drawn
--- across, at most one to a quarter of a grid step.
function A.draw_lane(lane: integer, points: {Point})
  if #points == 0 then return end
  table.sort(points, by_beat)
  local step = opt.grid / 4
  local from, to = math.max(0, points[1][1]), math.max(0, points[#points][1])
  local out: {types.LanePoint} = {}
  for _, p in ipairs(api.lane_points(lane)) do
    if p[1] < from - 1e-9 or p[1] > to + 1e-9 then out[#out + 1] = p end
  end
  local last: number
  for i, p in ipairs(points) do
    local beat = math.max(0, p[1])
    if not last or beat - last >= step - 1e-9 or i == #points then
      out[#out + 1] = { beat, lane_value(lane, p[2]) }
      last = beat
    end
  end
  api.lane_set_points(lane, out)
end

function A.toggle_lane(lane: integer)
  api.lane_set(lane, { enabled = not api.lane_get(lane).enabled })
end

function A.clear_lane(lane: integer)
  api.lane_set_points(lane, {})
end

-- Controller moves in a MIDI clip: the pitch wheel, pressure, or a control
-- change by number. Heights are fractions, 0 at the bottom; the wheel rests
-- in the middle.

local function control_value(kind: types.ControlType, fraction: number): number
  fraction = util.clamp(fraction, 0, 1)
  return kind == "bend" and fraction * 2 - 1 or fraction
end

--- Draw controller moves with a pencil: `points` are `{ beat, fraction }`
--- in the clip. They replace the moves of that kind over the stretch drawn
--- across, one to a note-grid step.
function A.draw_controls(clip: integer, kind: types.ControlType, number: integer, points: {Point})
  if #points == 0 then return end
  table.sort(points, by_beat)
  local c = paw.clip(clip)
  local grid = opt.note_grid
  local from, to = note_snap(points[1][1]), note_snap(points[#points][1])
  local same = function(control: types.Control): boolean
    return control.type == kind and control.key == nil and (kind ~= "cc" or control.number == number)
  end
  local out: {objects.ControlInput} = {}
  for _, control in ipairs(c:controls()) do
    if not (same(control) and control.start >= from - 1e-9 and control.start <= to + 1e-9) then out[#out + 1] = control as objects.ControlInput end
  end
  -- Each step takes the height drawn nearest to it.
  local steps, nearest: {number:number}, {number:number} = {}, {}
  for _, p in ipairs(points) do
    local at = note_snap(p[1])
    local off = math.abs(p[1] - at)
    if not nearest[at] or off < nearest[at] then steps[at], nearest[at] = p[2], off end
  end
  for beat = from, to + 1e-9, grid do
    local fraction = steps[note_snap(beat)]
    if fraction and beat < c.length then
      out[#out + 1] = { start = note_snap(beat), type = kind, number = kind == "cc" and number or nil, value = control_value(kind, fraction) }
    end
  end
  c:set_controls(out)
end

--- Remove the moves of one kind from a clip.
function A.clear_controls(clip: integer, kind: types.ControlType, number: integer)
  local c = paw.clip(clip)
  local out: {objects.ControlInput} = {}
  for _, control in ipairs(c:controls()) do
    if not (control.type == kind and control.key == nil and (kind ~= "cc" or control.number == number)) then out[#out + 1] = control as objects.ControlInput end
  end
  c:set_controls(out)
end

-- Moves of the strip chosen, moved and taken away, drawn as a line, and
-- the event list: `paw.controls` says what each does.
-- A window names a mode by number: 0 alone, 1 add, 2 toggle.
local modes: {integer:string} = { [0] = "only", [1] = "add", [2] = "toggle" }
local function mode_of(mode: integer | string): string return modes[mode as integer] or mode as string end
function A.select_control(clip: integer, place: integer, mode: integer | string) paw.controls.select(clip, place, mode_of(mode)) end
function A.select_controls(clip: integer, kind: string, number: integer, beat0: number, low: number, beat1: number, high: number, mode: integer | string): integer
  return paw.controls.select_box(clip, kind, number, beat0, low, beat1, high, mode_of(mode))
end
function A.select_all_controls(clip: integer, kind: string, number: integer): integer
  return paw.controls.select_box(clip, kind, number, -1, 0, paw.clip(clip).length + 1, 1)
end
function A.clear_control_selection(clip: integer) paw.controls.clear(clip) end
function A.move_controls(clip: integer, dbeat: number, dfraction: number, free?: boolean | integer): integer
  return paw.controls.move(clip, dbeat, dfraction, free == true or free == 1)
end
function A.remove_chosen_controls(clip: integer): integer return paw.controls.remove(clip) end
function A.line_controls(clip: integer, kind: string, number: integer, beat0: number, f0: number, beat1: number, f1: number, free?: boolean | integer): integer
  return paw.controls.line(clip, kind, number, beat0, f0, beat1, f1, free == true or free == 1)
end

--- The event list of the clip in the piano roll, in a window of its own.
function A.open_event_list(clip: integer)
  paw.canvas.open_view("eventlist", { title = "Events · " .. paw.clip(clip).name, width = 520, height = 440 })
end

function A.remove_point(lane: integer, index: integer)
  local points = api.lane_points(lane)
  table.remove(points, index)
  api.lane_set_points(lane, points)
end

-- Devices.

local function param_of(device: integer, key: string): types.ParamInfo
  for _, p in ipairs(api.device_get(device).param_info) do
    if p.key == key then return p end
  end
  error("the device has no parameter `" .. tostring(key) .. "`", 3)
end

--- Set a parameter from a slider's position, 0 to 1 across its range.
function A.set_param(device: integer, key: string, fraction: number)
  local p = param_of(device, key)
  api.device_set_param(device, key, paw.params.from_fraction(p, fraction))
end

--- Back to where the device starts out: a double click on a slider.
function A.reset_param(device: integer, key: string)
  api.device_set_param(device, key, param_of(device, key).default)
end

function A.toggle_bypass(device: integer)
  api.device_set(device, { bypass = not api.device_get(device).bypass })
end

function A.add_device(kind: string, query?: string): integer
  return paw.fx.add(assert(paw.cursor.track(), "no track selected"), kind, { query = query }).id
end

--- Move a device one place earlier (-1) or later (1) in its track's chain.
function A.move_device(device: integer, by: integer)
  local d = api.device_get(device)
  api.device_move(device, d.track, util.clamp(d.index + by, 1, #api.track_get(d.track).devices) as integer)
end

return M
