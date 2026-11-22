-- Tracks, devices and clips as objects.
--
-- An object is only an id with methods: reading `track.volume` asks the
-- kernel, writing it tells the kernel. Objects stay valid across undo, and
-- raise an error when the thing they point at no longer exists.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. The records
-- `paw.Track`, `paw.Device`, `paw.Clip` and `paw.Lane` give the fields that
-- an object reads from the kernel, and its methods.
local api = require("paw.api")
local type types = require("paw.types")
local music = require("paw.music")
local util = require("paw.util")
local options = require("paw.options")
local events = require("paw.events")

--- A value that this module passes on and never reads.
local record Value
end

--- A pitch as a script gives it: a MIDI number or a name such as "C4".
local type Pitch = integer | string

--- A note as a script gives it (`Clip:add_note`): `pitch` may be a name,
--- and the note may be the list `{ pitch, start, length, velocity }`.
local record NoteInput is {number | string}
  pitch: Pitch
  start: number
  length: number
  velocity: integer
  id: integer
  meta: types.Meta
  attr: types.NoteAttr
end

--- A change of a note as a script gives it (`Clip:set_note`): `pitch` may
--- be a name.
local record NoteChangeInput
  index: integer
  start: number
  length: number
  pitch: Pitch
  velocity: integer
  meta: types.Meta
  attr: types.NoteAttr | boolean
end

--- Several changes of a clip's notes (`Clip:edit_notes`).
local record NotesEditInput
  set: {NoteChangeInput}
  remove: {integer}
  add: {NoteInput}
end

--- Which notes `Clip:notes` gives: `low` and `high` may be names.
local record NoteRangeInput
  from: number
  to: number
  low: Pitch
  high: Pitch
end

--- A controller move as a script gives it (`Clip:set_controls`): `key`
--- may be a name.
local record ControlInput
  start: number
  type: types.ControlType
  value: number
  key: Pitch
  number: integer
  bank: integer
  index: integer
  program: integer
end

--- A MIDI message as a script gives it (`Track:midi`, `paw.midi.inject`):
--- `pitch` and `key` may be names.
local record MidiEventInput
  type: types.MidiEventType
  channel: integer
  pitch: Pitch
  velocity: number
  attr: types.NoteAttr
  value: number
  key: Pitch
  number: integer
  bank: integer
  index: integer
  program: integer
  port: string
end

--- An automation point as a script gives it: `{ beat, value }` or
--- `{ beat = 0, value = -60 }`.
local record PointInput is {number}
  beat: number
  value: number
end

--- A clip as `paw.restore_clip` takes it and `Clip:snapshot` gives it:
--- what `paw.api.clip_add` takes, and whether it is muted.
local record ClipSnapshot
  name: string
  start: number
  length: number
  kind: types.ClipKind
  muted: boolean
  file: string
  offset: number
  gain: number
  fade_in: number
  fade_out: number
  timebase: types.Timebase
  stretch: number
  pitch: number
  stretch_mode: types.StretchMode
  source_tempo: number
  loop: boolean
  loop_length: number
  loop_start: number
  warp: {types.WarpMarker}
  formants: boolean
  meta: types.Meta
  cue: boolean
  notes: {types.Note}
  controls: {types.Control}
end

--- What `Track:add_clip` takes: what `paw.api.clip_add` takes, with notes
--- as `Clip:add_note` takes each.
local record ClipInput
  name: string
  start: number
  length: number
  kind: types.ClipKind
  file: string
  offset: number
  gain: number
  fade_in: number
  fade_out: number
  timebase: types.Timebase
  stretch: number
  pitch: number
  stretch_mode: types.StretchMode
  source_tempo: number
  loop: boolean
  loop_length: number
  loop_start: number
  warp: {types.WarpMarker}
  formants: boolean
  meta: types.Meta
  cue: boolean
  notes: {NoteInput}
  controls: {types.Control}
end

--- A device as `paw.restore_device` takes it and `Device:snapshot` gives
--- it. `outputs` maps a pair number (as text) to a track.
local record DeviceSnapshot
  kind: string
  bypass: boolean
  state: string
  params: {string: number}
  meta: types.Meta
  sidechain: integer
  sidechain_pre: boolean
  outputs: {string: integer}
end

--- An automation lane of a track's snapshot: `device` is the place of its
--- device in the track's chain, from 1.
local record LaneSnapshot
  target: types.LaneTarget
  device: integer
  param: string
  enabled: boolean
  points: {types.LanePoint}
end

--- What `Device:set_sidechain` and `Track:send` take besides the track.
local record PreOptions
  pre: boolean
end

--- What `Track:add_device` takes besides the kind and the parameters.
local record AddDeviceOptions
  index: integer
end

--- A bar line of `paw.time.bars`: its beat and its bar, from 1.
local record BarLine
  beat: number
  bar: integer
end

--- A command as `paw.commands.get` gives it, as far as `allow_discard`
--- reads it.
local record CommandSpec
  run: function(Value): Value
  desc: string
  raw: boolean
  complete: Value
end

--- What `paw.command` takes besides the name and the handler.
local record CommandOptions
  desc: string
  raw: boolean
  complete: Value
end

-- What this module reads of `paw`, which paw/init.lua makes. A module of the
-- runtime in Teal does not see the global `paw` (runtime/types/paw.d.tl
-- requires this module).
local record Paw
  record Ui
    poke: function(ms?: number)
  end
  record Stretch
    markers: function(c: types.Clip): {types.WarpMarker}
  end
  record Routes
    set_output: function(device: integer, pair: integer, track: integer)
  end
  record Commands
    get: function(name: string): CommandSpec
  end
  --- paw/scope.tl: the subproject the window is in.
  record ScopeLevel
    id: integer
  end
  record Scope
    nest: function(): ScopeLevel
  end
  ui: Ui
  scope: Scope
  stretch: Stretch
  routes: Routes
  commands: Commands
  command: function(name: string, run: function(Value), opts: CommandOptions)
  defer: function(fn: function(), ms?: number): integer
  notify: function(text: string, level?: string)
end
local paw = (_G as {string: Paw}).paw

