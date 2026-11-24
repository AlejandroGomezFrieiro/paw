-- The modifier stack of a clip: `:clip.override transpose=3 velocity=-10` makes
-- a clip, a linked copy for example, play its notes changed while the notes
-- stay as they are. `:clip.stack` changes the stack, and `:clip.render` puts
-- its result into the notes. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys
local api = paw.api

--- A part with a synth, a clip `riff` of four beats (C4 D4 E4 F4, one on
--- each beat, velocity 100) and a linked copy of it after it; the cursor on
--- the copy in the arrange view. Gives the part, the clip and the copy.
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
  local t = paw.add_part({ name = "T" })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  local notes = {}
  for i, pitch in ipairs({ 60, 62, 64, 65 }) do
    notes[i] = { pitch = pitch, start = i - 1, length = 1, velocity = 100 }
  end
  local riff = t:add_clip({ name = "riff", start = 0, length = 4, notes = notes })
  paw.cursor.set_part(t)
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

--- The transpose and the velocity change of a clip's stack, as `{ 3, -10 }`.
local function overrides(clip)
  local out = {}
  for i, kind in ipairs({ "transpose", "velocity" }) do
    local m = paw.modifiers.find(clip.modifiers, kind)
    out[i] = m and paw.modifiers.value(m) or 0
  end
  return out
end

--- The samples of a 16-bit render, as a string.
local function samples(info)
  local data = T.read_file(info.path)
  return data:sub(data:find("data", 1, true) + 8)
end

test(":clip.override transpose=3 on a linked copy: it plays 3 semitones up and its notes stay the same", function()
  local _, riff, copy = linked()
  keys(":clip.override transpose=3 velocity=-10<CR>")
  eq(overrides(copy), { 3, -10 }, "the copy's overrides")
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
  eq(overrides(copy), { 0, 0 }, "clear takes both away")
  keys("u")
  eq(overrides(copy), { 3, -10 }, "u gives them back")
  keys("u")
  eq(overrides(copy), { 0, 0 }, "u again takes both away in one step")
  keys("<C-r>")
  keys("K")
  local said = T.hover_text()
  eq(said:find("plays with transpose +3, velocity -10", 1, true) ~= nil, true, "K: " .. said)
  paw.ui.close()
  -- Wide enough for the whole label on a clip of 4 beats.
  paw.opt.zoom = 4
  eq(T.screen(100, 30):find("riff ≡ +3", 1, true) ~= nil, true, "the label of the copy")
  local dir = T.scratch .. "/overrides-song"
  keys(":w " .. dir .. "<CR>")
  api.project_load(dir)
  paw.flush()
  t = paw.part(api.part_list()[1])
  local after = api.clip_list(t.id)[2]
  eq({ after.link, overrides(after) }, { "riff", { 3, -10 } }, "the reopened copy")
  eq(overrides(api.clip_list(t.id)[1]), { 0, 0 }, "the first clip has none")
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
  eq(overrides(copy), { 0, 0 }, "nothing changed")
end)

