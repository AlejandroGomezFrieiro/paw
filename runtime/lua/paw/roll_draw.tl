-- `paw.roll_draw`: the piano roll's insert mode, a pencil that draws notes
-- with the cursor and knows the note under it.
--
-- `i` on an empty place starts a note there, nothing long yet; `i` on a
-- note takes that note, at its start, and `a` at its end. The pencil has
-- an edge, the start or the end of its note, where the cursor is: `l` and
-- `h` move that edge a grid step right and left, so at the end `l`
-- lengthens and at the start `l` shortens. `o` goes to the other edge.
-- `+` `-` move the pitch, `j` `k` bend the note (its own MIDI 2.0 pitch
-- bend), `<` `>` move it in time, `c` makes it a chord. `<CR>` keeps it
-- and starts the next where it ends, and takes up a note that starts
-- there. `<Esc>` writes them all and leaves.
--
-- Nothing reaches the project until insert mode ends: then every note
-- drawn is written at once, which makes the whole of it one undo step and
-- lets `.` in normal mode draw the same shape again at the cursor, as Vim
-- repeats an insert.
--
-- The other way in, `paw.opt.roll_insert = "keys"` or `I`, turns the
-- keyboard into a piano instead (`view:enter`); this module then stays out
-- of the way.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local options = require("paw.options")
local seats = require("paw.seats")
local util = require("paw.util")
local music = require("paw.music")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")
local type objects = require("paw.objects")
local type DrawModule = require("paw.draw")
local type HarmonyModule = require("paw.harmony")
local type ChordsModule = require("paw.chords")
local type MarkersModule = require("paw.markers")
local type TempoModule = require("paw.tempo")
local type CommandsModule = require("paw.commands")

--- The edge of the note being drawn that the cursor is on.
local enum Edge
  "start"
  "end"
end

--- A note of a clip that the pencil took up: where it was, to change it
--- in its place (and the controllers that are its own with it).
local record Source
  clip: integer
  id: integer
  pitch: integer
  --- Project beats.
  start: number
  length: number
end

--- What an articulation sets on a note: its MIDI 2.0 attribute, or its
--- meta (where the core does not keep attributes).
local record ArtFields
  attr: types.NoteAttr
  meta: types.Meta
end

--- Where the pencil's articulations come from (`M.articulation`): an
--- extension that knows the instrument of a track. `names(track)` for
--- completion, `apply(track, text, note)` the fields for a note, or nil
--- and why not.
local record ArtProvider
  names: function(track: integer): {string}
  apply: function(track: integer, text: string, note: types.Note): ArtFields, string
end

--- Candidates that `<C-n>` `<C-p>` step through in place: their pitches,
--- their names, the one shown, and the pitches before.
local record Suggest
  list: {{integer}}
  names: {string}
  at: integer
  before: {integer}
end

--- A note's own pitch bend as the pencil draws it: `semis` at its end,
--- reached by a ramp that starts `ramp` beats before the end (half the
--- note when nil).
local record Bend
  semis: number
  ramp: number
end

--- A note drawn or kept, in project beats: what stays put when the active
--- clip changes. `source` is the clip's note it changes, nil for a new one.
local record Drawn
  pitch: integer
  start: number
  length: number
  velocity: integer
  source: Source
  bend: Bend
  --- Bent with `j` `k`: its bend is written again.
  bent: boolean
  --- The note being drawn, not one kept (for the look).
  pending: boolean
  --- What an articulation gives the note (`a`): its attribute or meta.
  fields: ArtFields
end

--- What insert mode holds: the notes kept so far, the notes being drawn
--- (`pen[1]` the one the cursor is on; more for a chord), the edge, the
--- digits typed for the next key, the notes taken up and erased, the
--- length being typed after `=`, and where it all began.
local record Session
  notes: {Drawn}
  pen: {Drawn}
  edge: Edge
  count: integer
  removed: {Source}
  reading: string
  named: boolean
  first: Drawn
  last: {Drawn}
  --- The name of the chord being drawn, nil for a note.
  chord: string
  --- The undo state when the drawing began: what it edits joins one step.
  undo: integer
  --- The notes being drawn are a strum: they end together.
  strum: boolean
  --- What `<C-n>` `<C-p>` offer now.
  suggest: Suggest
end

--- An edited clip of the roll (paw/roll_clips.lua): its id, the clip, and
--- where it starts in the roll's beats (`offset`) and the project's.
local record Part
  id: integer
  clip: objects.Clip
  offset: number
  start: number
  length: number
  track: integer
end

local record Clips
  parts: function(): {Part}
  target: function(beat: number, parts?: {Part}): Part
  span: function(): number, number
end

--- What a layer of the piano roll gets (paw/views/pianoroll.lua).
local record Layer
  data: types.Clip
  plane: contracts.Plane
  width: integer
  hue: DrawModule.Hue
  row: function(pitch: integer): integer
  x: function(beat: number): integer
end

--- The props of a note mark (paw/roles/notes.lua).
local record NoteMark is contracts.MarkProps
  label: string
  style: string
  color: string
  velocity: integer
  pending: boolean
  bend: number
  bend_at: number
end

--- The piano roll, as far as this module reads it.
local record Roll
  beat: number
  pitch: integer
  clip: function(self: Roll): objects.Clip
  step_length: function(self: Roll): number
  layer: function(name: string, order: integer, paint: function(Layer))
end

local record Frontend
  refresh: function()
end

local record Theme
  palette: {string: string}
end

local record Paw is partial.Paw
  ui: UiModule
  draw: DrawModule
  harmony: HarmonyModule
  chords: ChordsModule
  markers: MarkersModule
  tempo: TempoModule
  pick: function(spec: contracts.PickSource<ChordsModule.Voiced>)
  time: objects.Time
  clip: function(id: integer): objects.Clip
  roll_clips: Clips
  frontend: Frontend
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

--- The payload of `mode.changed` (paw/keymap.lua).
local record ModeChanged
  mode: string
  old: string
end

--- A key an extension adds to the pencil (`M.key`): `run(count, char)`.
local record PencilKey
  desc: string
  char: boolean
  run: function(count: integer, char: string)
end

local record M
  type Drawn = Drawn
  type ArtFields = ArtFields
  type ArtProvider = ArtProvider
  --- Where `a` takes articulations from: set by an extension.
  articulations: ArtProvider
  type Bend = Bend
  type PencilKey = PencilKey
  type Edge = Edge
  --- The keys extensions added, by their keys (`M.key`).
  keys: {string: PencilKey}
  --- A clip's controller moves, none read when it has none.
  controls_of: function(id: integer): {types.Control}
end
M.keys = {}

-- How insert mode in the piano roll enters notes: "draw" with the cursor,
-- or "keys", the keyboard as a piano.
options.define("roll_insert", "draw")
-- Semitones each `j` `k` bends the note being drawn.
local bend_step = options.define("bend_step", 1 as number)
-- Beats between the notes of a strum (`C`): a 64th note.
local strum_step = options.define("strum", 1 / 16 as number)
-- Which way a strum goes: "up" from the lowest note, or "down".
local strum_dir = options.define("strum_dir", "up", {values = {"up", "down"}})

local EPS = 1e-9
-- How far a note's own bend reaches each way (MIDI 2.0's default, the engine's NOTE_BEND_RANGE).
local BEND_RANGE = 48
-- The finest step of a bend's ramp, in beats, and the most steps it takes.
local RAMP_STEP, RAMP_STEPS = 1 / 32, 32

