-- The pointer's gestures in the piano roll: notes chosen, added, moved,
-- stretched, erased, quantized and their velocities drawn.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local seats = require("paw.seats")
local util = require("paw.util")
local transform = require("paw.notes")
local type types = require("paw.types")
local type objects = require("paw.objects")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")
local timegrid = require("paw.timegrid")

local paw = host.paw
local opt = options.opt
local A = M.act
local by_beat = host.by_beat
local note_snap = host.note_snap
local to_arrange = host.to_arrange
local type Portion = host.Portion
local type Point = host.Point
local type Value = host.Value

function A.close_roll()
  paw.ui.hide("pianoroll")
  to_arrange()
end

-- Notes, in the clips the piano roll has open. A gesture names a note by
-- its clip and its place there; where the roll edits several clips (see
-- `paw.roll_clips`), the chosen notes may be in any of them and a gesture
-- on one acts on all of them, each note staying in its own clip. Beats a
-- gesture gives are the roll's: from the start of the clip it names.

--- The notes chosen in a clip: their places, and the clip's stamp then.
local record Chosen
  places: {integer: boolean}
  stamp: integer
end

-- The notes chosen with the pointer: places in each clip, by clip id. They
-- are kept as long as the clip's notes are what the pointer's own edits
-- left; an edit made any other way (a key, an undo) forgets them, since
-- places move. Each window and terminal chooses notes of its own.
local chosen: {integer: Chosen} = {}
seats.keep(
  "frontend.chosen",
  function(): {integer: Chosen} return chosen end,
  function(c: {integer: Chosen}) chosen = c end,
  function(): {integer: Chosen} return {} end
)

local function stamp_of(clip: integer): integer
  local ok, data = pcall(api.clip_get, clip)
  return ok and (data as types.Clip).stamp or nil
end

--- Choose notes of `clip` by their places (`{ [place] = true }`), as the
--- pointer would: what `:select` does.
function M.choose_notes(clip: integer, places: {integer: boolean})
  chosen[clip] = next(places) and {places = places, stamp = stamp_of(clip)} or nil
  api.ui_redraw()
end

