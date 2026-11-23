-- The overrides of a clip: `:clip.override transpose=3 velocity=-10` makes
-- a clip, a linked copy for example, play its notes changed while the notes
-- stay as they are. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys
local api = paw.api

--- A track with a synth, a clip `riff` of four beats (C4 D4 E4 F4, one on
--- each beat, velocity 100) and a linked copy of it after it; the cursor on
--- the copy in the arrange view. Gives the track, the clip and the copy.
local function linked()
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
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  local notes = {}
  for i, pitch in ipairs({ 60, 62, 64, 65 }) do
    notes[i] = { pitch = pitch, start = i - 1, length = 1, velocity = 100 }
  end
  local riff = t:add_clip({ name = "riff", start = 0, length = 4, notes = notes })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  paw.opt.grid, paw.opt.note_grid = 1, 0.25
  keys("<Space>cl")
  api.undo_checkpoint()
  return t, riff, paw.clip(api.clip_list(t.id)[2].id)
end

--- The pitches of a clip's stored notes, as `60 62 64 65`.
local function pitches(clip)
  local out = {}
  for i, n in ipairs(api.clip_notes(clip.id)) do
    out[i] = n.pitch
  end
  return table.concat(out, " ")
end

--- The samples of a 16-bit render, as a string.
local function samples(info)
  local data = T.read_file(info.path)
  return data:sub(data:find("data", 1, true) + 8)
end

test(":clip.override transpose=3 on a linked copy: it plays 3 semitones up and its notes stay the same", function()
  local _, riff, copy = linked()
  keys(":clip.override transpose=3 velocity=-10<CR>")
  eq({ copy.transpose, copy.velocity }, { 3, -10 }, "the copy's overrides")
  eq({ pitches(riff), pitches(copy) }, { "60 62 64 65", "60 62 64 65" }, "the shared notes stay the same")
  local overridden = T.render({ bits = 16, tail = 0.1 })
  -- The same sound from a plain copy whose notes are 3 up and 10 softer.
  keys("<Space>cu")
  keys(":clip.override clear<CR>")
  local changed = {}
  for i, n in ipairs(api.clip_notes(copy.id)) do
    changed[i] = { pitch = n.pitch + 3, start = n.start, length = n.length, velocity = 90 }
  end
  copy:set_notes(changed)
  eq(samples(T.render({ bits = 16, tail = 0.1 })) == samples(overridden), true, "the render of the copy is 3 up")
end)

test("in the piano roll of a transposed copy, a note added at E4 is C#4 in the shared notes and shows as E4", function()
  local _, riff, copy = linked()
  keys(":clip.override transpose=3<CR>")
  keys("<CR>")
  local roll = paw.ui.views:get("pianoroll")
  eq(roll.clip_id, copy.id, "the roll is open on the copy")
  roll.pitch, roll.beat = paw.music.pitch("E4"), 0.5
  keys("<CR>")
  eq(pitches(copy), "60 61 62 64 65", "C#4 in the copy's notes")
  eq(pitches(riff), "60 61 62 64 65", "and in the clip's, which it shares")
  local shown = {}
  for _, n in ipairs(T.roll_notes()) do
    if n.k:find("/note:" .. copy.id .. ":", 1, true) then shown[#shown + 1] = n.props.label end
  end
  eq(table.concat(shown, " "), "D#4 E4 F4 G4 G#4", "the roll shows each note at the pitch it plays")
end)

test(":clip.override clear and u put the overrides back; :w and a reopen keep them", function()
  local t, _, copy = linked()
  local states = #api.undo_tree().states
  keys(":clip.override transpose=3 velocity=-10<CR>")
  eq(#api.undo_tree().states, states + 1, "one undo step")
  keys(":clip.override clear<CR>")
  eq({ copy.transpose, copy.velocity }, { 0, 0 }, "clear takes both away")
  keys("u")
  eq({ copy.transpose, copy.velocity }, { 3, -10 }, "u gives them back")
  keys("u")
  eq({ copy.transpose, copy.velocity }, { 0, 0 }, "u again takes both away in one step")
  keys("<C-r>")
  keys("K")
  local said = {}
  for _, line in ipairs(paw.ui.views:get("pager").lines) do
    said[#said + 1] = line.text
  end
  said = table.concat(said, "\n")
  eq(said:find("plays with transpose +3, velocity -10", 1, true) ~= nil, true, "K: " .. said)
  paw.ui.close()
  -- Wide enough for the whole label on a clip of 4 beats.
  paw.opt.zoom = 4
  eq(T.screen(100, 30):find("riff ≡ +3", 1, true) ~= nil, true, "the label of the copy")
  local dir = T.scratch .. "/overrides-song"
  keys(":w " .. dir .. "<CR>")
  api.project_load(dir)
  paw.flush()
  t = paw.track(api.track_list()[1])
  local after = api.clip_list(t.id)[2]
  eq({ after.link, after.transpose, after.velocity }, { "riff", 3, -10 }, "the reopened copy")
  eq(api.clip_list(t.id)[1].transpose, 0, "the first clip has none")
end)

test(":clip.override refuses what is not a whole number from -127 to 127", function()
  local _, _, copy = linked()
  local function said() return paw.ui.messages[#paw.ui.messages].text end
  T.expect_error("from %-127 to 127")
  T.expect_error("^usage: clip.override")
  keys(":clip.override transpose=200<CR>")
  eq(said():find("from -127 to 127", 1, true) ~= nil, true, "out of range: " .. said())
  keys(":clip.override pitch=3<CR>")
  eq(said():find("usage: clip.override", 1, true) ~= nil, true, "another word: " .. said())
  eq(copy.transpose, 0, "nothing changed")
end)

test(":export of a transposed copy writes the pitches it plays", function()
  local _, _, copy = linked()
  keys(":clip.override transpose=3 velocity=-10<CR>")
  local path = T.scratch .. "/copy.mid"
  keys(":export " .. path .. " clip<CR>")
  local file = assert(paw.midifile.read(path))
  local got = {}
  for _, n in ipairs(file.tracks[2].notes) do
    got[#got + 1] = n.pitch .. "/" .. n.velocity
  end
  eq(table.concat(got, " "), "63/90 65/90 67/90 68/90", "the notes of the copy, as it plays them")
  eq(pitches(copy), "60 62 64 65", "the copy's own notes stay the same")
end)
