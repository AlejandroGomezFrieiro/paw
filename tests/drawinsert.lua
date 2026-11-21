-- Tests of the piano roll's insert mode drawing a note with the cursor
-- (`paw.roll_draw`), and of the other way, the keyboard as a piano. Loaded
-- by tests/suite.lua with its helpers.
local T = ...
local eq, fresh, melody = T.eq, T.fresh, T.melody
local api = paw.api
local draw = paw.roll_draw
local roll = paw.ui.views.pianoroll

-- Each test leaves the piano roll as it found it: closed, the keyboard in
-- the arrange view, in normal mode, insert mode drawing.
local function test(name, fn)
  T.test(name, function()
    local ok, err = xpcall(fn, debug.traceback)
    paw.keymap.feed("<Esc><Esc>")
    paw.roll_clips.only()
    paw.opt.roll_insert = "draw"
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    if not ok then error(err, 0) end
  end)
end

--- Type keys one at a time, as a person does: the kernel closes the undo
--- step after each.
local function typed(text)
  for _, key in ipairs(paw.keymap.parse(text)) do
    paw.keymap.feed(key)
    api.undo_checkpoint()
  end
end

--- A track with an empty clip four beats long, open in the piano roll with
--- the cursor on C4 at its start.
local function empty()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  paw.ui.focus("arrange")
  paw.opt.note_grid, paw.opt.velocity, paw.opt.note_zoom = 0.25, 100, 8
  local track = paw.add_track({ name = "Lead" })
  track:add_device("synth")
  local clip = track:add_clip({ name = "tune", start = 0, length = 4 })
  api.undo_checkpoint()
  paw.ui.show("pianoroll")
  roll:edit(clip)
  roll:set(60, 0)
  return clip, track
end

local function at() return roll.pitch .. "@" .. roll.beat end

test("i l l Escape on C with no note there writes a C two grid steps long", function()
  local clip = empty()
  typed("i")
  eq(paw.keymap.mode, "i", "i starts insert mode")
  eq(select(2, draw.text()), "60@0+0", "with a note at the cursor, nothing long yet")
  typed("ll")
  eq(select(2, draw.text()), "60@0+0.5", "each l makes it a grid step longer")
  eq(at(), "60@0.5", "and the cursor follows its end")
  eq(melody(clip), "", "nothing is written while it is drawn")
  typed("<Esc>")
  eq(melody(clip), "60@0+0.5", "Escape writes it")
  eq(clip:notes()[1].velocity, 100, "as loud as the velocity option")
  eq(paw.keymap.mode, "n", "and leaves insert mode")
end)

test("l and h grow and shrink the note by grid steps, with counts and the arrows", function()
  local clip = empty()
  typed("i4l")
  eq(select(2, draw.text()), "60@0+1", "4l: four steps, a beat")
  typed("h")
  eq(select(2, draw.text()), "60@0+0.75", "h a step shorter")
  typed("<Right><Right><Left>")
  eq(select(2, draw.text()), "60@0+1", "the arrows too")
  typed("12l")
  eq(select(2, draw.text()), "60@0+4", "a count of two digits")
  typed("20h")
  eq(select(2, draw.text()), "60@0+0", "no shorter than nothing")
  local edits = api.project_get().edits
  typed("<Esc>")
  eq(melody(clip), "", "a note of no length is not written")
  eq(api.project_get().edits, edits, "and nothing changes")
  paw.opt.note_grid = 0.5
  typed("i3l<Esc>")
  eq(melody(clip), "60@0+1.5", "the step is the piano roll's grid")
end)

test("+ and - move the note being drawn by semitones, J and K by octaves, r to a named pitch", function()
  local clip = empty()
  typed("i2l3+")
  eq(select(2, draw.text()), "63@0+0.5", "3+: up three semitones")
  typed("J")
  eq(at(), "51@0.5", "J an octave down, and the cursor with it")
  typed("K<C-x>")
  eq(select(2, draw.text()), "62@0+0.5", "K, and Ctrl-x")
  typed("ra")
  eq(select(2, draw.text()), "57@0+0.5", "r a: the nearest A")
  typed("rf#")
  eq(select(2, draw.text()), "54@0+0.5", "r f #: the nearest F sharp")
  typed("rdK")
  typed("]")
  eq(paw.opt.velocity, 110, "] makes the notes louder")
  typed("<Esc>")
  eq(melody(clip), "62@0+0.5", "written where it was drawn to")
  eq(clip:notes()[1].velocity, 110, "as loud as that")
  paw.opt.velocity = 100
end)

