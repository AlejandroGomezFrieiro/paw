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

  --- What an extension keeps in `meta` (of the project, a part, a clip, a
  --- device or a note): the extension's own data, any JSON value by name.
  --- The kernel keeps it and does not look in it.
  type Meta = {string: any}

  -- Notes and controllers (model.rs) --------------------------------------

  --- What to change about a note (`session/document/notes.rs` `NoteChange`): what is
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

  --- New values for many notes of many clips, as one edit
  --- (`session/document/notes.rs` `NoteColumns`, `notes_set`): lists of the same
  --- length, entry i about the note at place `place[i]` (from 1, before
  --- the call) of clip `clip[i]`. A list left out keeps that value.
  record NoteColumns
    clip: {integer}
    place: {integer}
    start: {number}
    length: {number}
    pitch: {integer}
    velocity: {integer}
  end

  --- Which notes `clip_notes` gives (`NoteRange`): beats in the clip and
  --- pitches, both ends included; what is left out is open.
  record NoteRange
    from: number
    to: number
    low: integer
    high: integer
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
    --- In a `midi.in` event: true when parts do not get it
    --- (`engine_midi_filter`).
    filtered: boolean
  end

  --- A control of MIDI input that parts do not get
  --- (`session/midi_in.rs` `FilterRule`): a key (`note`) or a controller
  --- (`cc`), 0 to 127, from the port of that name (every port when left
  --- out), on `channel` 1 to 16 (every channel when left out).
  record MidiFilterRule
    port: string
    channel: integer
    note: integer
    cc: integer
  end

  -- The project and its parts (session/document/project.rs and parts.rs)

  --- What a project keeps of `:export` (`Project::export`), in
  --- `project.toml` under `[export]`: `presets` by name, each the words of
  --- `:export` as one text, or a list of them for several exports.
  record ProjectExport
    presets: {string: string | {string}}
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

  --- A part's attribute map (`attr_map::AttrMap`, see attr_map.rs). As
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

  --- What `paw.api.part_add` takes (`PartOpts`): `index` from 1; `nest`
  --- to make the part in that subproject.
  record PartOptions
    name: string
    index: integer
    volume: number
    pan: number
    output: integer
    color: string
    nest: integer
  end

  --- What `paw.api.part_list` takes: `nest` lists the parts of that
  --- subproject, `all` every part; neither, the song's.
  record PartListOptions
    nest: integer
    all: boolean
  end

  --- `follow` plays a subproject at the song's tempo where each clip is,
  --- `own` at its own.
  enum NestTempoMode
    "follow"
    "own"
  end

  --- The tempo of a subproject (`model::NestTempo`): with `follow`, `kept`
  --- is the song's tempo over it when it was made; with `own`, `points`,
  --- the first at beat 0.
  record NestTempo
    mode: NestTempoMode
    kept: {TempoChange}
    points: {TempoChange}
  end

  --- `follow` takes the song's meter where each clip is, `own` its own.
  enum NestMeterMode
    "follow"
    "own"
  end

  --- The meter of a subproject (`model::NestMeter`): with `own`,
  --- `changes`, the first at beat 0.
  record NestMeter
    mode: NestMeterMode
    changes: {SigChange}
  end

  --- A subproject (`Document::nest_view`): `length` in beats, `master` its
  --- master part, `parts` its other parts in order, `used` whether the
  --- song plays it.
  record Nest
    id: integer
    name: string
    length: number
    tempo: NestTempo
    meter: NestMeter
    master: integer
    parts: {integer}
    kind: string
    meta: Meta
    source: string
    origin: string
    used: boolean
  end

  --- What `paw.api.nest_add` takes (`NestOpts`).
  record NestOptions
    name: string
    length: number
    tempo: NestTempo
    meter: NestMeter
    kind: string
    meta: Meta
  end

  --- What `paw.api.nest_save` takes (`session::save::SaveOpts`): the
  --- subproject's `name`, the view's `parts` (of one place) and its time
  --- `from` and `to` in that place's beats, the subproject's `meter`, and
  --- `own_row` for a row of its own rather than per part.
  record NestSaveOptions
    name: string
    parts: {integer}
    from: number
    to: number
    meter: NestMeter
    own_row: boolean
  end

  --- A row that `paw.api.nest_save` gives a block per part, and the
  --- part of the subproject that the block plays (`session::save::HostRow`).
  record NestHostRow
    row: integer
    part: integer
  end

  --- What `paw.api.nest_save` did (`session::save::Saved`): the `nest`,
  --- per part the `rows` that get a block, with a row of its own the
  --- return `row`, the subproject's `parts`, the routes that changed
  --- at the boundary, in words (`changes`), the song's `group` that the
  --- return row is in, and the `buses` that no longer get the time when the
  --- row plays into the master because the parts played into several.
  record NestSaved
    nest: integer
    rows: {NestHostRow}
    row: integer
    parts: {integer}
    changes: {string}
    group: integer
    buses: {integer}
  end

  --- What `paw.api.scope_export` takes (`session::export::ExportOpts`):
  --- the project's `name`, the view's `parts` (of one place) and its
  --- time `from` and `to` in that place's beats.
  record ScopeExportOptions
    name: string
    parts: {integer}
    from: number
    to: number
  end

  --- What `paw.api.nest_export` and `paw.api.scope_export` wrote
  --- (`session::export::Exported`): the new `project.toml` (`path`), how
  --- many `parts` and `media` files, the media files that are `missing`,
  --- and the routes cut at the edge of a view, in words (`changes`).
  record NestExported
    path: string
    parts: integer
    media: integer
    missing: {string}
    changes: {string}
  end

  --- What `paw.api.nest_promote` did (`session::promote::Promoted`): the
  --- `group` part (nil for a subproject saved per part), the
  --- subproject's `parts` (per part: the rows its clips went back to),
  --- the block's window `from` and `to` and `zero` (song beats), and the
  --- targets of the lanes that were made one (`combined`).
  record NestPromoted
    group: integer
    parts: {integer}
    from: number
    to: number
    zero: number
    combined: {string}
  end

  --- The part of a subproject that a nest clip plays (`model::NestPlay`);
  --- the string "master" plays its mix.
  record NestPart
    part: integer
  end

  --- A file of a project kept in a folder (`Session::project_files`).
  record ProjectFile
    path: string
    modified: boolean
    what: string
    part: integer
    clip: integer
  end

  --- How `paw.api.project_load` and `project_recover` open a project
  --- (`OpenOpts`): devices offline. `as_path` only for `project_recover`.
  record OpenOptions
    plugins_offline: boolean
    offline: {integer}
    as_path: string
  end

  -- Devices (session/devices.rs, session/document/devices.rs) ----

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

  --- The owner of a chain, as a handle of `paw.chain` (`OwnerRef` in
  --- model/owner.rs): a part, `{ part = id }`.
  record ChainOwner
    part: integer
  end

  --- A node of a chain (`Node` in model/chain.rs): a device of the owner
  --- by id, or a split.
  record ChainNode
    device: integer
    split: ChainSplit
  end

  --- One path through a split (`Branch`): its nodes in series. `gain` in
  --- dB, `pan` from -1 to 1, `zone` the notes or velocities it hears.
  record ChainBranch
    id: integer
    name: string
    gain: number
    pan: number
    mute: boolean
    solo: boolean
    zone: ChainZone
    nodes: {ChainNode}
  end

  --- A range of notes or velocities, 0 to 127.
  record ChainZone
    low: integer
    high: integer
  end

  --- A macro of a split (`Macro`), 0 to 1.
  record ChainMacro
    id: integer
    name: string
    value: number
  end

  --- A macro that moves a parameter of a device in its split (`Link`).
  record ChainLink
    source: integer
    device: integer
    param: string
    depth: number
  end

  --- The definition a linked rack follows, and what it has of its own
  --- (`Linked<RackDef>` and `RackOwn`). `values` are the keys of the
  --- values it keeps, as the file has them (`5.mix`, `7.params.ratio`).
  record ChainLinked
    record Own
      ids: {integer: integer}
      values: {string}
    end
    of: integer
    overrides: Own
  end

  --- A split of a chain (`Split`): `kind` is the name of its kind
  --- (`chain`, `layer`, `band`, `ms`, `lr`, `key`, `vel`, `select`,
  --- `outs`, or a kind of an extension), `values` the values of its kind
  --- (`xover` of a band split), `mix` 0 to 1 and `gain` in dB.
  record ChainSplit
    id: integer
    kind: string
    values: Meta
    name: string
    mix: number
    gain: number
    branches: {ChainBranch}
    macros: {ChainMacro}
    links: {ChainLink}
    linked: ChainLinked
  end

  --- A device that takes its key from inside its chain (`Tap`): `from`
  --- is a node, nil for the input of the chain.
  record ChainTap
    device: integer
    from: integer
  end

  --- The chain of an owner's devices (`Chain` in model/chain.rs).
  record Chain
    root: ChainSplit
    taps: {ChainTap}
  end

  --- The meters of a chain (`ChainMeters` in session/engine.rs):
  --- `latency` of the chain in ms; `peaks`, the linear peak of each
  --- device, split and branch by its id; `time`, the nanoseconds each
  --- device ran since the engine started.
  record ChainMeters
    latency: number
    peaks: {integer: number}
    time: {integer: integer}
  end

  --- What a kind of split takes (`KindSpec`): the fewest and the most
  --- branches, and how many a new split gets.
  record SplitKindSpec
    min: integer
    max: integer
    first: integer
  end

  --- What `paw.api.chain_wrap` takes besides the kind (`WrapOpts`).
  record ChainWrapOptions
    branches: integer
    name: string
    values: Meta
  end

  --- What `paw.api.chain_branch_add` takes: `index` from 1.
  record ChainBranchOptions
    name: string
    index: integer
  end

  --- A place in a chain (`Place`): before or after a node, or in a
  --- branch at `index` (from 1; the end when nil).
  record ChainPlace
    before: integer
    after: integer
    branch: integer
    index: integer
  end

  --- What `paw.api.chain_set` changes: of a split, a branch or a macro.
  record ChainPatch
    name: string
    mix: number
    gain: number
    kind: string
    values: Meta
    pan: number
    mute: boolean
    solo: boolean
    zone: ChainZone
    value: number
  end

  --- A linked rack's definition, as `paw.api.rack_list` gives it.
  record RackDef
    id: integer
    name: string
    split: ChainSplit
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

  -- Clips (session/document/clips.rs, session.rs clip_json) ------------------

  --- `midi`, `audio`, `nest`, or the name of a clip kind that an
  --- extension defines (`paw.kinds.define("clip", ...)`).
  type ClipKind = string

  -- Kinds (paw-types/src/stream.rs) -------------------------------------------

  --- A stream type as `paw.api.stream_check` takes it: a stream kind and
  --- its properties, each a flag, a count, a word, or a ratio `{n, d}`.
  record StreamType
    base: string
    props: {string: boolean | integer | string | {integer}}
  end

  --- The time a stream counts in: `samples`, `beats` or `seconds`.
  enum StreamTime
    "samples"
    "beats"
    "seconds"
  end

  --- A kind as `paw.api.kinds_put` takes it: the fields that the kernel
  --- keeps of each family. `title` and `schema` (the words of each field
  --- of the kind's data) are of each family. `time`, `records`, `control`
  --- and `props` (its properties, in the words of `schema`) are of a
  --- stream kind, `gives` of a clip kind and `version` of a `meta` key.
  record KindSpec
    title: string
    schema: {string: ParamSchema}
    time: StreamTime
    records: boolean
    control: boolean
    props: {string: ParamSchema}
    gives: string
    version: integer
  end

  -- The records below come from paw.api.api_schema (tools/apidoc.lua): change the Rust types.

  --- How a part treats its automation.
  enum AutoMode
    "read"
    "touch"
    "latch"
    "write"
    "off"
  end

  enum ControlType
    "cc"
    "bend"
    "pressure"
    "registered"
    "assignable"
    "program"
  end

  --- Whether a device runs, and why not.
  enum DeviceStatus
    "running"
    "stopped"
    "loading"
    "offline"
    "missing"
  end

  --- Whether a device's own window shows.
  enum EditorState
    "open"
    "closed"
  end

  --- What a lane moves.
  enum LaneTarget
    "volume"
    "pan"
    "param"
    "state"
  end

  --- What a MIDI output sends where the port takes no MIDI 2.0 (see
  --- `paw_types::midi_form`).
  enum MidiOutForm
    "auto"
    "plain"
    "mpe"
    "cc14"
  end

  --- What kind of value a parameter takes.
  enum ParamKind
    "continuous"
    "boolean"
    "enum"
    "stepped"
  end

  --- The type of a parameter: a JSON Schema type, or `source`.
  enum ParamType
    "number"
    "boolean"
    "integer"
    "string"
    "array"
    "source"
  end

  --- How an audio clip is stretched.
  enum StretchMode
    "auto"
    "tonal"
    "percussive"
  end

  --- What an audio clip keeps when the tempo changes. Either way it keeps its
  --- length in seconds, so that a recording plays every sample at the time
  --- it was recorded at: its end beat follows from the tempo map.
  enum Timebase
    "time"
    "beats"
    "stretch"
  end

  --- A unit that a number can have in the text.
  enum Unit
    "dB"
    "Hz"
    "kHz"
    "ms"
    "s"
    "%"
    "st"
  end

  --- `paw.api.clip_get(id)` and each entry of `clip_list`, without the notes.
  --- MIDI clips have `note_count`, `control_count` and the stamps, which
  --- change when the notes or controls do; audio clips have `file` and how
  --- they play it, and `edits`, the number of edits. What does not apply to
  --- its kind is left out.
  record Clip
    bent: boolean
    control_count: integer
    --- The same for the controller moves.
    control_stamp: integer
    cue: boolean
    edits: integer
    fade_in: number
    fade_out: number
    file: string
    formants: boolean
    gain: number
    id: integer
    kind: ClipKind
    length: number
    --- A linked clip's link, and how many clips it has (`link_count` only
    --- from `clip_get`).
    link: string
    link_count: integer
    loop: boolean
    loop_length: number
    loop_start: number
    made: number
    meta: Meta
    --- A MIDI clip's modifiers, top to bottom (`model/modifiers.rs`).
    modifiers: {Modifier}
    muted: boolean
    name: string
    nest: integer
    note_count: integer
    offline: boolean
    offset: number
    origin: string
    part: integer
    pitch: number
    play: string | NestPart
    preview: boolean
    source: string
    source_tempo: number
    --- Changes whenever the notes do (`model::Notes::stamp`).
    stamp: integer
    start: number
    stretch: number
    stretch_mode: StretchMode
    stretching: boolean
    timebase: Timebase
    warp: {WarpMarker}
  end

  --- What `paw.api.clip_set` changes in a clip: each field as `clip_get`
  --- gives it, and what is left out stays. Nil clears a field that has a
  --- default (`clip_set(id, "loop_length", nil)`), and is refused for the
  --- others.
  record ClipChanges
    --- Beats an audio clip fades in over.
    fade_in: number
    --- Beats an audio clip fades out over.
    fade_out: number
    --- The sound file of an audio clip: another take of it.
    file: string
    --- An audio clip keeps the formants of the voice when it is shifted.
    formants: boolean
    --- The gain of an audio clip in dB, from -120 to 24.
    gain: number
    --- The length of the clip in beats.
    length: number
    --- The clip repeats over its length.
    loop: boolean
    --- Beats of one repeat; nil for the clip's content.
    loop_length: number
    --- Where a repeat starts in the clip's content, in beats.
    loop_start: number
    meta: Meta
    --- The modifiers of a MIDI clip, top to bottom. Nil or an empty list
    --- takes all of them away.
    modifiers: {Modifier}
    --- The clip is silent.
    muted: boolean
    --- The name of the clip.
    name: string
    --- Where an audio clip starts in its file, in seconds, or where a
    --- clip of another kind starts in its content.
    offset: number
    --- Move the clip to the end of this part.
    part: integer
    --- Semitones an audio clip is shifted by.
    pitch: number
    --- The tempo that an audio clip was recorded at.
    source_tempo: number
    --- Where the clip starts on the timeline, in beats.
    start: number
    --- How many times its length an audio clip is stretched to.
    stretch: number
    stretch_mode: StretchMode
    timebase: Timebase
    --- The markers of an audio clip; the `beat` of each is not read.
    warp: {WarpMarker}
  end

  --- A controller moving to a value at a point in a MIDI clip: a control
  --- change, the pitch wheel, pressure, a registered or assignable controller,
  --- or a program change. With `key` it belongs to the note on that key
  --- alone, as MIDI 2.0 has it: that note's own pitch bend, pressure or
  --- controller.
  record Control
    bank: integer
    index: integer
    key: integer
    number: integer
    program: integer
    --- Beats from the start of the clip; below 0 it is hidden before the
    --- clip's start and not played.
    start: number
    type: ControlType
    --- 0 to 1, or -1 to 1 for pitch bend. Kept as a fraction, so nothing of
    --- a 32-bit value is lost.
    value: number
  end

  --- A device on a part.
  record Device
    bypass: boolean
    --- Whether its own window shows; nil for a device with no window.
    editor: EditorState
    format: string
    id: integer
    --- Its place in the chain of its part, from 1.
    index: integer
    kind: string
    meta: Meta
    --- Not running: not installed, not made yet, or made and gone.
    missing: boolean
    name: string
    offline: boolean
    --- The part that each further output pair plays into, by the pair's
    --- number as text.
    outputs: {string: integer}
    --- The parameters that the project sets, over what the plugin's state
    --- says.
    overrides: {string: number}
    param_info: {ParamInfo}
    --- The value now of each parameter, by key.
    params: {string: number}
    part: integer
    --- Who made it and which it is, as its format names it; nil for a
    --- device of paw.
    plugin: DevicePlugin
    ports: DevicePorts
    --- The part it listens to.
    sidechain: integer
    sidechain_pre: boolean
    status: DeviceStatus
    --- Why the device has stopped working, for a plugin that crashed, hung
    --- or could not be made.
    stopped: string
  end

  --- What `paw.api.device_set` changes in a device: each field as
  --- `device_get` gives it, and what is left out stays.
  record DeviceChanges
    bypass: boolean
    meta: Meta
    --- The device is not made: it keeps its state and plays nothing.
    offline: boolean
    --- The part that each further output pair plays into, by the
    --- pair's number from 2; nil or an empty table for none.
    outputs: {integer | string: integer}
    --- The part it listens to; nil for none.
    sidechain: integer
    --- It listens to the side-chain before the fader of its part.
    sidechain_pre: boolean
    --- The plugin's state in base64, as `device_state` gives it; nil for
    --- none.
    state: string
  end

  --- Who made a plugin and which it is.
  record DevicePlugin
    format: string
    id: string
    name: string
    vendor: string
    version: string
  end

  --- What a running device takes and gives besides its main pair.
  record DevicePorts
    --- The names of its output pairs, the main one first.
    outputs: {string}
    --- It listens to a side-chain.
    sidechain: boolean
  end

  --- One kind as `paw.api.kinds_list` gives it.
  record KindInfo
    --- The family: `stream`, `clip`, `part` or `meta`.
    family: string
    --- The stream that the clips of a clip kind give to their lane.
    gives: string
    name: string
    --- The extension that defined the kind, or `paw.<feature>` for the core.
    owner: string
    --- The words of each field of the data of the kind (of a stream kind:
    --- of each property). Nil when the kind gave none.
    schema: {string: ParamSchema}
    title: string
    --- The version of the data of a `meta` key.
    version: integer
    --- A tool may write the data of the kind: the kind gave a schema.
    writable: boolean
  end

  --- A lane as `paw.api.lane_get` gives it, without its points.
  record Lane
    --- The device of a parameter or state lane.
    device: integer
    --- A lane that is off keeps its points but does not move its target.
    enabled: boolean
    id: integer
    --- The highest value of the target.
    max: number
    --- The lowest value of the target.
    min: number
    --- The key of the parameter of a parameter lane.
    param: string
    part: integer
    point_count: integer
    --- The names of the states of a state lane.
    states: {string}
    target: LaneTarget
  end

  --- What `paw.api.lane_set` changes in a lane.
  record LaneChanges
    --- A lane that is off keeps its points but does not move its target.
    enabled: boolean
  end

  --- MIDI from one port, by its name, and optionally one channel of it.
  record MidiInput
    --- From 1 to 16, or `None` for every channel.
    channel: integer
    --- The port's name as the system gives it (`paw.midi.inputs()`), or
    --- `None` for every port.
    port: string
  end

  --- MIDI to one output port, by its name, on a channel or on each
  --- message's own, in a form for ports that take no MIDI 2.0.
  record MidiOutput
    --- From 1 to 16, or `None` for the channel each message has.
    channel: integer
    form: MidiOutForm
    --- The member channels of an MPE zone, 1 to 15; `None` for 15.
    members: integer
    --- The port's name as `paw.midi.outputs()` gives it.
    port: string
  end

  --- One modifier of a clip's stack: its kind, its values, whether it is off,
  --- the beats that it changes, and the version of its values.
  record Modifier
    --- `transpose`, `velocity`, or a kind of an extension.
    kind: string
    --- The entry is off and changes nothing. The file leaves `off` out for
    --- an entry that is on.
    off: boolean
    --- The values of the kind, as the file has them. The file leaves
    --- `params` out when there are none.
    params: Meta
    --- The beats of the clip that the entry changes. Left out, the entry
    --- changes all of the clip.
    scope: ModifierScope
    --- The version of the kind's values; left out for 1.
    version: integer
  end

  --- The beats of a clip, from `from` up to `to`, in which an entry changes
  --- the notes and the controller moves that start there.
  record ModifierScope
    from: number
    to: number
  end

  record Note
    --- The MIDI 2.0 attribute its note-on carries, such as an articulation
    --- of the orchestral articulation profile (M2-123); `None` for none.
    attr: NoteAttr
    --- What names the note within its clip for as long as it lives, however
    --- it is moved or changed (`paw://clip/7/note/41`). 0 until the session
    --- gives it one, which it does to every note that has none, or shares
    --- one with a note before it, before the edit is played or kept.
    id: integer
    length: number
    --- The words sung on the note, as plain text: a syllable, a word, or a
    --- phrase. A MIDI file keeps it as a lyric event at the note's start.
    lyric: string
    --- Free-form data for extensions, such as the phonemes of a voice. It
    --- travels with the note through edits, unlike data kept beside the
    --- clip's note list.
    meta: Meta
    --- MIDI note number, 60 is middle C.
    pitch: integer
    --- Beats from the start of the clip. A note before 0 (or from the clip's
    --- length on) is hidden by a trim of the clip's edge: kept, but not
    --- played until the edge is dragged out over it again.
    start: number
    --- 1 to 127.
    velocity: integer
  end

  --- A note's MIDI 2.0 attribute: `{ "type": 17, "data": 40960 }`. Type 0
  --- means none, and a note never keeps it.
  record NoteAttr
    data: integer
    type: integer
  end

  --- A parameter of a device, as `param_info` lists it.
  record ParamInfo
    automatable: boolean
    --- A lane of the part moves it.
    automated: boolean
    --- The names of its steps, for a parameter of named steps.
    choices: {string}
    default: number
    group: string
    --- The device's own id for it, or its key.
    id: string
    --- Its place in the device's list, from 1.
    index: integer
    --- The key that scripts and lanes name it by.
    key: string
    kind: ParamKind
    max: number
    min: number
    name: string
    per_note: boolean
    read_only: boolean
    --- The number of its steps; 0 for a continuous one.
    steps: integer
    --- Its value now as the device writes it (`device_param`).
    text: string
    unit: string
    --- Its value now (`device_param`).
    value: number
  end

  --- What a parameter takes, as JSON Schema words.
  record ParamSchema
    --- Each number of a list is greater than the one before it.
    ascending: boolean
    default: boolean | number | string
    --- The choices of a text.
    enum: {string}
    --- `note` for a note value such as `1/4`. Other formats are only for
    --- people, as in JSON Schema.
    format: string
    --- What each number of a list takes.
    items: ParamSchema
    --- The source is the main input of its kind: a wire with no port
    --- feeds it.
    main: boolean
    maxItems: integer
    maximum: number
    minItems: integer
    minimum: number
    --- The kind of stream that a source must give. None takes any.
    stream: string
    type: ParamType
    --- The unit of a number, and of `minimum`, `maximum` and `default`.
    unit: Unit
  end

  --- `paw.api.part_get(id)`. `volume` in dB, `pan` -1 to 1, `output` the
  --- part it feeds (nil for the master), `index` from 1 among all parts.
  --- `devices` and `clips` are ids.
  record Part
    armed: boolean
    attr_map: AttrMap
    automation: AutoMode
    --- The chain file outside the project that the chain was copied from.
    chain_origin: string
    --- A chain read from a chain file outside the project's folder.
    chain_source: string
    clips: {integer}
    color: string
    devices: {integer}
    height: number
    id: integer
    index: integer
    input: string
    --- The kind of the part (`paw.kinds.define("part", ...)`); nil for
    --- an ordinary part.
    kind: string
    --- The parts that devices on this one listen to as side-chains.
    listens: {integer}
    master: boolean
    meta: Meta
    midi_input: MidiInput
    midi_output: MidiOutput
    monitor: boolean
    mute: boolean
    name: string
    --- The subproject that the part belongs to; nil for the song's.
    nest: integer
    --- The part folder outside the project that the part was copied from.
    origin: string
    output: integer
    --- The parts that further output pairs of its devices play into.
    pairs_into: {integer}
    pan: number
    --- The group that the part is in; nil at the top level.
    parent: integer
    sends: {Send}
    solo: boolean
    --- A part read from a part folder outside the project's folder.
    source: string
    volume: number
  end

  --- What `paw.api.part_set` changes in a part: each field as `part_get`
  --- gives it, and what is left out stays. Nil clears a field that can be
  --- empty (`part_set(id, "output", nil)`), and is refused for the others.
  record PartChanges
    --- The part records when the song records.
    armed: boolean
    --- How the MIDI 2.0 attributes of its notes reach an instrument that
    --- does not take them. Nil, false or an empty table for none.
    attr_map: AttrMap
    --- What a move of a control does to the part's automation while the
    --- song plays.
    automation: AutoMode
    color: string
    --- A share of the height of every part, from a quarter to eight
    --- times; nil or 1 for that height.
    height: number
    --- An audio input: a channel such as "1", a pair such as "1/2", or
    --- nil or "none" for none.
    input: string | integer
    --- The kind of the part: the name of a part kind, or nil for an
    --- ordinary part. A kind that no extension defines is kept.
    kind: string
    meta: Meta
    --- The MIDI the part plays when armed: a port's name, a table of
    --- `port` and `channel`, or nil or "all" for every port.
    midi_input: string | MidiInput
    --- Where the part sends MIDI: a port's name, a table of `port`,
    --- `channel`, `form` and `members`, or nil or "none" for none.
    midi_output: string | MidiOutput
    --- Hear the input even when the part is not armed.
    monitor: boolean
    mute: boolean
    name: string
    --- The part it feeds; nil for the master.
    output: integer
    --- From -1 (left) to 1 (right).
    pan: number
    --- The group that the part is in, or nil for the top level. A group
    --- cannot be put inside itself.
    parent: integer
    --- Its sends, each with a `level` in dB.
    sends: {Send}
    solo: boolean
    --- The fader in dB, from -120 to 24.
    volume: number
  end

  --- `paw.api.project_get()`.
  record Project
    --- Goes up with each change: compare two readings to see whether
    --- something in between edited the project.
    edits: integer
    export: ProjectExport
    --- The song's key, such as "D minor".
    key: string
    --- The end of the last clip, in beats.
    length: number
    meta: Meta
    --- The project has changes that are not saved.
    modified: boolean
    name: string
    --- The project's file; nil before it is saved.
    path: string
    sig_changes: {SigChange}
    sig_den: integer
    sig_num: integer
    --- Beats (quarter notes) per minute at the start of the song.
    tempo: number
    tempo_changes: {TempoChange}
    --- The tempo ramps from the start to the first tempo change.
    tempo_ramp: boolean
    --- A hash of the tempo and signature points, the same for the same
    --- points (after an undo too).
    tempo_stamp: integer
  end

  --- What `paw.api.project_set` changes in the project: each field as
  --- `project_get` gives it, and what is left out stays.
  record ProjectChanges
    --- The project's export presets by name.
    export: ProjectExport
    --- The song's key, such as "D minor"; nil for none.
    key: string
    meta: Meta
    name: string
    --- The lower number of the time signature at the start: 1, 2, 4,
    --- 8, 16, 32 or 64.
    sig_den: integer
    --- The upper number of the time signature at the start, 1 to 64.
    sig_num: integer
    --- The tempo at the start, from 1 to 999 beats per minute.
    tempo: number
  end

  record Send
    --- Send level in dB.
    level: number
    --- Taken after the part's devices but before its fader, pan and mute,
    --- so that the send does not follow the fader.
    pre: boolean
    target: integer
  end

  --- A time signature starting a bar at a beat.
  record SigChange
    beat: number
    den: integer
    num: integer
  end

  --- A tempo change along the song.
  record TempoChange
    beat: number
    bpm: number
    --- Ramp to the next change's tempo instead of holding this one.
    ramp: boolean
  end

  --- The transport as Lua reads it (`paw.api.transport_get`).
  record Transport
    click_accent: boolean
    click_level: number
    click_output: integer
    --- Takes that stopped and are not clips yet: each becomes clips a
    --- moment after it stops (`transport.recorded`).
    closing: integer
    count_in: integer
    counting: integer
    loop_enabled: boolean
    loop_end: number
    loop_start: number
    metronome: boolean
    playing: boolean
    position: number
    pre_roll: integer
    pre_roll_seconds: number
    punch_enabled: boolean
    punch_end: number
    punch_start: number
    record_offset: number
    recording: boolean
    --- The number of the take being recorded.
    take: integer
    tempo: number
    write: boolean
  end

  --- What `paw.api.transport_set` changes in the transport: each field as
  --- `transport_get` gives it, and what is left out stays.
  record TransportChanges
    click_accent: boolean
    --- The click's level, from -60 to 12 dB.
    click_level: number
    --- The output channel of the click, from 1 to 64, or 0 for with the
    --- song.
    click_output: number
    --- Bars of count-in before a recording, 0 to 16.
    count_in: number
    loop_enabled: boolean
    loop_end: number
    loop_start: number
    metronome: boolean
    --- Bars that play before the start of playback, 0 to 16.
    pre_roll: number
    --- Seconds that play before the start of playback, 0 to 30.
    pre_roll_seconds: number
    punch_enabled: boolean
    punch_end: number
    punch_start: number
    --- Milliseconds that a recorded take moves to make up for the
    --- latency of the input.
    record_offset: number
    recording: boolean
    --- Moves of the controls write automation while the song plays.
    write: boolean
  end

  --- A warp marker of an audio clip: moments of its file in seconds; in a
  --- clip's view, with the `beat` it plays on.
  record WarpMarker
    beat: number
    source: number
    target: number
  end

  -- The end of the records from paw.api.api_schema.

  --- What `paw.api.clip_render` did: the modifiers that left the stack,
  --- the notes of the clip after it, and the notes that a modifier left
  --- out.
  record Rendered
    modifiers: integer
    notes: integer
    dropped: integer
  end

  --- What `paw.api.clip_add` takes (`ClipOpts`): `kind` follows from
  --- `file` when left out; `cue` keeps it off the timeline. A subproject's
  --- clip (`kind = "nest"`, or `nest` given) places the subproject `nest`
  --- and plays its mix, or one part with `play = { part = id }`;
  --- `offset` is then the beat of the subproject where it starts.
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
    modifiers: {Modifier}
    version: integer
    timeline: Timeline
    data: KindData
    media: {MediaRef}
    sound: ClipContentData
    signals: {Signal}
    nest: integer
    play: string | NestPart
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

  --- One part's cue for `paw.api.cue` (`CueOpts`): a `clip` of its cues,
  --- `stop`, or `timeline`.
  record Cue
    part: integer
    clip: integer
    stop: boolean
    timeline: boolean
    quantize: Quantize
    legato: boolean
    from: number
  end

  --- What a part plays and has queued (`Session::cue_state`). `queued` is
  --- a clip's id, `"stop"` or `"timeline"`, on the beat `at`.
  record CueState
    part: integer
    since: number
    clip: integer
    phase: number
    length: number
    stopped: boolean
    queued: integer | string
    at: number
  end

  -- Automation (session/document/automation.rs) ------------------------------

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

  --- `paw.scope.own_time()`: the time of a subproject with its own tempo
  --- or meter, in its own beats, as the window inside it counts it, for
  --- the block `clip` it was entered through. The methods are the
  --- `paw.api.nest_tempo_*` functions of its map (bars from 0), and
  --- `song_beat` and `nest_beat` convert between its beats and the song's.
  record NestTime
    clip: integer
    own_tempo: boolean
    song_beat: function(self: NestTime, beat: number): number
    nest_beat: function(self: NestTime, song_beat: number): number
    seconds: function(self: NestTime, beat: number): number
    tempo: function(self: NestTime, beat: number): number
    signature: function(self: NestTime, beat: number): integer, integer
    bar_of: function(self: NestTime, beat: number): integer
    bar_start: function(self: NestTime, bar: integer): number
    bar_length: function(self: NestTime, beat: number): number
    is_bar_line: function(self: NestTime, beat: number): boolean
    bbt: function(self: NestTime, beat: number): integer, integer, number
    from_bbt: function(self: NestTime, bar: integer, beat: integer, fraction?: number): number
    points: function(self: NestTime): TempoPoints
    lines: function(self: NestTime, from: number, to: number, limit?: integer): {TempoLine}
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

  -- The loop of the kernel (api/timers.rs) -----------------------------------

  --- `paw.api.pending()` and `paw.api.settle()` (`Pending`): the work not
  --- done yet. `ready`: the next turn has work. `quiet`: nothing is in
  --- flight, no helper works, no plugin works or owes its state, and the
  --- engine plays nothing: only timers are left. `plugins_busy`: plugins
  --- with a thread of their own at work (a model that loads), whose result
  --- comes in a later block. `plugins_owe`: plugins that took a request (a
  --- model, a preset of their own) and show their new state only after
  --- their next blocks. `next_ms` is nil when nothing waits for the schedule clock.
  --- `in_flight` has the work of other threads and processes by kind
  --- (`bakes`, `hashes`, `loads`, `renders`, `takes`, `preview`,
  --- `measures`); a kind with none is left out.
  record Pending
    ready: boolean
    quiet: boolean
    next_ms: number
    in_flight: {string: integer}
    timers_due: integer
    timers: integer
    bakes_waiting: integer
    files: integer
    midi: integer
    helpers: integer
    helpers_busy: integer
    plugins_busy: integer
    plugins_owe: integer
    missed_wakes: integer
  end

  -- The transport and the engine (session/midi_in.rs, session/engine.rs) ------

  --- What a window shows of the song (`ViewRange`, stretched.rs): the
  --- beats from `from` up to `to`, and the parts shown (all when nil).
  record ViewRange
    from: number
    to: number
    parts: {integer}
  end

  --- The process times of the audio blocks, in milliseconds (`BlockTimes`).
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

  --- `paw.api.engine_get()` (`EngineView`): latencies in
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

  -- Undo (session/undo.rs, session/document/undo_tree.rs) ------------------------

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

  --- `paw.api.undo_tree()` (`Document::undo_tree`).
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

  --- `paw.api.undo_file_open()` (`Session::undo_file_open`): how many states
  --- came back from the undo file, or `stale` when it is for other files.
  record UndoFileOpen
    states: integer
    stale: boolean
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
    parts: DiffCount
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

  --- What `paw.api.undo_adjust()` found (`undo::AdjustStatus`): `ready`,
  --- the project is as it was before the last step; `old`, the current
  --- state has later ones; `other`, the current step is not the command's;
  --- `kept`, the step was saved or named and cannot change.
  enum AdjustStatus
    "ready"
    "old"
    "other"
    "kept"
  end

  --- `paw.api.undo_adjust()`: whether the last step can be made again, and
  --- the name that the current step had.
  record UndoAdjust
    status: AdjustStatus
    label: string
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
    nest: integer
    play: string | NestPart
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

  --- A part as a project file holds it (`model::Part`).
  record PartData
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
    nest: integer
  end

  --- A subproject as a project file holds it (`model::Nest`).
  record NestData
    id: integer
    name: string
    length: number
    tempo: NestTempo
    meter: NestMeter
    master: integer
    kind: string
    meta: Meta
    source: string
    origin: string
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
    master: PartData
    parts: {PartData}
    nests: {NestData}
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
    part: string
    year: string
    genre: string
    comment: string
    cover: string
  end

  --- The point in the signal where a render listens (`render::Tap`).
  enum RenderTap
    "pre"
    "post"
    "groups"
    "master"
  end

  --- The channels of a rendered file (`render::Channels`): `auto` is one
  --- channel when the two sides are equal to the bit, else two.
  enum RenderChannels
    "stereo"
    "mono"
    "auto"
  end

  --- What `paw.api.render` and `render_start` take (`RenderOpts`): `start`
  --- and `end` in beats, `tail` and `settle` in seconds.
  record RenderOptions
    start: number
    ["end"]: number
    tail: number
    sample_rate: integer
    bits: integer
    parts: {integer}
    freeze: integer
    block: integer
    through: {integer}
    dither: boolean
    normalize: number
    loudness: number
    gain: number
    channels: RenderChannels
    tap: RenderTap
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
  --- beats, `tail` in seconds; `part` measures that part's share, `file`
  --- a sound file instead of the project.
  record MeasureOptions
    start: number
    ["end"]: number
    tail: number
    sample_rate: integer
    part: integer
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

  --- The peak of one part's output in a measurement (`PartPeak`).
  record PartPeak
    id: integer
    peak: number
    peak_at: number
    over_at: number
  end

  --- What a measurement gives (`analysis::Analysis` with the parts' peaks,
  --- `elapsed`, `floor`, and what was measured: `file`, or `start`,
  --- `tempo`, `end`, `tail`, `part` and `edits`). Levels in LUFS, LU, dB.
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
    centroid: number
    series: MeasureSeries
    parts: {PartPeak}
    elapsed: number
    floor: number
    file: string
    start: number
    tempo: number
    ["end"]: number
    tail: number
    part: integer
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

  --- What a build of paw has (`build`): its Lua and the features that
  --- the `needs` of a manifest names.
  record Build
    vm: string
    features: {string}
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
    --- The window's folds (paw/folds.tl) and its fold level: only in the
    --- screen a project keeps.
    folds: {SavedFold}
    foldlevel: integer
    --- The window's vertical zoom (paw/vzoom.tl): only in the screen a
    --- project keeps.
    vzoom: SavedVZoom
  end

  --- A window's vertical zoom as the project's screen keeps it: rows
  --- per part, `parts` (`{ part, rows }` each), rows per automation
  --- lane and rows per key of the piano roll.
  record SavedVZoom
    part_rows: integer
    parts: {SavedPartRows}
    lane_rows: integer
    key_rows: integer
  end

  --- The rows of one part in a saved vertical zoom.
  record SavedPartRows
    part: integer
    rows: integer
  end

  --- A fold of a window as the project's screen keeps it.
  record SavedFold
    kind: string
    id: integer
    parts: {integer}
    from: number
    to: number
    name: string
    closed: boolean
  end

  --- A level of a window's scope stack as the project's screen keeps it.
  record SavedScope
    kind: string
    id: integer
    parts: {integer}
    from: number
    to: number
    name: string
    clip: integer
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
    --- The workspaces that `:workspace.save!` keeps, by name, and the
    --- one that the project opens in.
    workspaces: {string: SavedLayout}
    workspace: string
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
