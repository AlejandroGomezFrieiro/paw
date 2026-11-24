-- The pointer's gestures on clips: choose them, move, copy, trim, stretch
-- and fade them, split and glue them, open one, and run a menu's command
-- on one.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local seats = require("paw.seats")
local util = require("paw.util")
local commands = require("paw.commands")
local type types = require("paw.types")
local type KeymapModule = require("paw.keymap")
local type objects = require("paw.objects")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")
local timegrid = require("paw.timegrid")

local paw = host.paw
local A = M.act
local snap = host.snap
local to_arrange = host.to_arrange
local type Region = host.Region
local type Value = host.Value

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
  set: {integer: boolean}
  anchor: integer
end
--- The clips chosen before the last plain click, and when.
local record Recent
  set: {integer: boolean}
  at: number
end

local picked: Picked = {set = {}, anchor = nil}
local recently_chosen: Recent -- the clips chosen before the last plain click: { set, at }
-- A gesture is choosing: the cursor and mode it moves keep the choice.
local pointing = false
-- Each window and terminal chooses clips of its own.
seats.keep(
  "frontend.picked",
  function(): Picked return picked end,
  function(p: Picked) picked = p end,
  function(): Picked return {set = {}, anchor = nil} end
)
seats.keep(
  "frontend.recently_chosen",
  function(): Recent return recently_chosen end,
  function(r: Recent) recently_chosen = r end,
  function(): Recent return nil end
)

--- The ids of the chosen clips, in order.
function M.chosen_clips(): {integer}
  local keymap = paw.keymap
  -- Another kind of selection is open: that is what the keys act on.
  if keymap.mode == "x" and not (keymap.visual and keymap.visual.region) then
    return {}
  end
  local out: {integer} = {}
  for id in pairs(picked.set) do
    if pcall(api.clip_get, id) then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  return out
end

--- Where each drawn part is, by id: its row from 1.
local function row_index(): {integer: integer}
  local rows: {integer: integer} = {}
  for i, id in ipairs(paw.groups.rows()) do
    rows[id] = i
  end
  return rows
end

--- The chosen clips as a region for the operators: the rows and the stretch
--- they span, and `clips`, the set of them.
local function clip_region(): Region
  local rows = row_index()
  local set: {integer: boolean} = {}
  local r0, r1, c0, c1 = math.huge, -math.huge, math.huge, -math.huge
  for _, id in ipairs(M.chosen_clips()) do
    local c = api.clip_get(id)
    local row = rows[c.part]
    if row then
      set[id] = true
      r0, r1 = math.min(r0, row), math.max(r1, row)
      c0, c1 = math.min(c0, c.start), math.max(c1, c.start + c.length)
    end
  end
  if not next(set) then
    return nil
  end
  return {kind = "clips", clips = set, r0 = r0, r1 = r1, c0 = c0, c1 = c1}
end

--- Choose a set of clips (`{ [id] = true }`); with `visual` they become
--- visual mode's selection.
local function choose_clips(set: {integer: boolean}, anchor: integer, visual: boolean)
  picked = {set = set, anchor = anchor or picked.anchor}
  local keymap = paw.keymap
  pointing = true
  if visual and next(set) and clip_region() then
    if not paw.ui.float and paw.ui.focused ~= "arrange" then
      paw.ui.focus("arrange")
    end
    local region = clip_region()
    keymap.visual = {kind = "clips", row = region.r0, col = region.c0, view = paw.ui.focused, region = clip_region}
    if keymap.mode ~= "x" then
      keymap.set_mode("x")
    end
  elseif keymap.mode == "x" then
    keymap.set_mode("n")
  end
  pointing = false
  M.refresh()
end

--- The payload of `mode.changed` (paw/keymap.tl).
local type ModeChanged = KeymapModule.ModeChanged
local mode_changed = paw.keymap.mode_changed

events.on(
  mode_changed,
  function(e: ModeChanged)
    if not pointing and e.old == "x" and next(picked.set) then
      picked.set = {}
      M.refresh()
    end
  end
)
local cursor_changed: events.Event<events.Payload> = events.event("cursor.changed")
events.on(
  cursor_changed,
  function()
    if pointing or paw.keymap.mode == "x" or not next(picked.set) then
      return
    end
    local under = paw.cursor.clip()
    if not (under and picked.set[under.id]) then
      picked.set = {}
      M.refresh()
    end
  end
)