--- The places of the selected notes of `clip`, in order. None if the notes
--- of the clip changed after the selection.
function M.chosen_notes(clip: integer): {integer}
  local entry = chosen[clip]
  if not entry or entry.stamp ~= stamp_of(clip) then
    return {}
  end
  local out: {integer} = {}
  for place in pairs(entry.places) do
    out[#out + 1] = place
  end
  table.sort(out)
  return out
end

--- A handle on a clip at the pitches that it plays: its notes shifted by
--- its transpose (`:clip.override`), as the roll shows them.
local function played(clip: integer): objects.Clip
  local c = paw.clip(clip)
  return c:shifted(c.transpose or 0)
end

--- The notes of a clip by their places in it, and the places in order. A
--- note that the transpose takes out of 0 to 127 does not play: the handle
--- leaves it out, and it has no place here. The places of the other notes
--- do not change, so a gesture names each note by its place in the clip.
local function by_place(clip: objects.Clip): {integer: types.Note}, {integer}
  local notes, places = clip:notes()
  local out: {integer: types.Note} = {}
  for k, n in ipairs(notes) do
    out[places[k]] = n
  end
  return out, places
end

--- The clips a gesture on `clip` reaches, with how far each starts after
--- it (`offset`): every clip the roll edits when it is one of them, else
--- that clip alone.
local function portions_for(clip: integer): {Portion}
  local rc = paw.roll_clips
  if rc.editable(clip) then
    local portions = rc.portions() as {Portion}
    -- Offsets count from the clip named, which is the active one when the
    -- gesture gives beats.
    local base = rc.offset(clip)
    for _, portion in ipairs(portions) do
      portion.offset = portion.offset - base
    end
    return portions
  end
  local c = api.clip_get(clip)
  return {{id = clip, clip = played(clip), offset = 0, start = c.start, length = c.length}}
end

--- The chosen notes of the clips a gesture on `clip` reaches: clip id ->
--- places, and how many there are.
local function chosen_map(clip: integer): {integer: {integer}}, integer
  local map: {integer: {integer}} = {}
  local count = 0
  for _, portion in ipairs(portions_for(clip)) do
    local places = M.chosen_notes(portion.id)
    if #places > 0 then
      map[portion.id], count = places, count + #places
    end
  end
  return map, count
end

--- Every chosen note of the clips the roll edits, as `{ clip, place }`.
function M.chosen_refs(): {{integer}}
  local out: {{integer}} = {}
  local active = paw.roll_clips.active()
  if not active then
    return out
  end
  for _, portion in ipairs(portions_for(active)) do
    for _, place in ipairs(M.chosen_notes(portion.id)) do
      out[#out + 1] = {portion.id, place}
    end
  end
  return out
end

--- The chosen notes of `clip` (and of the clips edited with it) in words,
--- for a toolbar: `3 notes · 5.1.00 – 5.3.00`, or "" with none chosen.
function M.chosen_text(clip: integer): string
  local map, count = chosen_map(clip)
  if count == 0 then
    return ""
  end
  local first, last, clips = math.huge, -math.huge, 0
  for id, places in pairs(map) do
    local c = api.clip_get(id)
    local notes = api.clip_notes(id)
    clips = clips + 1
    for _, place in ipairs(places) do
      local n = notes[place]
      if n then
        first, last = math.min(first, c.start + n.start), math.max(last, c.start + n.start + n.length)
      end
    end
  end
  if first == math.huge then
    return ""
  end
  return string.format(
    "%d note%s%s · %s – %s",
    count,
    count == 1 and "" or "s",
    clips > 1 and " in " .. clips .. " clips" or "",
    paw.time.format(first),
    paw.time.format(last)
  )
end

--- Choose notes: `map` is clip id -> places, and replaces every choice.
local function choose_all(map: {integer: {integer}})
  chosen = {}
  for clip, places in pairs(map) do
    local set: {integer: boolean} = {}
    for _, place in ipairs(places) do
      set[place] = true
    end
    if next(set) then
      chosen[clip] = {places = set, stamp = stamp_of(clip)}
    end
  end
  api.ui_redraw()
end

local function choose(clip: integer, places: {integer})
  choose_all({[clip] = places})
end

--- Where a note is wanted: its start and pitch.
local record Wanted
  start: number
  pitch: integer
end

--- Where notes are now, given what they are: `wanted` is a list of
--- `{ start, pitch }`.
local function places_of(clip: integer, wanted: {Wanted}): {integer}
  local notes, order = by_place(played(clip))
  local out: {integer} = {}
  local used: {integer: boolean} = {}
  for _, want in ipairs(wanted) do
    for _, place in ipairs(order) do
      local n = notes[place]
      if not used[place] and n.pitch == want.pitch and math.abs(n.start - want.start) < 1e-6 then
        out[#out + 1], used[place] = place, true
        break
      end
    end
  end
  return out
end

-- A gesture's beat on the grid, unless it is `free` (Shift held) or snap
-- is off in the piano roll (`paw.opt.snap`): then to the nearest of
-- 960 ticks a beat, as MIDI files count them.
local function snap_note(beat: number, free: boolean): number
  if free or not opt.snap then
    return math.max(0, math.floor(beat * 960 + 0.5) / 960)
  end
  return note_snap(beat)
end

--- A press and drag on the empty grid: a note from `start` for `length`,
--- which is then the one chosen note. `free` leaves it off the grid. A
--- click gives no length (nil, or 0 or less): the note is the piano roll's
--- note length (`set_note_length`); a drawn length becomes that length. A
--- click on a note shown behind the roll's own (another part's) makes its
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
  local portion = portions_for(clip)[1]
  if rc.editable(clip) then
    portion = rc.target(start + rc.offset(clip)) as Portion
    start = start + rc.offset(clip) - portion.offset
  end
  local c = portion.clip
  free = free or not opt.snap
  start = snap_note(start, free)
  if start >= c.length or c:note_at(pitch, start) then
    return
  end
  local roll = host.roll()
  if not length or length <= 0 then
    length = roll:step_length()
  else
    length = math.max(free and 1 / 64 or timegrid.step("note"), snap_note(length, free))
    roll:set_step(length)
  end
  local index = c:add_note(
    roll.new_note(
      c, {pitch = pitch, start = start, length = math.min(length, c.length - start), velocity = opt.velocity}
    )
  )
  c:part():play_note(pitch, opt.velocity, 150)
  choose(portion.id, {index})
  return index
end

--- Ctrl and a click on a note shown behind the roll's own: its clip is
--- edited too, or no longer. `beat` is the roll's.
function A.context_click(clip: integer, beat: number, pitch: number)
  local behind = paw.roll_clips.context_at(math.floor(pitch + 0.5), beat + paw.roll_clips.offset(clip))
  if behind then
    paw.roll_clips.toggle(behind.clip)
  end
end

--- The clips list of the roll's side panel: make one active, edit it too
--- (or no longer), show a part's notes behind the roll's or not.
function A.roll_activate(_: integer, id: number)
  paw.roll_clips.activate(math.floor(id))
end
function A.roll_toggle_clip(_: integer, id: number)
  paw.roll_clips.toggle(math.floor(id))
end
function A.roll_show_part(_: integer, id: number)
  local part = math.floor(id)
  for _, t in ipairs(paw.roll_clips.parts()) do
    if t.id == part then
      return paw.roll_clips.show_part(part, not t.on)
    end
  end
end

--- Choose notes with a click: `mode` is "only" (the note alone), "add" or
--- "toggle" (Shift or Ctrl held).
function A.select_note(clip: integer, index: integer, mode?: string)
  if mode == "only" or mode == nil then
    return choose(clip, {index})
  end
  local map = chosen_map(clip)
  local set: {integer: boolean} = {}
  for _, place in ipairs(map[clip] or {}) do
    set[place] = true
  end
  if mode == "toggle" and set[index] then
    set[index] = nil
  else
    set[index] = true
  end
  local out: {integer} = {}
  for place in pairs(set) do
    out[#out + 1] = place
  end
  map[clip] = out
  choose_all(map)
end

--- Choose the notes a box touches: from `beat0, pitch0` to `beat1, pitch1`,
--- in any order, in every clip the roll edits. `mode` as for `select_note`.
function A.select_notes_box(
  clip: integer, beat0: number, pitch0: number, beat1: number, pitch1: number, mode?: string
): integer
  if beat0 > beat1 then
    beat0, beat1 = beat1, beat0
  end
  if pitch0 > pitch1 then
    pitch0, pitch1 = pitch1, pitch0
  end
  local map: {integer: {integer}} = (mode == "add" or mode == "toggle") and chosen_map(clip) or {}
  local count = 0
  for _, portion in ipairs(portions_for(clip)) do
    local set: {integer: boolean} = {}
    for _, place in ipairs(map[portion.id] or {}) do
      set[place] = true
    end
    local notes, order = by_place(portion.clip)
    for _, place in ipairs(order) do
      local n = notes[place]
      local start = n.start + portion.offset
      if n.start >= 0 and n.pitch >= pitch0 and n.pitch <= pitch1 and start < beat1 and start + n.length > beat0 then
        if mode == "toggle" and set[place] then
          set[place] = nil
        else
          set[place] = true
        end
      end
    end
    local out: {integer} = {}
    for place in pairs(set) do
      out[#out + 1] = place
    end
    map[portion.id], count = out, count + #out
  end
  choose_all(map)
  return count
end

function A.select_all_notes(clip: integer)
  local map: {integer: {integer}} = {}
  for _, portion in ipairs(portions_for(clip)) do
    local out: {integer} = {}
    local notes, order = by_place(portion.clip)
    for _, place in ipairs(order) do
      local n = notes[place]
      -- Not those hidden by a trim of the clip's edges.
      if n.start >= 0 and n.start < portion.length then
        out[#out + 1] = place
      end
    end
    map[portion.id] = out
  end
  choose_all(map)
end

function A.clear_note_selection()
  if next(chosen) then
    choose_all({})
  end
end

--- The notes a gesture on the note at `index` acts on: all the chosen ones
--- if it is one of them, else that note alone, which is then the chosen
--- one. Clip id -> places.
local function grabbed(clip: integer, index: integer): {integer: {integer}}
  local map = chosen_map(clip)
  for _, place in ipairs(map[clip] or {}) do
    if place == index then
      return map
    end
  end
  choose(clip, {index})
  return {[clip] = {index}}
end

--- The parts a map of chosen notes is in, each with its notes and places.
local function grabbed_portions(clip: integer, map: {integer: {integer}}): {Portion}
  local out: {Portion} = {}
  for _, portion in ipairs(portions_for(clip)) do
    if map[portion.id] then
      portion.notes, portion.places = by_place(portion.clip), map[portion.id]
      out[#out + 1] = portion
    end
  end
  return out
end

--- A note with its fields laid over: a copy.
local function note_with(n: types.Note, start: number, pitch: integer): objects.NoteInput
  local out: objects.NoteInput = {}
  for k, v in pairs(n as {string: Value}) do
    (out as {string: Value})[k] = v
  end
  out.start, out.pitch = start, pitch
  return out
end

--- Drag notes: the one at `index` and, if it is chosen, the others chosen
--- with it, by `dbeat` and `dpitch`. The grabbed note lands on the grid
--- unless `free`; the rest keep their distance from it. With `copy` the
--- notes stay and copies are dropped. Each note stays in its own clip.
function A.drag_notes(clip: integer, index: integer, dbeat: number, dpitch?: number, copy?: boolean, free?: boolean)
  local held = played(clip):note(index)
  if not held then
    return
  end
  local portions = grabbed_portions(clip, grabbed(clip, index))
  local by = snap_note(held.start + dbeat, free) - held.start
  local up = math.floor((dpitch or 0) + 0.5)
  -- Nothing leaves its clip or the keyboard.
  for _, portion in ipairs(portions) do
    for _, place in ipairs(portion.places) do
      local n = portion.notes[place]
      by = math.max(by, -n.start)
      by = math.min(by, portion.length - n.start - math.min(n.length, timegrid.step("note")))
      up = util.clamp(up, -n.pitch, 127 - n.pitch) as integer
    end
  end
  if math.abs(by) < 1e-9 and up == 0 and not copy then
    return
  end
  local after: {integer: {Wanted}} = {}
  for _, portion in ipairs(portions) do
    local wanted: {Wanted} = {}
    local set: {objects.NoteChangeInput} = {}
    local add: {objects.NoteInput} = {}
    for _, place in ipairs(portion.places) do
      local n = portion.notes[place]
      local moved: Wanted = {start = n.start + by, pitch = n.pitch + up}
      wanted[#wanted + 1] = moved
      if copy then
        add[#add + 1] = note_with(n, moved.start, moved.pitch)
      else
        set[#set + 1] = {index = place, start = moved.start, pitch = moved.pitch}
      end
    end
    portion.clip:edit_notes({set = set, add = add})
    after[portion.id] = wanted
  end
  if up ~= 0 then
    paw.clip(clip):part():play_note(held.pitch + up, held.velocity, 120)
  end
  local map: {integer: {integer}} = {}
  for id, wanted in pairs(after) do
    map[id] = places_of(id, wanted)
  end
  choose_all(map)
end

--- Drag an end of the note at `index`, and the same end of the notes chosen
--- with it: `dstart` moves their starts (the ends stay), `dlength` their ends.
function A.stretch_notes(clip: integer, index: integer, dstart?: number, dlength?: number, free?: boolean): boolean
  local held = played(clip):note(index)
  if not held then
    return
  end
  local portions = grabbed_portions(clip, grabbed(clip, index))
  local least = (free or not opt.snap) and 1 / 64 or timegrid.step("note")
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
  local map: {integer: {integer}} = {}
  for _, portion in ipairs(portions) do
    local wanted: {Wanted} = {}
    local set: {objects.NoteChangeInput} = {}
    for _, place in ipairs(portion.places) do
      local n = portion.notes[place]
      local stop = n.start + n.length
      local start = util.clamp(n.start + dstart, 0, stop - least)
      local length = math.max(least, math.min(stop + dlength, portion.length) - start)
      wanted[#wanted + 1] = {start = start, pitch = n.pitch}
      set[#set + 1] = {index = place, start = start, length = length}
    end
    portion.clip:edit_notes({set = set})
    map[portion.id] = places_of(portion.id, wanted)
  end
  choose_all(map)
  return dlength ~= 0 or dstart ~= 0
end

--- Take a note away, and with it the others if it is one of the chosen.
function A.remove_note(clip: integer, index: integer)
  for _, portion in ipairs(grabbed_portions(clip, grabbed(clip, index))) do
    portion.clip:edit_notes({remove = portion.places})
  end
  choose_all({})
end

--- Take the chosen notes away: what Delete does in the piano roll.
function A.remove_chosen_notes(clip: integer): boolean
  local map, count = chosen_map(clip)
  if count == 0 then
    return false
  end
  for _, portion in ipairs(grabbed_portions(clip, map)) do
    portion.clip:edit_notes({remove = portion.places})
  end
  choose_all({})
  return true
end

-- One note at a time, as scripts and older frontends ask for it. The
-- pitch is one that the clip plays: on a transposed copy, the note moves
-- from the pitch that the roll shows.
function A.move_note(clip: integer, index: integer, start: number, pitch: integer): integer
  pitch = util.clamp(pitch, 0, 127) as integer
  local c = played(clip)
  local before = c:note(index)
  local at = c:set_note(index, {start = note_snap(start), pitch = pitch})
  if before and before.pitch ~= pitch then
    c:part():play_note(pitch, before.velocity, 120)
  end
  return at
end

function A.resize_note(clip: integer, index: integer, length: number)
  paw.clip(clip):set_note(index, {length = math.max(timegrid.step("note"), note_snap(length))})
end

--- How hard a note is played; with the note among the chosen, all of them.
function A.set_velocity(clip: integer, index: integer, velocity: number): integer
  local v = util.clamp(math.floor(velocity + 0.5), 1, 127) as integer
  local map = chosen_map(clip)
  local among = false
  for _, place in ipairs(map[clip] or {}) do
    among = among or place == index
  end
  if not among then
    return paw.clip(clip):set_note(index, {velocity = v})
  end
  for _, portion in ipairs(grabbed_portions(clip, map)) do
    local set: {objects.NoteChangeInput} = {}
    for i, place in ipairs(portion.places) do
      set[i] = {index = place, velocity = v}
    end
    portion.clip:edit_notes({set = set})
  end
  choose_all(map)
end

--- Hear a pitch on the part of the clip that is open: a click on the keyboard.
function A.audition(clip: integer, pitch: integer)
  paw.clip(clip):part():play_note(util.clamp(pitch, 0, 127) as integer, opt.velocity, 250)
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
      if not n.hidden and math.floor(pitch + 0.5) == n.pitch and beat >= n.start and beat < n.start + n.length then
        return true
      end
    end
    return false
  end
  local count = 0
  for _, portion in ipairs(portions_for(clip)) do
    local hit: {integer} = {}
    local notes, order = by_place(portion.clip)
    for _, place in ipairs(order) do
      local n = notes[place]
      -- Notes hidden by a trim of the clip's start are not there to cross.
      local seen: Seen = {start = n.start + portion.offset, length = n.length, pitch = n.pitch, hidden = n.start < 0}
      for i = 1, #points do
        local a, b = points[i], points[math.min(i + 1, #points)]
        if crosses(seen, a[1], a[2], b[1], b[2]) then
          hit[#hit + 1] = place
          break
        end
      end
    end
    if #hit > 0 then
      portion.clip:edit_notes({remove = hit})
    end
    count = count + #hit
  end
  if count > 0 then
    choose_all({})
  end
  return count
end

--- A drag with the right button down the keyboard: choose every note from
--- `low` to `high` (either way round). `mode` as for `select_note`.
function A.select_pitches(clip: integer, low: number, high: number, mode?: string): integer
  local from, to: number, number = 0, paw.clip(clip).length
  for _, portion in ipairs(portions_for(clip)) do
    from, to = math.min(from, portion.offset), math.max(to, portion.offset + portion.length)
  end
  return A.select_notes_box(clip, from - 1, low, to + 1, high, mode)
end

--- Draw over the velocity strip: `points` are `{ beat, fraction }` as the
--- pointer went (fraction 0 at the bottom, 1 at the top). Each note starting
--- within the stretch drawn over, or within `reach` beats of a click, takes
--- the height drawn above its start; with notes chosen, only those.
function A.draw_velocities(clip: integer, points: {Point}, reach?: number): integer
  if #points == 0 then
    return 0
  end
  table.sort(points, by_beat)
  reach = reach or 0
  local from, to = points[1][1] - reach, points[#points][1] + reach
  local function height(beat: number): number
    if beat <= points[1][1] then
      return points[1][2]
    end
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
  for _, portion in ipairs(portions_for(clip)) do
    local only: {integer: boolean} = {}
    for _, place in ipairs(map[portion.id] or {}) do
      only[place] = true
    end
    local set: {objects.NoteChangeInput} = {}
    local notes, order = by_place(portion.clip)
    for _, place in ipairs(order) do
      local n = notes[place]
      local start = n.start + portion.offset
      if (chosen_count == 0 or only[place]) and n.start >= 0 and start >= from - 1e-9 and start <= to + 1e-9 then
        set[#set + 1] = {index = place, velocity = util.clamp(math.floor(height(start) * 127 + 0.5), 1, 127) as integer}
      end
    end
    if #set > 0 then
      portion.clip:edit_notes({set = set})
    end
    count = count + #set
  end
  if count > 0 and chosen_count > 0 then
    choose_all(map)
  end
  return count
end

--- The length a click on the grid gives a note: the piano roll's note
--- length. 0 or nil for one grid step.
function A.set_note_length(length?: number)
  host.roll():set_step(length and length > 0 and length or nil)
end

--- The snap button: whether the pointer's notes land on the grid.
function A.toggle_note_snap()
  opt.snap = not opt.snap
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
  local after: {integer: {Wanted}} = {}
  for _, portion in ipairs(portions_for(clip)) do
    local notes, order = by_place(portion.clip)
    -- The chosen notes, or every note with none chosen.
    local places = map[portion.id] or {}
    if not some then
      places = order
    end
    local set: {objects.NoteChangeInput} = {}
    local wanted: {Wanted} = {}
    local picked: {types.Note} = {}
    for i, place in ipairs(places) do
      picked[i] = notes[place]
    end
    -- On the grid of the clip, and each note stays inside it.
    local moved = transform.quantize(
      picked, {grid = timegrid.step("note"), strength = strength, within = portion.length}
    )
    for i, place in ipairs(places) do
      local n = moved[i]
      set[i] = {index = place, start = n.start, length = n.length}
      wanted[i] = {start = n.start, pitch = n.pitch}
    end
    if #set > 0 then
      portion.clip:edit_notes({set = set})
      after[portion.id] = wanted
    end
    count = count + #set
  end
  if count == 0 then
    return 0
  end
  if some then
    local out: {integer: {integer}} = {}
    for id, wanted in pairs(after) do
      out[id] = places_of(id, wanted)
    end
    choose_all(out)
  end
  return count
end

--- A click on the piano roll's ruler: the playhead to that beat of the clip.
function A.roll_seek(clip: integer, beat: number)
  paw.transport.seek(math.max(0, paw.clip(clip).start + math.max(0, beat)))
end