test(":export of a transposed copy writes the pitches it plays", function()
  local _, _, copy = linked()
  keys(":clip.override transpose=3 velocity=-10<CR>")
  local path = T.scratch .. "/copy.mid"
  keys(":export clip " .. path .. "<CR>")
  local file = assert(paw.midifile.read(path))
  local got = {}
  for _, n in ipairs(file.tracks[2].notes) do
    got[#got + 1] = n.pitch .. "/" .. n.velocity
  end
  eq(table.concat(got, " "), "63/90 65/90 67/90 68/90", "the notes of the copy, as it plays them")
  eq(pitches(copy), "60 62 64 65", "the copy's own notes stay the same")
end)

--- The roll on a transposed copy (3 up), its cursor on the note of
--- `beat` that plays `pitch`.
local function roll_on(copy, pitch, beat)
  keys(":clip.override transpose=3<CR>")
  keys("<CR>")
  local roll = paw.ui.views:get("pianoroll")
  eq(roll.clip_id, copy.id, "the roll is open on the copy")
  roll.pitch, roll.beat = paw.music.pitch(pitch), beat
end

test("in the piano roll of a transposed copy, the pencil bends a note on the pitch it plays", function()
  local _, _, copy = linked()
  roll_on(copy, "G4", 2)
  keys("ikk<Esc>")
  eq(pitches(copy), "60 62 64 65", "the note keeps its stored pitch, E4")
  local keyed = {}
  for _, c in ipairs(api.clip_controls(copy.id)) do
    if c.type == "bend" then keyed[c.key] = true end
  end
  eq(keyed, { [64] = true }, "its own bend is on the key it has, E4")
  local bent = {}
  for _, n in ipairs(T.roll_notes()) do
    if n.props.bend then bent[#bent + 1] = n.props.label .. " " .. n.props.bend end
  end
  eq(table.concat(bent, ", "), "G4 2", "the roll shows the bend on the note that plays G4")
end)

test("a move of a note of a transposed copy (act.move_note) starts from the pitch it plays", function()
  local _, riff, copy = linked()
  roll_on(copy, "G4", 2)
  -- The third note, E4, plays G4: up a tone to A4 is F#4 in the shared notes.
  paw.frontend.act.move_note(copy.id, 3, 2, paw.music.pitch("A4"))
  eq(pitches(riff), "60 62 66 65", "the shared notes")
end)

test("in a transposed copy, a note the transpose takes above 127 leaves the places of the others", function()
  local _, riff, copy = linked()
  riff:add_note({ pitch = 126, start = 0.5, length = 0.25, velocity = 100 })
  api.undo_checkpoint()
  roll_on(copy, "G4", 2)
  keys("]")
  local velocities = {}
  for i, n in ipairs(api.clip_notes(copy.id)) do
    velocities[i] = n.pitch .. "/" .. n.velocity
  end
  eq(table.concat(velocities, " "), "60/100 126/100 62/100 64/110 65/100", "] makes the note under the cursor louder")
end)

--- The stack of a clip in words, as `transpose +5, velocity -20 (off)`.
local function stack(clip)
  local out = {}
  for i, m in ipairs(clip.modifiers or {}) do
    out[i] = paw.modifiers.describe(m)
  end
  return table.concat(out, ", ")
end

local function said() return paw.ui.messages[#paw.ui.messages].text end

test(":clip.stack add, off, move and rm change the stack, each in one undo step", function()
  local _, _, copy = linked()
  local states = #api.undo_tree().states
  local steps = {
    { ":clip.stack add transpose 5<CR>", "transpose +5", "added modifier 1" },
    { ":clip.stack add velocity -20<CR>", "transpose +5, velocity -20", "added modifier 2" },
    { ":clip.stack off 1<CR>", "transpose +5 (off), velocity -20", "modifier 1 off" },
    { ":clip.stack move 2 1<CR>", "velocity -20, transpose +5 (off)", "moved modifier 2 to 1" },
    { ":clip.stack rm 2<CR>", "velocity -20", "removed modifier 2" },
  }
  for i, step in ipairs(steps) do
    keys(step[1])
    eq(stack(copy), step[2], step[1])
    eq(#api.undo_tree().states, states + i, "one undo step: " .. step[1])
    eq(said():find(step[3], 1, true) ~= nil, true, "the message: " .. said())
  end
  keys("u")
  eq(stack(copy), "velocity -20, transpose +5 (off)", "u puts the removed entry back")
end)

test(":clip.render 1 puts the transpose into the notes and keeps the velocity entry; u takes it back", function()
  local _, riff, copy = linked()
  keys("<Space>cu")
  keys(":clip.override transpose=3 velocity=-10<CR>")
  local states = #api.undo_tree().states
  keys(":clip.render 1<CR>")
  eq(pitches(copy), "63 65 67 68", "the copy's notes, 3 up")
  eq(stack(copy), "velocity -10", "the velocity entry stays")
  eq(said(), "riff: rendered 1 modifiers into its notes: 4 notes", "the message")
  eq(pitches(riff), "60 62 64 65", "the clip that it was linked to keeps its notes")
  eq(#api.undo_tree().states, states + 1, "one undo step")
  keys("u")
  eq({ pitches(copy), stack(copy) }, { "60 62 64 65", "transpose +3, velocity -10" }, "u")
end)

test(
  ":clip.render refuses a linked clip and entries not at the top; :clip.render! leaves the link in one step",
  function()
    local _, riff, copy = linked()
    keys(":clip.override transpose=3<CR>")
    T.expect_error("is linked to 2 clips: :clip.render! takes it out of the link first")
    T.expect_error("move modifier 2 to 1 first")
    T.expect_error("has modifiers 1 to 1, not 2")
    keys(":clip.render<CR>")
    eq(said():find(":clip.render! takes it out", 1, true) ~= nil, true, "linked: " .. said())
    keys(":clip.render 2-2<CR>")
    eq(said():find("move modifier 2 to 1 first", 1, true) ~= nil, true, "not at the top: " .. said())
    keys(":clip.stack off 2<CR>")
    eq(said():find("not 2", 1, true) ~= nil, true, "no entry 2: " .. said())
    local states = #api.undo_tree().states
    keys(":clip.render!<CR>")
    eq({ pitches(copy), stack(copy), copy:get().link }, { "63 65 67 68", "", nil }, "the copy, rendered and unlinked")
    eq(pitches(riff), "60 62 64 65", "the clip keeps its notes")
    eq(#api.undo_tree().states, states + 1, "one undo step")
  end
)

test("S on a clip with scoped modifiers: the right half keeps each scope over its own beats", function()
  local t, riff = linked()
  local function entry(from, to)
    return { kind = "transpose", params = { semitones = 1 }, scope = { from = from, to = to } }
  end
  api.clip_set(riff.id, "modifiers", { entry(0, 1), entry(1, 3), entry(2.5, 4) })
  paw.cursor.set_beat(2)
  keys("S")
  local right = api.clip_list(t.id)[2]
  eq(right.start, 2, "the right half")
  local scopes = {}
  for i, m in ipairs(right.modifiers) do
    scopes[i] = m.scope.from .. "-" .. m.scope.to
  end
  eq(table.concat(scopes, " "), "0-1 0.5-2", "the scope before the cut goes, the scope over it starts at 0")
end)