--- Let go of the chosen clips.
function A.clear_clip_selection()
  if next(picked.set) then
    choose_clips({}, nil, false)
  end
end

--- Put the cursor on a part at a beat: a click on a lane or a header. A
--- click on a lane (one with a beat) lets go of the chosen clips.
function A.select(part: integer, beat?: number)
  pointing = true
  to_arrange()
  if part ~= 0 then
    paw.cursor.set_part(part)
  end
  if beat then
    paw.cursor.set_beat(snap(beat))
  end
  pointing = false
  if beat and next(picked.set) then
    picked.set = {}
    M.refresh()
  end
end

--- Put the cursor in a clip where it was clicked, on the grid but inside
--- the clip, so that the keys act on it.
local function cursor_into(id: integer, beat?: number)
  local c = api.clip_get(id)
  pointing = true
  to_arrange()
  paw.cursor.set_part(c.part)
  beat = snap(beat or c.start)
  if beat < c.start or beat >= c.start + c.length then
    beat = c.start
  end
  paw.cursor.set_beat(beat)
  pointing = false
end

--- The clips on drawn rows `row0` to `row1` reaching into beats `from` to `to`.
local function clips_in(row0: integer, row1: integer, from: number, to: number): {integer}
  local rows = paw.groups.rows()
  local out: {integer} = {}
  for row = math.max(1, math.min(row0, row1)), math.min(#rows, math.max(row0, row1)) do
    for _, c in ipairs(api.clip_list(rows[row])) do
      if c.start < to - 1e-9 and c.start + c.length > from + 1e-9 then
        out[#out + 1] = c.id
      end
    end
  end
  return out
end

--- A click on a clip: the cursor goes there, and `mode` says what happens
--- to the chosen clips: "only" (or nil) the clip alone, "toggle" (Ctrl) in
--- or out, "add" (Shift) the clips from the last one chosen to this one: on
--- one part those that start between them, across parts those in the
--- rectangle the two span.
function A.select_clip(id: integer, beat?: number, mode?: string)
  cursor_into(id, beat)
  mode = mode or "only"
  if mode == "only" then
    -- What was chosen before, for a double click that follows.
    recently_chosen = {set = {}, at = api.now()}
    for _, other in ipairs(M.chosen_clips()) do
      recently_chosen.set[other] = true
    end
    return choose_clips({[id] = true}, id, false)
  end
  local set: {integer: boolean} = {}
  for _, other in ipairs(M.chosen_clips()) do
    set[other] = true
  end
  if mode == "toggle" then
    set[id] = not set[id] or nil
    return choose_clips(set, set[id] and id or picked.anchor, true)
  end
  local anchor = picked.anchor
    and set[picked.anchor]
    and pcall(api.clip_get, picked.anchor)
    and api.clip_get(picked.anchor)
  local c = api.clip_get(id)
  if not anchor then
    set[id] = true
    return choose_clips(set, id, true)
  end
  local rows = row_index()
  local from, to = math.min(anchor.start, c.start), math.max(anchor.start, c.start)
  if anchor.part == c.part then
    for _, other in ipairs(api.clip_list(c.part)) do
      if other.start >= from - 1e-9 and other.start <= to + 1e-9 then
        set[other.id] = true
      end
    end
  else
    to = math.max(anchor.start + anchor.length, c.start + c.length)
    for _, other in ipairs(clips_in(rows[anchor.part] or 1, rows[c.part] or 1, from, to)) do
      set[other] = true
    end
  end
  set[id] = true
  choose_clips(set, anchor.id, true)
end

--- A box drawn with the right button over the timeline, from row `row0`
--- at `beat0` to `row1` at `beat1` (rows of drawn parts, from 1): the
--- clips it touches are chosen. `mode` as for `select_clip`: "add" keeps
--- those chosen already, "toggle" turns the ones it touches over.
function A.select_clips_box(row0: integer, beat0: number, row1: integer, beat1: number, mode?: string): integer
  local set: {integer: boolean} = {}
  if mode == "add" or mode == "toggle" then
    for _, id in ipairs(M.chosen_clips()) do
      set[id] = true
    end
  end
  local touched = clips_in(row0, row1, math.min(beat0, beat1), math.max(beat0, beat1))
  for _, id in ipairs(touched) do
    if mode == "toggle" and set[id] then
      set[id] = nil
    else
      set[id] = true
    end
  end
  choose_clips(set, touched[1] or picked.anchor, true)
  local count = 0
  for _ in pairs(set) do
    count = count + 1
  end
  return count
end

--- Choose a set of clips (`{ [id] = true }`), as visual mode's selection:
--- what `:select` does.
function M.choose_clips(set: {integer: boolean})
  choose_clips(set, nil, true)
end

--- Every clip on the timeline, chosen.
function A.select_all_clips()
  local set: {integer: boolean} = {}
  for _, part in ipairs(paw.groups.rows()) do
    for _, c in ipairs(api.clip_list(part)) do
      set[c.id] = true
    end
  end
  choose_clips(set, nil, true)
end

--- A clip's snapshot moved to `start`.
local function snapshot_at(clip: objects.Clip, start: number): objects.ClipSnapshot
  local taken = clip:snapshot()
  local out: objects.ClipSnapshot = {}
  for k, v in pairs(taken as {string: Value}) do
    (out as {string: Value})[k] = v
  end
  out.start = start
  return out
end

--- Drop a clip somewhere else: at `start`, on `part` if given. With `copy`
--- the clip stays and a copy is dropped.
function A.move_clip(id: integer, start: number, part?: integer, copy?: boolean): integer
  local clip = paw.clip(id)
  start = snap(start)
  part = part and part ~= 0 and part or clip:get().part
  if copy then
    local made = paw.restore_clip(snapshot_at(clip, start), part)
    return made.id
  end
  api.clip_set(id, {start = start})
  if part ~= api.clip_get(id).part then
    api.clip_set(id, {part = part})
  end
  return id
end

--- The clips a gesture on clip `id` acts on: all the chosen ones if it is
--- one of them, else that clip alone, which is then the chosen one.
local function grabbed_clips(id: integer): {integer}
  local ids = M.chosen_clips()
  for _, other in ipairs(ids) do
    if other == id then
      return ids
    end
  end
  choose_clips({[id] = true}, id, false)
  return {id}
end

--- Drag clips: the one at `id` and, if it is chosen, the others chosen with
--- it, by `dbeat` beats and `drows` rows of drawn parts, keeping their
--- places to one another. Snapping is relative: the clips move by whole
--- grid steps, so the grabbed clip keeps its distance from the grid line
--- before it, which is none if it started on one. `free` (Shift) moves them
--- by exactly `dbeat`. With `copy` (Ctrl) they stay and copies are dropped,
--- which are then the chosen clips. Nothing goes before the start or off
--- the parts. One undo step, as one call. Returns the ids of what moved.
function A.drag_clips(id: integer, dbeat: number, drows?: number, copy?: boolean, free?: boolean): {integer}
  local ids = grabbed_clips(id)
  local by = free and dbeat or util.round(dbeat, timegrid.step())
  local rows_by = math.floor((drows or 0) + 0.5)
  local rows, list = row_index(), paw.groups.rows()
  local clips: {types.Clip} = {}
  for i, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    clips[i] = c
    by = math.max(by, -c.start)
    local row = rows[c.part]
    if row then
      rows_by = util.clamp(rows_by, 1 - row, #list - row) as integer
    end
  end
  if math.abs(by) < 1e-9 and rows_by == 0 and not copy then
    return ids
  end
  local out: {integer} = {}
  for i, c in ipairs(clips) do
    local row = rows[c.part]
    local part = row and list[row + rows_by] or c.part
    if copy then
      local made = paw.restore_clip(snapshot_at(paw.clip(c.id), c.start + by), part)
      out[i] = made.id
    else
      api.clip_set(c.id, {start = c.start + by})
      if part ~= c.part then
        api.clip_set(c.id, {part = part})
      end
      out[i] = c.id
    end
  end
  if copy then
    local set: {integer: boolean} = {}
    for _, cid in ipairs(out) do
      set[cid] = true
    end
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
  for _, n in ipairs(notes) do
    n.start = n.start + by
  end
  api.clip_set_notes(id, notes)
  local c = api.clip_get(id)
  if c.control_count > 0 then
    local controls = api.clip_controls(id)
    for _, move in ipairs(controls) do
      move.start = move.start + by
    end
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
  if slip and free and edge == "end" then
    return A.stretch_clips(id, dbeat)
  end
  local ids = grabbed_clips(id)
  local held = api.clip_get(id)
  local least = free and 1 / 64 or timegrid.step()
  if slip then
    for _, cid in ipairs(ids) do
      local c = api.clip_get(cid)
      if c.loop then
        -- A looped clip's repeats turn round under it.
        paw.stretch.move_content(cid, -dbeat)
      elseif c.kind == "audio" then
        -- Later in the clip is earlier in the file, which has no time before 0.
        api.clip_set(cid, {offset = math.max(0, c.offset - paw.stretch.file_seconds(c, dbeat))})
      else
        shift_content(cid, dbeat)
      end
    end
    return ids
  end
  local at = edge == "start" and held.start or held.start + held.length
  local by = (free and math.max(0, at + dbeat) or snap(at + dbeat)) - at
  if math.abs(by) < 1e-9 then
    return ids
  end
  for _, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    if edge == "start" then
      local d = math.min(by, c.length - least)
      d = math.max(d, -c.start)
      -- A looped clip turns its loop round instead of running out of file.
      if c.kind == "audio" and not c.loop then
        d = math.max(d, file_start(c))
      end
      if math.abs(d) > 1e-9 then
        api.clip_set(cid, {start = c.start + d})
        api.clip_set(cid, {length = c.length - d})
        if c.loop then
          paw.stretch.move_content(cid, d)
        elseif c.kind == "audio" then
          api.clip_set(cid, {offset = math.max(0, c.offset + paw.stretch.file_seconds(c, d))})
        else
          shift_content(cid, -d)
        end
        if c.kind == "audio" then
          api.clip_set(cid, {fade_in = math.min(c.fade_in, c.length - d)})
          api.clip_set(cid, {fade_out = math.min(c.fade_out, c.length - d)})
        end
      end
    else
      local length = math.max(least, c.length + by)
      api.clip_set(cid, {length = length})
      if c.kind == "audio" then
        api.clip_set(cid, {fade_in = math.min(c.fade_in, length)})
        api.clip_set(cid, {fade_out = math.min(c.fade_out, length)})
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
  if math.abs(by) < 1e-9 then
    return ids
  end
  for _, cid in ipairs(ids) do
    local c = api.clip_get(cid)
    if c.kind == "audio" then
      local ok, err = pcall(paw.stretch.to, cid, math.max(timegrid.step(), c.length + by)) as (boolean, string)
      if not ok then
        paw.notify((tostring(err):gsub("^[^:]*:%d+: ", "")), "warn")
      end
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
    if not (t.loop_end > t.loop_start) then
      return paw.notify("there is no loop to stretch the clip to", "warn")
    end
    from, to = t.loop_start, t.loop_end
  end
  local ok, err = pcall(
    function()
      if from then
        paw.stretch.fit(id, from, to)
      else
        paw.stretch.reset(id)
      end
    end
  ) as (boolean, string)
  if not ok then
    paw.notify((tostring(err):gsub("^[^:]*:%d+: ", "")), "warn")
  end
end

--- Warp markers in the window (`paw.stretch.warp_add`): a double click on
--- an audio clip's top band puts one at `beat`; a marker's handle dragged
--- moves marker `index` to `beat` (on the grid unless `free`), stretching
--- the sound on either side of it; its menu takes it off. Each one undo
--- step; a refusal is said, not raised.
local function warp_run(f: function())
  local ok, err = pcall(f) as (boolean, string)
  if not ok then
    paw.notify((tostring(err):gsub("^[^:]*:%d+: ", ""):gsub("^runtime error: ", "")), "warn")
  end
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
      if which == "out" then
        api.clip_set(cid, {fade_out = fade})
      else
        api.clip_set(cid, {fade_in = fade})
      end
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
    if c.kind == "audio" then
      api.clip_set(cid, {gain = util.clamp(c.gain + by, -60, 24)})
    end
  end
end

--- Drag a clip's right edge to a new length, never shorter than a grid step.
function A.resize_clip(id: integer, length: number)
  api.clip_set(id, {length = math.max(timegrid.step(), paw.cursor.snap(length))})
end

--- A double click on an empty lane: a clip of one bar in the bar clicked.
function A.add_clip(part: integer, beat: number): integer
  local start = paw.time.bar_floor(math.max(0, beat))
  local id = api.clip_add(part, {start = start, length = paw.time.bar(start)})
  A.select(part, api.clip_get(id).start)
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
    for _, other in ipairs(M.chosen_clips()) do
      before[other] = true
    end
  end
  local together: {integer} = {}
  if before[id] then
    for other in pairs(before) do
      local ok, c = pcall(api.clip_get, other)
      if ok and (c as types.Clip).kind == "midi" then
        together[#together + 1] = other
      end
    end
    table.sort(together)
  end
  A.select_clip(id, clip.start)
  for _, opener in ipairs(M.openers) do
    if opener(clip) then
      return
    end
  end
  if clip.kind ~= "midi" then
    return
  end
  if #together > 1 then
    paw.roll_clips.open(together, id)
  else
    host.roll():edit(clip)
  end
  -- Opened by the pointer, the roll shows the clips whole where it can, at
  -- its next paint.
  host.roll().fit_next = true
end

--- Run a command on a clip or a part that was not under the cursor: what
--- a context menu does. The cursor goes there first, as a click would put it.
function A.clip_command(id: integer, beat: number, line: string)
  A.menu_target(id, beat)
  commands.exec(line)
end

--- The cursor goes to the clip a menu was opened on; the chosen clips stay
--- chosen if it is one of them, else it is chosen alone.
function A.menu_target(id: integer, beat?: number)
  local among = false
  for _, other in ipairs(M.chosen_clips()) do
    among = among or other == id
  end
  if among then
    return cursor_into(id, beat)
  end
  A.select_clip(id, beat)
end

local splitting = false

--- Split every chosen clip that the edit cursor is inside, there: what
--- `clip.split` (`S`, and the clip menu's "Split at the edit cursor") does
--- while clips are chosen. Both halves are chosen afterwards. Returns false
--- when no clip is chosen, for `clip.split` to split the clip under the
--- cursor instead.
function A.split_clips(): boolean
  local ids = M.chosen_clips()
  if splitting or #ids == 0 then
    return false
  end
  local beat, part, visual = paw.cursor.beat, paw.cursor.part_id(), paw.keymap.mode == "x"
  local set: {integer: boolean} = {}
  splitting, pointing = true, true
  local ok, err = pcall(
    function()
      for _, id in ipairs(ids) do
        set[id] = true
        local c = api.clip_get(id)
        if beat > c.start + 1e-9 and beat < c.start + c.length - 1e-9 then
          paw.cursor.set_part(c.part)
          commands.exec("clip.split")
          local right = paw.part(c.part):clip_at(beat)
          if right then
            set[right.id] = true
          end
        end
      end
    end
  ) as (boolean, string)
  if part then
    paw.cursor.set_part(part)
  end
  splitting, pointing = false, false
  if not ok then
    error(err, 0)
  end
  choose_clips(set, ids[1], visual or #ids > 1)
  return true
end

--- Glue the chosen clips on each part into one clip, the gaps between
--- them included: what the clip menu's "Glue" and `J` on chosen clips do.
--- MIDI clips are joined; audio clips are glued into a new file
--- (`paw.media.glue`). A part whose chosen clips are of both kinds is left
--- as it is.
function A.glue_clips()
  local region = clip_region()
  if not region then
    return paw.notify("no clips chosen to glue", "warn")
  end
  local glued = false
  for _, part in ipairs(paw.edit.arrange.parts(region)) do
    local audio: {integer} = {}
    local midi = 0
    for _, c in ipairs(api.clip_list(part)) do
      if region.clips[c.id] then
        if c.kind == "audio" then
          audio[#audio + 1] = c.id
        else
          midi = midi + 1
        end
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
      local fine, result = pcall(paw.edit.arrange.join, part, region.c0, region.c1, region.clips)
      ok = fine
      if fine then
        done = result as boolean
      else
        why = tostring(result)
      end
    elseif #audio > 0 and midi > 0 then
      paw.notify("audio and MIDI clips cannot be glued together", "warn")
    end
    if not ok then
      return paw.notify(why:match("^[^\n]*"), "warn")
    end
    glued = glued or done
  end
  if not glued then
    paw.notify("glue takes two or more chosen clips of one kind on a part", "warn")
  end
  local left: {integer: boolean} = {}
  for _, id in ipairs(M.chosen_clips()) do
    left[id] = true
  end
  choose_clips(left, nil, false)
end

--- The clip menu's "Split at the edit cursor" and "Glue", opened on clip
--- `id`: on the chosen clips if it is one of them, else on it alone. The
--- edit cursor stays where it is.
function A.menu_split(id: integer)
  grabbed_clips(id)
  if not A.split_clips() then
    commands.exec("clip.split")
  end
end

function A.menu_glue(id: integer)
  grabbed_clips(id)
  A.glue_clips()
end

-- What the gestures of other areas need: a gesture that moves the cursor
-- says so, and the clips chosen stay chosen.
return {set_pointing = function(on: boolean) pointing = on end}
