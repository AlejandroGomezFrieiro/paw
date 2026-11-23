-- The table `paw.frontend` and the records that it gives. Its parts
-- (paw/frontend.tl lists them) put their functions on it; the gestures go
-- on its one table `act`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local events = require("paw.events")
local type registry = require("paw.registry")
local type types = require("paw.types")
local type objects = require("paw.objects")
local type CanvasModule = require("paw.canvas")
local type EditModule = require("paw.edit")
local type PanesModule = require("paw.panes")
local type StatuslineModule = require("paw.statusline")
local type TempoModule = require("paw.tempo")
local type host = require("paw.frontend.host")

local type Region = EditModule.Region
local type Candidate = host.Candidate
local type Prompt = host.Prompt
local type Message = host.Message
local type Hint = host.Hint
local type RangeChoice = host.RangeChoice
local type Point = host.Point
local type Portion = host.Portion

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

--- The candidates of a prompt that show (`M.completions`).
local record Completions
  total: integer
  chosen: integer
  items: {Candidate}
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

local record Hints
  title: string
  items: {Hint}
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
  menus: {string: {MenuLabel}}
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

--- The start values of the render dialog (`M.render_dialog`).
local record RenderDialog
  path: string
  ranges: {RangeChoice}
  sample_rate: integer
  formats: {string: boolean}
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
  select_notes_box: function(
    clip: integer, beat0: number, pitch0: number, beat1: number, pitch1: number, mode?: string
  ): integer
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
  select_controls: function(
    clip: integer,
    kind: string,
    number: integer,
    beat0: number,
    low: number,
    beat1: number,
    high: number,
    mode: integer | string
  ): integer
  select_all_controls: function(clip: integer, kind: string, number: integer): integer
  clear_control_selection: function(clip: integer)
  move_controls: function(clip: integer, dbeat: number, dfraction: number, free?: boolean | integer): integer
  remove_chosen_controls: function(clip: integer): integer
  line_controls: function(
    clip: integer,
    kind: string,
    number: integer,
    beat0: number,
    f0: number,
    beat1: number,
    f1: number,
    free?: boolean | integer
  ): integer
  open_event_list: function(clip: integer)
  remove_point: function(lane: integer, index: integer)
  set_param: function(device: integer, key: string, fraction: number)
  reset_param: function(device: integer, key: string)
  toggle_bypass: function(device: integer)
  add_device: function(kind: string, query?: string): integer
  move_device: function(device: integer, by: integer)
end

local record M
  type Portion = Portion
  type Point = Point
  type Act = Act
  type ParamState = ParamState
  type DeviceState = DeviceState
  type MenuEntry = MenuEntry
  type MenuLabel = MenuLabel
  type BandEntry = BandEntry
  type Band = Band
  type BandState = BandState
  type Bands = Bands
  type Completions = Completions
  type PromptState = PromptState
  type Modal = Modal
  type Line = Line
  type ProjectState = ProjectState
  type Send = Send
  type TrackState = TrackState
  type TakeRow = TakeRow
  type ClipState = ClipState
  type Target = Target
  type SendState = SendState
  type Routing = Routing
  type State = State
  type FloatText = FloatText
  type Renderer = Renderer
  type DialogInfo = DialogInfo
  type Closing = Closing
  type RenderDialog = RenderDialog
  type Check = Check
  type InputMenu = InputMenu
  type EngineMenu = EngineMenu
  type PairMenu = PairMenu
  type WindowLayout = WindowLayout
  type RenderRequest = RenderRequest
  type Dropped = Dropped
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
  menus: {string: {MenuEntry}}
  --- Bands of extensions under the ruler, by name, with the extension
  --- that put each one.
  bands: registry.Registry<Band>
  --- The pointer's gestures.
  act: Act
  -- The functions, by the part that defines them.
  -- frontend/state.tl
  format_value: function(param: types.ParamInfo, value: number): string
  refresh: function()
  band_state: function(): Bands
  completions: function(prompt: Prompt): Completions
  send_list: function(track: types.Track): {Send}
  float: function(width: integer, height: integer): FloatText
  lane_span: function(lane: types.Lane): number, number
  lane_name: function(lane: types.Lane): string
  take_rows: function(clip: types.Clip): {TakeRow}
  take_preview: function(id: integer, take: integer, points?: number): {number}
  content_key: function(clip: types.Clip): string
  preview: function(id: integer): {number}
  vca_words: function(id: integer): string
  state: function(known: integer): State
  peaks: function(clip: integer, points?: number): {number}
  -- frontend/dialogs.tl
  save_as: function(after?: function())
  window_renderer_set: function(info: Renderer)
  dialog_info: function(): DialogInfo
  closing: function(): Closing
  render_dialog: function(): RenderDialog
  input_menu: function(track: integer): InputMenu
  recent_menu: function(): {RangeChoice}
  layout_get: function(): WindowLayout
  layout_set: function(layout: WindowLayout)
  engine_menu: function(): EngineMenu
  -- frontend/act/clips.tl
  chosen_clips: function(): {integer}
  choose_clips: function(set: {integer: boolean})
  -- frontend/act/routing.tl
  routing: function(track: integer): Routing
  sidechain_menu: function(device: integer): {Check}
  outputs_menu: function(device: integer): {PairMenu}
  -- frontend/act/notes.tl
  choose_notes: function(clip: integer, places: {integer: boolean})
  chosen_notes: function(clip: integer): {integer}
  chosen_refs: function(): {{integer}}
  chosen_text: function(clip: integer): string
  --- Editors of extensions for clips: given a clip, true if it opened it.
  openers: {function(clip: objects.Clip): boolean}
  --- What the window said of the OpenGL that draws it.
  window_renderer: Renderer
  --- What to do about a window that draws on the processor, by cause.
  software_advice: {string: string}
  --- Another file for the window's layout than the state folder's (tests).
  layout_path: string
end

M.revision, M.max_params, M.peak_points, M.preview_notes = 0, 16, 128, 2000

local function bump()
  M.revision = M.revision + 1
end
for _, name in ipairs(
  {
    "changed",
    "transport.changed",
    "cursor.changed",
    "project.loaded",
    "engine.started",
    "option.changed",
    "lanes.changed",
  }
) do
  local event: events.Event<events.Payload> = events.event(name)
  events.on(event, bump)
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

return M