local session: Session
local keys_once: boolean -- `I` asked for the piano keys this time
local how_next: string -- how the next insert mode takes up a note: "a" at its end
local record Seat
  session: Session
  keys_once: boolean
end
seats.keep(
  "roll_draw",
  function(): Seat return {session = session, keys_once = keys_once} end,
  function(s: Seat) session, keys_once = s.session, s.keys_once end,
  function(): Seat return {} end
)

local function roll(): Roll
  return paw.ui.views.pianoroll as Roll
end
local function clips(): Clips
  return paw.roll_clips
end

local function changed()
  if paw.frontend then
    paw.frontend.refresh()
  else
    api.ui_redraw()
  end
end

--- Where the active clip starts in the project, or nil with none open.
local function origin(): number
  local clip = roll():clip()
  return clip and clip.start
end

--- True if you draw a note now: insert mode in the piano roll, the kind that draws.
function M.active(): boolean
  return session ~= nil and paw.keymap.mode == "i"
end

local function finish_of(d: Drawn): number
  return d.start + d.length
end

local function key_of(clip: integer, id: integer): string
  return clip .. ":" .. id
end

--- The notes of clips that the pencil holds: taken up, kept or erased.
local function taken(): {string: boolean}
  local out: {string: boolean} = {}
  if not session then
    return out
  end
  for _, list in ipairs({session.notes, session.pen}) do
    for _, d in ipairs(list) do
      if d.source then
        out[key_of(d.source.clip, d.source.id)] = true
      end
    end
  end
  for _, s in ipairs(session.removed) do
    out[key_of(s.clip, s.id)] = true
  end
  return out
end

--- A note's own bend, as its clip holds it: the per-note pitch bend moves
--- on its key from its start to its end. Nil for none.
local function bend_in(controls: {types.Control}, pitch: integer, start: number, length: number): Bend
  local first: number
  local last: number
  for _, c in ipairs(controls) do
    if c.type == "bend" and c.key == pitch and c.start >= start - EPS and c.start < start + length - EPS then
      if not first and math.abs(c.value) > EPS then
        first = c.start
      end
      last = c.value
    end
  end
  if not first or not last or math.abs(last) <= EPS then
    return nil
  end
  return {semis = last * BEND_RANGE, ramp = start + length - first}
end

--- Per-note bends of a clip, read once for each frame that shows it.
local function controls_of(id: integer): {types.Control}
  local c = api.clip_get(id)
  if (c.control_count or 0) == 0 then
    return {}
  end
  return api.clip_controls(id)
end

--- The bend of a note of a clip in the clip's beats, or nil: `semis` at
--- its end and where its ramp starts, as a fraction of its length. The
--- piano roll shows it on the note, `K` says it.
function M.bend_of(controls: {types.Control}, note: types.Note): number, number
  local b = bend_in(controls, note.pitch, note.start, note.length)
  if not b then
    return nil
  end
  return b.semis, note.length > EPS and util.clamp(1 - b.ramp / note.length, 0, 1) or 0
end

M.controls_of = controls_of

--- The note of a clip edited in the roll that `fits(start, finish)` on a
--- pitch, in project beats, and its part. Notes the pencil holds are left out.
local function find(pitch: integer, fits: function(start: number, finish: number): boolean): types.Note, Part
  local held = taken()
  for _, part in ipairs(clips().parts()) do
    local notes = part.clip:notes({low = pitch, high = pitch})
    for _, n in ipairs(notes) do
      local start = n.start + part.start
      if not held[key_of(part.id, n.id)] and fits(start, start + n.length) then
        return n, part
      end
    end
  end
end

--- A new note at `start` (project beats) on `pitch`, no length yet.
local function fresh(pitch: integer, start: number): Drawn
  return {pitch = pitch, start = start, length = 0, velocity = opt.velocity}
end

--- A clip's note as the pencil holds it, with its bend.
local function took(n: types.Note, part: Part): Drawn
  local start = n.start + part.start
  return {
    pitch = n.pitch,
    start = start,
    length = n.length,
    velocity = n.velocity,
    source = {clip = part.id, id = n.id, pitch = n.pitch, start = start, length = n.length},
    bend = bend_in(controls_of(part.id), n.pitch, n.start, n.length),
  }
end

--- The pencil at `beat` (project) on `pitch`: on the note there, or a new
--- one. `how` "i" takes the note under it at its start, "a" the note
--- under it or ending at the beat at its end (else a new one a step on),
--- "next" a note that starts at the beat, at its start.
local function take(beat: number, pitch: integer, how: string)
  local n, part: types.Note, Part
  if how ~= "next" then
    n, part = find(pitch, function(s: number, f: number): boolean return s <= beat + EPS and f > beat + EPS end)
  end
  if n then
    session.pen, session.edge = {took(n, part)}, how == "a" and "end" or "start"
    return
  end
  if how == "next" then
    n, part = find(pitch, function(s: number): boolean return math.abs(s - beat) < EPS end)
    if n then
      session.pen, session.edge = {took(n, part)}, "start"
      return
    end
  elseif how == "a" then
    n, part = find(pitch, function(_: number, f: number): boolean return math.abs(f - beat) < EPS end)
    if n then
      session.pen, session.edge = {took(n, part)}, "end"
      return
    end
  end
  if how == "a" then
    beat = beat + opt.note_grid
  end
  session.pen, session.edge = {fresh(pitch, beat)}, "end"
end

--- Where the cursor goes: the edge of the note being drawn.
local function edge_beat(): number
  local d = session.pen[1]
  return session.edge == "start" and d.start or finish_of(d)
end

--- The cursor goes to the edge of the note being drawn. It may go past the
--- end of the clip, which grows when the note is written.
local function place()
  local r, at = roll(), origin()
  if not at then
    return
  end
  r.pitch = session.pen[1].pitch
  r.beat = edge_beat() - at
  changed()
end

--- Take up what is at the cursor, if something else moved it (a click, a
--- suggestion accepted): the pencil starts afresh there.
local function sync()
  local at = origin()
  if not session or not at then
    return
  end
  local r = roll()
  if r.pitch ~= session.pen[1].pitch or math.abs(r.beat + at - edge_beat()) > EPS then
    take(r.beat + at, r.pitch, "i")
  end
end

--- Start drawing at the cursor. `how` as `take` has it: "i" or "a".
function M.start(how?: string)
  local at = origin()
  if not at then
    return
  end
  local r = roll()
  session = {notes = {}, pen = {}, edge = "end", removed = {}, undo = api.undo_current()}
  take(r.beat + at, r.pitch, how or "i")
  local d = session.pen[1]
  session.first = {pitch = d.pitch, start = d.start, length = 0, velocity = d.velocity}
  place()
end

--- The next insert mode takes up the note under the cursor at its end, or
--- starts a step on (`a`).
function M.append()
  how_next = "a"
end

--- The count typed so far, taken: 1 when there is none.
local function take_count(): integer
  local n = session.count or 1
  session.count = nil
  return n
end

--- True if a count was typed for the key that takes it now.
local function counted(): boolean
  local given = session.count ~= nil
  return given
end

--- What every key of the pencil does first: the cursor's note, the count;
--- the length typed after `=` and a pitch named by `r` end here.
local function begin(): boolean
  if not session then
    return false
  end
  sync()
  session.reading, session.named, session.suggest = nil, nil, nil
  return true
end