test("Enter and Space keep the note and draw the next: after it, after a rest", function()
  local clip = empty()
  typed("i2l<CR>")
  eq(draw.text(), "60@0+0.5", "Enter keeps the note")
  eq(select(2, draw.text()), "60@0.5+0", "and the next starts where it ends")
  typed("2+2l<Space>")
  eq(select(2, draw.text()), "62@1.25+0", "Space leaves a step's rest before the next")
  typed("2+4l")
  eq(melody(clip), "", "none of it is written yet")
  typed("<Esc>")
  eq(melody(clip), "60@0+0.5 62@0.5+0.5 64@1.25+1", "a line, written together")
  -- Backspace takes the last note kept back, to draw again.
  roll:set(72, 3)
  typed("$i2l<CR>2+<BS>")
  eq(select(2, draw.text()), "72@4+0.5", "Backspace makes the note kept last the one being drawn")
  typed("l<Esc>")
  eq(melody(clip):match("%S+$"), "72@4+0.75", "and it is written as drawn again")
  eq(clip.length, 8, "the clip grew a bar to hold what was drawn past its end")
end)

--- The clip's own moves of one kind on a key, as "start:semitones".
local function bends(clip, key)
  local out = {}
  for _, c in ipairs(clip:controls()) do
    if c.type == "bend" and c.key == key then out[#out + 1] = string.format("%g:%g", c.start, c.value * 48) end
  end
  return table.concat(out, " ")
end

test("pencil: on a note the pencil takes it: h l move the edge under the cursor, at its start or its end", function()
  local clip = empty()
  clip:add_note({ pitch = 60, start = 0, length = 1 })
  api.undo_checkpoint()
  typed("il")
  eq(select(2, draw.text()), "60@0.25+0.75", "at its start, l moves the start a step right")
  eq(at(), "60@0.25", "the cursor at the start")
  typed("<Esc>")
  eq(melody(clip), "60@0.25+0.75", "Escape writes it in its place: three steps from a step later")
  typed("u")
  eq(melody(clip), "60@0+1", "one undo step")
  typed("ah<Esc>")
  eq(melody(clip), "60@0+0.75", "a takes it at its end: h shortens it")
  typed("u")
  typed("ehh<Esc>")
  eq(melody(clip), "60@0+1", "in normal mode h only moves")
  typed("eah<Esc>")
  eq(melody(clip), "60@0+0.75", "after e the cursor is where it ends, and a takes it there")
  typed("u0ioh<Esc>")
  eq(melody(clip), "60@0+0.75", "o goes to the other edge")
  typed("u0i2h<Esc>")
  eq(melody(clip), "60@0+1", "no note goes before its clip")
end)

test("pencil: the pencil takes up the note where Enter goes, and no note grows over the next of its pitch", function()
  local clip = empty()
  clip:add_notes({ { pitch = 60, start = 0, length = 0.5 }, { pitch = 60, start = 0.5, length = 0.5 } })
  api.undo_checkpoint()
  typed("i<CR>")
  eq(select(2, draw.text()), "60@0.5+0.5", "Enter goes to the next note, which starts there, and takes it")
  typed("l<Esc>")
  eq(melody(clip), "60@0+0.5 60@0.75+0.25", "l at its start shortens it")
  typed("u")
  roll:set(60, 0)
  typed("a4l")
  eq(select(2, draw.text()), "60@0+0.5", "it stops at the next note of its pitch")
  typed("x<Esc>")
  eq(melody(clip), "60@0.5+0.5", "x erases the note under the pencil")
end)

test("pencil: j and k bend the note at its end: its own pitch bend, shown and described", function()
  local clip = empty()
  typed("i4lkk")
  eq(draw.describe(), "C4 · end · 4 steps · 1 beat · bend +2", "two semitones up at its end")
  typed("<Esc>")
  eq(melody(clip), "60@0+1", "the note")
  eq(bends(clip, 60), "0.5:0.125 0.53125:0.25 0.5625:0.375 0.59375:0.5 0.625:0.625 0.65625:0.75 0.6875:0.875 "
    .. "0.71875:1 0.75:1.125 0.78125:1.25 0.8125:1.375 0.84375:1.5 0.875:1.625 0.90625:1.75 0.9375:1.875 0.96875:2",
    "a ramp of its own pitch bend from its middle")
  roll:set(60, 0)
  local said = {}
  for _, line in ipairs(roll:describe()) do said[#said + 1] = type(line) == "table" and line.text or line end
  eq(table.concat(said, "\n"):find("bends up 2 semitones by its end, from 50% of it", 1, true) ~= nil, true, "K says it")
  local mark
  for _, n in ipairs(T.roll_notes()) do if n.props.bend then mark = n end end
  eq(mark and mark.props.bend .. " " .. mark.props.bend_at, "2 0.5", "the roll shows it")
  typed("ij<Esc>")
  eq(select(2, bends(clip, 60):gsub("%S+", "")), 16, "taken up, the note bends again from its bend")
  eq(bends(clip, 60):match("%S+$"), "0.96875:1", "a semitone less")
  typed("i+<Esc>")
  eq(bends(clip, 60) .. "|" .. bends(clip, 61):match("%S+$"), "|0.96875:1", "its bend goes with its pitch")
end)

test("pencil: the length in note values, the note in time, again with dot, and Ctrl-u takes back all", function()
  local clip = empty()
  typed("i=8.")
  eq(select(2, draw.text()), "60@0+0.75", "=8. a dotted eighth")
  typed("=4t")
  eq(select(2, draw.text()), "60@0+0.666667", "=4t a triplet quarter")
  typed("=16>")
  eq(select(2, draw.text()), "60@0.25+0.25", "> a step later")
  typed("2.")
  eq(draw.text(), "60@0.25+0.25 60@0.5+0.25", "2. the note twice again after it")
  typed("<C-u>")
  eq(draw.text() .. "|" .. select(2, draw.text()), "|60@0+0", "Ctrl-u takes back all")
  typed("<Esc>")
  eq(melody(clip), "", "and nothing is written")
end)

test("one insert is one undo step, the clip's growth with it", function()
  local clip = empty()
  roll:set(60, 3)
  typed("i2l<CR>2+4l<Space>+2l<Esc>")
  eq(melody(clip), "60@3+0.5 62@3.5+1 63@4.75+0.5", "three notes drawn, running past the end")
  eq(clip.length, 8, "the clip grew to hold them")
  typed("u")
  eq(melody(clip) .. " " .. clip.length, " 4", "u takes them all back at once, and the growth")
  typed("<C-r>")
  eq(melody(clip), "60@3+0.5 62@3.5+1 63@4.75+0.5", "Ctrl-r puts them back")
end)

test("i m Enter in the arrange view: the clip that m makes and the notes drawn into it are one undo step", function()
  local _, track = empty()
  paw.ui.focus("arrange")
  paw.cursor.set_track(track)
  paw.cursor.set_beat(8)
  typed("im<CR>4l<Esc>")
  local clips = track:clips()
  eq(#clips, 2, "m made a clip")
  eq(melody(clips[2]), "60@0+1", "with the note drawn")
  typed("u")
  eq(#track:clips(), 1, "one u takes back the clip with its notes")
  typed("<C-r>")
  eq(melody(track:clips()[2]), "60@0+1", "Ctrl-r puts both back")
end)

test("dot draws the last insert again at the cursor, moved to its pitch", function()
  local clip = empty()
  typed("i2l<CR>4+2l<Esc>")
  eq(melody(clip), "60@0+0.5 64@0.5+0.5", "a shape drawn")
  roll:set(67, 2)
  typed(".")
  eq(melody(clip), "60@0+0.5 64@0.5+0.5 67@2+0.5 71@2.5+0.5", "the same shape from G at beat 3")
  eq(paw.keymap.mode, "n", "back in normal mode")
  typed("u")
  eq(melody(clip), "60@0+0.5 64@0.5+0.5", "a step of its own to undo")
  -- `a` takes the note under the cursor at its end, or starts a step after the cursor.
  roll:set(60, 0)
  typed("a2l<Esc>")
  eq(melody(clip), "60@0+1 64@0.5+0.5", "a lengthens the note under the cursor from its end")
  roll:set(72, 2)
  typed("al<Esc>")
  eq(melody(clip):match("%S+$"), "72@2.25+0.25", "with no note there, a step after the cursor")
end)

test("with several clips edited, what is drawn goes into the active one", function()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  paw.opt.note_grid = 0.25
  local a = paw.add_track({ name = "A" }):add_clip({ name = "a", start = 0, length = 4 })
  local b = paw.add_track({ name = "B" }):add_clip({ name = "b", start = 0, length = 4 })
  api.undo_checkpoint()
  paw.ui.show("pianoroll")
  roll:edit(a)
  paw.roll_clips.open({ a.id, b.id }, b.id)
  roll:set(65, 1)
  typed("i4l<Esc>")
  eq(melody(a) .. "|" .. melody(b), "|65@1+1", "into b, the active clip, where both are")
  paw.roll_clips.activate(a.id)
  roll:set(67, 2)
  typed("i4l<Esc>")
  eq(melody(a) .. "|" .. melody(b), "67@2+1|65@1+1", "and into a once it is the active one")
end)

test("a suggestion's keys come before the drawing ones: Escape dismisses it, and drawing goes on", function()
  local clip = empty()
  local complete = paw.complete
  local source = {
    name = "drawinsert", priority = 0,
    complete = function(_, done) done({ { label = "fifth", notes = { { pitch = 67, start = 1, length = 1 } } } }) end,
  }
  local auto = paw.opt.complete_auto
  paw.opt.complete_auto = false
  complete.register(source)
  local ok, err = xpcall(function()
    typed("i2l<C-Space>")
    eq(complete.current() ~= nil, true, "a suggestion shows while a note is drawn")
    typed("<Esc>")
    eq(complete.current(), nil, "the first Escape dismisses it")
    eq(draw.active(), true, "and the note is still being drawn")
    eq(melody(clip), "", "nothing written yet")
    typed("l<Esc>")
    eq(melody(clip), "60@0+0.75", "the second Escape writes it")
  end, debug.traceback)
  complete.unregister(source.name)
  complete.dismiss()
  paw.opt.complete_auto = auto
  if not ok then error(err, 0) end
end)

-- The terminal's piano roll as cells: what is at a beat and pitch of the
-- roll, with its colours, from the view drawn by itself.
local function cell(beat, pitch)
  local shot = api.ui_view_snapshot("pianoroll", 100, 30)
  -- The rows above the notes (title, chord row, ruler) as the view counted them.
  local g = roll.geometry
  local x = g.keys + math.floor((beat - roll.scroll) * g.zoom + 0.5)
  local y = g.head + roll.top - pitch
  for _, run in ipairs(shot.rows[y + 1] or {}) do
    if x >= run.x and x < run.x + run.w then
      local chars = {}
      for ch in run.text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
      return { ch = chars[x - run.x + 1] or " ", fg = run.fg, bg = run.bg }
    end
  end
end

test("the note being drawn is drawn in insert mode's colour, its pitch and length in the title and on the key line", function()
  local clip = empty()
  local palette = require("paw.theme").palette
  typed("i2+4l")
  local note = cell(0.5, 62)
  eq(note.fg, palette.insert, "the note being drawn has the insert colour")
  eq(note.bg, paw.draw.mix(palette.bg, palette.insert, 0.3), "on a faint shade of it")
  eq(cell(1, 62).bg, palette.insert, "the cursor is at its end")
  local screen = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(screen:find("DRAW D4 end  4 steps · 1 beat  vel 100", 1, true) ~= nil, true, "the title says what is being drawn")
  local line = paw.ui.keybar.entries()
  eq(line[1][1] .. " " .. line[1][2], "D4 end · 4 steps · 1 beat", "the key line starts with it")
  eq(line[2][1] .. " " .. line[2][2], "l longer", "then the keys that draw")
  eq(#paw.ui.keybar.check(), 0, "every key it shows is mapped")
  local drawn
  for _, n in ipairs(T.roll_notes()) do if n.props.pending then drawn = n end end
  eq(drawn and api.json_encode(drawn.r), "[0,62,1,1]", "a window is sent it as a note being drawn, to paint where it is")
  typed("<CR>")
  local kept = cell(0.5, 62)
  eq(kept.fg ~= palette.insert and kept.bg ~= note.bg, true, "a note kept no longer looks like the one being drawn")
  typed("<Esc>")
  eq(melody(clip), "62@0+1", "it is written")
  eq(cell(0.5, 62).bg, kept.bg, "and looks as it did when kept: what was seen is what is written")
end)

test("I, or the roll_insert option, makes the keyboard a piano instead", function()
  local clip = empty()
  paw.opt.octave = 4
  roll.length = nil
  typed("Is")
  eq(draw.active(), false, "I draws nothing")
  typed("d<Esc>")
  eq(melody(clip), "62@0+0.25 64@0.25+0.25", "s and d are D and E, entered as typed")
  paw.opt.roll_insert = "keys"
  roll:set(60, 2)
  typed("ia<Esc>")
  eq(melody(clip):match("%S+$"), "60@2+0.25", "with roll_insert = keys, i does the same")
  paw.opt.roll_insert = "draw"
  typed("i")
  eq(draw.active(), true, "and draws again when it is set back")
  eq(paw.ui.keybar.entries()[2][1], "l", "with the drawing keys on the key line")
  typed("<Esc>I")
  eq(paw.ui.keybar.entries()[1][1], "a s d f g h j k", "and the piano's on I")
  typed("<Esc>")
end)

test("pencil: chord symbols, absolute and in the key, read into pitches", function()
  local function pitches(symbol, key)
    local v, why = paw.chords.parse(symbol, key and paw.harmony.parse_key(key), 60)
    if not v then return "nil: " .. tostring(why) end
    return table.concat(v.pitches, " ")
  end
  local cases = {
    { "C", "60 64 67" }, { "Cmaj7", "60 64 67 71" }, { "C3maj7", "48 52 55 59" }, { "Csus4", "60 65 67" },
    { "Am7b5", "57 60 63 67" }, { "F#m9/C#", "61 66 69 76 80" }, { "C(add9)", "60 64 67 74" },
    { "V7", "55 59 62 65" }, { "ii7", "62 65 69 72" }, { "bVII", "58 62 65" }, { "V64", "62 67 71" },
    { "V6/4", "62 67 71" }, { "I6", "64 67 72" }, { "viio7", "59 62 65 68" }, { "iiø7", "62 65 68 72" },
    { "V/ii", "57 61 64" }, { "V7/V", "62 66 69 72" }, { "viio7/V", "66 69 72 75" }, { "N6", "65 68 73" },
    { "Ger6", "56 60 63 66" },
    { "V7", "64 68 71 74", "A minor" }, { "iv", "62 65 69", "A minor" }, { "VI", "65 69 72", "A minor" },
    { "bVII", "55 59 62", "A minor" },
  }
  for _, c in ipairs(cases) do
    eq(pitches(c[1], c[3]), c[2], c[1] .. (c[3] and " in " .. c[3] or ""))
  end
  eq(paw.chords.parse("V7").name, "G7", "a chord in the key has its name")
  eq(paw.chords.parse("Dm7").roman, "ii7", "and its numeral")
end)

test("pencil: c chooses a chord, which h l = < > shape as one note until Enter or Escape", function()
  local clip = empty()
  typed("ic")
  eq(paw.ui.float and paw.ui.float.name, "pick", "c opens the chord picker")
  typed("Cmaj7<CR>")
  eq(select(2, draw.text()), "60@0+0 64@0+0 67@0+0 71@0+0", "the chord at the pencil")
  typed("ll")
  eq(draw.label():match("^DRAW Cmaj7 end  2 steps"), "DRAW Cmaj7 end  2 steps", "shaped as one note, its name in the title")
  typed("<Esc>")
  eq(melody(clip), "60@0+0.5 64@0+0.5 67@0+0.5 71@0+0.5", "four notes two steps long")
  typed("u")
  eq(melody(clip), "", "one undo step")
  roll:set(60, 0)
  typed("i4c<CR>4l<CR>2l<Esc>")
  eq(melody(clip), "60@0+1 64@0+1 67@0+1 71@0+1 60@1+0.5", "4c: the diatonic seventh; Enter keeps it and draws on after it")
end)

test("pencil: m puts marks of the song at the pencil: a tempo, a key change for the chords, a signature, a marker", function()
  local clip = empty()
  typed("i4lmt96<CR>")
  eq(paw.tempo.at(0), 96, "mt: the tempo from the pencil")
  typed("<CR>mkD minor<CR>")
  eq(paw.markers.list()[1].name, "key D minor", "mk: a key change from the pencil")
  typed("rgc<CR>")
  eq(select(2, draw.text()), "55@1+0 58@1+0 62@1+0", "the chords after it are of that key: G minor on G")
  typed("4lms6/8<CR>m'Verse<CR>")
  eq(select(1, paw.tempo.signature_at(4)) .. "/" .. select(2, paw.tempo.signature_at(4)), "6/8", "ms: from the next bar")
  eq(paw.markers.list()[2] and paw.markers.list()[2].name, "Verse", "m': a marker")
  typed("<Esc>")
  eq(melody(clip), "60@0+1 55@1+1 58@1+1 62@1+1", "the notes")
  typed("u")
  eq(melody(clip) .. "|" .. paw.tempo.at(0) .. "|" .. #paw.markers.list(), "|120|0", "one undo step takes all back")
end)
