-- Text fixtures of a small project, and `T.check_keys(fixture, keys,
-- expected)`: one check helper for the key tests. tests/suite.lua loads
-- this file with `dofile` and calls it with `T`. The format of a fixture
-- has its reference in tests/suite.lua ("Text fixtures").
local api = paw.api

-- One line of a fixture, read: its kind and its fields. Nil for a blank
-- line or a comment.
local function parse_line(line, number)
  local text = line:gsub("%-%-.*$", ""):match("^%s*(.-)%s*$")
  if text == "" then return nil end
  local name = text:match("^track%s+(.+)$")
  if name then return { kind = "track", name = name } end
  local clip, start, length = text:match("^clip%s+(%S+)%s+([%d.]+)%+([%d.]+)$")
  if clip then return { kind = "clip", name = clip, start = tonumber(start), length = tonumber(length) } end
  local pitch, beat = text:match("^cursor%s+(%d*)@([%d.]+)$")
  if beat then return { kind = "cursor", pitch = tonumber(pitch), beat = tonumber(beat) } end
  local note_pitch, note_start, note_length, mark = text:match("^(%d+)%s+([%d.]+)%+([%d.]+)%s*(%*?)$")
  if note_pitch then
    return {
      kind = "note",
      pitch = tonumber(note_pitch),
      start = tonumber(note_start),
      length = tonumber(note_length),
      chosen = mark == "*",
    }
  end
  error(string.format("fixture line %d is not a track, a clip, a note or a cursor: %s", number, line), 3)
end