--- A strum's notes end together, where the one that starts first ends.
local function align()
  if not session.strum then
    return
  end
  local first = session.pen[1]
  for _, d in ipairs(session.pen) do
    if d.start < first.start then
      first = d
    end
  end
  local finish = first.start + first.length
  for _, d in ipairs(session.pen) do
    d.length = math.max(0, finish - d.start)
  end
end

--- What the drawing edits after its first edit joins that step: the
--- marks of the song (asked on a prompt, outside insert mode's keys) and
--- the notes written at the end.
local function join()
  if session.undo and api.undo_current() ~= session.undo then
    api.undo_join(api.undo_current())
  end
end

--- The notes on `pitch` around a note, in project beats: where the one
--- before it ends and where the one after it starts. The notes the pencil
--- holds count where it holds them.
local function room(d: Drawn): number, number
  local before, after = -math.huge, math.huge
  local function see(s: number, f: number)
    if s < d.start - EPS then
      before = math.max(before, f)
    end
    if s > d.start + EPS then
      after = math.min(after, s)
    end
  end
  local held = taken()
  for _, part in ipairs(clips().parts()) do
    local notes = part.clip:notes({low = d.pitch, high = d.pitch})
    for _, n in ipairs(notes) do
      if not held[key_of(part.id, n.id)] then
        see(n.start + part.start, n.start + part.start + n.length)
      end
    end
  end
  for _, list in ipairs({session.notes, session.pen}) do
    for _, o in ipairs(list) do
      if o ~= d and o.pitch == d.pitch and o.length > EPS then
        see(o.start, finish_of(o))
      end
    end
  end
  return before, after
end

--- Where the clips edited start, in project beats: no note goes before.
local function lowest(): number
  local lo = clips().span()
  return (origin() or 0) + (lo or 0)
end

--- Say that a note stops at a neighbour of the same pitch.
local function blocked(d: Drawn)
  paw.notify(
    music.name(d.pitch) .. " stops at the next " .. music.name(d.pitch) .. ": notes of one pitch do not overlap", "warn"
  )
end

--- Move the edge under the cursor `steps` grid steps right, or left with a
--- negative count: at the end, the note grows; at its start, it shrinks.
--- No note grows over the next note of its pitch.
function M.grow(steps: integer)
  if not begin() then
    return
  end
  local delta = steps * take_count() * opt.note_grid
  local hit = false
  for _, d in ipairs(session.pen) do
    local before, after = room(d)
    if session.edge == "end" then
      if delta > after - finish_of(d) then
        delta, hit = math.max(0, after - finish_of(d)), true
      end
      delta = math.max(delta, -d.length)
    else
      delta = math.min(delta, d.length)
      local floor = math.max(before, lowest())
      if delta < floor - d.start then
        delta, hit = math.min(0, floor - d.start), before > lowest()
      end
    end
  end
  for _, d in ipairs(session.pen) do
    if session.edge == "start" then
      d.start = d.start + delta
    end
    d.length = math.max(0, d.length + (session.edge == "end" and delta or -delta))
  end
  if session.edge == "end" then
    align()
  end
  if hit then
    blocked(session.pen[1])
  end
  place()
end

--- Move the notes being drawn `steps` grid steps later, or earlier: `>` `<`.
function M.nudge(steps: integer)
  if not begin() then
    return
  end
  local delta = steps * take_count() * opt.note_grid
  local hit = false
  for _, d in ipairs(session.pen) do
    local before, after = room(d)
    if delta > after - finish_of(d) then
      delta, hit = math.max(0, after - finish_of(d)), true
    end
    local floor = math.max(before, lowest())
    if delta < floor - d.start then
      delta, hit = math.min(0, floor - d.start), before > lowest()
    end
  end
  for _, d in ipairs(session.pen) do
    d.start = d.start + delta
  end
  if hit then
    blocked(session.pen[1])
  end
  place()
end

--- Shorten a note that now runs over the next note of its pitch.
local function fit(d: Drawn)
  local _, after = room(d)
  if finish_of(d) > after + EPS then
    d.length = math.max(0, after - d.start)
    blocked(d)
  end
end

--- Hear the note under the cursor.
local function audition()
  local at = origin()
  local part = at and clips().target(session.pen[1].start - at)
  if part then
    part.clip:track():play_note(session.pen[1].pitch, opt.velocity, 180)
  end
end

--- Move the notes being drawn by `semitones` (times the count), and hear
--- the new pitch. `step(pitch, n)`, if given, says where `n` such moves go
--- instead: by steps of a scale, say.
function M.pitch(semitones: integer, step?: function(pitch: integer, n: integer): integer)
  if not begin() then
    return
  end
  local n = take_count()
  session.chord = nil
  for _, d in ipairs(session.pen) do
    local to = step and step(d.pitch, n) or d.pitch + semitones * n
    d.pitch = util.clamp(to, 0, 127) as integer
    fit(d)
  end
  place()
  audition()
end

--- Set the pitch by its name (`r` then a letter): the nearest of that
--- name, the chord with it. `#` and `b` next make it sharp or flat.
function M.name(letter: string)
  if not begin() then
    return
  end
  session.count = nil
  local pc = ({c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11} as {string: integer})[(letter or ""):lower()]
  if not pc then
    return paw.notify("r takes a note's name: c d e f g a b", "warn")
  end
  local root = session.pen[1].pitch
  local delta = (pc - root) % 12
  if delta > 6 then
    delta = delta - 12
  end
  for _, d in ipairs(session.pen) do
    d.pitch = util.clamp(d.pitch + delta, 0, 127) as integer
    fit(d)
  end
  place()
  audition()
  session.named = true
end

--- `#` or `b` right after `r` and a name: a semitone up or down.
function M.accidental(semitones: integer): boolean
  if not session or not session.named then
    return false
  end
  M.pitch(semitones)
  return true
end

--- Bend the notes being drawn by `dir` steps of `bend_step` semitones
--- (times the count): their own pitch bend rises (or falls) to that at
--- their end, from half of each.
function M.bend(dir: integer)
  if not begin() then
    return
  end
  local n = take_count()
  for _, d in ipairs(session.pen) do
    local b = d.bend or {semis = 0}
    b.semis = util.clamp(b.semis + dir * n * bend_step:get(), -BEND_RANGE, BEND_RANGE)
    b.ramp = nil
    d.bend, d.bent = b, true
  end
  changed()
end

--- Go to the other edge of the note (`o`), or to `edge`.
function M.edge(edge?: Edge)
  if not begin() then
    return
  end
  session.count = nil
  session.edge = edge or (session.edge == "start" and "end" or "start")
  place()
end

--- The velocity of the notes being drawn and of the next, by `dir` tens.
function M.velocity(dir: integer)
  if not begin() then
    return
  end
  local n = take_count()
  opt.velocity = util.clamp(opt.velocity + 10 * dir * n, 1, 127) as integer
  for _, d in ipairs(session.pen) do
    d.velocity = util.clamp(d.velocity + 10 * dir * n, 1, 127) as integer
  end
  changed()
end

--- Keep the notes being drawn among those to write, replacing new ones
--- kept before at the same pitch and start. One of no length is kept only
--- when it was a clip's note: it goes, then.
local function put()
  for _, d in ipairs(session.pen) do
    if d.length > EPS or d.source then
      for i = #session.notes, 1, -1 do
        local n = session.notes[i]
        if not n.source and not d.source and n.pitch == d.pitch and math.abs(n.start - d.start) < EPS then
          table.remove(session.notes, i)
        end
      end
      if d.length <= EPS then
        session.removed[#session.removed + 1] = d.source
      else
        session.notes[#session.notes + 1] = d
      end
    end
  end
end

local function copy(d: Drawn): Drawn
  return {
    pitch = d.pitch,
    start = d.start,
    length = d.length,
    velocity = d.velocity,
    bend = d.bend and {semis = d.bend.semis, ramp = d.bend.ramp},
    bent = d.bend ~= nil,
    fields = d.fields,
  }
end

--- Keep the notes and go on. "legato" starts the next note at the end,
--- "rest" a step (or count steps) after it; a note of the clip that starts
--- there is taken up. "chord" draws another note at the same start and as
--- long (`chord`'s count stacks).
function M.next(how: string)
  if session and session.suggest and how == "legato" then
    session.suggest = nil
    paw.notify("taken")
    return place()
  end
  if not begin() then
    return
  end
  local n = take_count()
  local d = session.pen[1]
  put()
  session.last = session.pen
  if how == "chord" then
    session.pen = {copy(d)}
    session.pen[1].bend, session.pen[1].bent = nil, nil
    return place()
  end
  take(finish_of(d) + (how == "rest" and n * opt.note_grid or 0), d.pitch, "next")
  place()
end

--- Keep the notes being drawn and draw them again where they end (`.`),
--- count times.
function M.again()
  if not begin() then
    return
  end
  local n = take_count()
  local shape = session.pen
  if shape[1].length <= EPS and session.last then
    shape = session.last
  end
  if shape[1].length <= EPS then
    return paw.notify("nothing to draw again yet", "warn")
  end
  for _ = 1, n do
    put()
    local from = finish_of(session.pen[1])
    local list: {Drawn} = {}
    for i, d in ipairs(shape) do
      list[i] = copy(d)
      list[i].start = from + (d.start - shape[1].start)
    end
    session.pen = list
  end
  session.edge = "end"
  place()
end

--- Make the notes being drawn these pitches, the first under the cursor:
--- a chord at the same start and as long.
function M.chord(pitches: {integer}, name?: string)
  if not begin() then
    return
  end
  session.count = nil
  session.chord = name
  session.strum = nil
  local d = session.pen[1]
  local list: {Drawn} = {d}
  for i = 2, #pitches do
    list[i] = {
      pitch = util.clamp(pitches[i], 0, 127) as integer, start = d.start, length = d.length, velocity = d.velocity
    }
  end
  d.pitch = util.clamp(pitches[1], 0, 127) as integer
  session.pen = list
  for _, n in ipairs(list) do
    fit(n)
  end
  place()
end

--- The key a marker names: "key D minor", or nil.
local function key_of_marker(name: string): HarmonyModule.Key
  local spec = (name or ""):match("^key:?%s+(.+)$")
  if not spec then
    return nil
  end
  local ok, key = pcall(paw.harmony.parse_key, spec) as (boolean, HarmonyModule.Key)
  return ok and key or nil
end

--- The key the pencil's chords are in: of the last key change (`mk`, a
--- marker "key D minor") at or before the pencil, else the project's,
--- else C major, said.
local function key_here(): HarmonyModule.Key
  local beat = session.pen[1].start
  local found: HarmonyModule.Key
  for _, m in ipairs(paw.markers.list()) do
    local k = m.beat <= beat + EPS and key_of_marker(m.name) or nil
    if k then
      found = k
    end
  end
  if found then
    return found
  end
  if not paw.harmony.project_key() then
    paw.notify("no key set: the chords are those of C major (:key sets one, mk a change)")
    return paw.harmony.parse_key("C major")
  end
  return paw.harmony.key(beat)
end

local KEY_NAMES: {string} = {}
for _, root in ipairs({"C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"}) do
  KEY_NAMES[#KEY_NAMES + 1] = root .. " major"
  KEY_NAMES[#KEY_NAMES + 1] = root .. " minor"
end

--- What a mark asks, its prompt, and what it does with the answer at the
--- pencil's beat: true when done, or false and why not.
local record MarkKind
  prompt: string
  text: function(beat: number): string
  complete: {string}
  put: function(beat: number, text: string): boolean, string
end

local MARKS: {string: MarkKind} = {
  k = {
    prompt = "Key from here: ",
    complete = KEY_NAMES,
    text = function(_: number): string return "" end,
    put = function(beat: number, text: string): boolean, string
      local ok, key = pcall(paw.harmony.parse_key, text) as (boolean, HarmonyModule.Key)
      if not ok then
        return false, "not a key: " .. text
      end
      if beat <= EPS and not paw.harmony.project_key() then
        paw.harmony.set_key(key)
      else
        paw.markers.add(beat, "key " .. paw.harmony.key_name(key))
      end
      return true
    end,
  },
  t = {
    prompt = "Tempo from here (96, or 96~ to ramp to the next): ",
    text = function(beat: number): string return string.format("%g", paw.tempo.at(beat)) end,
    put = function(beat: number, text: string): boolean, string
      local bpm, ramp = text:match("^%s*([%d%.]+)%s*(~?)%s*$")
      local n = tonumber(bpm)
      if not n or n < 1 or n > 960 then
        return false, "a tempo is 1 to 960 BPM"
      end
      paw.tempo.set(beat, n, {ramp = ramp == "~"})
      return true
    end,
  },
  s = {
    prompt = "Time signature from this bar: ",
    text = function(beat: number): string local num, den = paw.tempo.signature_at(beat); return num .. "/" .. den end,
    put = function(beat: number, text: string): boolean, string
      local num, den = text:match("^%s*(%d+)%s*/%s*(%d+)%s*$")
      local a, b = math.tointeger(tonumber(num)), math.tointeger(tonumber(den))
      if not a or not b or a < 1 or b < 1 then
        return false, "a time signature is like 6/8"
      end
      local bar = paw.tempo.bar_of(beat)
      if not paw.tempo.is_bar_line(beat) then
        bar = bar + 1
      end
      paw.tempo.set_signature(bar, a, b)
      return true
    end,
  },
  r = {
    prompt = "Region from here to the end of the note (a name, or none): ",
    text = function(_: number): string return "" end,
    put = function(beat: number, text: string): boolean, string
      local d = session and session.pen[1]
      local length = d and d.length > 1e-9 and (d.start + d.length - beat)
        or paw.tempo.bar_start(paw.tempo.bar_of(beat) + 1) - beat
      paw.markers.add(beat, text, {length = length})
      return true
    end,
  },
  ["'"] = {
    prompt = "Marker here: ",
    text = function(_: number): string return paw.markers.default_name() end,
    put = function(beat: number, text: string): boolean, string paw.markers.add(beat, text); return true end,
  },
}

-- The controllers `e` names: modulation, expression, breath, the sustain pedal.
local EXPRESSIONS: {string: integer} = {m = 1, e = 11, b = 2, s = 64}

--- Put the value of a controller at the pencil's start in its clip, as one
--- edit of the insert's undo step: a point of `number` at `value` (0 to 127).
local function put_control(number: integer, value: integer)
  local at = origin()
  if not at then
    return
  end
  local d = session.pen[1]
  local part = clips().target(d.start - at)
  if not part then
    return
  end
  local start = d.start - part.start
  local list: {types.Control} = {}
  for _, c in ipairs(controls_of(part.id)) do
    if not (c.type == "cc" and c.number == number and not c.key and math.abs(c.start - start) < EPS) then
      list[#list + 1] = c
    end
  end
  list[#list + 1] = {start = start, type = "cc", number = number, value = util.clamp(value, 0, 127) / 127}
  table.sort(list, function(a: types.Control, b: types.Control): boolean return a.start < b.start end)
  join()
  api.clip_set_controls(part.id, list)
  paw.notify(string.format("CC %d at %d from %s", number, value, music.name(d.pitch)))
  changed()
end

--- A point of expression at the pencil (`e` then what): `em` the
--- modulation wheel, `ee` expression, `eb` breath, `es` the sustain pedal,
--- `e` and a number any controller. A count first is the value (`100em`);
--- else paw asks it.
function M.expression(what: string)
  if not begin() then
    return
  end
  local given = counted()
  local value = take_count()
  local number = EXPRESSIONS[what or ""]
  local function ask(n: integer)
    if given then
      return put_control(n, value)
    end
    paw.ui.input(
      {prompt = string.format("CC %d value (0 to 127): ", n), mode = "i"},
      function(text: string)
        local v = math.tointeger(tonumber(text))
        if not v or v < 0 or v > 127 then
          return paw.notify("a value is 0 to 127", "warn")
        end
        if session then
          put_control(n, v)
        end
      end
    )
  end
  if number then
    return ask(number)
  end
  if what and what:match("^%d$") then
    paw.ui.input(
      {prompt = "Controller number: ", text = what, mode = "i"},
      function(text: string)
        local n = math.tointeger(tonumber(text))
        if not n or n < 0 or n > 127 then
          return paw.notify("a controller is 0 to 127", "warn")
        end
        if session then
          ask(n)
        end
      end
    )
    return
  end
  paw.notify("e then m modulation, e expression, b breath, s sustain, or a controller's number", "warn")
end

--- Put a mark of the song at the pencil's start (`m` then its kind): `k`
--- a key change, `t` a tempo, `s` a time signature from the bar, `'` a
--- marker. Each asks its value, and is in the insert's undo step.
function M.mark(kind: string)
  if not begin() then
    return
  end
  session.count = nil
  local spec = MARKS[kind]
  if not spec then
    return paw.notify("m then k a key, t a tempo, s a time signature, r a region, ' a marker", "warn")
  end
  local beat = session.pen[1].start
  local complete: function(string): {string | CommandsModule.Entry}
  if spec.complete then
    complete = function(typed: string): {string | CommandsModule.Entry}
      local out: {string | CommandsModule.Entry} = {}
      for _, k in ipairs(spec.complete) do
        if k:lower():find(typed:lower(), 1, true) == 1 then
          out[#out + 1] = k
        end
      end
      return out
    end
  end
  paw.ui.input(
    {prompt = spec.prompt, text = spec.text(beat), mode = "i", complete = complete},
    function(text: string)
      if session then
        join()
      end
      local ok, why = spec.put(beat, text)
      if not ok then
        return paw.notify(why, "warn")
      end
      paw.notify(string.format("from beat %g: %s", beat + 1, text))
    end
  )
end

--- Choose a chord to draw at the pencil (`c`): the diatonic chord on the
--- pencil's pitch first (`4c` its seventh, `5c` its ninth), the others of
--- the key, then common chords on the pitch. Typing searches them; a
--- symbol typed (`V7/V`, `F#m9/C#`, `C4maj7`) is drawn as typed. The
--- chord takes the note's place, its start and length, and the keys shape
--- it as one note until Enter or Escape.
function M.pick_chord(strum?: boolean)
  if not begin() then
    return
  end
  local given = counted()
  local n = take_count()
  -- `C` takes a count as the 64ths between the notes of its strum.
  local lag = strum and (given and n / 16 or strum_step:get()) or 0
  if strum then
    n = 3
  end
  local key = key_here()
  local root = session.pen[1].pitch
  local items: {ChordsModule.Voiced} = {}
  local stack = paw.chords.stack(root, n >= 3 and n or 3, key)
  local names: {string} = {}
  for i, p in ipairs(stack) do
    names[i] = music.name(p)
  end
  items[1] = {
    symbol = table.concat(names, " "),
    name = "diatonic",
    roman = (n >= 3 and n or 3) .. " notes in thirds",
    pitches = stack,
  }
  for _, v in ipairs(paw.chords.offer(key, root)) do
    items[#items + 1] = v
  end
  local function draw(v: ChordsModule.Voiced)
    M.chord(v.pitches, v.name ~= "diatonic" and v.name or nil)
    if not session then
      return
    end
    if v.name == "diatonic" then
      session.chord = nil
    end
    if strum then
      -- From the lowest up (or the highest down), each note a lag later.
      local order: {Drawn} = {}
      for i, d in ipairs(session.pen) do
        order[i] = d
      end
      local down = strum_dir:get() == "down"
      table.sort(
        order,
        function(a: Drawn, b: Drawn): boolean
          if down then
            return a.pitch > b.pitch
          end
          return a.pitch < b.pitch
        end
      )
      local base = session.pen[1].start
      for k, d in ipairs(order) do
        d.start = base + (k - 1) * lag
      end
      session.strum = true
      align()
      place()
    end
  end
  local function line(v: ChordsModule.Voiced): string
    local notes: {string} = {}
    for i, p in ipairs(v.pitches) do
      notes[i] = music.name(p)
    end
    return string.format("%-10s %-8s %s", v.symbol, v.roman or "", table.concat(notes, " "))
  end
  paw.pick(
    {
      title = strum and "Strum" or "Chord",
      prompt = (strum and "strum" or "chord") .. " (a symbol, or search) > ",
      items = items,
      format = line,
      search = function(v: ChordsModule.Voiced): string
        return v.symbol .. " " .. (v.name or "") .. " " .. (v.roman or "")
      end,
      on_choose = draw,
      choose = "draw it",
      actions = {
        -- A symbol typed is drawn as typed; else the line chosen.
        ["<CR>"] = {
          desc = "draw it",
          fn = function(v: ChordsModule.Voiced, query: string)
            local typed = query ~= "" and paw.chords.parse(query, key, root)
            if typed then
              return draw(typed)
            end
            if v then
              return draw(v)
            end
            local _, why = paw.chords.parse(query, key, root)
            paw.notify(why or "no chord", "warn")
          end,
        },
      },
    }
  )
end

--- Pitches in words: "C4 E4 G4".
local function pitches_text_of(list: {Drawn}): string
  local names: {string} = {}
  for i, d in ipairs(list) do
    names[i] = music.name(d.pitch)
  end
  return table.concat(names, " ")
end

--- The track the pencil draws for: the active clip's.
local function track_here(): integer
  local clip = roll():clip()
  return clip and api.clip_get(clip.id).track
end

--- Set where `a` takes articulations from (the articulations extension
--- does): `names(track)` and `apply(track, text, note)`.
function M.articulation(provider: ArtProvider)
  M.articulations = provider
end

--- Give the notes being drawn an articulation (`a`): asked by name, with
--- the names of the track's instrument to complete.
function M.articulate()
  if not begin() then
    return
  end
  session.count = nil
  local provider = M.articulations
  if not provider then
    return paw.notify("no articulations: `:ext.load articulations` gives the pencil its names", "warn")
  end
  local track = track_here()
  local names = provider.names(track) or {}
  local complete = function(typed: string): {string | CommandsModule.Entry}
    local out: {string | CommandsModule.Entry} = {}
    for _, k in ipairs(names) do
      if k:lower():find(typed:lower(), 1, true) == 1 then
        out[#out + 1] = k
      end
    end
    return out
  end
  paw.ui.input(
    {prompt = "Articulation: ", mode = "i", complete = complete},
    function(text: string)
      if not session then
        return
      end
      for _, d in ipairs(session.pen) do
        local fields, why = provider.apply(
          track, text, {pitch = d.pitch, start = d.start, length = d.length, velocity = d.velocity}
        )
        if not fields then
          return paw.notify(why or ("no articulation " .. text), "warn")
        end
        d.fields = fields
      end
      paw.notify(text .. " on " .. pitches_text_of(session.pen))
      changed()
    end
  )
end

-- Suggestions -----------------------------------------------------------------

-- The degrees (0 the tonic) a chord on each degree goes to most, first.
local NEXT_DEGREE: {{integer}} = {
  {3, 4, 5, 1, 2},
  {4, 6, 0},
  {5, 3, 1},
  {4, 0, 1},
  {0, 5, 3},
  {3, 1, 4},
  {0, 2},
}

--- What may come next at the pencil: after a chord, chords of the key that
--- often follow it (the chord kept last, or the one paw.harmony reads
--- before the pencil); after a note, notes of the key near it.
local function candidates(): {{integer}}, {string}
  local key = key_here()
  local pen = session.pen[1]
  local list: {{integer}} = {}
  local names: {string} = {}
  local last = session.last
  local before: {integer}
  if last and #last > 0 then
    before = {}
    for i, d in ipairs(last) do
      before[i] = d.pitch
    end
  end
  local chordal = (before and #before > 1) or #session.pen > 1
  if not before then
    local c = paw.harmony.at(pen.start - 1e-6)
    if c then
      chordal = true
    end
    before = {c and (pen.pitch + ((c.root - pen.pitch) % 12)) or pen.pitch}
  end
  local low = before[1]
  for _, p in ipairs(before) do
    low = math.min(low, p)
  end
  local degree = paw.harmony.degree(key, low) % #key.steps
  if chordal then
    local romans = {"I", "II", "III", "IV", "V", "VI", "VII"}
    for _, step in ipairs(NEXT_DEGREE[degree + 1] or {0}) do
      local root = paw.harmony.degree_pitch(key, step)
      root = root + 12 * math.floor((pen.pitch - root + 6) / 12)
      local pitches = paw.chords.stack(root, 3, key)
      list[#list + 1] = pitches
      local minor = (pitches[2] - pitches[1]) % 12 == 3
      local roman = minor and romans[step + 1]:lower() or romans[step + 1]
      if (pitches[3] - pitches[1]) % 12 == 6 then
        roman = roman .. "o"
      end
      local notes: {string} = {}
      for i, q in ipairs(pitches) do
        notes[i] = music.name(q)
      end
      names[#names + 1] = roman .. " " .. table.concat(notes, " ")
    end
  else
    for _, step in ipairs({1, -1, 2, -2, 0, 4, -3}) do
      local p = paw.harmony.step(key, before[1], step)
      list[#list + 1] = {p}
      names[#names + 1] = music.name(p)
    end
  end
  return list, names
end

--- Show the next (`dir` 1, `<C-n>`) or the previous (-1, `<C-p>`)
--- suggestion in place of the notes being drawn. Any key that edits takes
--- it; `<C-e>` puts back what was there.
function M.suggest(dir: integer)
  if not session then
    return
  end
  sync()
  local s = session.suggest
  if not s then
    local list, names = candidates()
    if #list == 0 then
      return paw.notify("nothing to suggest here", "warn")
    end
    local before: {integer} = {}
    for i, d in ipairs(session.pen) do
      before[i] = d.pitch
    end
    s = {list = list, names = names, at = dir > 0 and 0 or #list + 1, before = before}
  end
  s.at = (s.at + dir - 1) % #s.list + 1
  local pitches = s.list[s.at]
  M.chord(pitches)
  session.suggest = s
  paw.notify(string.format("%d/%d %s · Enter takes it, Ctrl-e puts back", s.at, #s.list, s.names[s.at]))
  audition()
end

--- Put back the notes that were there before the suggestions (`<C-e>`).
function M.unsuggest(): boolean
  if not session or not session.suggest then
    return false
  end
  local before = session.suggest.before
  M.chord(before)
  session.suggest = nil
  return true
end

--- The notes being drawn now, as `{ pitch, start, length, velocity }` in
--- project beats, the one under the cursor first. An extension's key
--- changes them in place, then calls `paw.roll_draw.shown()`.
function M.pen(): {Drawn}
  if not begin() then
    return {}
  end
  return session.pen
end

--- Show what an extension's key changed in the notes being drawn.
function M.shown()
  if session then
    place()
  end
end

--- Erase the notes being drawn (`x`): a clip's note goes when insert mode
--- writes; the pencil stays, with nothing long.
function M.erase()
  if not begin() then
    return
  end
  session.count = nil
  local d = session.pen[1]
  for _, p in ipairs(session.pen) do
    if p.source then
      session.removed[#session.removed + 1] = p.source
    end
  end
  session.pen, session.edge = {fresh(d.pitch, d.start)}, "end"
  place()
end

--- Take back the last note kept: it is the one being drawn again.
function M.back()
  if not begin() then
    return
  end
  session.count = nil
  local last = table.remove(session.notes)
  if not last then
    return
  end
  last.pending = nil
  session.pen, session.edge = {last}, "end"
  place()
end

--- Take back all that this insert drew (`Ctrl-u`): the pencil is where it began.
function M.back_all()
  if not begin() then
    return
  end
  session.count = nil
  local f = session.first
  session.notes, session.removed = {}, {}
  session.pen, session.edge = {fresh(f.pitch, f.start)}, "end"
  place()
end

-- The length in LilyPond's words, typed after `=`: 4 a beat, 8 half of
-- one, 2. a dotted half, 8t a triplet eighth.
local function length_of(text: string): number
  local n, dots, triplet = text:match("^(%d+)(%.*)(t?)$")
  local whole = tonumber(n)
  if
    not whole
    or whole < 1
    or whole > 128
    or math.floor(math.log(whole) / math.log(2) + 0.5) ~= math.log(whole) / math.log(2)
  then
    return nil
  end
  local beats = 4 / whole * (2 - 0.5 ^ (#dots))
  if triplet ~= "" then
    beats = beats * 2 / 3
  end
  return beats
end

--- Start typing a length (`=`), or add to it: each key that makes one
--- sets the notes being drawn that long at once.
function M.length_key(char?: string): boolean
  if not session then
    return false
  end
  if not char then
    begin()
    session.count = nil
    session.reading = ""
    paw.notify("= a length: 1 2 4 8 16 32, . dotted, t triplet")
    return true
  end
  if not session.reading then
    return false
  end
  local text = session.reading .. char
  session.reading = text
  local beats = length_of(text)
  if beats then
    for _, d in ipairs(session.pen) do
      d.length = beats
      fit(d)
    end
    align()
    session.edge = "end"
    place()
  end
  return true
end

--- A digit of the count for the next key, or of a length after `=`.
function M.digit(d: integer)
  if not session then
    return
  end
  if session.reading then
    M.length_key(tostring(d))
    return
  end
  sync()
  if d == 0 and not session.count then
    return M.edge("start")
  end
  session.count = (session.count or 0) * 10 + d
  api.ui_redraw()
end

--- Every note drawn and kept, the ones being drawn last (with `pending`)
--- if they have a length.
local function drawn(): {Drawn}
  local list: {Drawn} = {}
  for _, n in ipairs(session.notes) do
    n.pending = nil
    list[#list + 1] = n
  end
  for _, d in ipairs(session.pen) do
    if d.length > EPS then
      d.pending = true
      list[#list + 1] = d
    end
  end
  return list
end

--- The ids of a clip's notes that the pencil holds, which the roll does not
--- draw where they were: they show where the pencil has them.
function M.hidden(clip: integer): {integer: boolean}
  if not M.active() then
    return nil
  end
  local out: {integer: boolean} = {}
  for k in pairs(taken()) do
    local c, id = k:match("^(%d+):(%d+)$")
    if tonumber(c) == clip then
      out[math.floor(tonumber(id))] = true
    end
  end
  return out
end

--- The ramp of a bend, as the clip holds it: steps of the per-note pitch
--- bend on the note's key from where the ramp starts, the last at the bend.
local function ramp(d: Drawn, start: number): {types.Control}
  local out: {types.Control} = {}
  local b = d.bend
  if not b or math.abs(b.semis) <= EPS or d.length <= EPS then
    return out
  end
  local length = util.clamp(b.ramp or d.length / 2, 0, d.length)
  local steps = math.max(1, math.min(RAMP_STEPS, math.floor(length / RAMP_STEP + 0.5)))
  local from = start + d.length - length
  for i = 0, steps - 1 do
    out[#out + 1] = {
      start = from + i * length / steps, type = "bend", key = d.pitch, value = b.semis * (i + 1) / steps / BEND_RANGE
    }
  end
  return out
end

--- What one clip gets: the changes of its notes, the notes it gains and
--- loses, and its own controllers to change.
local record Edit
  part: Part
  clip: objects.Clip
  set: {types.NoteChange}
  add: {types.Note}
  remove: {integer}
  moves: {Drawn}
  finish: number
end

--- Write what was drawn into the clips, all at once: one undo step. A new
--- note of the same pitch that starts where one is drawn is replaced, a
--- note taken up is changed in its place (with its own controllers), and
--- a clip grows by whole bars to hold what runs past its end. Returns
--- what it did, in words.
local function write(): string
  local at = origin()
  if not at then
    return nil
  end
  local list = drawn()
  if #list == 0 and #session.removed == 0 then
    return nil
  end
  local parts = clips().parts()
  local by_id: {integer: Part} = {}
  for _, p in ipairs(parts) do
    by_id[p.id] = p
  end
  local edits: {integer: Edit} = {}
  local function edit_of(part: Part): Edit
    local e = edits[part.id]
    if not e then
      e = {part = part, clip = part.clip, set = {}, add = {}, remove = {}, moves = {}, finish = 0}
      edits[part.id] = e
    end
    return e
  end
  -- Where each note of a clip is now, by its id.
  local places: {integer: {integer: integer}} = {}
  local function place_of(clip: integer, id: integer): integer
    if not places[clip] then
      places[clip] = {}
      local notes = api.clip_notes(clip)
      for i, n in ipairs(notes) do
        places[clip][n.id] = i
      end
    end
    return places[clip][id]
  end
  local added, changed_n, removed = 0, 0, 0
  for _, s in ipairs(session.removed) do
    local part = by_id[s.clip]
    local i = part and place_of(s.clip, s.id)
    if i then
      local e = edit_of(part)
      e.remove[#e.remove + 1] = i
      e.moves[#e.moves + 1] = {pitch = s.pitch, start = s.start, length = 0, velocity = 0, source = s}
      removed = removed + 1
    end
  end
  for _, n in ipairs(list) do
    local part = n.source and by_id[n.source.clip] or clips().target(n.start - at, parts)
    local start = n.start - part.start
    local i = n.source and place_of(n.source.clip, n.source.id)
    if part and start > -EPS then
      local e = edit_of(part)
      if i then
        local change: types.NoteChange = {
          index = i, pitch = n.pitch, start = start, length = n.length, velocity = n.velocity
        }
        if n.fields then
          change.attr, change.meta = n.fields.attr, n.fields.meta
        end
        e.set[#e.set + 1] = change
        changed_n = changed_n + 1
      else
        local note = (paw.ui.views.pianoroll as {string: function(objects.Clip, types.Note): types.Note}).new_note(
          part.clip, {pitch = n.pitch, start = math.max(0, start), length = n.length, velocity = n.velocity}
        )
        if n.fields then
          if n.fields.attr then
            note.attr = n.fields.attr
          end
          if n.fields.meta then
            note.meta = n.fields.meta
          end
        end
        e.add[#e.add + 1] = note
        added = added + 1
        local found, spots = part.clip:notes({from = start - EPS, to = start + 2 * EPS, low = n.pitch, high = n.pitch})
        for k, old in ipairs(found) do
          if math.abs(old.start - start) < EPS and not taken()[key_of(part.id, old.id)] then
            e.remove[#e.remove + 1] = spots[k]
          end
        end
      end
      if n.bent or n.source then
        e.moves[#e.moves + 1] = n
      end
      e.finish = math.max(e.finish, start + n.length)
    end
  end
  join()
  api.undo_label("Draw notes")
  for _, e in pairs(edits) do
    if e.finish > e.part.length + EPS then
      e.clip.length = paw.time.bar_ceil(e.part.start + e.finish - EPS) - e.part.start
    end
    api.clip_notes_edit(e.part.id, {set = e.set, remove = e.remove, add = e.add})
    -- A note's own controllers go with it; a bend drawn replaces its bend.
    local moved = false
    local controls = controls_of(e.part.id)
    for _, n in ipairs(e.moves) do
      local s = n.source
      local shift = s and (n.start - s.start) or 0
      local new_start, new_finish = n.start - e.part.start, n.start + n.length - e.part.start
      local old_start = s and s.start - e.part.start
      local old_finish = s and s.start + s.length - e.part.start
      if s and (shift ~= 0 or s.pitch ~= n.pitch or n.length <= EPS) then
        local kept: {types.Control} = {}
        for _, c in ipairs(controls) do
          if c.key == s.pitch and c.start >= old_start - EPS and c.start < old_finish - EPS then
            -- An erased note's own moves go with it.
            if n.length > EPS then
              c.key, c.start = n.pitch, c.start + shift
              kept[#kept + 1] = c
            end
            moved = true
          else
            kept[#kept + 1] = c
          end
        end
        controls = kept
      end
      if n.bent then
        local kept: {types.Control} = {}
        for _, c in ipairs(controls) do
          if not (
            c.type == "bend" and c.key == n.pitch and c.start >= new_start - EPS and c.start < new_finish - EPS
          ) then
            kept[#kept + 1] = c
          end
        end
        for _, c in ipairs(ramp(n, new_start)) do
          kept[#kept + 1] = c
        end
        controls, moved = kept, true
      end
    end
    if moved then
      table.sort(controls, function(a: types.Control, b: types.Control): boolean return a.start < b.start end)
      api.clip_set_controls(e.part.id, controls)
    end
  end
  paw.ui.poke()
  local said: {string} = {}
  local function say(n: integer, verb: string)
    if n > 0 then
      said[#said + 1] = string.format("%s %d note%s", verb, n, n == 1 and "" or "s")
    end
  end
  say(added, "wrote")
  say(changed_n, "changed")
  say(removed, "removed")
  return #said > 0 and table.concat(said, ", ") or nil
end

--- End the drawing: write it, and forget it. Returns what it did, in words.
function M.finish(): string
  if not session then
    return nil
  end
  sync()
  local said = write()
  session = nil
  changed()
  return said
end

--- Insert mode the piano keys way this once, whatever `roll_insert` says.
function M.keys_once()
  keys_once = true
end

--- Change from drawing to the piano keys and stay in insert mode. paw
--- writes the drawn notes, and the letters are notes from now on.
function M.to_keys()
  if not session then
    return
  end
  M.finish()
  keys_once = true
  paw.notify("typing notes as a piano: a s d f g h j k are a scale, Esc stops")
end

--- A key of the pencil from an extension: `lhs` in the piano roll's
--- insert mode, `spec.run(count, char)` with the count typed before it
--- (and the key typed after it, with `spec.char`). It reads and changes
--- `paw.roll_draw.pen()`, then calls `paw.roll_draw.shown()`.
---   paw.roll_draw.key("gs", { desc = "Staccato: half as long", run = function(n) ... end })
function M.key(lhs: string, spec: PencilKey)
  M.keys[lhs] = spec
  paw.keymap.set(
    lhs,
    function(ctx: {string: string})
      if not begin() then
        return
      end
      spec.run(take_count(), ctx.char)
    end,
    {view = "pianoroll", mode = "i", desc = spec.desc, char = spec.char or nil}
  )
end

-- Entering insert mode in the piano roll starts a note at the cursor, unless
-- the keys are a piano this time; leaving it writes what was drawn. A
-- prompt asked from insert mode (a chord's name) leaves the drawing as it is.
local record Entered
  clip: objects.Clip
  notes: integer
end
local entered: Entered
events.on(
  events.event("mode.changed") as events.Event<ModeChanged>,
  function(e: ModeChanged)
    if e.old == "i" and e.mode == "c" and session then
      return
    end
    if e.old == "c" and e.mode == "i" and session then
      return changed()
    end
    if e.old == "i" or (e.old == "c" and session) then
      keys_once = nil
      local said = M.finish()
      -- Whatever was entered, drawn or typed, is said once it is in.
      local from = entered
      entered = nil
      if not said and from then
        local ok, notes = pcall(function(): integer return #from.clip:notes() end) as (boolean, integer)
        local added = ok and notes - from.notes or 0
        if added > 0 then
          said = string.format("wrote %d note%s", added, added == 1 and "" or "s")
        end
      end
      if said then
        paw.notify(said)
      end
      return
    end
    if e.mode == "i" and paw.ui.focused == "pianoroll" and roll():clip() then
      local clip = roll():clip()
      entered = {clip = clip, notes = #clip:notes()}
      local how = how_next
      how_next = nil
      if keys_once or opt.roll_insert == "keys" then
        return
      end
      M.start(how)
    end
  end
)

-- What shows ------------------------------------------------------------------

--- A length in grid steps and in beats: "2 steps · 0.5 beats".
local function length_text(length: number): string
  local steps = length / opt.note_grid
  return string.format("%g step%s · %g beat%s", steps, steps == 1 and "" or "s", length, length == 1 and "" or "s")
end

--- A bend in words: "bend +2", or "" for none.
local function bend_text(d: Drawn): string
  if not d.bend or math.abs(d.bend.semis) <= EPS then
    return ""
  end
  return string.format(" · bend %+g", d.bend.semis)
end

--- The pitches being drawn: "C4", or "C4 E4 G4" for a chord.
local function pitches_text(): string
  if session.chord and #session.pen > 1 then
    return session.chord .. (session.strum and " strum" or "")
  end
  local names: {string} = {}
  for i, d in ipairs(session.pen) do
    names[i] = music.name(d.pitch)
  end
  return table.concat(names, " ")
end

--- The note being drawn, in words: `C4 · end · 2 steps · 0.5 beats`, or nil.
function M.describe(): string
  if not M.active() then
    return nil
  end
  sync()
  local d = session.pen[1]
  return pitches_text() .. " · " .. session.edge .. " · " .. length_text(d.length) .. bend_text(d)
end

--- What the piano roll's title says in insert mode.
function M.label(): string
  if not M.active() then
    return string.format("INS C%d  step %g  vel %d", opt.octave, roll():step_length(), opt.velocity)
  end
  sync()
  local d = session.pen[1]
  local what = session.reading and ("=" .. session.reading .. " ") or session.count and (session.count .. " ") or ""
  return string.format(
    "DRAW %s%s %s  %s%s  vel %d", what, pitches_text(), session.edge, length_text(d.length), bend_text(d), d.velocity
  )
end

--- What the window says while in insert mode.
function M.status(): string
  if not M.active() then
    return string.format("entering notes · a is C%d · step %g · Esc to stop", opt.octave, roll():step_length())
  end
  return "drawing "
    .. M.describe()
    .. " · l h move the "
    .. session.edge
    .. " · o the other edge · Enter next · Esc writes"
end

--- The notes that you drew and kept, as "60@1+0.5 64@1+0.5" in the beats of
--- the roll. The second value is the notes that you draw now, "67@1.5+0".
function M.text(): string, string
  if not session then
    return "", nil
  end
  sync()
  local at = origin() or 0
  local out, pen: {string}, {string} = {}, {}
  for _, n in ipairs(session.notes) do
    out[#out + 1] = string.format("%d@%g+%g", n.pitch, n.start - at, n.length)
  end
  for _, n in ipairs(session.pen) do
    pen[#pen + 1] = string.format("%d@%g+%g", n.pitch, n.start - at, n.length)
  end
  return table.concat(out, " "), table.concat(pen, " ")
end

--- The edge the cursor is on: "start" or "end", nil when not drawing.
function M.edge_now(): Edge
  return M.active() and session.edge or nil
end

local styles: {string: string} = {}

--- The terminal's look for the note being drawn: the insert mode's colour,
--- faint behind and bright in front, unlike any clip's notes.
local function pending_style(): string
  local palette = (require("paw.theme") as Theme).palette
  local key = palette.bg .. palette.insert
  if not styles[key] then
    paw.ui.hl("NoteDrawing", {fg = palette.insert, bg = paw.draw.mix(palette.bg, palette.insert, 0.3), bold = true})
    styles[key] = "NoteDrawing"
  end
  return styles[key]
end

-- Above the clips' notes and below a snippet's marks and suggestions: the notes kept, as they
-- will look once written, and the ones being drawn in the insert colour.
roll().layer(
  "draw",
  35,
  function(L: Layer)
    if not M.active() then
      return
    end
    sync()
    local at = L.data.start
    local insert = (require("paw.theme") as Theme).palette.insert
    local colour = paw.draw.track_colour(api.track_get(L.data.track))
    for i, n in ipairs(drawn()) do
      local row = L.row(n.pitch)
      local x0, x1 = L.x(n.start - at), L.x(n.start + n.length - at)
      if row and x1 > 0 and x0 < L.width then
        local b = n.bend and math.abs(n.bend.semis) > EPS and n.bend or nil
        local mark: NoteMark = {
          label = music.name(n.pitch),
          style = n.pending and pending_style() or paw.draw.note_style(L.hue, n.velocity),
          color = n.pending and insert or colour,
          velocity = n.velocity,
          pending = n.pending,
          key = "drawn:" .. i,
          bend = b and b.semis,
          bend_at = b and util.clamp(1 - (b.ramp or n.length / 2) / n.length, 0, 1),
        }
        L.plane:mark("note", n.start - at, n.pitch, n.length, 1, mark)
      end
    end
  end
)

return M
