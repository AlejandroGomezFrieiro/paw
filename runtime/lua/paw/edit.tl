-- Editing by region: what the operators of the arrange view and the piano
-- roll do. A region comes from `paw.keymap` (a motion, a text object or a
-- visual selection) and has rows `r0` to `r1`, beats `c0` up to `c1`, and a
-- `kind`. Everything here is plain calls on `paw.api`, for use from
-- extensions and scripts as much as from key mappings.
--
-- In the arrange view rows are positions in the track list. "line" regions
-- are whole tracks; the other kinds are a stretch of time on some tracks,
-- and clips reaching across its ends are cut there. A region with `clips`
-- (a set of clip ids, from clips chosen with the pointer) is about those
-- clips alone, whole, and nothing else in its stretch.
--
-- In the piano roll rows are pitches and beats count from the start of the
-- clip. A "char" region is a stretch of time at every pitch, a "block" one
-- only between two pitches, a "line" one whole pitches. Notes belong to the
-- region they start in, and are never cut. A region with `notes` (from a
-- text object such as `iv`, the notes of a voice) is about those notes
-- alone, in the block they span. Where the roll edits several
-- clips at once, `yank`, `delete`, `each` and `paste` take the list of them
-- (`paw.roll_clips.parts()`: `{ clip, offset }` each, beats counting from
-- the start of the first) in place of one clip; every note stays in its own.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local options = require("paw.options")
local transform = require("paw.notes")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type registers = require("paw.keymap.registers")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")

local EPS = 1e-9

--- A value that this module passes on and never reads.
local record Value
end

--- A region of a view (`paw.keymap`): rows `r0` to `r1`, beats `c0` up to
--- `c1`, its `kind` ("char", "line" or "block"), in the arrange view
--- maybe `clips`, a set of clip ids, and in the piano roll maybe `notes`,
--- the ids of notes by the id of their clip.
local type Region = contracts.Region

local type ClipSnapshot = objects.ClipSnapshot

--- A note that a register holds: a note of a clip, and the clip it came
--- from when it was yanked from several (`clip`).
local record YankedNote
  start: number
  length: number
  pitch: integer
  velocity: integer
  id: integer
  meta: types.Meta
  attr: types.NoteAttr
  clip: integer
end

--- What a register holds: whole tracks (`kind = "tracks"`), a stretch of
--- time with what each track holds in it (`"range"`: `length`, `rows`), or
--- notes of the piano roll (`"notes"`: `shape`, the region's kind, `top`,
--- its highest pitch, `length` and `notes`).
local record Yanked is registers.Register
  tracks: {objects.TrackSnapshot}
  length: number
  rows: {{ClipSnapshot}}
  shape: string
  top: number
  notes: {YankedNote}
end

--- A clip that the piano roll edits, with how many beats after the first
--- clip it starts.
local record Part
  clip: objects.Clip
  offset: number
end

--- What the piano roll's operators edit: one clip (a `paw.Clip`, with its
--- `id`), or the clips it edits, as a list of parts.
local record Target is {Part}
  id: integer
end

--- How a piece of a clip plays (`paw.stretch.moved`).
local record Moved
  shift: number
  offset: number
  loop_start: number
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Groups
  rows: function(): {integer}
end
local record Stretch
  carry: function(c: types.Clip, snap: ClipSnapshot, by: number): Moved
  sounding: function(c: types.Clip, notes: {types.Note}, limit?: integer): {types.Note}
end
local record Takes
  piece: function(c: types.Clip, from: number, to: number, shift?: number): Value
end
local record Paw
  cursor: CursorModule
  groups: Groups
  stretch: Stretch
  takes: Takes
  track: function(which: number | string): objects.Track
  clip: function(id: integer): objects.Clip
  restore_track: function(snap: objects.TrackSnapshot, index?: integer): objects.Track
  restore_clip: function(snap: ClipSnapshot, track: integer | objects.Track): objects.Clip
  notify: function(text: string, level?: string)
end
local paw = (_G as {string: Paw}).paw

local record A
end
local record R
end
local record M
  type Region = Region
  type Yanked = Yanked
  type YankedNote = YankedNote
  type Part = Part
  type Target = Target
  arrange: A
  roll: R
end
M.arrange, M.roll = A, R

-- Arrange ---------------------------------------------------------------------

