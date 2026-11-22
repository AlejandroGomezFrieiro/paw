-- The shapes of the data that crosses `paw.api`, for the modules written in
-- Teal and for runtime/types/paw.d.tl, which names them as `types.Name` in
-- the kernel's signatures (`// @param` and `// @return` in api.rs and the
-- other files that add to `paw.api`).
--
--   local type types = require("paw.types")
--   local attr: types.NoteAttr = { type = 0x11, data = 0xA000 }
--
-- It holds types only: at run time it is an empty table. Each record is
-- what the Rust code that builds or reads the table has: the comment over
-- it names that code. A field can be nil, as in every Teal record: a view
-- leaves out what does not apply.

local type role_props = require("paw.role_props")

local record types
  --- How `paw.api.base64_encode` writes: `url` for the URL alphabet (`-_`),
  --- `pad = false` for no `=` at the end.
  record Base64Options
    url: boolean
    pad: boolean
  end

  --- The MIDI 2.0 attribute of a note's start (`paw.attr`): its type, and
  --- sixteen bits of data.
  record NoteAttr
    type: integer
    data: integer
  end

  --- What an extension keeps in `meta` (of the project, a track, a clip, a
  --- device or a note): the extension's own data, any JSON value by name.
  --- The kernel keeps it and does not look in it.
  type Meta = {string: any}

  -- Notes and controllers (model.rs) --------------------------------------

  --- A note of a MIDI clip (`model::Note`, `api.rs` `note_to_lua`). `start`
  --- in beats from the clip's start, `pitch` 0 to 127, `velocity` 1 to 127
  --- (100 when left out), `id` its name in the clip (0 or nil: none yet).
  record Note
    start: number
    length: number
    pitch: integer
    velocity: integer
    id: integer
    meta: Meta
    attr: NoteAttr
  end

  --- What to change about a note (`session/notes.rs` `NoteChange`): what is
  --- left out stays. `attr = false` takes the attribute away. `index` only in
  --- `NotesEdit.set`.
  record NoteChange
    index: integer
    start: number
    length: number
    pitch: integer
    velocity: integer
    meta: Meta
    attr: NoteAttr | boolean
  end

  --- Several changes to one clip's notes, as one edit (`NotesEdit`): every
  --- index is a note's place before the call, from 1.
  record NotesEdit
    set: {NoteChange}
    remove: {integer}
    add: {Note}
  end

  --- Which notes `clip_notes` gives (`NoteRange`): beats in the clip and
  --- pitches, both ends included; what is left out is open.
  record NoteRange
    from: number
    to: number
    low: integer
    high: integer
  end

  enum ControlType
    "cc"
    "bend"
    "pressure"
    "registered"
    "assignable"
    "program"
  end

  --- A controller move of a MIDI clip (`model::Control`): `start` in beats,
  --- `value` 0 to 1 (-1 to 1 for `bend`), `key` for a note's own controller.
  --- `number` for `cc`; `bank` and `index` for `registered` and
  --- `assignable`; `program` and `bank` for `program`.
  record Control
    start: number
    type: ControlType
    value: number
    key: integer
    number: integer
    bank: integer
    index: integer
    program: integer
  end

  enum MidiEventType
    "note_on"
    "note_off"
    "cc"
    "bend"
    "pressure"
    "registered"
    "assignable"
    "program"
  end

  --- A MIDI message from a script (`api.rs` `midi_kind`): a note
  --- (`note_on`, `note_off` with `pitch`, `velocity` 0 to 127 and `attr`),
  --- or a controller move as a clip keeps them (see `Control`), on
  --- `channel` 1 to 16 (1 when left out). `port` only for `midi_inject`.
  record MidiEvent
    type: MidiEventType
    channel: integer
    pitch: integer
    velocity: number
    attr: NoteAttr
    value: number
    key: integer
    number: integer
    bank: integer
    index: integer
    program: integer
    port: string
    --- In a `midi.in` event: true when tracks do not get it
    --- (`engine_midi_filter`).
    filtered: boolean
  end

  --- A control of MIDI input that tracks do not get
  --- (`session/midi_in.rs` `FilterRule`): a key (`note`) or a controller
  --- (`cc`), 0 to 127, from the port of that name (every port when left
  --- out), on `channel` 1 to 16 (every channel when left out).
  record MidiFilterRule
    port: string
    channel: integer
    note: integer
    cc: integer
  end

  -- The project and its tracks (session/project.rs, session/tracks.rs) -----

  --- A tempo change of the project file (`model::TempoChange`).
  record TempoChange
    beat: number
    bpm: number
    ramp: boolean
  end

  --- A time signature of the project file (`model::SigChange`).
  record SigChange
    beat: number
    num: integer
    den: integer
  end

  --- `paw.api.project_get()` (`Session::project_view`). `edits` goes up
  --- with each change; `length` is the end of the last clip, in beats.
  record Project
    name: string
    tempo: number
    sig_num: integer
    sig_den: integer
    tempo_ramp: boolean
    tempo_changes: {TempoChange}
    sig_changes: {SigChange}
    key: string
    path: string
    length: number
    meta: Meta
    modified: boolean
    edits: integer
  end

  --- A send of a track (`model::Send`): to the track `target`, `level` in
  --- dB, `pre` before the fader.
  record Send
    target: integer
    level: number
    pre: boolean
  end

  --- The MIDI a track plays when armed (`model::MidiInput`): nil fields
  --- mean every port, every channel (1 to 16).
  record MidiInput
    port: string
    channel: integer
  end

  enum MidiOutForm
    "auto"
    "plain"
    "mpe"
    "cc14"
  end

  --- Where a track sends MIDI (`model::MidiOutput`).
  record MidiOutput
    port: string
    channel: integer
    form: MidiOutForm
    members: integer
  end

  enum AutoMode
    "read"
    "touch"
    "latch"
    "write"
    "off"
  end

  --- One articulation of an attribute map (`attr_map::Art`), as a table;
  --- the map takes the `out` line alone too.
  record AttrArt
    out: string
    delay: number
  end

  enum AttrSend
    "change"
    "every"
  end

  --- A track's attribute map (`attr_map::AttrMap`, see attr_map.rs). As
  --- the kernel gives it, the keys of `by_type` are numbers written as text.
  record AttrMap
    send: AttrSend
    chase: {integer}
    default: string | AttrArt
    arts: {string: string | AttrArt}
    by_type: {string: string | AttrArt}
    attribute: boolean
    delay: number
  end

  --- `paw.api.track_get(id)` (`Session::track_view`). `volume` in dB, `pan`
  --- -1 to 1, `output` the track it feeds (nil for the master), `index`
  --- from 1. `devices` and `clips` are ids.
  record Track
    id: integer
    name: string
    volume: number
    pan: number
    mute: boolean
    solo: boolean
    armed: boolean
    output: integer
    sends: {Send}
    devices: {integer}
    clips: {integer}
    color: string
    meta: Meta
    index: integer
    master: boolean
    input: string
    monitor: boolean
    midi_input: MidiInput
    midi_output: MidiOutput
    height: number
    automation: AutoMode
    attr_map: AttrMap
    listens: {integer}
    pairs_into: {integer}
    source: string
    origin: string
    chain_source: string
    chain_origin: string
  end

  --- What `paw.api.track_add` takes (`TrackOpts`): `index` from 1.
  record TrackOptions
    name: string
    index: integer
    volume: number
    pan: number
    output: integer
    color: string
  end

  --- A file of a project kept in a folder (`Session::project_files`).
  record ProjectFile
    path: string
    modified: boolean
    what: string
    track: integer
    clip: integer
  end

  --- How `paw.api.project_load` and `project_recover` open a project
  --- (`OpenOpts`): devices offline. `as_path` only for `project_recover`.
  record OpenOptions
    plugins_offline: boolean
    offline: {integer}
    as_path: string
  end

  -- Devices (session/devices.rs) ---------------------------------------------

  enum ParamKind
    "boolean"
    "enum"
    "stepped"
    "continuous"
  end

  --- A parameter of a device (`session.rs` `param_json`). In a device's
  --- `param_info` it has `index` (from 1) and `automated`; from
  --- `device_param` it has `value` and `text` too.
  record ParamInfo
    key: string
    id: string
    name: string
    group: string
    min: number
    max: number
    default: number
    unit: string
    choices: {string}
    kind: ParamKind
    steps: integer
    automatable: boolean
    read_only: boolean
    per_note: boolean
    index: integer
    automated: boolean
    value: number
    text: string
  end

  --- A kind of device installed (`devices.rs` `type_json`).
  record DeviceType
    kind: string
    name: string
    category: string
    format: string
    vendor: string
    params: {ParamInfo}
    id: string
    version: string
    features: {string}
  end

  --- What `paw.api.device_find` looks for: each part optional.
  record DeviceQuery
    kind: string
    format: string
    id: string
    name: string
    vendor: string
  end

  --- The plugin a device is, as its format names it.
  record DevicePlugin
    format: string
    id: string
    name: string
    vendor: string
    version: string
  end

  --- What a running device takes and gives besides its main pair
  --- (`ports::ports_json`): the names of its output pairs.
  record DevicePorts
    sidechain: boolean
    outputs: {string}
  end

  enum DeviceStatus
    "running"
    "loading"
    "stopped"
    "offline"
    "missing"
  end

  enum EditorState
    "open"
    "closed"
  end

  --- `paw.api.device_get(id)` (`Session::device_view`). `params` is each
  --- parameter's value now by key, `overrides` what the project sets.
  --- `outputs` maps a pair number (as text) to a track.
  record Device
    plugin: DevicePlugin
    id: integer
    kind: string
    name: string
    offline: boolean
    format: string
    track: integer
    index: integer
    bypass: boolean
    params: {string: number}
    overrides: {string: number}
    param_info: {ParamInfo}
    meta: Meta
    editor: EditorState
    missing: boolean
    stopped: string
    status: DeviceStatus
    sidechain: integer
    sidechain_pre: boolean
    outputs: {string: integer}
    ports: DevicePorts
  end

  --- What `paw.api.device_add` takes (`DeviceOpts`): `index` from 1.
  record DeviceOptions
    index: integer
    params: {string: number}
    state: string
  end

  --- A request to a device, as `paw.api.device_call` makes it.
  record DeviceCallData
    method: string
    data: string
  end

  --- A preset for `paw.api.device_load` (`PresetLoad`).
  record PresetLoad
    name: string
    state: string
    params: {string: number}
    factory: string
    call: DeviceCallData
  end

  --- A device that refused data of `device_post`.
  record DeviceRefusal
    device: integer
    error: string
  end

  --- What `plugins_add_dir` found: device kinds, and notes on the files
  --- that paw cannot use.
  record PluginDir
    kinds: {string}
    notes: {string}
  end

  -- Clips (session/clips.rs, session.rs clip_json) ---------------------------

  --- `midi`, `audio`, or the name of a kind that an extension defines.
  type ClipKind = string

  enum Timebase
    "time"
    "beats"
    "stretch"
  end

  enum StretchMode
    "auto"
    "tonal"
    "percussive"
  end

  --- A warp marker of an audio clip: moments of its file in seconds; in a
  --- clip's view, with the `beat` it plays on.
  record WarpMarker
    source: number
    target: number
    beat: number
  end

  --- `paw.api.clip_get(id)` and each entry of `clip_list` (`clip_json`),
  --- without the notes. MIDI clips have `note_count`, `control_count` and
  --- the stamps, which change when the notes or controls do; audio clips
  --- have `file` and how they play it, and `edits`, the number of edits.
  record Clip
    id: integer
    name: string
    start: number
    length: number
    muted: boolean
    kind: ClipKind
    track: integer
    meta: Meta
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
    timebase: Timebase
    stretch: number
    pitch: number
    stretch_mode: StretchMode
    source_tempo: number
    loop: boolean
    loop_start: number
    loop_length: number
    stretching: boolean
    made: number
    preview: boolean
    bent: boolean
    formants: boolean
    warp: {WarpMarker}
  end

  --- What `paw.api.clip_add` takes (`ClipOpts`): `kind` follows from
  --- `file` when left out; `cue` keeps it off the timeline.
  record ClipOptions
    kind: ClipKind
    name: string
    start: number
    length: number
    notes: {Note}
    file: string
    offset: number
    gain: number
    fade_in: number
    fade_out: number
    controls: {Control}
    meta: Meta
    timebase: Timebase
    stretch: number
    pitch: number
    stretch_mode: StretchMode
    source_tempo: number
    warp: {WarpMarker}
    formants: boolean
    loop: boolean
    loop_length: number
    loop_start: number
    cue: boolean
    version: integer
    timeline: Timeline
    data: KindData
    media: {MediaRef}
    sound: ClipContentData
    signals: {Signal}
  end

  enum Timeline
    "beats"
    "seconds"
  end

  --- A plain value that a kind serialized its data or a signal's body to
  --- (`model::KindValue`): a table of lists and maps of strings, numbers
  --- and booleans, saved as JSON. Teal cannot name a type that is a list
  --- or a map at each level, so the kind's `serialize` and `deserialize`
  --- give it its own type.
  type KindValue = any

  --- The data of a custom clip (`model::KindData`): `json` a plain value,
  --- or `text` UTF-8 text in the kind's own format.
  record KindData
    json: KindValue
    text: KindText
  end

  record KindText
    ext: string
    text: string
  end

  --- A file that a custom clip uses (`model::MediaRef`), by the kind's word.
  record MediaRef
    role: string
    path: string
    derived: boolean
  end

  --- Where a custom clip's signal goes (`model::SignalTo`): `kind` is
  --- `kernel` (with `body`, a plain value) or `osc` (`port`, `address`, `args`).
  record SignalTo
    kind: string
    body: KindValue
    port: string
    address: string
    args: {number | string | boolean}
  end

  --- A timed message of a custom clip (`model::Signal`).
  record Signal
    at: number
    lead_ms: integer
    latch: string
    to: SignalTo
  end

  --- What `paw.api.clip_custom` gives (`model::CustomContent`).
  record CustomContent
    type: string
    version: integer
    timeline: Timeline
    offset: number
    data: KindData
    media: {MediaRef}
    sound: ClipContentData
    signals: {Signal}
  end

  --- What `paw.api.clip_set_custom` takes (`session::CustomSet`).
  record CustomSet
    data: KindData
    version: integer
    timeline: Timeline
    offset: number
    media: {MediaRef}
    sound: ClipContentData
    signals: {Signal}
  end

  enum AudioEditKind
    "reverse"
    "gain"
    "pencil"
  end

  --- An edit of an audio clip's sound (`edits::AudioEdit`), in seconds of
  --- its sound: `gain` with `from`, `to`, `db`; `pencil` with `at`,
  --- `channel` (0 or 1, both when nil) and `values`.
  record AudioEdit
    kind: AudioEditKind
    from: number
    to: number
    db: number
    at: number
    channel: integer
    values: {number}
  end

  --- What `clip_reverse` gives: how many edits the clip has.
  record ClipEdits
    edits: integer
  end

  --- What `clip_glue` gives: the new clip, its file, and how many were glued.
  record ClipGlued
    id: integer
    file: string
    glued: integer
  end

  --- A MIDI 2.0 clip file (`clipfile`): `length` in beats; `skipped` says
  --- what the file held that a clip has no place for (`midi2_read` only).
  record Midi2Clip
    notes: {Note}
    controls: {Control}
    length: number
    skipped: {string}
  end

  -- Cues (session/cues.rs) ---------------------------------------------------

  enum Quantize
    "off"
    "1/16"
    "1/8"
    "1/4"
    "beat"
    "bar"
    "2bars"
    "4bars"
  end

  --- One track's cue for `paw.api.cue` (`CueOpts`): a `clip` of its cues,
  --- `stop`, or `timeline`.
  record Cue
    track: integer
    clip: integer
    stop: boolean
    timeline: boolean
    quantize: Quantize
    legato: boolean
    from: number
  end

  --- What a track plays and has queued (`Session::cue_state`). `queued` is
  --- a clip's id, `"stop"` or `"timeline"`, on the beat `at`.
  record CueState
    track: integer
    since: number
    clip: integer
    phase: number
    length: number
    stopped: boolean
    queued: integer | string
    at: number
  end

  -- Automation (session/automation.rs) ---------------------------------------

  enum LaneTarget
    "volume"
    "pan"
    "param"
    "state"
  end

  --- `paw.api.lane_get(id)` and each entry of `lane_list`
  --- (`Session::lane_json`), without the points. `states` (names) only for
  --- a state lane.
  record Lane
    id: integer
    track: integer
    enabled: boolean
    point_count: integer
    min: number
    max: number
    target: LaneTarget
    device: integer
    param: string
    states: {string}
  end

  --- One of the states of a state lane (`model::LaneState`).
  record LaneState
    name: string
    state: string
    params: {string: number}
    call: DeviceCallData
    program: integer
    bank: integer
  end

  --- What `paw.api.lane_add` takes (`LaneOpts`).
  record LaneOptions
    target: LaneTarget
    device: integer
    param: string
    enabled: boolean
    points: {LanePoint}
    states: {LaneState}
  end

  --- An automation point: `{ beat, value }`.
  type LanePoint = {number, number}

  enum LaneShape
    "linear"
    "hold"
    "smooth"
  end

  --- The shape of the stretch that leaves the point at `beat`
  --- (`model::Segment`); `tension` -1 to 1.
  record LaneSegment
    beat: number
    shape: LaneShape
    tension: number
  end

  -- Tempo (tempo_api.rs) --------------------------------------------------------

  --- A tempo point of `tempo_points` and `tempo_set_points`.
  record TempoPoint
    beat: number
    bpm: number
    ramp: boolean
  end

  --- A time signature point; `bar` (from 1) only from `tempo_points`.
  record SigPoint
    beat: number
    num: integer
    den: integer
    bar: integer
  end

  --- `paw.api.tempo_points()`: every point of the project's map.
  record TempoPoints
    tempos: {TempoPoint}
    signatures: {SigPoint}
  end

  --- A bar or beat line of `tempo_lines`: `bar` from 1, `index` 0 on a bar line.
  record TempoLine
    beat: number
    bar: integer
    index: integer
  end

  --- A tempo point placed in seconds, for `tempo_from_seconds`.
  record TempoSecondsPoint
    seconds: number
    bpm: number
    ramp: boolean
  end

  --- A time signature placed in seconds, for `tempo_from_seconds`.
  record SigSecondsPoint
    seconds: number
    num: integer
    den: integer
  end

  --- What `tempo_from_seconds` gives: the points in beats, and the
  --- conversions of that map.
  record TempoMapInSeconds
    tempos: {TempoPoint}
    signatures: {SigPoint}
    beat: function(seconds: number): number
    seconds: function(beat: number): number
  end

  -- The transport and the engine (session/midi_in.rs, session/engine.rs) ------

  --- `paw.api.transport_get()` (`Session::transport_view`): `position` in
  --- beats, `take` the number of the take being recorded.
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
  end

  --- The process times of the audio blocks, in milliseconds (`block_json`).
  record BlockStats
    count: integer
    mean: number
    max: number
    p50: number
    p99: number
    p999: number
    budget: number
  end

  --- The audio device that went away and is waited for.
  record AudioLost
    device: string
    auto: boolean
  end

  --- `paw.api.engine_get()` (`Session::engine_info`): latencies in
  --- milliseconds.
  record EngineInfo
    backend: string
    device: string
    sample_rate: integer
    device_id: string
    input_device_id: string
    buffer_size: integer
    cpu: number
    block: integer
    xruns: integer
    input_device: string
    input_channels: integer
    input_latency: number
    output_latency: number
    latency: number
    midi: boolean
    blocks: BlockStats
    leaked: integer
    threads: integer
    threads_wanted: integer
    device_sleep: boolean
    device_runs: integer
    device_sleeps: integer
    engine_rests: integer
    shared_groups: integer
    late_blocks: integer
    midi_dropped: integer
    record_dropped: integer
    devices_stopped: integer
    audio_files: integer
    lost: AudioLost
  end

  --- A sine for the null backend to take as input.
  record TestInput
    frequency: number
    level: number
    channels: integer
  end

  --- What `paw.api.engine_restart` takes (`EngineOpts`).
  record EngineOptions
    backend: string
    sample_rate: integer
    buffer_size: integer
    input: boolean
    output_device: string
    input_device: string
    test_input: TestInput
    test_midi: {string}
    midi: boolean
  end

  --- An audio device the system offers.
  record AudioDevice
    name: string
    id: string
    channels: integer
    sample_rate: integer
    min_block: integer
    max_block: integer
  end

  --- `paw.api.audio_devices()` (`Session::audio_devices`).
  record AudioDevices
    backend: string
    outputs: {AudioDevice}
    inputs: {AudioDevice}
    output: string
    input: string
    output_id: string
    input_id: string
    buffer_size: integer
    backends: {string}
    sample_rate: integer
    rates: {integer}
  end

  --- What `paw.api.audio_use` takes (`AudioUseOpts`).
  record AudioUseOptions
    output: string
    input: string
    buffer: integer
    backend: string
    rate: integer
  end

  --- What `paw.api.audio_watch` takes: `period` in milliseconds.
  record AudioWatchOptions
    auto: boolean
    period: number
  end

  --- What `paw.api.audio_test_device` takes.
  record TestDeviceOptions
    present: boolean
    fail_after: integer
    back_after: integer
  end

  --- A MIDI port (`midi_inputs`, `midi_outputs`); `own` for a port of paw's.
  record MidiPort
    id: string
    name: string
    open: boolean
    own: boolean
  end

  enum PreviewState
    "loading"
    "playing"
    "ended"
    "failed"
  end

  --- `paw.api.preview_get()` (`Session::preview_view`): times in seconds,
  --- `outline` the loudest sample of each of 256 stretches of the file.
  record Preview
    file: string
    level: number
    state: PreviewState
    error: string
    position: number
    length: number
    outline: {number}
  end

  -- Undo (session/undo.rs) -------------------------------------------------------

  --- One state of the undo tree.
  record UndoState
    id: integer
    parent: integer
    children: {integer}
    redo: integer
    time: number
    label: string
    keys: string
    name: string
    keep: boolean
    current: boolean
    saved: boolean
  end

  --- `paw.api.undo_tree()` (`Session::undo_tree`).
  record UndoTree
    current: integer
    root: integer
    saved: integer
    limit: integer
    pending: boolean
    states: {UndoState}
    bytes: integer
    byte_limit: integer
  end

  --- How many of a kind of thing a diff added, removed and changed.
  record DiffCount
    added: integer
    removed: integer
    changed: integer
  end

  --- `paw.api.undo_diff()` (`undo::diff`): `items` are lines that say what
  --- changed, `project` the fields of the project that did.
  record UndoDiff
    tracks: DiffCount
    devices: DiffCount
    clips: DiffCount
    notes: DiffCount
    lanes: DiffCount
    project: {string}
    items: {string}
    same: boolean
    from: integer
    to: integer
  end

  --- A checkpoint on disk; `state` only from `checkpoint_write`.
  record Checkpoint
    file: string
    name: string
    time: number
    state: integer
  end

  --- A device as a project file holds it (`model::DeviceInst`).
  record DeviceData
    id: integer
    kind: string
    bypass: boolean
    params: {string: number}
    state: string
    meta: Meta
    loaded: integer
    name: string
    offline: boolean
    sidechain: integer
    sidechain_pre: boolean
    outputs: {string: integer}
    param_ids: {string: string}
    files: {string: string}
  end

  --- What a clip holds, as a project file has it (`model::ClipContent`).
  record ClipContentData
    kind: ClipKind
    notes: {Note}
    controls: {Control}
    file: string
    offset: number
    gain: number
    edits: {AudioEdit}
  end

  --- A clip as a project file holds it (`model::Clip`).
  record ClipData
    id: integer
    name: string
    start: number
    length: number
    muted: boolean
    content: ClipContentData
    fade_in: number
    fade_out: number
    timebase: Timebase
    stretch: number
    pitch: number
    stretch_mode: StretchMode
    source_tempo: number
    warp: {WarpMarker}
    formants: boolean
    loop: boolean
    loop_length: number
    loop_start: number
    meta: Meta
    source: string
    origin: string
  end

  --- What a lane moves, as a project file holds it (`model::Target`).
  record LaneTargetData
    kind: LaneTarget
    device: integer
    param: string
  end

  --- A lane as a project file holds it (`model::Lane`).
  record LaneData
    id: integer
    target: LaneTargetData
    enabled: boolean
    points: {LanePoint}
    shapes: {LaneSegment}
    states: {LaneState}
  end

  --- A track as a project file holds it (`model::Track`).
  record TrackData
    id: integer
    name: string
    volume: number
    pan: number
    mute: boolean
    solo: boolean
    armed: boolean
    output: integer
    sends: {Send}
    devices: {DeviceData}
    clips: {ClipData}
    lanes: {LaneData}
    color: string
    meta: Meta
    input: string
    monitor: boolean
    midi_input: MidiInput
    midi_output: MidiOutput
    height: number
    automation: AutoMode
    cues: {ClipData}
    attr_map: AttrMap
    source: string
    origin: string
    chain_source: string
    chain_origin: string
  end

  --- A project as a project file holds it (`model::Project`), for
  --- `undo_project` and `project_file_text`.
  record ProjectData
    name: string
    tempo: number
    sig_num: integer
    sig_den: integer
    tempo_ramp: boolean
    tempo_changes: {TempoChange}
    sig_changes: {SigChange}
    key: string
    master: TrackData
    tracks: {TrackData}
    meta: Meta
  end

  -- Media and renders (session/media.rs, session/render.rs) -------------------

  --- A file the project's clips play (`Session::media_list`).
  record MediaFile
    path: string
    missing: boolean
    inside: boolean
    on_disk: boolean
    --- `b3:` and the BLAKE3 hash of its bytes; nil until paw has read it.
    hash: string
    --- Its size in bytes; nil until paw has read it.
    size: integer
  end

  --- What `media_search` and `media_relink` did: files found, the paths
  --- still missing, and (relink) how many clips now play the new file.
  record MediaFound
    found: integer
    missing: {string}
    clips: integer
  end

  --- What `media_collect` did: files copied into `dir`, files that play a
  --- copy of the same bytes already there, files missing.
  record MediaCollected
    copied: integer
    same: integer
    missing: {string}
    dir: string
  end

  --- `{ min, max }` of a stretch of an audio clip, or `{ min, max, rms }`
  --- of a sound file's (`media_peaks`).
  type Peak = {number}

  --- A format a render can write (`render::formats_json`): `why` says what
  --- one that is not `available` needs.
  record RenderFormat
    name: string
    extensions: {string}
    bits: {integer}
    lossy: boolean
    available: boolean
    why: string
  end

  --- What a render tags its file with, over `project.meta.tags`.
  record RenderTags
    title: string
    artist: string
    album: string
    track: string
    year: string
    genre: string
    comment: string
    cover: string
  end

  --- What `paw.api.render` and `render_start` take (`RenderOpts`): `start`
  --- and `end` in beats, `tail` and `settle` in seconds.
  record RenderOptions
    start: number
    ["end"]: number
    tail: number
    sample_rate: integer
    bits: integer
    tracks: {integer}
    freeze: integer
    dither: boolean
    normalize: number
    loudness: number
    channels: integer
    master: boolean
    threads: integer
    sleep: boolean
    quality: string
    bitrate: integer
    ffmpeg: string
    tags: RenderTags
    settle: number
  end

  --- What a render wrote (`render.rs`): `gain` in dB, `loudness` in LUFS,
  --- `elapsed` and `processing` in milliseconds; `left_out` names devices
  --- that stopped during it.
  record RenderResult
    path: string
    frames: integer
    seconds: number
    sample_rate: integer
    peak: number
    format: string
    bits: integer
    channels: integer
    gain: number
    loudness: number
    nonfinite: integer
    elapsed: number
    processing: number
    blocks: integer
    threads: integer
    device_runs: integer
    device_sleeps: integer
    left_out: {string}
  end

  enum RenderStage
    "rendering"
    "encoding"
  end

  --- The render that runs (`Session::render_status`).
  record RenderStatus
    path: string
    fraction: number
    seconds: number
    cancelling: boolean
    stage: RenderStage
  end

  -- Measuring (measure/) -------------------------------------------------------------

  --- What `paw.api.measure` takes (`MeasureOpts`): `start` and `end` in
  --- beats, `tail` in seconds; `track` measures that track's part, `file`
  --- a sound file instead of the project.
  record MeasureOptions
    start: number
    ["end"]: number
    tail: number
    sample_rate: integer
    track: integer
    file: string
  end

  --- A stretch of clipped samples: `at` in seconds, `peak` in dBFS.
  record ClipRun
    at: number
    frames: integer
    peak: number
  end

  --- A band of the spectrum: edges in Hz, `share` of the energy in dB.
  record SpectrumBand
    name: string
    low: number
    high: number
    share: number
  end

  --- Values every `hop` seconds (`analysis::Series`).
  record MeasureSeries
    hop: number
    momentary: {number}
    short_term: {number}
    correlation: {number}
    correlation_hop: {number}
    mono_loss: {number}
    sample_peak: {number}
    true_peak: {number}
    dc_left: {number}
    dc_right: {number}
  end

  --- The peak of one track's output in a measurement (`TrackPeak`).
  record TrackPeak
    id: integer
    peak: number
    peak_at: number
    over_at: number
  end

  --- What a measurement gives (`analysis::Analysis` with the tracks' peaks,
  --- `elapsed`, `floor`, and what was measured: `file`, or `start`,
  --- `tempo`, `end`, `tail`, `track` and `edits`). Levels in LUFS, LU, dB.
  record Measurement
    sample_rate: number
    frames: integer
    seconds: number
    integrated: number
    momentary_max: number
    short_term_max: number
    lra: number
    lra_low: number
    lra_high: number
    true_peak: number
    true_peak_at: number
    sample_peak: number
    sample_peak_at: number
    plr: number
    crest: number
    rms: number
    clipped_samples: integer
    over_samples: integer
    clip_runs: integer
    runs: {ClipRun}
    dc: {number}
    dc_mean: {number}
    correlation: number
    width: number
    side: number
    mono_integrated: number
    mono_loss: number
    sound_start: number
    sound_end: number
    bands: {SpectrumBand}
    series: MeasureSeries
    tracks: {TrackPeak}
    elapsed: number
    floor: number
    file: string
    start: number
    tempo: number
    ["end"]: number
    tail: number
    track: integer
    edits: integer
  end

  --- Where a measurement is (`measure_poll`): `result` or `error` once `done`.
  record MeasureStatus
    done: boolean
    progress: number
    elapsed: number
    result: Measurement
    error: string
  end

  -- Lua devices (luadev_api.rs) ------------------------------------------------------

  --- A device script found: `active` false for one hidden by a script of
  --- the same name in a directory of a higher rank.
  record LuaDeviceScript
    kind: string
    path: string
    name: string
    category: string
    error: string
    active: boolean
  end

  --- A device script that did not load.
  record LuaDeviceError
    kind: string
    path: string
    error: string
  end

  --- What `lua_devices_add` and `lua_devices_rescan` found: kinds added
  --- and changed, and the scripts that did not load.
  record LuaDeviceScan
    added: {string}
    changed: {string}
    errors: {LuaDeviceError}
  end

  -- Files, processes, the kernel (fs_api.rs, io.rs, api.rs) ---------------------

  enum FileKind
    "file"
    "dir"
    "link"
  end

  --- `paw.api.fs_stat(path)`: `dir` whether a link leads to a directory,
  --- `mtime` in seconds since 1970.
  record FileStat
    kind: FileKind
    dir: boolean
    size: number
    mtime: number
  end

  --- The format a sound file's header says (`fs_sound`).
  record SoundFormat
    rate: integer
    channels: integer
    seconds: number
  end

  --- The space of a disk, in bytes (`fs_space`).
  record DiskSpace
    free: number
    total: number
  end

  --- A node of a tab's tree as a layout keeps it (`paw.layout.capture`,
  --- `project_screen`): a window, with its view, the target of its buffer or
  --- what its view opens in it, its options and whether it is closed; or a
  --- split, with `dir` and its `children`. Both may have a `size`, a
  --- `weight` and a `min`. The kernel keeps it as JSON.
  record SavedNode
    view: string
    target: string
    size: integer
    weight: number
    min: integer
    float_below: integer
    hidden: boolean
    opts: {string: string | number | boolean}
    dir: string
    children: {SavedNode}
    --- The window's scope stack (paw/scope.tl), outermost first: only in
    --- the screen a project keeps.
    scope: {SavedScope}
  end

  --- A level of a window's scope stack as the project's screen keeps it.
  record SavedScope
    kind: string
    id: integer
    tracks: {integer}
    from: number
    to: number
    name: string
  end

  --- A tab as a layout keeps it: its name, its tree, and the place in the
  --- tree's order of the window with the keyboard.
  record SavedTab
    name: string
    layout: SavedNode
    current: integer
  end

  --- The tabs and windows of a seat (`paw.layout.capture`): the tabs and
  --- the current one.
  record SavedLayout
    tab: integer
    tabs: {SavedTab}
  end

  --- The tabs and windows that a project keeps (`project_screen`): a
  --- `default`, and the layout of each kind of seat (`paw.seats.kind`). A
  --- project saved with one layout has the fields of that layout instead.
  record ProjectScreen
    default: SavedLayout
    seats: {string: SavedLayout}
    --- The named scopes (`:scope.name`), each a stack outermost first.
    scopes: {{SavedScope}}
    tab: integer
    tabs: {SavedTab}
  end

  --- An entry of `read_dir`: `mtime` in seconds since 1970.
  record DirEntry
    name: string
    is_dir: boolean
    mtime: number
  end

  --- The levels of a sound file (`ext_api::sound_envelope`), as linear
  --- gain: `peaks` the loudest sample of each channel. `onset` gives the
  --- time of the first frame at `from` or later louder than `level`;
  --- `blocks` the loudest sample of each block of `ms` milliseconds.
  record SoundEnvelope
    rate: integer
    channels: integer
    frames: integer
    seconds: number
    peaks: {number}
    peak: number
    onset: function(level: number, from?: number): number
    blocks: function(from?: number, to?: number, ms?: number): {number}
  end

  --- How `sound_write` writes a WAV file: `bits` 16, 24, or 32 for float.
  record SoundWriteOptions
    rate: integer
    channels: integer
    bits: integer
  end

  --- What `paw.api.proc_spawn` takes (`SpawnOpts`).
  record SpawnOptions
    env: {string: string}
    cwd: string
    log: string
    pipe: boolean
  end

  --- `paw.api.proc_status(id)`: `code` nil while it runs or when a
  --- signal ended it.
  record ProcStatus
    running: boolean
    code: integer
    pid: integer
  end

  --- `paw.api.env()`: where paw keeps its files, and how it runs.
  record Env
    config_dir: string
    runtime_dir: string
    clean: boolean
    scripted: boolean
    data_dir: string
    state_dir: string
    pid: integer
    argv: {string}
    teal_types: string
  end

  -- XML (xml.rs) ---------------------------------------------------------------------

  --- The bytes an element takes in the text it was read from (`spans`).
  record XmlSpan
    from: integer
    open: integer
    close: integer
    to: integer
    lead: integer
    tail: integer
  end

  --- An XML element as `xml_decode` gives it and `xml_encode` takes it.
  record XmlElement
    name: string
    attr: {string: string | number}
    order: {string}
    children: {XmlElement}
    text: string
    span: XmlSpan
  end

  --- How `xml_decode` reads: `meta` is set as the metatable of each element.
  record XmlDecodeOptions
    spans: boolean
    meta: metatable<XmlElement>
  end

  --- How `xml_encode` writes (see its comment).
  record XmlEncodeOptions
    indent: string
    digits: integer
    declaration: boolean | string
    source: string
  end

  -- The screen (api.rs, grid.rs, scene.rs) ---------------------------------------------

  --- A colour: a name, `#rrggbb`, or 0 to 255.
  type Colour = string | integer

  --- A style of cells (`api.rs` `parse_style`): attributes true to set,
  --- false to clear, nil to keep.
  record CellStyle
    fg: Colour
    bg: Colour
    bold: boolean
    dim: boolean
    italic: boolean
    underline: boolean
    reverse: boolean
    strike: boolean
  end

  --- `{ w, h }`, or `{ x, y }`, in cells, pixels or units of a scene.
  record Size
    w: number
    h: number
  end

  record Point
    x: number
    y: number
  end

  --- A rectangle in units of a scene (`scene.rs` `Area`).
  record Rect
    x: number
    y: number
    w: number
    h: number
  end

  --- What a terminal can show besides cells (`ui_caps`, `ui_caps_set`):
  --- `cell` is a cell's size in pixels, `pixels` whether a view can be
  --- shown in pixels there.
  record Caps
    graphics: boolean
    pixels: boolean
    cell: Size
    pixel_mouse: boolean
    fg: string
    bg: string
    under: boolean
  end

  --- What `ui_frames` counts: whole frames, frames of the live parts, and
  --- of those the ones that changed no cell.
  record FrameCounts
    full: integer
    live: integer
    unchanged: integer
  end

  --- `ui_frame_snapshot`: each row as text and as its cells with their
  --- styles; `live` the number of live parts.
  record FrameSnapshot
    text: {string}
    cells: {string}
    live: integer
  end

  --- A run of cells of one style (`paw_scene::cells::Run`): from column
  --- `x`, `w` wide; `attrs` the bits of bold, italic, underline, strike.
  record CellRun
    x: integer
    w: integer
    text: string
    fg: string
    bg: string
    attrs: integer
  end

  --- A view drawn by itself (`ui_view_snapshot`, `scene_cells`): rows of
  --- runs of one style, the colours of the theme, and the cursor.
  record ViewSnapshot
    width: integer
    height: integer
    fg: string
    bg: string
    rows: {{CellRun}}
    cursor: Point
  end

  --- An operation of `paw.canvas.paint`: its letter, then its numbers and
  --- texts (see `paw.canvas`).
  type CanvasOp = {string | number}

  --- A picture of pixels as a window is sent it (`canvas_pixels`): its
  --- size, and its pixels as straight RGBA in base64, row by row.
  record PictureBlob
    w: integer
    h: integer
    rgba: string
  end

  --- A page of `canvas_export`, in pixels.
  record CanvasPage
    ops: {CanvasOp}
    width: number
    height: number
  end

  --- An axis of a plane of a scene (`paw_scene::Axis`).
  record SceneAxis
    domain: string
    from: number
    per: number
  end

  record ScenePlane
    x: SceneAxis
    y: SceneAxis
  end

  --- A hit region's action (`paw.roles`): its `kind` names the view's
  --- gesture for it, `view.gestures[kind]`. A view's own kind of hit adds
  --- what that gesture needs (`record FaderHit is types.Hit`).
  interface Hit
    kind: string
  end

  --- What `scene_open` takes (`scene.rs` `OpenOpts`). `props` is what the
  --- role shows (runtime/types/paw/role_props.d.tl, from the props that
  --- the window reads); `hit` comes back as it was in `scene_hit`.
  record SceneOpenOptions
    role: string
    props: role_props.Props
    hit: Hit
    bind: string
    key: string
    clip: Rect
    plane: ScenePlane
    into: string
  end

  --- What `scene_picture` takes: the drawing, the size `px` (`{ w, h }`)
  --- it was drawn at, `under` the cells, and the part that shows.
  record ScenePictureOptions
    ops: {CanvasOp}
    px: {number}
    under: boolean
    clip: Rect
  end

  --- What `scene_hit` finds: `hit` is what `scene_open` was given.
  record SceneHit
    key: string
    hit: Hit
    at: Point
    rect: Rect
  end

  --- A box of a glyph in staff spaces: `{ x, y }` corners.
  record GlyphBox
    bBoxNE: {number}
    bBoxSW: {number}
  end

  --- A music font's SMuFL metadata (`smufl`): `engravingDefaults` by name
  --- (numbers, and `textFontFamily`, a list of names), anchors by glyph
  --- and name, and `glyphs`, every glyph name with its code point.
  record Smufl
    fontName: string
    fontVersion: number
    engravingDefaults: {string: number | {string}}
    glyphBBoxes: {string: GlyphBox}
    glyphsWithAnchors: {string: {string: {number}}}
    glyphs: {string: integer}
  end
end

return types