--- Make the project of a fixture in a new project, and put the cursor
--- where the fixture says. Gives the tracks by name.
local function build(text)
  local tracks, track, clip = {}, nil, nil
  -- The notes of each clip, by its id: the clip gets them all at once.
  local notes_of, clips_made = {}, {}
  local cursor
  local number = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    number = number + 1
    local item = parse_line(line, number)
    if item and item.kind == "track" then
      track, clip = paw.add_track({ name = item.name }), nil
      track:add_device("synth")
      tracks[item.name] = track
    elseif item and item.kind == "clip" then
      assert(track, "fixture line " .. number .. ": a clip is in a track")
      clip = track:add_clip({ name = item.name, start = item.start, length = item.length, notes = {} })
      notes_of[clip.id], clips_made[#clips_made + 1] = {}, clip
    elseif item and item.kind == "note" then
      assert(clip, "fixture line " .. number .. ": a note is in a clip")
      table.insert(notes_of[clip.id], item)
    elseif item and item.kind == "cursor" then
      cursor = { track = track, clip = clip, pitch = item.pitch, beat = item.beat }
    end
  end
  -- The marked notes are chosen by their places in the clip's own order.
  for _, made in ipairs(clips_made) do
    local wanted = {}
    for _, note in ipairs(notes_of[made.id]) do
      wanted[#wanted + 1] = { pitch = note.pitch, start = note.start, length = note.length }
    end
    made:set_notes(wanted)
    local marked = {}
    for _, note in ipairs(notes_of[made.id]) do
      if note.chosen then marked[note.pitch .. "@" .. note.start] = true end
    end
    local places = {}
    for place, note in ipairs(made:notes()) do
      if marked[note.pitch .. "@" .. note.start] then places[place] = true end
    end
    if next(places) then paw.frontend.choose_notes(made.id, places) end
  end
  -- A cursor with a pitch is the roll's, on the clip above it; one with no
  -- pitch is the arrange view's, on the track above it.
  if cursor and cursor.pitch then
    assert(cursor.clip, "a cursor with a pitch is in a clip")
    local roll = paw.ui.views:get("pianoroll")
    roll:edit(cursor.clip)
    roll:set(cursor.pitch, cursor.beat)
  elseif cursor then
    paw.ui.focus("arrange")
    paw.cursor.set_track(cursor.track)
    paw.cursor.set_beat(cursor.beat)
  end
  paw.flush()
  api.undo_checkpoint()
  return tracks
end

-- The places of the notes that are chosen in `clip`: by the pointer, or by
-- a selection of visual mode that names its notes.
local function chosen_places(clip, notes)
  local places = {}
  for _, place in ipairs(paw.frontend.chosen_notes(clip.id)) do
    places[place] = true
  end
  local selection = paw.ui.focused == "pianoroll" and paw.keymap.selection()
  local named = selection and selection.notes and selection.notes[clip.id]
  if named then
    for place, note in ipairs(notes) do
      if named[note.id] then places[place] = true end
    end
  end
  return places
end

--- The fixture of the project as it is now: each track but the master, its
--- clips in the order they start, their notes in the order they start (the
--- lower pitch first), and the cursor of the view that has the focus.
local function text_of()
  local out = {}
  local function add(depth, line) out[#out + 1] = string.rep("  ", depth) .. line end
  local roll = paw.ui.focused == "pianoroll" and paw.ui.views:get("pianoroll")
  local roll_clip = roll and roll:clip()
  local cursor_track = paw.ui.focused == "arrange" and paw.cursor.track_id()
  for _, track in ipairs(paw.tracks()) do
    add(0, "track " .. track.name)
    local clips = track:clips()
    table.sort(clips, function(a, b) return a.start < b.start end)
    for _, clip in ipairs(clips) do
      add(1, string.format("clip %s %g+%g", clip.name, clip.start, clip.length))
      local notes = clip:notes()
      local places = chosen_places(clip, notes)
      local order = {}
      for place in ipairs(notes) do
        order[#order + 1] = place
      end
      table.sort(order, function(a, b)
        local x, y = notes[a], notes[b]
        if x.start ~= y.start then return x.start < y.start end
        return x.pitch < y.pitch
      end)
      for _, place in ipairs(order) do
        local note = notes[place]
        add(2, string.format("%d %g+%g%s", note.pitch, note.start, note.length, places[place] and " *" or ""))
      end
      if roll_clip and roll_clip.id == clip.id then add(2, string.format("cursor %d@%g", roll.pitch, roll.beat)) end
    end
    if cursor_track == track.id then add(1, string.format("cursor @%g", paw.cursor.beat)) end
  end
  -- A mode other than normal: "x v", "x V" or "x b" for a selection.
  local K = paw.keymap
  if K.mode ~= "n" then add(0, "mode " .. K.mode .. (K.visual and (" " .. K.visual.kind) or "")) end
  return table.concat(out, "\n")
end

-- The fixture as a list of its lines, with no indent, comment or blank line:
-- what two fixtures must have the same. The order of the notes of a clip
-- does not count: each run of note lines is sorted.
local function lines_of(text)
  local out, run = {}, {}
  local function end_run()
    table.sort(run)
    for _, note in ipairs(run) do
      out[#out + 1] = note
    end
    run = {}
  end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local item = line:gsub("%-%-.*$", ""):match("^%s*(.-)%s*$"):gsub("%s+", " ")
    if item:match("^%d") then
      run[#run + 1] = item
    elseif item ~= "" then
      end_run()
      out[#out + 1] = item
    end
  end
  end_run()
  return out
end

return function(T)
  --- Make the project of `fixture` in a new project (`T.start()` first),
  --- type `keys` as the user types them, and compare the project with
  --- `expected`. A failure gives the project as a fixture, ready to paste.
  --- `what` says what the keys do. Gives the tracks of the fixture by name.
  local function check_keys(fixture, keys, expected, what)
    T.start()
    local tracks = build(fixture)
    T.keys(keys)
    local got = text_of()
    if table.concat(lines_of(got), "\n") ~= table.concat(lines_of(expected), "\n") then
      error(
        string.format(
          "%s: after the keys %q the project is not the expected one. It is:\n[[\n%s\n]]",
          what or "the keys",
          keys,
          got
        ),
        2
      )
    end
    return tracks
  end
  T.check_keys = check_keys
  T.fixture = build
  T.fixture_text = text_of
end