--- The ids of the tracks a region covers.
function A.tracks(region: Region): {integer}
  local list, out: {integer}, {integer} = paw.groups.rows(), {}
  for row = math.max(1, region.r0) as integer, region.r1 as integer do
    if list[row] then
      out[#out + 1] = list[row]
    end
  end
  return out
end

-- A copy of a record with some of its fields changed.
local function with<T>(t: T, changes: {string: Value}): T
  return util.merge(t as {string: Value}, changes) as T
end

--- The part of a clip between two beats as a snapshot, or nil if there is none.
local function piece(c: types.Clip, notes: {types.Note}, from: number, to: number): ClipSnapshot
  local a, b = math.max(c.start, from), math.min(c.start + c.length, to)
  if b - a <= EPS then
    return nil
  end
  local snap: ClipSnapshot = {name = c.name, start = a, length = b - a, kind = c.kind, muted = c.muted}
  -- It plays as the clip does: stretched, shifted, looped from where it begins.
  local moved = paw.stretch.carry(c, snap, a - c.start)
  -- What extensions keep with a clip describes the whole of it, so it goes
  -- with a whole copy and not with a part.
  if a - c.start < EPS and c.start + c.length - b < EPS and c.meta and next(c.meta) then
    snap.meta = c.meta
  else
    -- Its takes are another matter: every piece keeps them, lined up.
    local takes = paw.takes.piece(c, a, b, c.loop and moved.shift)
    if takes then
      snap.meta = {takes = takes}
    end
  end
  if c.kind == "midi" and c.loop then
    -- A looped piece keeps everything it repeats, wherever it begins.
    snap.notes = {}
    for i, n in ipairs(notes) do
      snap.notes[i] = with(n, {start = (n.start + moved.shift) as Value})
    end
    for _, move in ipairs(c.control_count > 0 and api.clip_controls(c.id) or {}) do
      snap.controls = snap.controls or {}
      snap.controls[#snap.controls + 1] = with(move, {start = (move.start + moved.shift) as Value})
    end
  elseif c.nest then
    -- A block: a copy plays the same subproject (one subproject, two
    -- blocks), from where the piece begins in it.
    snap.nest, snap.play = c.nest, c.play
    snap.offset = (c.offset or 0) + (a - c.start)
  elseif c.kind == "midi" then
    snap.notes = {}
    for _, n in ipairs(notes) do
      local start = c.start + n.start
      if start >= a - EPS and start < b - EPS then
        snap.notes[#snap.notes + 1] = with(
          n, {start = (start - a) as Value, length = math.min(n.length, b - start) as Value}
        )
      end
    end
    -- Controller moves go with the stretch they happen in.
    for _, move in ipairs(c.control_count > 0 and api.clip_controls(c.id) or {}) do
      local start = c.start + move.start
      if start >= a - EPS and start < b - EPS then
        snap.controls = snap.controls or {}
        snap.controls[#snap.controls + 1] = with(move, {start = (start - a) as Value})
      end
    end
  else
    snap.file, snap.gain = c.file, c.gain
    snap.offset = moved.offset
    -- A fade stays with the edge it belongs to; a new edge gets none.
    snap.fade_in = a - c.start < EPS and math.min(c.fade_in, b - a) or 0
    snap.fade_out = c.start + c.length - b < EPS and math.min(c.fade_out, b - a) or 0
  end
  return snap
end

local function notes_of(c: types.Clip): {types.Note}
  return c.kind == "midi" and api.clip_notes(c.id) or nil
end

--- What a track holds between two beats: clip snapshots that start counting
--- from `from`.
function A.copy(track: integer, from: number, to: number): {ClipSnapshot}
  local out: {ClipSnapshot} = {}
  for _, c in ipairs(api.clip_list(track)) do
    local p = piece(c, notes_of(c), from, to)
    if p then
      p.start = p.start - from
      out[#out + 1] = p
    end
  end
  return out
end

--- Empty a track between two beats, cutting the clips that reach across
--- either end. With `from` equal to `to` it only cuts there. With `only`,
--- a set of clip ids, the other clips are left alone.
function A.clear(track: integer, from: number, to: number, only?: {integer: boolean})
  for _, c in ipairs(api.clip_list(track)) do
    local finish = c.start + c.length
    if c.start < to - EPS and finish > from + EPS and (not only or only[c.id]) then
      local notes = notes_of(c)
      local left, right = piece(c, notes, c.start, from), piece(c, notes, to, finish)
      -- The clip itself stays as what is left of it, so its id lives on.
      local keep = left or right
      if not keep then
        api.clip_remove(c.id)
      else
        api.clip_set(c.id, {start = keep.start})
        api.clip_set(c.id, {length = keep.length})
        if keep.loop_start then
          api.clip_set(c.id, {loop_start = keep.loop_start})
        end
        if notes then
          api.clip_set_notes(c.id, keep.notes)
          if c.control_count > 0 then
            api.clip_set_controls(c.id, keep.controls or {})
          end
        else
          api.clip_set(c.id, {offset = keep.offset})
          api.clip_set(c.id, {fade_in = keep.fade_in})
          api.clip_set(c.id, {fade_out = keep.fade_out})
        end
        -- What is left of the clip keeps its takes as its piece has them.
        if keep.meta and keep.meta.takes and keep.meta ~= c.meta then
          local meta = util.merge(c.meta, {takes = keep.meta.takes})
          api.clip_set(c.id, {meta = meta})
        end
        if left and right then
          paw.restore_clip(right, track)
        end
      end
    end
  end
end

--- Move every clip of a track that starts at or after `from`.
function A.ripple(track: integer, from: number, by: number)
  for _, c in ipairs(api.clip_list(track)) do
    if c.start >= from - EPS then
      api.clip_set(c.id, {start = math.max(0, c.start + by)})
    end
  end
end

--- The clips of a track that start inside a region, or all of them for whole tracks.
local function starting_in(track: integer, region: Region): {types.Clip}
  local out: {types.Clip} = {}
  for _, c in ipairs(api.clip_list(track)) do
    if region.clips then
      if region.clips[c.id] then
        out[#out + 1] = c
      end
    elseif region.kind == "line" or (c.start >= region.c0 - EPS and c.start < region.c1 - EPS) then
      out[#out + 1] = c
    end
  end
  return out
end

--- The clips of a track that reach into a region.
local function touching(track: integer, region: Region): {types.Clip}
  local out: {types.Clip} = {}
  for _, c in ipairs(api.clip_list(track)) do
    if region.clips then
      if region.clips[c.id] then
        out[#out + 1] = c
      end
    elseif region.kind == "line" or (c.start < region.c1 - EPS and c.start + c.length > region.c0 + EPS) then
      out[#out + 1] = c
    end
  end
  return out
end

--- A region as a value for a register: whole tracks, or a stretch of time
--- with what each track holds in it.
function A.yank(region: Region): Yanked
  if region.clips then
    -- Clips chosen one by one: each of them whole, where it is.
    local rows: {{ClipSnapshot}} = {}
    for i, id in ipairs(A.tracks(region)) do
      rows[i] = {}
      for _, c in ipairs(starting_in(id, region)) do
        local p = piece(c, notes_of(c), c.start, c.start + c.length)
        p.start = p.start - region.c0
        rows[i][#rows[i] + 1] = p
      end
    end
    return {kind = "range", length = region.c1 - region.c0, rows = rows}
  end
  if region.kind == "line" then
    local tracks: {objects.TrackSnapshot} = {}
    for i, id in ipairs(A.tracks(region)) do
      tracks[i] = paw.track(id):snapshot()
    end
    return {kind = "tracks", tracks = tracks}
  end
  local rows: {{ClipSnapshot}} = {}
  for i, id in ipairs(A.tracks(region)) do
    rows[i] = A.copy(id, region.c0, region.c1)
  end
  return {kind = "range", length = region.c1 - region.c0, rows = rows}
end

--- Remove a region and return what it held. Whole tracks go; a stretch of
--- time leaves a gap, or with `paw.opt.ripple` what follows moves up.
function A.delete(region: Region): Yanked
  local value = A.yank(region)
  for _, id in ipairs(A.tracks(region)) do
    if region.clips then
      for _, c in ipairs(starting_in(id, region)) do
        api.clip_remove(c.id)
      end
    elseif region.kind == "line" then
      api.track_remove(id)
    else
      A.clear(id, region.c0, region.c1)
      if options.opt.ripple then
        A.ripple(id, region.c1, region.c0 - region.c1)
      end
    end
  end
  return value
end

--- Where the last paste left the cursor, and where it ended.
local record LastPaste
  row: integer
  beat: number
  finish: number
  edits: integer
end
local last_paste: LastPaste

-- The project's count of edits, read alone (`project_get(key)`, which Teal
-- does not see).
local function edits(): integer
  return (api.project_get as function(string): integer)("edits")
end

--- Put a register's value at the cursor, `count` times one after another.
--- Tracks go below the cursor's track, or above it with `before`. A stretch
--- of time goes after the clip under the cursor, or right at the cursor with
--- `before`; it replaces what is there, or with `paw.opt.ripple` pushes it
--- along.
function A.paste(value: Yanked, before?: boolean, count?: integer)
  local cursor = paw.cursor
  if not value then
    return paw.notify("nothing to paste yet", "warn")
  end
  if value.kind == "tracks" then
    -- On the master, the tracks go after the last one.
    local at = cursor.on_master() and #api.track_list() + 1 or (cursor.index() or 0) + (before and 0 or 1)
    local first: objects.Track
    for _ = 1, count or 1 do
      for _, snap in ipairs(value.tracks) do
        local track = paw.restore_track(snap, at)
        first, at = first or track, at + 1
      end
    end
    if first then
      cursor.set_track(first)
    end
    local n = #value.tracks * (count or 1)
    return paw.notify(n == 1 and "pasted 1 track" or "pasted " .. n .. " tracks")
  elseif value.kind ~= "range" then
    return paw.notify("that register holds " .. value.kind .. ", which does not go on the timeline", "warn")
  end

  local row, at = cursor.index(), cursor.beat
  if not row then
    return paw.notify(
      cursor.on_master() and "the master track has no clips: paste on a track" or "no track to paste on", "warn"
    )
  end
  if not before then
    local made = edits()
    if last_paste and last_paste.row == row and last_paste.beat == at and last_paste.edits == made then
      -- Pasting again right after a paste carries on where that one ended.
      at = last_paste.finish
    else
      local clip = cursor.clip()
      if clip then
        at = clip.start + clip.length
      end
    end
  end
  local list, start = paw.groups.rows(), at
  for _ = 1, count or 1 do
    start = at
    for i, clips in ipairs(value.rows) do
      local track = list[row + i - 1]
      if track then
        if options.opt.ripple then
          A.clear(track, at, at)
          A.ripple(track, at, value.length)
        else
          A.clear(track, at, at + value.length)
        end
        for _, snap in ipairs(clips) do
          paw.restore_clip(with(snap, {start = (at + snap.start) as Value}), track)
        end
      end
    end
    at = at + value.length
  end
  cursor.set_beat(start)
  last_paste = {row = row, beat = start, finish = at, edits = edits()}
  -- Said, so that what the screen said of the yank before is not taken
  -- for what the paste did.
  paw.notify("pasted " .. util.amount(value.length * (count or 1), "beat"))
end

--- Move the clips that start in a region by `by` beats.
function A.shift(region: Region, by: number)
  for _, id in ipairs(A.tracks(region)) do
    for _, c in ipairs(starting_in(id, region)) do
      api.clip_set(c.id, {start = math.max(0, c.start + by)})
    end
  end
end

--- Snap the clips that start in a region to the grid, and the notes in them
--- to the piano roll's.
function A.quantize(region: Region)
  local grid, note_grid = options.opt.grid, options.opt.note_grid
  for _, id in ipairs(A.tracks(region)) do
    for _, c in ipairs(starting_in(id, region)) do
      api.clip_set(c.id, {start = util.round(c.start, grid)})
      api.clip_set(c.id, {length = math.max(grid, util.round(c.length, grid))})
      if c.kind == "midi" then
        api.clip_set_notes(c.id, transform.quantize(api.clip_notes(c.id), {grid = note_grid}))
      end
    end
  end
end

--- Mute what a region covers, or unmute it if all of it is muted already:
--- whole tracks, or the clips reaching into a stretch of time.
function A.mute(region: Region)
  -- A track's `mute` or a clip's `muted`, read and written by its name.
  local things: {{string: boolean}} = {}
  local field = "muted"
  for _, id in ipairs(A.tracks(region)) do
    if region.kind == "line" then
      things[#things + 1], field = paw.track(id) as {string: boolean}, "mute"
    else
      for _, c in ipairs(touching(id, region)) do
        things[#things + 1] = paw.clip(c.id) as {string: boolean}
      end
    end
  end
  local all = #things > 0
  for _, thing in ipairs(things) do
    all = all and thing[field]
  end
  for _, thing in ipairs(things) do
    thing[field] = not all
  end
end

--- The places in `notes` of the notes of a clip that a region covers: each
--- note for whole tracks or clips chosen one by one, else the notes that
--- start in its stretch of time. A note of a looped clip is in it when one
--- of its repeats starts there.
local function notes_covered(c: types.Clip, notes: {types.Note}, region: Region): {integer: boolean}
  local places: {integer: boolean} = {}
  if region.clips or region.kind == "line" then
    for i = 1, #notes do
      places[i] = true
    end
    return places
  end
  -- Each note with its place as its id (a note can have no id), so that
  -- each repeat of a looped clip names the note that it plays.
  local placed: {types.Note} = {}
  for i, n in ipairs(notes) do
    placed[i] = with(n, {id = i as Value})
  end
  for _, n in ipairs(paw.stretch.sounding(c, placed)) do
    local start = c.start + n.start
    if start >= region.c0 - EPS and start < region.c1 - EPS then
      places[n.id] = true
    end
  end
  return places
end

--- The names of the clips that changed in words: "Bass", "Bass and Keys",
--- "Bass, Keys and Lead"; more than three names as the count of clips.
local function clips_in_words(names: {string}, count: integer): string
  if #names > 3 then
    return count .. " clips"
  elseif #names == 1 then
    return names[1]
  end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

--- Move the notes that a region covers in the MIDI clips reaching into it
--- up or down, and say how many moved, how far and in which clips.
function A.transpose(region: Region, semitones: integer)
  local moved, changed: integer, integer = 0, 0
  -- The names of the clips that changed, each once.
  local names, named: {string}, {string: boolean} = {}, {}
  for _, id in ipairs(A.tracks(region)) do
    for _, c in ipairs(touching(id, region)) do
      if c.kind == "midi" then
        local notes = api.clip_notes(c.id)
        local covered = notes_covered(c, notes, region)
        local here = 0
        for i, n in ipairs(notes) do
          local pitch = util.clamp(n.pitch + semitones, 0, 127) as integer
          -- A note at the end of the MIDI range stays there and is not counted.
          if covered[i] and pitch ~= n.pitch then
            n.pitch, here = pitch, here + 1
          end
        end
        if here > 0 then
          api.clip_set_notes(c.id, notes)
          moved, changed = moved + here, changed + 1
          if not named[c.name] then
            named[c.name], names[#names + 1] = true, c.name
          end
        end
      end
    end
  end
  if moved == 0 then
    return paw.notify("no notes to move there", "warn")
  end
  local steps = math.abs(semitones)
  paw.notify(
    string.format(
      "moved %d note%s %s %d semitone%s in %s",
      moved,
      moved == 1 and "" or "s",
      semitones > 0 and "up" or "down",
      steps,
      steps == 1 and "" or "s",
      clips_in_words(names, changed)
    )
  )
end

--- Make one clip of the MIDI clips a track has between two beats (of those
--- in the set `only`, if given). Returns whether there was more than one
--- to join.
function A.join(track: integer, from: number, to: number, only?: {integer: boolean}): boolean
  local clips = touching(track, {c0 = from, c1 = to, clips = only})
  if #clips < 2 then
    return false
  end
  for _, c in ipairs(clips) do
    if c.kind ~= "midi" then
      error("only MIDI clips can be joined", 0)
    end
  end
  -- Clips over each other (a take over a clip) join as well as clips side
  -- by side: from the first start to the last end.
  table.sort(clips, function(a: types.Clip, b: types.Clip): boolean return a.start < b.start end)
  local first, finish: types.Clip, number = clips[1], 0
  for _, c in ipairs(clips) do
    finish = math.max(finish, c.start + c.length)
  end
  local notes, controls = api.clip_notes(first.id), api.clip_controls(first.id)
  for i = 2, #clips do
    local by = clips[i].start - first.start
    -- The notes of a clip with other overrides (`:clip.override`) than the
    -- first's keep their sound: the difference goes into them. A note that
    -- does not play stays out.
    local up = (clips[i].transpose or 0) - (first.transpose or 0)
    local louder = (clips[i].velocity or 0) - (first.velocity or 0)
    for _, n in ipairs((api.clip_notes(clips[i].id))) do
      n.start, n.pitch = n.start + by, n.pitch + up
      n.velocity = util.clamp(n.velocity + louder, 1, 127) as integer
      if n.pitch >= 0 and n.pitch <= 127 then
        notes[#notes + 1] = n
      end
    end
    for _, move in ipairs(api.clip_controls(clips[i].id)) do
      move.start = move.start + by
      move.key = move.key and move.key + up
      if not move.key or (move.key >= 0 and move.key <= 127) then
        controls[#controls + 1] = move
      end
    end
    api.clip_remove(clips[i].id)
  end
  api.clip_set(first.id, {length = finish - first.start})
  api.clip_set_notes(first.id, notes)
  if #controls > 0 then
    api.clip_set_controls(first.id, controls)
  end
  return true
end

--- How far a region reaches in time: its own stretch, or for whole tracks
--- from the start to the end of their last clip.
function A.span(region: Region): number, number
  if region.kind ~= "line" then
    return region.c0, region.c1
  end
  local finish = 0.0
  for _, id in ipairs(A.tracks(region)) do
    for _, c in ipairs(api.clip_list(id)) do
      finish = math.max(finish, c.start + c.length)
    end
  end
  return 0, finish
end

-- Piano roll ------------------------------------------------------------------

--- Whether a region names a note of a clip, when it names notes at all.
--- Without the clip, a note of any clip with the note's id is named.
local function named(note: types.Note, region: Region, clip?: integer): boolean
  local by_clip = region.notes
  if not by_clip then
    return true
  end
  if clip then
    return by_clip[clip] ~= nil and by_clip[clip][note.id] == true
  end
  for _, ids in pairs(by_clip) do
    if ids[note.id] then
      return true
    end
  end
  return false
end

--- Whether a note (of the clip `clip`, an id) belongs to a region.
function R.inside(note: types.Note, region: Region, clip?: integer): boolean
  if not named(note, region, clip) then
    return false
  end
  local rows = note.pitch >= region.r0 and note.pitch <= region.r1
  local time = note.start >= region.c0 - EPS and note.start < region.c1 - EPS
  if region.kind == "line" then
    return rows
  end
  if region.kind == "block" then
    return rows and time
  end
  return time
end

--- The notes of a region and the place of each among the clip's notes.
--- Only the part of the clip the region covers is asked for.
function R.notes(clip: objects.Clip, region: Region): {types.Note}, {integer}
  local range: objects.NoteRangeInput = {}
  if region.kind ~= "line" then
    range.from, range.to = region.c0 - 2 * EPS, region.c1
  end
  if region.kind ~= "char" then
    range.low, range.high = util.clamp(region.r0, 0, 127) as integer, util.clamp(region.r1, 0, 127) as integer
  end
  local notes, places: {types.Note}, {integer} = {}, {}
  local found, at = clip:notes(range)
  for i, n in ipairs(found) do
    if R.inside(n, region, clip.id) then
      notes[#notes + 1], places[#places + 1] = n, at[i]
    end
  end
  return notes, places
end

--- One clip, or the clips the roll edits, as a list of `{ clip, offset }`;
--- and whether it is one clip alone.
local function parts_of(target: Target): {Part}, boolean
  if target.id then
    return {{clip = target as objects.Clip, offset = 0}}, true
  end
  return target as {Part}, #target <= 1
end

--- A region in the beats of a clip `offset` beats after the first.
local function shifted(region: Region, offset: number): Region
  if offset == 0 or region.kind == "line" then
    return region
  end
  return with(region, {c0 = (region.c0 - offset) as Value, c1 = (region.c1 - offset) as Value})
end

--- A region of a clip's notes as a value for a register. Taken from
--- several clips, each note says which it came from (`clip`).
function R.yank(target: Target, region: Region): Yanked
  local parts, single = parts_of(target)
  local notes: {YankedNote} = {}
  for _, part in ipairs(parts) do
    for _, n in ipairs((R.notes(part.clip, shifted(region, part.offset)))) do
      local start = n.start + part.offset
      -- Whole pitches keep their place in time; anything else counts from
      -- where the region starts.
      notes[#notes + 1] = with(
        n as YankedNote,
        {
          start = (region.kind == "line" and start or start - region.c0) as Value,
          clip = (not single and part.clip.id or nil) as Value,
        }
      )
    end
  end
  if not single then
    table.sort(
      notes,
      function(a: YankedNote, b: YankedNote): boolean
        if math.abs(a.start - b.start) > EPS then
          return a.start < b.start
        end
        return a.pitch < b.pitch
      end
    )
  end
  return {kind = "notes", shape = region.kind, top = region.r1, length = region.c1 - region.c0, notes = notes}
end

--- Remove a region's notes and return them.
function R.delete(target: Target, region: Region): Yanked
  local value = R.yank(target, region)
  for _, part in ipairs((parts_of(target))) do
    local _, places = R.notes(part.clip, shifted(region, part.offset))
    if #places > 0 then
      part.clip:edit_notes({remove = places})
    end
  end
  return value
end

--- Change the notes of a region with `fn(note)`, each note's start in its
--- own clip's beats.
function R.each(target: Target, region: Region, fn: function(note: types.Note))
  for _, part in ipairs((parts_of(target))) do
    local notes, places = R.notes(part.clip, shifted(region, part.offset))
    local set: {objects.NoteChangeInput} = {}
    for i, n in ipairs(notes) do
      fn(n)
      set[i] = {
        index = places[i],
        start = n.start,
        length = n.length,
        pitch = n.pitch,
        velocity = n.velocity,
        meta = n.meta or {},
      }
    end
    if #set > 0 then
      part.clip:edit_notes({set = set})
    end
  end
end

--- Put notes into a clip, where notes already sounding where they land give
--- way, growing it to reach `finish` (its own beats).
local function put(clip: objects.Clip, add: {YankedNote}, finish: number)
  local remove: {integer} = {}
  local olds, places = clip:notes()
  for k, old in ipairs(olds) do
    for _, new in ipairs(add) do
      if
        old.pitch == new.pitch and old.start < new.start + new.length - EPS and old.start + old.length > new.start + EPS
      then
        remove[#remove + 1] = places[k]
        break
      end
    end
  end
  local note_grid = options.opt.note_grid
  if finish > clip.length + EPS then
    clip.length = math.ceil(finish / note_grid - EPS) * note_grid
  end
  if #add > 0 or #remove > 0 then
    clip:edit_notes({remove = remove, add = add as {objects.NoteInput}})
  end
end

--- Put yanked notes into a clip at a beat. A stretch of time keeps its
--- pitches; a block or whole pitches go with their top at `pitch`. Notes
--- already sounding where the new ones land give way, and the clip grows if
--- they reach past its end. Returns the beat where the pasted stretch ends.
--- Given the clips the roll edits, notes yanked from one of them go back
--- into it and the rest into `into` (one of them; the first by default).
function R.paste(target: Target, value: Yanked, pitch: integer, beat: number, into?: Part): number
  if not value then
    paw.notify("nothing to paste yet", "warn")
    return
  end
  if value.kind ~= "notes" then
    paw.notify("that register holds " .. value.kind .. ", not notes", "warn")
    return
  end
  local parts, single = parts_of(target)
  into = not single and into or parts[1]
  local by_clip: {integer: Part} = {}
  for _, part in ipairs(parts) do
    by_clip[part.clip.id] = part
  end
  local adds: {Part: {YankedNote}} = {}
  local finish: {Part: number} = {}
  for _, n in ipairs(value.notes) do
    local part = not single and by_clip[n.clip] or into
    local note = with(n, {})
    -- What is pasted is a note of its own, whatever it was copied from.
    note.clip, note.id = nil, nil
    if value.shape ~= "line" then
      note.start = beat + n.start
    end
    note.start = note.start - part.offset
    if value.shape ~= "char" then
      note.pitch = (n.pitch + pitch - value.top) as integer
    end
    if note.pitch >= 0 and note.pitch <= 127 then
      adds[part] = adds[part] or {}
      table.insert(adds[part], note)
      finish[part] = math.max(finish[part] or 0, note.start + note.length)
    end
  end
  -- Room for the whole stretch that was yanked, not only the notes in it.
  if value.shape ~= "line" and adds[into] then
    finish[into] = math.max(finish[into], beat - into.offset + value.length)
  end
  local pasted = 0
  for _, part in ipairs(parts) do
    if adds[part] then
      put(part.clip, adds[part], finish[part])
      pasted = pasted + #adds[part]
    end
  end
  paw.notify(pasted == 1 and "pasted 1 note" or "pasted " .. pasted .. " notes")
  return value.shape == "line" and beat or beat + value.length
end

return M
