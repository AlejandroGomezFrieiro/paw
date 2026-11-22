-- `paw.roll_clips`: the clips the piano roll edits, and the notes it shows
-- around them.
--
-- The roll edits one clip, the *active* one, where new notes go. Others can
-- be edited with it (REAPER's "editability follows selection"): selections,
-- operators, motions, yank and paste work on the notes of all of them, and a
-- note that moves stays in its own clip. Behind them the roll shows the
-- notes of other tracks that sound at the same time, faintly and in their
-- tracks' colours: the *context*, so the harmony can be seen where it is
-- written.
--
-- Beats here are the roll's: from the start of the active clip. A note at
-- its own clip's beat `b` is at `b + offset` in the roll, `offset` being how
-- far its clip starts after the active one.
local api = paw.api
local EPS = 1e-9
local M = {}

-- Which tracks' notes the roll shows behind its own: "all" pitched tracks,
-- those of the active clip's "group", "none", or a list of track ids. Drum
-- tracks (those with a drum map) are left out of "all" and "group".
paw.option.define("roll_context", "all", { type = { "string", "table" }, values = { "all", "group", "none" } })
-- At most this many context notes, so that a dense song stays quick to draw.
paw.option.define("roll_context_max", 4000)

local others = {} -- ids of the clips edited with the active one, in order
local shown = {} -- track id -> true or false: a toggle over `roll_context`
local generation = 0 -- goes up when the set or the toggles change
local cache = { key = nil, notes = {} }
-- Each window and terminal edits clips of its own.
paw.seats.keep("roll_clips", function() return others, shown, cache end, function(o, s, c)
  others, shown, cache = o, s, c
end, function() return {}, {}, { key = nil, notes = {} } end)
-- And each window of the roll: a new one edits the same clips, and finds
-- the notes around them for itself.
paw.layout.window_keep("pianoroll", function() return { others, shown, cache } end, function(v)
  others, shown, cache = v[1], v[2], v[3]
end, function(v)
  local o, s = {}, {}
  for i, id in ipairs(v[1]) do
    o[i] = id
  end
  for k, x in pairs(v[2]) do
    s[k] = x
  end
  return { o, s, { key = nil, notes = {} } }
end, "roll_clips")

local function roll() return paw.ui.views.pianoroll end

local function midi(id)
  if not id then return nil end
  local ok, c = pcall(api.clip_get, id)
  return ok and c.kind == "midi" and c or nil
end

local function changed()
  generation = generation + 1
  paw.emit("roll_clips.changed", { active = M.active(), count = #M.ids() })
  if paw.frontend then
    paw.frontend.refresh()
  else
    api.ui_redraw()
  end
end

--- The id of the active clip, or nil with no clip open.
function M.active() return roll().clip_id end

--- The ids of the editable clips, the active one first, then the others in
--- the order they were added.
function M.ids()
  local active = M.active()
  if not midi(active) then return {} end
  local out = { active }
  for _, id in ipairs(others) do
    if id ~= active and midi(id) then out[#out + 1] = id end
  end
  return out
end

--- True if a clip is one of the editable clips.
function M.editable(id)
  for _, other in ipairs(M.ids()) do
    if other == id then return true end
  end
  return false
end

--- Where a clip's beats are in the roll: add this to them.
function M.offset(id)
  local a, c = midi(M.active()), midi(id)
  return (a and c) and c.start - a.start or 0
end

--- The editable clips, the active one first: `{ id, clip, offset, start,
--- length, track, name }` each, `clip` a handle (`paw.clip`).
function M.parts()
  local a = midi(M.active())
  if not a then return {} end
  local out = {}
  for _, id in ipairs(M.ids()) do
    local c = midi(id)
    out[#out + 1] = {
      id = id,
      clip = paw.clip(id),
      offset = c.start - a.start,
      start = c.start,
      length = c.length,
      track = c.track,
      name = c.name,
    }
  end
  return out
end

--- The stretch of the roll the editable clips cover: from, to.
function M.span()
  local lo, hi = 0, 0
  for i, part in ipairs(M.parts()) do
    if i == 1 then
      lo, hi = part.offset, part.offset + part.length
    end
    lo, hi = math.min(lo, part.offset), math.max(hi, part.offset + part.length)
  end
  return lo, hi
end

--- The editable clip a new note at `beat` goes into: the active one, unless
--- the beat is outside it and inside another. Returns the part.
function M.target(beat, parts)
  parts = parts or M.parts()
  local active = parts[1]
  if not active or (beat >= -EPS and beat < active.length - EPS) then return active end
  for _, part in ipairs(parts) do
    if beat >= part.offset - EPS and beat < part.offset + part.length - EPS then return part end
  end
  return active
end

-- Which clips -----------------------------------------------------------------

--- Edit these clips together. `active` (or the first of them) gets the new
--- notes. paw does not use clips that are not MIDI.
function M.open(ids, active)
  local list = {}
  for _, id in ipairs(ids) do
    if midi(id) then list[#list + 1] = id end
  end
  active = midi(active) and active or list[1]
  if not active then return paw.notify("no MIDI clip to open in the piano roll", "warn") end
  roll():edit(paw.clip(active))
  others = {}
  for _, id in ipairs(list) do
    if id ~= active then others[#others + 1] = id end
  end
  changed()
end

--- Edit the active clip alone. This is what paw does when you open a clip.
function M.only()
  if #others == 0 then return end
  others = {}
  changed()
end

--- Make a clip the active clip. A clip that is not editable yet takes the
--- place of the old active clip in the set. The cursor stays at its
--- position in the song.
function M.activate(id)
  local view = roll()
  local old, new = midi(view.clip_id), midi(id)
  if not new or id == view.clip_id then return end
  local list, kept = {}, M.editable(id)
  for _, other in ipairs(M.ids()) do
    if other ~= id and (kept or other ~= view.clip_id) then list[#list + 1] = other end
  end
  others = list
  view.clip_id = id
  if old then
    local by = old.start - new.start
    view.beat, view.scroll = view.beat + by, view.scroll + by
  end
  paw.notify("editing " .. new.name .. (#list > 0 and string.format(" and %d more", #list) or ""))
  changed()
end

--- Make the clip `n` places after the active one (before it, with a
--- negative `n`) active, the editable clips taken in the order they start.
function M.cycle(n)
  local ids = M.ids()
  if #ids < 2 then return paw.notify("the piano roll edits one clip", "warn") end
  local starts = {}
  for _, id in ipairs(ids) do
    starts[id] = api.clip_get(id).start
  end
  table.sort(ids, function(a, b)
    if starts[a] ~= starts[b] then return starts[a] < starts[b] end
    return a < b
  end)
  for i, id in ipairs(ids) do
    if id == M.active() then return M.activate(ids[(i - 1 + n) % #ids + 1]) end
  end
end

--- Add a clip to the editable set, or remove it. If you remove the active
--- clip, the next clip becomes active. The last clip stays.
function M.toggle(id)
  if not midi(id) then return end
  local ids = M.ids()
  if not M.editable(id) then
    others[#others + 1] = id
    changed()
    return true
  end
  if #ids == 1 then return paw.notify("the piano roll edits at least one clip", "warn") end
  if id == M.active() then M.activate(ids[2]) end
  local list = {}
  for _, other in ipairs(others) do
    if other ~= id then list[#list + 1] = other end
  end
  others = list
  changed()
  return false
end

-- Notes -----------------------------------------------------------------------

--- The notes of the editable clips in the roll's beats, in the order they
--- start (lower pitches first in a chord), each with `clip` (its clip's id),
--- `place` (its place among that clip's notes, for `edit_notes`) and
--- `offset`. With one clip they are that clip's notes in its own order.
--- `range` is as for `Clip:notes`, its beats the roll's.
function M.notes(range, parts)
  parts = parts or M.parts()
  local out = {}
  for _, part in ipairs(parts) do
    local mine = range
      and {
        from = range.from and range.from - part.offset,
        to = range.to and range.to - part.offset,
        low = range.low,
        high = range.high,
      }
    local found, places = part.clip:notes(mine)
    for i, n in ipairs(found) do
      n.start, n.clip, n.place, n.offset = n.start + part.offset, part.id, places and places[i] or i, part.offset
      out[#out + 1] = n
    end
  end
  if #parts > 1 then
    table.sort(out, function(a, b)
      if math.abs(a.start - b.start) > EPS then return a.start < b.start end
      if a.pitch ~= b.pitch then return a.pitch < b.pitch end
      return a.clip < b.clip
    end)
  end
  return out
end

--- The note of an editable clip on `pitch` that sounds at roll beat `beat`,
--- the active clip first. Returns the note (in the beats of the roll), its
--- place and its part.
function M.note_at(pitch, beat, parts)
  for _, part in ipairs(parts or M.parts()) do
    local note, place = part.clip:note_at(pitch, beat - part.offset)
    if note then
      if part.offset ~= 0 then note.start = note.start + part.offset end
      return note, place, part
    end
  end
end

-- Context ---------------------------------------------------------------------

--- The tracks whose notes can show behind the notes of the roll. These are
--- the tracks with MIDI clips (of the scope, in a narrowed tab), but not the
--- track of the active clip. `{ id, name, color, drums, on }` each. `on`
--- tells if its notes show.
function M.tracks()
  local a = midi(M.active())
  if not a then return {} end
  local option = paw.opt.roll_context
  local group = paw.groups.of(a.track) or (paw.groups.is_group(a.track) and a.track)
  local listed = {}
  if type(option) == "table" then
    for _, id in ipairs(option) do
      listed[id] = true
    end
  end
  local out = {}
  -- In a tab narrowed to a group (`paw.scope`), the group's tracks alone.
  local scope = rawget(paw, "scope")
  for _, id in ipairs(scope and scope.tracks() or api.track_list()) do
    local t = api.track_get(id)
    if id ~= a.track and not t.master then
      local has_midi = false
      for _, c in ipairs(api.clip_list(id)) do
        has_midi = has_midi or c.kind == "midi"
      end
      if has_midi then
        local drums = paw.harmony.is_drums(t)
        local on
        if type(option) == "table" then
          on = listed[id] or false
        elseif option == "group" then
          on = not drums and group ~= nil and (paw.groups.of(id) == group or id == group)
        elseif option == "none" or option == false then
          on = false
        else
          on = not drums
        end
        if shown[id] ~= nil then on = shown[id] end
        out[#out + 1] = { id = id, name = t.name, color = paw.draw.track_colour(t), drums = drums, on = on }
      end
    end
  end
  return out
end

--- Show the notes of a track behind the notes of the roll, or not. nil
--- returns to the value of `paw.opt.roll_context`.
function M.show_track(id, on)
  shown[id] = on
  changed()
end

--- The context notes, in the beats of the roll. These are the notes of the
--- other clips of the active clip's track, and of the clips of the shown
--- tracks (not the editable clips), that sound in the range of the editable
--- clips. Each is `{ pitch, start, length, velocity, clip, track, color }`,
--- at most `paw.opt.roll_context_max` of them. paw keeps them until the
--- project, the set of clips or the toggles change.
function M.context()
  local a = midi(M.active())
  if not a then return {} end
  local lo, hi = M.span()
  local ids = M.ids()
  local key = table.concat({
    api.project_get("edits"),
    generation,
    table.concat(ids, ","),
    tostring(paw.opt.roll_context),
    paw.opt.roll_context_max,
    lo,
    hi,
  }, "|")
  if cache.key == key then return cache.notes end
  local editable, out = {}, {}
  for _, id in ipairs(ids) do
    editable[id] = true
  end
  local max = paw.opt.roll_context_max
  local from, to = a.start + lo, a.start + hi
  local own = api.track_get(a.track)
  local looked = { { id = a.track, on = true, color = paw.draw.track_colour(own) } }
  for _, track in ipairs(M.tracks()) do
    looked[#looked + 1] = track
  end
  for _, track in ipairs(looked) do
    if track.on then
      for _, c in ipairs(api.clip_list(track.id)) do
        if c.kind == "midi" and not editable[c.id] and c.start < to - EPS and c.start + c.length > from + EPS then
          local shift = c.start - a.start
          -- Only what the clip lets sound, and only within the stretch.
          local notes =
            api.clip_notes(c.id, { from = math.max(0, from - c.start), to = math.min(c.length, to - c.start) })
          for _, n in ipairs(notes) do
            if #out >= max then break end
            if n.start >= -EPS and n.start < c.length - EPS then
              out[#out + 1] = {
                pitch = n.pitch,
                start = n.start + shift,
                length = math.min(n.length, c.length - n.start),
                velocity = n.velocity,
                clip = c.id,
                track = track.id,
                color = track.color,
              }
            end
          end
        end
      end
    end
  end
  cache = { key = key, notes = out }
  return out
end

--- The context note on `pitch` that sounds at roll beat `beat`, if any.
function M.context_at(pitch, beat)
  for _, n in ipairs(M.context()) do
    if n.pitch == pitch and beat >= n.start - EPS and beat < n.start + n.length - EPS then return n end
  end
end

--- The pitches that sound at roll beat `beat`, in the editable clips and
--- the context, lowest first. The second value is the name of the chord
--- that they make, when `paw.harmony` can tell it.
function M.sounding(beat)
  local set, out = {}, {}
  for _, n in ipairs(M.notes({ from = beat, to = beat + EPS })) do
    set[n.pitch] = true
  end
  for _, n in ipairs(M.context()) do
    if beat >= n.start - EPS and beat < n.start + n.length - EPS then set[n.pitch] = true end
  end
  for pitch in pairs(set) do
    out[#out + 1] = pitch
  end
  table.sort(out)
  local name
  local harmony, a = rawget(paw, "harmony"), midi(M.active())
  if harmony and harmony.at and a then
    local ok, chord = pcall(harmony.at, a.start + beat)
    if ok and type(chord) == "table" then name = chord.name end
  end
  return out, name
end

-- The active track -------------------------------------------------------------

--- The tracks whose notes the roll shows, in the order of the track list:
--- the active clip's and those shown behind it.
function M.visible()
  local a = midi(M.active())
  if not a then return {} end
  local on = { [a.track] = true }
  for _, t in ipairs(M.tracks()) do
    if t.on then on[t.id] = true end
  end
  local out = {}
  for _, id in ipairs(api.track_list()) do
    if on[id] then out[#out + 1] = id end
  end
  return out
end

--- A track's MIDI clip to edit from the roll: the one under the roll's
--- cursor in the song, else the one nearest it.
local function clip_of(track, at)
  local best, gap
  for _, c in ipairs(api.clip_list(track)) do
    if c.kind == "midi" then
      local d = at < c.start and c.start - at or at >= c.start + c.length and at - (c.start + c.length) + EPS or 0
      if not gap or d < gap then
        best, gap = c, d
      end
    end
  end
  return best
end

--- Make active the track `n` places after the track of the active clip, in
--- the tracks that the roll shows (before it with a negative `n`). Its clip
--- under the cursor gets the new notes. The notes of the old clip show
--- behind. With `wrap`, it goes round. False when the roll shows no other track.
function M.step_track(n, wrap)
  local view, list = roll(), M.visible()
  local a = midi(M.active())
  if not a or #list < 2 then return false end
  local at = 1
  for i, id in ipairs(list) do
    if id == a.track then at = i end
  end
  local to = at + n
  if wrap then to = (to - 1) % #list + 1 end
  to = math.max(1, math.min(#list, to))
  if to == at then
    paw.notify(n > 0 and "the last track the roll shows" or "the first track the roll shows", "warn")
    return true
  end
  local c = clip_of(list[to], a.start + view.beat)
  if c then M.activate(c.id) end
  return true
end

-- Choosing --------------------------------------------------------------------

--- Each clip near the roll, as rows for a list. Each shown track is a row
--- (`kind` "track", `on` tells if its notes show). Under it are its MIDI
--- clips in the range of the roll (`kind` "clip", `on` tells if it is
--- editable, `active`). The track of the active clip is first, with its clips.
function M.rows()
  local a = midi(M.active())
  if not a then return {} end
  local lo, hi = M.span()
  local from, to = a.start + lo, a.start + hi
  local out = {}
  local function clips_of(track)
    for _, c in ipairs(api.clip_list(track)) do
      if c.kind == "midi" and c.start < to - EPS and c.start + c.length > from + EPS then
        out[#out + 1] =
          { kind = "clip", id = c.id, name = c.name, on = M.editable(c.id), active = c.id == a.id, track = track }
      end
    end
  end
  local own = api.track_get(a.track)
  out[#out + 1] =
    { kind = "track", id = a.track, name = own.name, color = paw.draw.track_colour(own), on = true, active = true }
  clips_of(a.track)
  for _, t in ipairs(M.tracks()) do
    out[#out + 1] = { kind = "track", id = t.id, name = t.name, color = t.color, on = t.on, active = false }
    clips_of(t.id)
  end
  return out
end

--- `:roll.tracks`: a list of the tracks near the roll and of their clips.
--- On a track, Enter shows or hides its notes. On a clip, Enter adds it to
--- the editable set or removes it.
function M.pick()
  if not M.active() then return paw.notify("open a clip in the piano roll first", "warn") end
  local function line(row)
    if row.kind == "track" then
      if row.active then return "    " .. row.name .. "  (this clip's track)" end
      return (row.on and "[x] " or "[ ] ") .. row.name
    end
    return "      " .. (row.active and "(active) " or row.on and "[edit] " or "[    ] ") .. row.name
  end
  paw.pick({
    title = "Piano roll: tracks and clips",
    items = M.rows(),
    format = line,
    empty = "no other tracks with MIDI clips",
    actions = {
      ["<CR>"] = {
        keep = true,
        desc = "show or hide / edit or not",
        fn = function(row, _, p)
          if not row then return end
          if row.kind == "track" and not row.active then
            M.show_track(row.id, not row.on)
            row.on = not row.on
          elseif row.kind == "clip" and not row.active then
            row.on = M.toggle(row.id) and true or false
          end
          local entry = p and p.matches and p.matches[p.selected]
          if entry then entry.text = line(row) end
        end,
      },
      ["<C-a>"] = {
        desc = "make the clip active",
        fn = function(row)
          if row and row.kind == "clip" then M.activate(row.id) end
        end,
      },
    },
  })
end

-- The set goes when the clip does, or when the project changes under it.
paw.on("project.loaded", function()
  others, shown = {}, {}
  generation = generation + 1
end)

return M