local record M
  type Pitch = Pitch
  type NoteInput = NoteInput
  type NoteChangeInput = NoteChangeInput
  type NotesEditInput = NotesEditInput
  type NoteRangeInput = NoteRangeInput
  type ControlInput = ControlInput
  type MidiEventInput = MidiEventInput
  type PointInput = PointInput
  type ClipSnapshot = ClipSnapshot
  type ClipInput = ClipInput
  type DeviceSnapshot = DeviceSnapshot
  type LaneSnapshot = LaneSnapshot
  type PreOptions = PreOptions
  type AddDeviceOptions = AddDeviceOptions
  type BarLine = BarLine

  --- A track as `paw.track(id)` gives it: its id, the fields of
  --- `paw.api.track_get` (each read from the kernel, and set in it when
  --- written), and its methods. `output` may be set to a track too.
  record Track
    id: integer
    name: string
    volume: number
    pan: number
    mute: boolean
    solo: boolean
    armed: boolean
    output: integer
    sends: {types.Send}
    color: string
    meta: types.Meta
    index: integer
    master: boolean
    input: string
    monitor: boolean
    midi_input: types.MidiInput
    midi_output: types.MidiOutput
    height: number
    automation: types.AutoMode
    attr_map: types.AttrMap
    listens: {integer}
    pairs_into: {integer}
    source: string
    origin: string
    chain_source: string
    chain_origin: string
    get: function(self: Track): types.Track
    exists: function(self: Track): boolean
    remove: function(self: Track)
    move: function(self: Track, index: integer)
    add_device: function(self: Track, kind: string, params?: {string: number}, opts?: AddDeviceOptions): Device
    devices: function(self: Track): {Device}
    device: function(self: Track, which: integer | string): Device
    add_clip: function(self: Track, opts?: ClipInput): Clip
    clips: function(self: Track): {Clip}
    clip_at: function(self: Track, beat: number): Clip
    meter: function(self: Track): number, number
    note_on: function(self: Track, pitch: Pitch, velocity?: number, attr?: types.NoteAttr)
    note_off: function(self: Track, pitch?: Pitch)
    midi: function(self: Track, event: MidiEventInput)
    play_note: function(self: Track, pitch: Pitch, velocity?: number, ms?: number, attr?: types.NoteAttr)
    send: function(self: Track, target: integer | Track, level?: number, opts?: PreOptions)
    snapshot: function(self: Track): TrackSnapshot
    duplicate: function(self: Track): Track
    lanes: function(self: Track): {Lane}
    lane: function(self: Track, target: types.LaneTarget): Lane
    automate: function(self: Track, target: types.LaneTarget): Lane
    value_at: function(self: Track, target: types.LaneTarget, beat: number): number
  end

  --- A device as `paw.device(id)` gives it: its id, the fields of
  --- `paw.api.device_get`, and its methods.
  record Device
    id: integer
    plugin: types.DevicePlugin
    kind: string
    name: string
    offline: boolean
    format: string
    index: integer
    bypass: boolean
    params: {string: number}
    overrides: {string: number}
    param_info: {types.ParamInfo}
    meta: types.Meta
    editor: types.EditorState
    missing: boolean
    stopped: string
    status: types.DeviceStatus
    sidechain: integer
    sidechain_pre: boolean
    outputs: {string: integer}
    ports: types.DevicePorts
    get: function(self: Device): types.Device
    exists: function(self: Device): boolean
    remove: function(self: Device)
    track: function(self: Device): Track
    set: function(self: Device, name: string | {string: number | string}, value?: number | string): Device
    info: function(self: Device): types.DeviceType
    snapshot: function(self: Device): DeviceSnapshot
    set_output: function(self: Device, pair: integer, track?: integer | Track): Device
    set_sidechain: function(self: Device, track?: integer | Track, opts?: PreOptions): Device
    restart: function(self: Device)
    set_offline: function(self: Device, on?: boolean)
    open_editor: function(self: Device): boolean
    close_editor: function(self: Device): boolean
    lanes: function(self: Device): {Lane}
    lane: function(self: Device, param: string): Lane
    automate: function(self: Device, param: string): Lane
    state_lane: function(self: Device): Lane
    automate_state: function(self: Device): Lane
    capture: function(self: Device, name?: string): types.LaneState
    value_at: function(self: Device, param: string, beat: number): number
    move: function(self: Device, index: integer, track?: integer | Track)
  end

  --- A clip as `paw.clip(id)` gives it: its id, the fields of
  --- `paw.api.clip_get`, and its methods.
  record Clip
    id: integer
    name: string
    start: number
    length: number
    muted: boolean
    kind: types.ClipKind
    meta: types.Meta
    cue: boolean
    source: string
    origin: string
    offline: boolean
    note_count: integer
    control_count: integer
    stamp: integer
    control_stamp: integer
    edits: integer
    file: string
    offset: number
    gain: number
    fade_in: number
    fade_out: number
    timebase: types.Timebase
    stretch: number
    pitch: number
    stretch_mode: types.StretchMode
    source_tempo: number
    loop: boolean
    loop_start: number
    loop_length: number
    stretching: boolean
    made: number
    bent: boolean
    formants: boolean
    warp: {types.WarpMarker}
    get: function(self: Clip): types.Clip
    exists: function(self: Clip): boolean
    remove: function(self: Clip)
    track: function(self: Clip): Track
    notes: function(self: Clip, range?: NoteRangeInput): {types.Note}, {integer}
    note_at: function(self: Clip, pitch: Pitch, beat: number): types.Note, integer
    set_note: function(self: Clip, index: integer, fields: NoteChangeInput): integer
    remove_note: function(self: Clip, index: integer)
    edit_notes: function(self: Clip, edit: NotesEditInput)
    peaks: function(self: Clip, n: integer): {types.Peak}
    set_notes: function(self: Clip, notes: {NoteInput})
    controls: function(self: Clip): {types.Control}
    set_controls: function(self: Clip, controls: {ControlInput})
    add_notes: function(self: Clip, notes: {NoteInput})
    add_note: function(self: Clip, note: NoteInput): integer
    snapshot: function(self: Clip): ClipSnapshot
    duplicate: function(self: Clip, opts?: DuplicateOptions): Clip
    --- The data of a clip of a kind that an extension defines, decoded
    --- (paw/clip_kinds.tl): nil for a MIDI or audio clip, and nil and why
    --- for data that its kind cannot read.
    data: function<D>(self: Clip): D, string
    --- Give a clip of a kind new data, and what the kind compiles from
    --- it, as one undo step (`paw.clip_kinds.set`).
    set_data: function<D>(self: Clip, data: D)
  end

  --- What `Clip:duplicate` takes: where the copy goes.
  record DuplicateOptions
    start: number
    track: integer | Track
  end

  --- An automation lane as `paw.lane(id)` gives it: its id, the fields of
  --- `paw.api.lane_get`, and its methods.
  record Lane
    id: integer
    enabled: boolean
    point_count: integer
    min: number
    max: number
    target: types.LaneTarget
    device: integer
    param: string
    get: function(self: Lane): types.Lane
    exists: function(self: Lane): boolean
    remove: function(self: Lane)
    track: function(self: Lane): Track
    points: function(self: Lane): {types.LanePoint}
    set_points: function(self: Lane, points: {PointInput})
    add: function(self: Lane, beat: number, value: number)
    clear: function(self: Lane)
    value_at: function(self: Lane, beat: number): number
    states: function(self: Lane): {types.LaneState}
    add_state: function(self: Lane, state: types.LaneState): integer
    state_index: function(self: Lane, which: number | string): integer
    set_state: function(self: Lane, beat: number, which: number | string)
  end

  --- A track as plain data (`Track:snapshot`, `paw.restore_track`).
  record TrackSnapshot
    name: string
    volume: number
    pan: number
    output: integer
    color: string
    mute: boolean
    sends: {types.Send}
    input: string
    monitor: boolean
    midi_input: types.MidiInput
    midi_output: types.MidiOutput
    height: number
    attr_map: types.AttrMap
    meta: types.Meta
    devices: {DeviceSnapshot}
    clips: {ClipSnapshot}
    lanes: {LaneSnapshot}
  end

  --- What `paw.add_track` takes: as `paw.api.track_add`, with `output` a
  --- track or an id.
  record TrackInput
    name: string
    index: integer
    volume: number
    pan: number
    output: integer | Track
    color: string
    nest: integer
  end

  --- `paw.project`: the fields of `paw.api.project_get` (each set with
  --- `paw.api.project_set` when written), and the functions on the project.
  record Project
    name: string
    tempo: number
    sig_num: integer
    sig_den: integer
    tempo_ramp: boolean
    tempo_changes: {types.TempoChange}
    sig_changes: {types.SigChange}
    key: string
    path: string
    length: number
    meta: types.Meta
    modified: boolean
    edits: integer
    new: function()
    load: function(path: string, opts?: types.OpenOptions)
    save: function(path?: string): string
    get: function(): types.Project
    unsaved: function(): boolean
    is_folder: function(path: string): boolean
    write: function(path?: string): string, string
    guard: function(what: string, force?: boolean): boolean
    discarding: function(): boolean
    allow_discard: function(name: string)
  end

  --- `paw.transport`: the fields of `paw.api.transport_get` (`position`
  --- seeks and `tempo` sets the project's when written), and its functions.
  record Transport
    playing: boolean
    position: number
    tempo: number
    loop_enabled: boolean
    loop_start: number
    loop_end: number
    metronome: boolean
    recording: boolean
    punch_enabled: boolean
    punch_start: number
    punch_end: number
    count_in: integer
    counting: integer
    pre_roll: integer
    pre_roll_seconds: number
    click_level: number
    click_accent: boolean
    click_output: integer
    record_offset: number
    write: boolean
    take: integer
    play: function()
    stop: function()
    record: function()
    seek: function(beats: number)
    get: function(): types.Transport
    toggle: function()
  end

  --- `paw.midi`: the MIDI ports, and events delivered as if from one.
  record Midi
    inputs: function(): {types.MidiPort}
    open_port: function(name: string)
    close_port: function(name: string): boolean
    select: function(which?: string | {string})
    inject: function(event: MidiEventInput)
    ump: function(event: MidiEventInput): {integer}
    inject_ump: function(words: {integer}): boolean
    outputs: function(): {types.MidiPort}
    open_output: function(name: string)
    close_output: function(name: string): boolean
    note_on: function(pitch: Pitch, velocity?: number, channel?: integer)
    note_off: function(pitch: Pitch, channel?: integer)
  end

  --- `paw.time`: musical time, by the tempo map.
  record Time
    bar: function(at?: number): number
    bar_start: function(n: integer): number
    signature_at: function(beat?: number): integer, integer
    tempo_at: function(beat?: number): number
    bar_of: function(beat: number): integer
    bar_floor: function(beat: number): number
    bar_ceil: function(beat: number): number
    bars: function(from: number, to: number): {BarLine}
    format: function(beats: number): string
    seconds: function(beats: number, at?: number): number
    to_seconds: function(beat: number): number
    to_beat: function(seconds: number): number
    clock: function(beat: number): string
  end

  points: function(points: {PointInput}): {types.LanePoint}
  notes: function(notes: {NoteInput}): {types.Note}
  restore_track: function(snap: TrackSnapshot, index?: integer): Track
  restore_clip: function(snap: ClipSnapshot, track: integer | Track): Clip
  restore_device: function(snap: DeviceSnapshot, track: integer | Track, index?: integer): Device
  add_track: function(opts?: TrackInput): Track
  tracks: function(): {Track}
  track: function(which: number | string): Track
  device: function(id: integer): Device
  clip: function(id: integer): Clip
  lane: function(id: integer): Lane
  master: Track
  project: Project
  transport: Transport
  midi: Midi
  time: Time
end

local Track, Device, Clip, Lane = M.Track, M.Device, M.Clip, M.Lane
local type TrackSnapshot = M.TrackSnapshot

local track_mt = Track as metatable<Track>
local device_mt = Device as metatable<Device>
local clip_mt = Clip as metatable<Clip>
local lane_mt = Lane as metatable<Lane>

--- A kernel function that reads an object's whole table, by its id.
local type Get = function(id: integer): {string: Value}
--- A kernel function that reads one field of an object.
local type Field = function(id: integer, key: string): Value
--- How a field of an object is set.
local type Set = function(id: integer, key: string, value: Value)

-- `field(id, key)`, when given, reads one entry without the whole table.
local function class<T>(cls: metatable<T>, name: string, get: Get, set: Set, field?: Field)
  local methods = cls as {string: Value}
  rawset(methods, "__name", name as Value)
  cls.__index = function(self: T, key: string): Value
    local method = methods[key]
    if method ~= nil then
      return method
    end
    local id = rawget(self as {string: integer}, "id")
    if field and type(key) == "string" then
      return field(id, key)
    end
    return get(id)[key]
  end
  cls.__newindex = function(self: T, key: string, value: Value)
    set(rawget(self as {string: integer}, "id"), key, value)
  end
  cls.__eq = function(a: T, b: T): boolean
    return rawget(a as {string: integer}, "id") == rawget(b as {string: integer}, "id")
  end
  cls.__tostring = function(self: T): string return name .. "(" .. rawget(self as {string: integer}, "id") .. ")" end
end

local function wrap<T>(cls: metatable<T>, id: integer): T
  return id and setmetatable({id = id} as T, cls) or nil
end

local function id_of(value: integer | Track): integer
  if value is Track then
    return value.id
  end
  return value
end

-- The setters of the kernel, by one key: a value in a patch, or nil by the
-- key alone (a patch cannot hold nil).
local function setter<P>(set_patch: function(integer, P), set_key: function(integer, string, nil)): Set
  return function(id: integer, key: string, value: Value)
    if value == nil then
      return set_key(id, key, nil)
    end
    local patch: {string: Value} = {[key] = value}
    set_patch(id, patch as P)
  end
end

local track_set = setter(
  api.track_set as function(integer, types.Track), api.track_set as function(integer, string, nil)
)
local device_set = setter(
  api.device_set as function(integer, types.Device), api.device_set as function(integer, string, nil)
)
local clip_set = setter(api.clip_set as function(integer, types.Clip), api.clip_set as function(integer, string, nil))
local lane_set = setter(api.lane_set as function(integer, types.Lane), api.lane_set as function(integer, string, nil))
-- `track_get(id, key)`: one field of a track, which Teal does not see.
local track_field = api.track_get as Field

-- Tracks ---------------------------------------------------------------------

class(
  track_mt,
  "Track",
  api.track_get as Get,
  function(id: integer, key: string, value: Value)
    if key == "output" then
      value = id_of(value as integer | Track) as Value
    end
    track_set(id, key, value)
  end,
  track_field
)

--- A plain table with every field of the track, read once.
function Track:get(): types.Track
  return api.track_get(self.id)
end

--- True if the track is still in the project.
function Track:exists(): boolean
  return (pcall(track_field, self.id, "id"))
end

--- Take the track out of the project, with its clips and devices.
function Track:remove()
  api.track_remove(self.id)
end

--- Move to a 1-based position in the track list.
function Track:move(index: integer)
  api.track_move(self.id, index)
end

--- Add a device to the end of the chain, or at the 1-based `opts.index`.
---   track:add_device("synth", { cutoff = 800 })
function Track:add_device(kind: string, params?: {string: number}, opts?: AddDeviceOptions): Device
  return wrap(device_mt, api.device_add(self.id, kind, {params = params, index = opts and opts.index}))
end

--- The track's devices in the order they process, as `paw.Device` objects.
function Track:devices(): {Device}
  local out: {Device} = {}
  for i, id in ipairs(api.track_get(self.id).devices) do
    out[i] = wrap(device_mt, id)
  end
  return out
end

--- The first device of a kind, or the device at a 1-based position.
function Track:device(which: integer | string): Device
  for i, device in ipairs(self:devices()) do
    if i == which or device.kind == which then
      return device
    end
  end
end

--- Add a clip. With `file` it is an audio clip, otherwise a MIDI clip.
---   track:add_clip({ start = 0, length = 4, notes = { { pitch = "C4", start = 0, length = 1 } } })
---   track:add_clip({ start = 8, file = "take1.wav" })
function Track:add_clip(opts?: ClipInput): Clip
  local given = opts or {}
  local clip = given as types.ClipOptions
  if given.notes then
    local copy = util.merge(given as {string: Value}, {}) as types.ClipOptions
    copy.notes = M.notes(given.notes)
    clip = copy
  end
  return wrap(clip_mt, api.clip_add(self.id, clip))
end

--- The track's clips, as `paw.Clip` objects.
function Track:clips(): {Clip}
  local out: {Clip} = {}
  for i, clip in ipairs(api.clip_list(self.id)) do
    out[i] = wrap(clip_mt, clip.id)
  end
  return out
end

--- The clip that covers `beat`, if any. Where two clips overlap, the later clip wins.
function Track:clip_at(beat: number): Clip
  local found: integer
  for _, clip in ipairs(api.clip_list(self.id)) do
    if beat >= clip.start and beat < clip.start + clip.length then
      found = clip.id
    end
  end
  return wrap(clip_mt, found)
end

--- Peak level as linear `left, right`.
function Track:meter(): number, number
  return api.track_meter(self.id)
end

--- Start a note now, outside the timeline. `pitch` may be a name like "C4".
--- With `attr`, a MIDI 2.0 attribute (`paw.attr`), the note carries it, and
--- what the track's `attr_map` sends for it goes first.
function Track:note_on(pitch: Pitch, velocity?: number, attr?: types.NoteAttr)
  paw.ui.poke()
  api.note_on(self.id, music.pitch(pitch), velocity, attr)
end

--- Stop a note, or every note when `pitch` is left out.
function Track:note_off(pitch?: Pitch)
  api.note_off(self.id, pitch and music.pitch(pitch))
end

-- An event with its `key` and `pitch` as MIDI numbers.
local function midi_event(event: MidiEventInput): types.MidiEvent
  if event.key then
    event = util.merge(event as {string: Value}, {key = music.pitch(event.key) as Value}) as MidiEventInput
  end
  if event.pitch then
    event = util.merge(event as {string: Value}, {pitch = music.pitch(event.pitch) as Value}) as MidiEventInput
  end
  return event as types.MidiEvent
end

--- Send a MIDI message to this track's devices now, outside the timeline:
--- a controller, the pitch wheel, pressure, or with `key` one note's own.
---   track:midi({ type = "cc", number = 1, value = 0.5 })
---   track:midi({ type = "bend", value = -0.25 })
---   track:midi({ type = "bend", key = "C4", value = 0.1 })
function Track:midi(event: MidiEventInput)
  api.midi_send(self.id, midi_event(event))
end

--- Play a note for `ms` milliseconds (default 200), with `attr` if given.
function Track:play_note(pitch: Pitch, velocity?: number, ms?: number, attr?: types.NoteAttr)
  self:note_on(pitch, velocity, attr)
  paw.defer(
    function()
      if self:exists() then
        self:note_off(pitch)
      end
    end,
    ms or 200
  )
end

--- Send some of this track's output to another track. `level` is in dB.
--- With `{ pre = true }` the send is taken before the fader and pan, so it
--- keeps its level when the fader moves: `vocal:send(reverb, -6, { pre = true })`.
function Track:send(target: integer | Track, level?: number, opts?: PreOptions)
  local sends = api.track_get(self.id).sends
  sends[#sends + 1] = {target = id_of(target), level = level or 0, pre = opts and opts.pre or nil}
  api.track_set(self.id, {sends = sends})
end

--- Everything about the track as plain data: its settings, devices (plugins
--- with their state), clips and automation. `paw.restore_track` makes a
--- track from it again, in this project or after the original is gone.
function Track:snapshot(): TrackSnapshot
  local t = self:get()
  local snap: TrackSnapshot = {
    name = t.name,
    volume = t.volume,
    pan = t.pan,
    output = t.output,
    color = t.color,
    mute = t.mute,
    sends = t.sends,
    input = t.input,
    monitor = t.monitor,
    midi_input = t.midi_input,
    height = t.height,
    midi_output = t.midi_output,
    -- How its notes' articulations reach its instrument.
    attr_map = t.attr_map,
    -- What extensions keep with the track: a drum map, the group it is in.
    meta = next(t.meta or {}) and t.meta or nil,
    devices = {},
    clips = {},
    lanes = {},
  }
  local position: {integer: integer} = {}
  for i, device in ipairs(self:devices()) do
    position[device.id] = i
    snap.devices[i] = device:snapshot()
  end
  for i, clip in ipairs(self:clips()) do
    snap.clips[i] = clip:snapshot()
  end
  -- Its clips off the timeline, for cues (`paw.api.cue`), with their meta.
  for _, clip in ipairs(api.cue_list(self.id)) do
    snap.clips[#snap.clips + 1] = wrap(clip_mt, clip.id):snapshot()
  end
  for i, lane in ipairs(api.lane_list(self.id)) do
    snap.lanes[i] = {
      target = lane.target,
      device = lane.device and position[lane.device],
      param = lane.param,
      enabled = lane.enabled,
      points = api.lane_points(lane.id),
    }
  end
  return snap
end

--- Make a track from a snapshot, at a 1-based position in the track list.
function M.restore_track(snap: TrackSnapshot, index?: integer): Track
  local exists = function(id: integer): boolean return id ~= nil and (pcall(track_field, id, "id")) end
  local track = M.add_track(
    {
      name = snap.name,
      volume = snap.volume,
      pan = snap.pan,
      color = snap.color,
      index = index,
      -- What it fed may be gone by now; then it goes to the master.
      output = exists(snap.output) and snap.output or nil,
    }
  )
  local sends: {types.Send} = {}
  for _, send in ipairs(snap.sends or {}) do
    if exists(send.target) then
      sends[#sends + 1] = send
    end
  end
  if snap.mute then
    track.mute = true
  end
  if #sends > 0 then
    track.sends = sends
  end
  if snap.input then
    track.input = snap.input
  end
  if snap.monitor then
    track.monitor = true
  end
  if snap.midi_input then
    track.midi_input = snap.midi_input
  end
  if snap.midi_output then
    track.midi_output = snap.midi_output
  end
  if snap.attr_map then
    track.attr_map = snap.attr_map
  end
  if snap.height then
    api.track_set(track.id, {height = snap.height})
  end
  if snap.meta then
    api.track_set(track.id, {meta = snap.meta})
  end
  local devices: {Device} = {}
  for i, d in ipairs(snap.devices or {}) do
    devices[i] = M.restore_device(d, track)
  end
  for _, clip in ipairs(snap.clips or {}) do
    M.restore_clip(clip, track)
  end
  for _, lane in ipairs(snap.lanes or {}) do
    api.lane_add(
      track.id,
      {
        target = lane.target,
        device = lane.device and devices[lane.device].id,
        param = lane.param,
        enabled = lane.enabled,
        points = lane.points,
      }
    )
  end
  return track
end

--- Copy the track with its devices, clips and automation, and put the copy after it.
function Track:duplicate(): Track
  local snap = self:snapshot()
  snap.name = snap.name .. " copy"
  -- The tracks the original's output pairs play into stay the original's.
  for _, device in ipairs(snap.devices) do
    device.outputs = nil
  end
  return M.restore_track(snap, self.index + 1)
end

--- The automation lanes of the track, its devices' included.
function Track:lanes(): {Lane}
  local out: {Lane} = {}
  for i, lane in ipairs(api.lane_list(self.id)) do
    out[i] = wrap(lane_mt, lane.id)
  end
  return out
end

--- The lane for "volume" or "pan", if there is one.
function Track:lane(target: types.LaneTarget): Lane
  for _, lane in ipairs(api.lane_list(self.id)) do
    if lane.target == target then
      return wrap(lane_mt, lane.id)
    end
  end
end

--- The lane for "volume" or "pan", made if there is none yet.
---   track:automate("volume"):set_points({ { 0, -60 }, { 8, 0 } })
function Track:automate(target: types.LaneTarget): Lane
  return self:lane(target) or wrap(lane_mt, api.lane_add(self.id, {target = target}))
end

--- The value of "volume" or "pan" at a beat while the song plays. This is
--- the value of the lane when the lane is on. If not, it is the value of
--- the track.
function Track:value_at(target: types.LaneTarget, beat: number): number
  local lane = self:lane(target)
  local value = lane and lane.enabled and api.lane_value_at(lane.id, beat)
  if value then
    return value
  end
  return track_field(self.id, target) as number
end

-- Devices --------------------------------------------------------------------

class(
  device_mt,
  "Device",
  api.device_get as Get,
  function(id: integer, key: string, value: Value)
    if key == "sidechain" then
      value = id_of(value as integer | Track) as Value
    end
    if key == "outputs" and value is {string: Value} then
      local ids: {string: integer} = {}
      for pair, track in pairs(value as {integer | string: integer | Track}) do
        ids[tostring(pair)] = id_of(track)
      end
      value = next(ids) and ids as Value or nil
    end
    device_set(id, key, value)
  end
)

--- Everything about the device as plain data (`paw.api.device_get`).
function Device:get(): types.Device
  return api.device_get(self.id)
end

--- True if the device is still in the project.
function Device:exists(): boolean
  return (pcall(api.device_get, self.id))
end

--- Take the device off its track.
function Device:remove()
  api.device_remove(self.id)
end

--- The track this device is on.
function Device:track(): Track
  return wrap(track_mt, api.device_get(self.id).track)
end

--- Set one parameter, or several from a table.
---   device:set("cutoff", 800)
---   device:set({ cutoff = 800, resonance = 0.4 })
function Device:set(name: string | {string: number | string}, value?: number | string): Device
  if name is {string: number | string} then
    for k, v in pairs(name) do
      api.device_set_param(self.id, k, v)
    end
  else
    api.device_set_param(self.id, name, value)
  end
  return self
end

--- The description of this device: its name, category, format, and its
--- parameters with their ranges. A plugin's parameters are those of this
--- instance, which is the only place they are known.
function Device:info(): types.DeviceType
  local d = api.device_get(self.id)
  local info = api.device_find({kind = d.kind})
  if info then
    info.params = d.param_info
    return info
  end
end

--- The device as plain data, for `paw.restore_device`. For a plugin, the
--- data contains its state, which holds more than its parameters.
function Device:snapshot(): DeviceSnapshot
  local d = self:get()
  local state = api.device_state(self.id)
  -- What extensions keep with the device goes where the device goes.
  local meta = type(d.meta) == "table" and next(d.meta) and d.meta or nil
  return {
    kind = d.kind,
    bypass = d.bypass,
    state = state,
    params = not state and d.params or nil,
    meta = meta,
    sidechain = d.sidechain,
    sidechain_pre = d.sidechain_pre or nil,
    outputs = next(d.outputs or {}) and d.outputs or nil,
  }
end

--- Play the output pair `pair` of the device (2 and more: the first pair
--- plays on its own track) into a track, or nowhere with nil.
--- `device.outputs` is a table of pair number to track id.
--- `device.ports.outputs` names the pairs.
function Device:set_output(pair: integer, track?: integer | Track): Device
  paw.routes.set_output(self.id, pair, id_of(track))
  return self
end

--- Listen to the sound of a different track as the side-chain of the
--- device. With `comp:set_sidechain(kick)`, a compressor on the bass ducks
--- under the kick. `{ pre = true }` takes the sound before the fader, pan
--- and mute of that track. nil (or no track) removes the side-chain.
--- `device.sidechain` is the id of the track.
function Device:set_sidechain(track?: integer | Track, opts?: PreOptions): Device
  device_set(self.id, "sidechain", id_of(track) as Value)
  api.device_set(self.id, {sidechain_pre = track ~= nil and opts ~= nil and opts.pre == true})
  return self
end

--- Show the window of the plugin. `device.editor` is "open", "closed", or
--- nil for devices that have no window.
--- Start the device again: for a plugin that stopped (`stopped` tells why)
--- or did not load. It returns with the last state of it in the project.
function Device:restart()
  return api.device_restart(self.id)
end

--- Set the device offline, or online again. An offline device is not made
--- (a plugin has no process), and the chain passes over it. Its state and
--- parameters do not change.
function Device:set_offline(on?: boolean)
  api.device_set(self.id, {offline = on ~= false})
end

--- Show the plugin's own window.
function Device:open_editor(): boolean
  return api.device_editor(self.id, true)
end

--- Close the plugin's own window.
function Device:close_editor(): boolean
  return api.device_editor(self.id, false)
end

--- The key of a parameter given by key or by name.
local function param_key(d: types.Device, name: string): string
  for _, p in ipairs(d.param_info) do
    if p.key == name then
      return p.key
    end
  end
  for _, p in ipairs(d.param_info) do
    if p.name:lower() == tostring(name):lower() then
      return p.key
    end
  end
  return name
end

--- The automation lanes of the device's parameters, as `paw.Lane` objects.
function Device:lanes(): {Lane}
  local out: {Lane} = {}
  for _, lane in ipairs(api.lane_list(api.device_get(self.id).track)) do
    if lane.device == self.id then
      out[#out + 1] = wrap(lane_mt, lane.id)
    end
  end
  return out
end

--- The lane for a parameter, if there is one.
function Device:lane(param: string): Lane
  local d = api.device_get(self.id)
  local key = param_key(d, param)
  for _, lane in ipairs(api.lane_list(d.track)) do
    if lane.device == self.id and lane.param == key then
      return wrap(lane_mt, lane.id)
    end
  end
end

--- The lane for a parameter, made if there is none yet.
---   synth:automate("cutoff"):add(0, 200)
function Device:automate(param: string): Lane
  return self:lane(param)
    or wrap(lane_mt, api.lane_add(api.device_get(self.id).track, {target = "param", device = self.id, param = param}))
end

--- The device's state lane, if it has one.
function Device:state_lane(): Lane
  local d = api.device_get(self.id)
  for _, lane in ipairs(api.lane_list(d.track)) do
    if lane.target == "state" and lane.device == self.id then
      return wrap(lane_mt, lane.id)
    end
  end
end

--- The device's state lane, made if there is none yet: a lane whose points
--- each give the device one of the lane's states, from that point on.
---   local lane = amp:automate_state()
---   lane:set_state(16, lane:add_state(amp:capture("crunch")))
function Device:automate_state(): Lane
  return self:state_lane()
    or wrap(lane_mt, api.lane_add(api.device_get(self.id).track, {target = "state", device = self.id}))
end

--- The device's whole state now, as a state lane takes it: `{ name, state,
--- params }`. The plugin's saved state, and the parameters set in the project.
function Device:capture(name?: string): types.LaneState
  local d = api.device_get(self.id)
  local params: {string: number} = {}
  for key, value in pairs(d.params or {}) do
    params[key] = value
  end
  local state = api.device_state(self.id)
  if not state and next(params) == nil then
    error("the device keeps no state: give the lane `params` or a `program`", 2)
  end
  return {name = name or (d.meta or {}).preset as string or d.name, state = state, params = params}
end

--- The value of a parameter at a beat while the song plays. This is the
--- value of the lane when the lane is on. If not, it is the value of the device.
function Device:value_at(param: string, beat: number): number
  local lane = self:lane(param)
  local value = lane and lane.enabled and api.lane_value_at(lane.id, beat)
  if value then
    return value
  end
  local d = api.device_get(self.id)
  return d.params[param_key(d, param)]
end

--- Move within the chain, or to another track: `device:move(1)`, `device:move(2, other)`.
function Device:move(index: integer, track?: integer | Track)
  api.device_move(self.id, id_of(track) or api.device_get(self.id).track, index)
end

-- Clips ----------------------------------------------------------------------

class(
  clip_mt,
  "Clip",
  api.clip_get as Get,
  function(id: integer, key: string, value: Value)
    if key == "track" then
      value = id_of(value as integer | Track) as Value
    end
    clip_set(id, key, value)
  end
)

--- Everything about the clip as plain data (`paw.api.clip_get`).
function Clip:get(): types.Clip
  return api.clip_get(self.id)
end

--- True if the clip is still in the project.
function Clip:exists(): boolean
  return (pcall(api.clip_get, self.id))
end

--- Take the clip out of its track.
function Clip:remove()
  api.clip_remove(self.id)
end

--- The track the clip is on.
function Clip:track(): Track
  return wrap(track_mt, api.clip_get(self.id).track)
end

--- The notes of a MIDI clip: a list of { pitch, start, length, velocity }.
--- `start` is in beats from the start of the clip. A note can have `meta`,
--- a table of extension data such as a lyric. A note can also have `attr`,
--- the MIDI 2.0 attribute of its note-on (`{ type, data }`, see `paw.attr`).
---
--- With a range, only the notes that sound in it. The second value is then
--- the place of each note in the whole list, for `set_note` and `remove_note`:
---   local notes, at = clip:notes({ from = 4, to = 8, low = "C3", high = "C5" })
function Clip:notes(range?: NoteRangeInput): {types.Note}, {integer}
  if range and (range.low or range.high) then
    range = util.merge(
      range as {string: Value},
      {low = range.low and music.pitch(range.low) as Value, high = range.high and music.pitch(range.high) as Value}
    ) as NoteRangeInput
  end
  return api.clip_notes(self.id, range as types.NoteRange)
end

--- The note on a pitch that sounds at a beat of the clip, and its place in
--- the notes of the clip. Nothing when there is no such note.
function Clip:note_at(pitch: Pitch, beat: number): types.Note, integer
  return api.clip_note_at(self.id, music.pitch(pitch), beat)
end

-- A change of a note with its `pitch` as a MIDI number.
local function note_change(change: NoteChangeInput): types.NoteChange
  if change.pitch then
    return util.merge(change as {string: Value}, {pitch = music.pitch(change.pitch) as Value}) as types.NoteChange
  end
  return change as types.NoteChange
end

--- Change one note, by its place in the notes of the clip (from 1). The
--- other notes do not change: `clip:set_note(3, { length = 2 })`. Returns
--- the new place of the note, because notes stay in the order of their
--- start. `attr = false` removes its attribute.
function Clip:set_note(index: integer, fields: NoteChangeInput): integer
  return api.clip_note_set(self.id, index, note_change(fields))
end

--- Remove the note at a place among the clip's notes (from 1).
function Clip:remove_note(index: integer)
  api.clip_note_remove(self.id, index)
end

--- Change, remove and add several notes as one edit. Every index is a
--- note's place before the call:
---   clip:edit_notes({ set = { { index = 3, start = 1 } }, remove = { 5, 6 }, add = { note } })
function Clip:edit_notes(edit: NotesEditInput)
  local set: {types.NoteChange} = {}
  for i, change in ipairs(edit.set or {}) do
    set[i] = note_change(change)
  end
  api.clip_notes_edit(self.id, {set = set, remove = edit.remove or {}, add = M.notes(edit.add or {})})
end

--- The waveform of an audio clip: `n` { min, max, rms } entries. Each entry
--- covers an equal part of the sound of the clip, scaled by its gain. It
--- gives how far the wave goes each way (-1 to 1) and how loud it is there.
--- paw keeps the result, so the code that draws can ask for it each frame.
function Clip:peaks(n: integer): {types.Peak}
  return api.clip_peaks(self.id, n)
end

--- Replace every note of the clip with `notes` (as `add_note` takes each).
function Clip:set_notes(notes: {NoteInput})
  api.clip_set_notes(self.id, M.notes(notes))
end

--- The events of the clip that are not notes: controller moves, the pitch
--- wheel, pressure and program changes. Each is `{ start, type, value }`,
--- with `start` in beats from the start of the clip. `type` is "cc" (with
--- `number`), "bend" (-1 to 1), "pressure", "registered" or "assignable"
--- (with `bank` and `index`), or "program" (with `program` and maybe
--- `bank`). Values go from 0 to 1 at any resolution. With `key`, a move is
--- for the note on that key only, as in MIDI 2.0: its own bend, pressure
--- or controller.
function Clip:controls(): {types.Control}
  return api.clip_controls(self.id)
end

---   clip:set_controls({ { start = 0, type = "cc", number = 64, value = 1 },
---                       { start = 1, type = "bend", key = "E4", value = 0.02 } })
function Clip:set_controls(controls: {ControlInput})
  local out: {types.Control} = {}
  for i, c in ipairs(controls) do
    out[i] = c.key and util.merge(c as {string: Value}, {key = music.pitch(c.key) as Value}) as types.Control
      or c as types.Control
  end
  api.clip_set_controls(self.id, out)
end

--- Add several notes as one edit (as `add_note` takes each).
function Clip:add_notes(notes: {NoteInput})
  api.clip_add_notes(self.id, M.notes(notes))
end

---   clip:add_note({ pitch = "E4", start = 1, length = 0.5, velocity = 90 })
---   clip:add_note({ pitch = "G4", start = 2, attr = paw.attr.m2("11.A") })   -- pizzicato
--- Returns the note's place among the clip's notes.
function Clip:add_note(note: NoteInput): integer
  return api.clip_note_add(self.id, M.notes({note})[1])
end

--- The clip as plain data, for `paw.restore_clip`.
function Clip:snapshot(): ClipSnapshot
  local c = self:get()
  local snap: ClipSnapshot = {
    name = c.name,
    start = c.start,
    length = c.length,
    kind = c.kind,
    muted = c.muted,
    file = c.file,
    offset = c.offset,
    gain = c.gain,
    fade_in = c.fade_in,
    fade_out = c.fade_out,
    -- How it plays: an audio clip's timebase, stretch and shift; looping.
    timebase = c.timebase,
    stretch = c.stretch,
    pitch = c.pitch,
    stretch_mode = c.stretch_mode,
    source_tempo = c.source_tempo,
    loop = c.loop or nil,
    loop_length = c.loop_length,
    loop_start = c.loop_start,
    warp = paw.stretch.markers(c),
    formants = c.formants or nil,
    -- What extensions keep with the clip goes where the clip goes.
    meta = next(c.meta) and c.meta or nil,
    -- A clip off the timeline, played only when cued.
    cue = c.cue or nil,
  }
  if c.kind == "midi" then
    snap.notes = self:notes()
    if c.control_count > 0 then
      snap.controls = self:controls()
    end
  end
  return snap
end

--- Copy the clip. By default the copy goes right after the original.
function Clip:duplicate(opts?: M.DuplicateOptions): Clip
  opts = opts or {}
  local snap = self:snapshot()
  snap.start = opts.start or (snap.start + snap.length)
  local track: integer | Track = opts.track
  if not track then
    track = self:track()
  end
  return M.restore_clip(snap, track)
end

-- Automation lanes -------------------------------------------------------------
-- Fields: `target` ("volume", "pan", "param" or "state"), `device` and
-- `param` for a parameter, `device` and `states` (their names) for a state
-- lane, `enabled`, `point_count`, `min` and `max`, `track`.

class(lane_mt, "Lane", api.lane_get as Get, lane_set)

--- Everything about the lane as plain data (`paw.api.lane_get`).
function Lane:get(): types.Lane
  return api.lane_get(self.id)
end

--- True if the lane is still in the project.
function Lane:exists(): boolean
  return (pcall(api.lane_get, self.id))
end

--- Take the lane away, and the automation in it.
function Lane:remove()
  api.lane_remove(self.id)
end

--- The track the lane belongs to.
function Lane:track(): Track
  return wrap(track_mt, api.lane_get(self.id).track)
end

--- The points as a list of { beat, value }, sorted by beat.
function Lane:points(): {types.LanePoint}
  return api.lane_points(self.id)
end

--- Replace the points: `lane:set_points({ { 0, -60 }, { 8, 0 } })`. Points may
--- also be written { beat = 0, value = -60 }.
function Lane:set_points(points: {PointInput})
  api.lane_set_points(self.id, M.points(points))
end

--- Add a point. It replaces a point at the same beat. The value is in the
--- units of the target: dB for volume and -1 to 1 for pan. For a parameter,
--- it is in the range of the parameter.
function Lane:add(beat: number, value: number)
  api.lane_add_point(self.id, beat, value)
end

--- Remove every point of the lane.
function Lane:clear()
  api.lane_set_points(self.id, {})
end

--- The value at a beat, when the lane is on and when it is off. Nil without points.
function Lane:value_at(beat: number): number
  return api.lane_value_at(self.id, beat)
end

--- The states of a state lane: `{ name, state, params, call, program, bank }` each.
function Lane:states(): {types.LaneState}
  return api.lane_states(self.id)
end

--- Add a state to a state lane, or replace the one of its name. Returns
--- its index, from 0: the value of a point that gives it.
function Lane:add_state(state: types.LaneState): integer
  return api.lane_add_state(self.id, state)
end

--- The index of a state of a state lane, by its name or its index. Nil
--- when the lane has no such state.
function Lane:state_index(which: number | string): integer
  local states = api.lane_states(self.id)
  if which is number then
    return states[which as integer + 1] and which as integer or nil
  end
  for i, s in ipairs(states) do
    if s.name == which then
      return i - 1
    end
  end
  local lower = tostring(which):lower()
  for i, s in ipairs(states) do
    if s.name:lower():find(lower, 1, true) then
      return i - 1
    end
  end
end

--- Give the device a state of a state lane from `beat` on: a point that
--- names the state by its name or its index.
---   lane:set_state(16, "crunch")
function Lane:set_state(beat: number, which: number | string)
  local index = self:state_index(which)
  if not index then
    error("the lane has no state `" .. tostring(which) .. "`", 2)
  end
  api.lane_add_point(self.id, beat, index)
end

-- Module ---------------------------------------------------------------------

--- Normalize automation points to { beat, value } pairs.
function M.points(points: {PointInput}): {types.LanePoint}
  local out: {types.LanePoint} = {}
  for i, p in ipairs(points) do
    out[i] = {p.beat or p[1], p.value or p[2]}
  end
  return out
end

--- Normalize notes: accept pitch names and fill in defaults.
function M.notes(notes: {NoteInput}): {types.Note}
  local out: {types.Note} = {}
  for i, note in ipairs(notes) do
    out[i] = {
      pitch = music.pitch(note.pitch or note[1]),
      start = note.start or note[2] as number or 0,
      length = note.length or note[3] as number or 1,
      velocity = note.velocity or note[4] as integer or options.opt.velocity,
      meta = note.meta,
      attr = note.attr,
      -- A note given back keeps its name (`paw.address`); a new one gets one.
      id = note.id,
    }
  end
  return out
end

--- Add a clip from a snapshot to a track.
function M.restore_clip(snap: ClipSnapshot, track: integer | Track): Clip
  local opts = util.merge(snap as {string: Value}, {}) as ClipSnapshot
  opts.muted = nil
  local clip = wrap(clip_mt, api.clip_add(id_of(track), opts as types.ClipOptions))
  if snap.muted then
    clip.muted = true
  end
  return clip
end

--- Add a device from a snapshot to a track, at the end of the chain or at
--- the 1-based `index`.
function M.restore_device(snap: DeviceSnapshot, track: integer | Track, index?: integer): Device
  local device = wrap(
    device_mt,
    api.device_add(
      id_of(track),
      snap.kind,
      {
        params = snap.params,
        state = snap.state,
        index = index,
      }
    )
  )
  if snap.bypass then
    device.bypass = true
  end
  if snap.meta then
    api.device_set(device.id, {meta = snap.meta})
  end
  -- The track it listened to is kept while it exists and can still be
  -- listened to from here; otherwise the side-chain is dropped, and said so.
  if snap.sidechain then
    local ok = pcall(device.set_sidechain, device, snap.sidechain, {pre = snap.sidechain_pre})
    if not ok then
      paw.notify(
        string.format(
          "%s no longer has its side-chain: track %s is gone or would make a loop",
          device.name,
          tostring(snap.sidechain)
        ),
        "warn"
      )
    end
  end
  -- So are the tracks its further output pairs played into.
  for pair, track_id in pairs(snap.outputs or {}) do
    if not pcall(device.set_output, device, tonumber(pair) as integer, track_id) then
      paw.notify(
        string.format(
          "%s output pair %s no longer plays anywhere: track %s is gone or would make a loop",
          device.name,
          tostring(pair),
          tostring(track_id)
        ),
        "warn"
      )
    end
  end
  return device
end

--- A new track, last unless `opts.index` says where: `opts` as `paw.api.track_add`
--- takes them (`name`, `volume`, `output` as a track or an id, ...). In a
--- window inside a subproject, the track is made in that subproject unless
--- `opts.nest` says another.
function M.add_track(opts?: M.TrackInput): Track
  if opts and opts.output then
    opts = util.merge(opts as {string: Value}, {output = id_of(opts.output) as Value}) as M.TrackInput
  end
  local inside = paw.scope and paw.scope.nest()
  if inside and not (opts and opts.nest) then
    opts = util.merge((opts or {}) as {string: Value}, {nest = inside.id as Value}) as M.TrackInput
  end
  return wrap(track_mt, api.track_add(opts as types.TrackOptions))
end

--- Every track, in order, as `paw.Track` objects (the master is `paw.master`).
function M.tracks(): {Track}
  local out: {Track} = {}
  for i, id in ipairs(api.track_list()) do
    out[i] = wrap(track_mt, id)
  end
  return out
end

--- A track by id, or by name.
function M.track(which: number | string): Track
  if which is number then
    return wrap(track_mt, which as integer)
  end
  for _, id in ipairs(api.track_list()) do
    if track_field(id, "name") as string == which then
      return wrap(track_mt, id)
    end
  end
end

--- The device, clip or automation lane of an id, as an object.
function M.device(id: integer): Device
  return wrap(device_mt, id)
end
--- The clip of an id, as a `paw.Clip`.
function M.clip(id: integer): Clip
  return wrap(clip_mt, id)
end
--- The automation lane of an id, as a `paw.Lane`.
function M.lane(id: integer): Lane
  return wrap(lane_mt, id)
end

M.master = wrap(track_mt, 0)

-- Fields set before the table has its metatable: the project's own setter
-- takes only settings.
local discarding = false

-- `paw.project.tempo = 140`, `paw.project.save("song")`
local project: M.Project = {
  new = api.project_new,
  load = api.project_load,
  save = api.project_save,
  get = api.project_get,
}
M.project = project
local project_field = api.project_get as function(key: string): Value
local project_set = api.project_set as function(key: string, value: Value)
setmetatable(
  project,
  {
    __index = function(_: M.Project, key: string): Value return project_field(key) end,
    __newindex = function(_: M.Project, key: string, value: Value) project_set(key, value) end,
  } as metatable<M.Project>
)

-- `paw.transport.play()`, `paw.transport.position`, `paw.transport.loop_enabled = true`
local transport: M.Transport = {
  play = api.transport_play,
  stop = function() paw.ui.poke(); api.transport_stop() end,
  --- Turn recording on and play. Each armed track records a take until the
  --- transport stops or `recording` is turned off.
  record = function() paw.ui.poke(); api.transport_record() end,
  --- Put the playhead at a beat. While the song is stopped, play starts
  --- from there until the cursor moves (`paw.opt.play_from`).
  seek = function(beats: number) api.transport_seek(beats); events.emit("playhead.placed") end,
  get = api.transport_get,
  toggle = function()
    if api.transport_get().playing then
      M.transport.stop()
    else
      api.transport_play()
    end
  end,
}
M.transport = transport
local transport_set = api.transport_set as function(key: string, value: Value)
setmetatable(
  transport,
  {
    __index = function(_: M.Transport, key: string): Value return (api.transport_get() as {string: Value})[key] end,
    __newindex = function(_: M.Transport, key: string, value: Value)
      if key == "position" then
        M.transport.seek(value as number)
      elseif key == "tempo" then
        api.project_set({tempo = value as number})
      else
        transport_set(key, value)
      end
    end,
  } as metatable<M.Transport>
)

--- Whether replacing the project now would lose work: it has changes that
--- are not saved, or it has no file and something in it. A project opened
--- from a MIDI file or a REAPER project has no changes to count, but it is
--- not on disk either, and this is every guard's one question.
rawset(
  project as {string: Value},
  "unsaved",
  function(): boolean local p = api.project_get(); return p.modified or (p.path == nil and #api.track_list() > 0) end
    as Value
)

--- Whether `path` is a project kept as a folder: a folder with a
--- `project.toml`, or that file.
rawset(
  project as {string: Value},
  "is_folder",
  function(path: string): boolean
    path = tostring(path):gsub("/+$", "")
    if path:match("project%.toml$") then
      return true
    end
    local f = io.open(path .. "/project.toml", "rb")
    if f then
      f:close()
    end
    return f ~= nil
  end as Value
)

--- Save the project as `:w` does, always as a folder: `path`, or its
--- file when nil. A path that ends in `.json` names the folder of the
--- same name without `.json`, because one JSON file is only the form of
--- paw's safety copies and undo states. Returns the path saved, and a
--- note that tells where the project went when that is not `path`.
rawset(
  project as {string: Value},
  "write",
  function(path?: string): string, string
    local target = path or api.project_get().path
    local stem = target is string and target:match("^(.+)%.[jJ][sS][oO][nN]$")
    if not stem then
      return M.project.save(path)
    end
    local saved = M.project.save(stem)
    local name = target:match("([^/]+)$") or target
    local folder = stem:match("([^/]+)$") or stem
    local note = path and string.format("a project is a folder: saved it in %s/, not in %s", folder, name)
      or string.format("a project is a folder: saved it in %s/ (%s stays as it was)", folder, name)
    return saved, note
  end as Value
)

--- Whether the project may be replaced: says why not, naming `what` (the
--- command, whose `!` form goes on anyway), when there is unsaved work.
--- `force` is for a choice made later from a list, which asked before.
rawset(
  project as {string: Value},
  "guard",
  function(what: string, force?: boolean): boolean
    if force or discarding or not M.project.unsaved() then
      return true
    end
    paw.notify(string.format("the project has unsaved work: `:w` saves it, `:%s!` goes on without it", what), "error")
    return false
  end as Value
)

--- Whether a `!` command is running, for a choice made later from a list.
rawset(project as {string: Value}, "discarding", function(): boolean return discarding end as Value)

--- Define `<name>!`, which is `name` with the unsaved work thrown away.
rawset(
  project as {string: Value},
  "allow_discard",
  function(name: string)
    local spec = paw.commands.get(name)
    paw.command(
      name .. "!",
      function(ctx: Value)
        discarding = true
        local ok, err = pcall(paw.commands.get(name).run, ctx)
        discarding = false
        if not ok then
          error(err, 0)
        end
      end,
      {
        desc = (spec.desc:gsub("%.$", "")) .. "; the unsaved work is thrown away",
        raw = spec.raw,
        complete = spec.complete,
      }
    )
  end as Value
)

-- MIDI input -----------------------------------------------------------------

-- `paw.midi.inputs()`, `paw.midi.select({ "Keystation" })`, `paw.midi.note_on("C4", 100)`
M.midi = {
  --- Every port that can send MIDI: { id, name, open, own }.
  inputs = api.midi_inputs,
  --- A port of this program's for other programs to send MIDI to: they see
  --- it as `paw: <name>`, it is listed among the inputs with `own` set, and
  --- a track takes it by `name` like any other port. `close_port` takes it
  --- away, and says whether there was one.
  open_port = api.midi_open_port,
  close_port = api.midi_close_port,
  --- Open only the ports matching these ids or parts of names, or all of
  --- them with no argument.
  select = function(which?: string | {string})
    if which is string then
      which = {which}
    end
    api.midi_select(which as {string})
  end,
  --- Deliver an event as if it came from a MIDI port:
  --- `{ type = "note_on", pitch = "C4", velocity = 100, channel = 1 }`, or
  --- a controller move as `Clip:controls` describes them. What arrives,
  --- from here or from a port, is also the event `midi.in` for scripts.
  inject = function(event: MidiEventInput) api.midi_inject(midi_event(event)) end,
  --- An event as a MIDI 2.0 packet: two 32-bit words. And the other way:
  --- deliver a Universal MIDI Packet (MIDI 1.0 or 2.0) as if from a port.
  ump = function(event: MidiEventInput): {integer} return api.midi_ump(midi_event(event)) end,
  inject_ump = api.midi_inject_ump,
  --- The ports MIDI can be sent to, `{ id, name, own }` each: a track
  --- sends what it plays to one with `track.midi_output = { port = name,
  --- channel = 1 }` (channel nil: each message's own).
  outputs = api.midi_outputs,
  --- A port of this program's that other programs read from (`paw out:
  --- <name>`): a track sending to `name` plays a synth in another program.
  open_output = api.midi_open_output,
  close_output = api.midi_close_output,
}

function M.midi.note_on(pitch: Pitch, velocity?: number, channel?: integer)
  M.midi.inject({type = "note_on", pitch = pitch, velocity = velocity, channel = channel})
end

function M.midi.note_off(pitch: Pitch, channel?: integer)
  M.midi.inject({type = "note_off", pitch = pitch, channel = channel})
end

-- Musical time ---------------------------------------------------------------

local time: M.Time = {}
M.time = time

-- These ask the tempo map (`paw.tempo`): bars follow the signature changes
-- along the song and seconds follow the tempo changes.

--- Length in beats of the bar at beat `at` (the first bar if left out).
function time.bar(at?: number): number
  return api.tempo_bar_length(at or 0)
end

--- Beat where bar `n` (1-based) starts.
function time.bar_start(n: integer): number
  return api.tempo_bar_start(n - 1)
end

--- The signature (two numbers) and the tempo at a beat, as `paw.tempo` has them.
function time.signature_at(beat?: number): integer, integer
  return api.tempo_signature(beat or 0)
end
function time.tempo_at(beat?: number): number
  return api.tempo_at(beat or 0)
end

--- The bar (1-based) a beat is in.
function time.bar_of(beat: number): integer
  return api.tempo_bar_of(beat) + 1
end

--- Where the bar a beat is in starts.
function time.bar_floor(beat: number): number
  return api.tempo_bar_start(api.tempo_bar_of(beat))
end

--- The first bar line at or after a beat.
function time.bar_ceil(beat: number): number
  local bar = api.tempo_bar_of(beat)
  local start = api.tempo_bar_start(bar)
  -- The bar of a beat a hair before a bar line can be the bar after the
  -- line (the kernel rounds): its start is then the line asked for, not
  -- a bar before the next one.
  if start >= beat - 1e-12 then
    return start
  end
  return api.tempo_bar_start(bar + 1)
end

--- The bar lines from beat `from` up to `to`: { beat, bar } each, bars
--- counting from 1.
function time.bars(from: number, to: number): {BarLine}
  local out: {BarLine} = {}
  local bar = api.tempo_bar_of(math.max(0, from))
  if api.tempo_bar_start(bar) < from - 1e-9 then
    bar = bar + 1
  end
  while #out < 10000 do
    local beat = api.tempo_bar_start(bar)
    if beat >= to then
      break
    end
    out[#out + 1] = {beat = beat, bar = bar + 1}
    bar = bar + 1
  end
  return out
end

--- "bar.beat.hundredths" for a position in beats, counting from 1; beats
--- are of the signature's unit (an eighth in 6/8).
function time.format(beats: number): string
  local bar, beat, frac = api.tempo_bbt(beats)
  local part = math.floor(frac * 100 + 0.5)
  if part >= 100 then
    part = 99
  end
  return string.format("%d.%d.%02d", bar + 1, beat + 1, part)
end

--- Seconds that `beats` beats take from beat `at` (the start if left out).
function time.seconds(beats: number, at?: number): number
  at = at or 0
  return api.tempo_seconds(at + beats) - api.tempo_seconds(at)
end

--- Seconds from the start of the song to beat `beat`, and back.
function time.to_seconds(beat: number): number
  return api.tempo_seconds(beat)
end
function time.to_beat(seconds: number): number
  return api.tempo_beat(seconds)
end

--- "m:ss.s" for a beat's time from the start of the song.
function time.clock(beat: number): string
  local seconds = api.tempo_seconds(beat)
  return string.format("%d:%04.1f", math.floor(seconds / 60), seconds % 60)
end

return M
