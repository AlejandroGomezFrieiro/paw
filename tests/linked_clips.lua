-- Linked clips: `<Space>cl` puts a linked copy after a MIDI clip, and an
-- edit of the notes of one changes all of them; `<Space>cu` makes a clip a
-- plain copy again. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys
local api = paw.api

--- A track with a synth and one clip `riff` of four beats, a note on every
--- beat; the cursor on it in the arrange view.
local function song()
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  T.after(function()
    paw.keymap.feed("<Esc><Esc>")
    paw.ui.views:get("pianoroll").clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
  end)
  local t = paw.add_track({ name = "T" })
  t:add_device("synth")
  local notes = {}
  for beat = 0, 3 do
    notes[#notes + 1] = { pitch = 60 + beat, start = beat, length = 1 }
  end
  local riff = t:add_clip({ name = "riff", start = 0, length = 4, notes = notes })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  paw.opt.grid, paw.opt.note_grid = 1, 0.25
  api.undo_checkpoint()
  return t, riff
end

local function states() return #api.undo_tree().states end

--- The clips of track `t` as `name@start:link`, in timeline order.
local function layout(t)
  local out = {}
  for _, c in ipairs(api.clip_list(t.id)) do
    out[#out + 1] = string.format("%s@%g:%s", c.name, c.start, c.link or "-")
  end
  return table.concat(out, " ")
end

local function note_count(id) return api.clip_get(id).note_count end

--- The note counts of two clips, as "5 4".
local function counts(a, b) return note_count(a) .. " " .. note_count(b) end

test(
  "<Space>cl puts a linked copy after the clip; a note added in the copy's piano roll is in both; u takes it out of both",
  function()
    local t, riff = song()
    local before = states()
    keys("<Space>cl")
    eq(layout(t), "riff@0:riff riff@4:riff", "a linked copy after the clip")
    eq(states(), before + 1, "one undo step")
    local copy = api.clip_list(t.id)[2].id
    eq(paw.cursor.beat, 4, "the cursor on the copy")
    keys("<CR>")
    eq(paw.ui.views:get("pianoroll").clip_id, copy, "the roll is open on the copy")
    local roll = paw.ui.views:get("pianoroll")
    roll.pitch, roll.beat = 72, 2
    keys("<CR>")
    eq(counts(copy, riff.id), "5 5", "the note is in the copy and in the clip")
    keys("u")
    eq(counts(copy, riff.id), "4 4", "u takes it out of both")
  end
)

test(":w writes the notes of a link to one file in linked/, and the link holds after a reopen", function()
  local t = song()
  keys("<Space>cl")
  local dir = T.scratch .. "/linked-song"
  keys(":w " .. dir .. "<CR>")
  eq(T.read_file(dir .. "/linked/riff.midi2"):sub(1, 8), "SMF2CLIP", "the link's MIDI 2.0 clip file")
  eq(io.open(dir .. "/tracks/T/clips/riff.midi2") == nil, true, "no file of the clip's own")
  local entries = api.json_decode(T.read_file(dir .. "/tracks/T/track.json")).clips
  eq(#entries, 2, "two clip entries")
  for i, entry in ipairs(entries) do
    eq(entry.link .. " " .. entry.content.file, "riff linked/riff.midi2", "entry " .. i)
  end
  api.project_load(dir)
  paw.flush()
  t = paw.track(api.track_list()[1])
  eq(layout(t), "riff@0:riff riff@4:riff", "both clips linked after the reopen")
  local first, second = api.clip_list(t.id)[1].id, api.clip_list(t.id)[2].id
  api.clip_note_add(first, { pitch = 72, start = 2, length = 1 })
  eq(note_count(second), 5, "an edit of one still changes the other")
end)

test("<Space>cu makes the clip a plain copy: a later edit of it leaves the other clip alone", function()
  local t, riff = song()
  keys("<Space>cl")
  local copy = api.clip_list(t.id)[2].id
  local before = states()
  keys("<Space>cu")
  eq(layout(t), "riff@0:riff riff@4:-", "the copy is out of the link")
  eq(states(), before + 1, "one undo step")
  api.clip_note_add(copy, { pitch = 72, start = 2, length = 1 })
  eq(counts(copy, riff.id), "5 4", "the edit stays in the copy")
  keys("<Space>cu")
  eq(paw.ui.messages[#paw.ui.messages].text, "the clip is not linked", "a plain clip says so")
end)

test("K on a linked clip names the link and its clips, and the arrange view marks it with ≡", function()
  song()
  keys("<Space>cl")
  keys("K")
  local said = T.hover_text()
  eq(said:find("linked: riff, 2 clips", 1, true) ~= nil, true, "K: " .. said)
  paw.ui.close()
  local screen = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(screen:find("riff ≡", 1, true) ~= nil, true, "the label of a linked clip")
end)

test("S on a linked clip splits only that clip: the other clip of the link keeps its notes", function()
  local t, riff = song()
  keys("<Space>cl")
  local copy = api.clip_list(t.id)[2].id
  paw.cursor.set_beat(6)
  keys("S")
  eq(note_count(riff.id), 4, "the clip keeps its four notes")
  eq(note_count(copy), 2, "the left half of the copy has its first two notes")
  eq(api.clip_get(riff.id).link_count, 1, "the copy left the link")
end)
