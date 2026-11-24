-- Tests of multi-part MIDI editing: other parts' notes behind the piano
-- roll's, several clips edited at once, the roll's layers. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local eq, fresh, melody = T.eq, T.fresh, T.melody

-- Each test leaves the piano roll as it found it: closed, the keyboard in
-- the arrange view, editing one clip.
local function test(name, fn)
  T.test(name, function()
    local ok, err = xpcall(fn, debug.traceback)
    paw.keymap.feed("<Esc><Esc>")
    paw.roll_clips.only()
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    if not ok then error(err, 0) end
  end)
end
local api = paw.api
local rc = paw.roll_clips

local keys = T.keys

local function notes(list)
  local out = {}
  for _, n in ipairs(list) do
    out[#out + 1] = { pitch = n[1], start = n[2], length = n[3] or 1, velocity = 100 }
  end
  return out
end

--- A song of three parts: Keys (a clip from 0), Bass (a clip from 2) and
--- Pad (a clip from 0), all pitched; and Drums, with a drum map.
local function song()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  paw.opt.grid, paw.opt.note_grid, paw.opt.ripple, paw.opt.roll_context = 1, 0.25, false, "all"
  local keys_t = paw.add_part({ name = "Keys" })
  local bass_t = paw.add_part({ name = "Bass" })
  local pad_t = paw.add_part({ name = "Pad" })
  local drums_t = paw.add_part({ name = "Drums" })
  drums_t.meta = { drums = { map = "gm", rows = {} } }
  local s = {
    keys = keys_t:add_clip({
      name = "chords",
      start = 0,
      length = 8,
      notes = notes({ { 60, 0 }, { 64, 1 }, { 67, 2 } }),
    }),
    bass = bass_t:add_clip({ name = "line", start = 2, length = 4, notes = notes({ { 36, 0 }, { 43, 1 }, { 40, 2 } }) }),
    pad = pad_t:add_clip({ name = "pad", start = 0, length = 8, notes = notes({ { 72, 0, 4 }, { 76, 4, 4 } }) }),
    drums = drums_t:add_clip({
      name = "beat",
      start = 0,
      length = 8,
      notes = notes({ { 36, 0, 0.25 }, { 38, 1, 0.25 } }),
    }),
    parts = { keys = keys_t, bass = bass_t, pad = pad_t, drums = drums_t },
  }
  api.undo_checkpoint()
  return s
end

local function pitches(list)
  local out = {}
  for _, n in ipairs(list) do
    out[#out + 1] = n.pitch .. "@" .. n.start
  end
  table.sort(out)
  return table.concat(out, " ")
end

test("the piano roll shows other pitched parts' notes behind its own, in their beats", function()
  local s = song()
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(s.keys)
  eq(pitches(rc.context()), "36@2 40@4 43@3 72@0 76@4", "bass and pad, the bass two beats in; no drums")
  eq(rc.context()[1].color, paw.draw.part_colour(api.part_get(s.parts.bass.id)), "each in its part's colour")
  rc.show_part(s.parts.pad.id, false)
  eq(pitches(rc.context()), "36@2 40@4 43@3", "a part can be hidden")
  rc.show_part(s.parts.drums.id, true)
  eq(pitches(rc.context()), "36@0 36@2 38@1 40@4 43@3", "and a drum part shown")
  rc.show_part(s.parts.pad.id, nil)
  rc.show_part(s.parts.drums.id, nil)
  paw.opt.roll_context = "none"
  eq(#rc.context(), 0, "roll_context none shows nothing")
  paw.opt.roll_context = { s.parts.pad.id }
  eq(pitches(rc.context()), "72@0 76@4", "or a list of parts")
  paw.opt.roll_context = "all"
  roll:edit(s.bass)
  eq(pitches(rc.context()), "67@0 72@-2 76@2", "from the bass clip's start, only what sounds during it")
  roll:set(43, 1)
  local sounding = rc.sounding(1)
  eq(table.concat(sounding, " "), "43 72", "the keys sounding at the cursor, in every part shown")
  paw.ui.show("pianoroll")
  local text = table.concat(api.ui_snapshot(140, 40), "\n")
  eq(text:find("render failed", 1, true), nil, "the roll draws")
  paw.ui.hide("pianoroll")
end)

test("an edit of the roll's own notes keeps the notes behind them, an edit of those notes finds them again", function()
  local s = song()
  local derived = require("paw.derived")
  local function made()
    for _, st in ipairs(derived.stats()) do
      if st.name == "roll.context" then return st.made end
    end
  end
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(s.keys)
  paw.ui.focus("pianoroll")
  eq(pitches(rc.context()), "36@2 40@4 43@3 72@0 76@4", "the bass and the pad behind")
  local before = made()
  -- `x` on the E of the chords clip.
  roll.pitch, roll.beat = 64, 1
  keys("x")
  paw.flush()
  eq(#s.keys:notes(), 2, "the note is gone")
  eq(pitches(rc.context()), "36@2 40@4 43@3 72@0 76@4", "the same notes behind")
  eq(made(), before, "and they were not found again")
  s.bass:add_notes({ { pitch = 48, start = 3, length = 1, velocity = 100 } })
  paw.flush()
  eq(pitches(rc.context()), "36@2 40@4 43@3 48@5 72@0 76@4", "a note of the bass shows behind")
  eq(made(), before + 1, "found again once")
end)

-- The terminal's piano roll as cells: what is at a beat and pitch of the
-- roll, with its colours (`#rrggbb`), from the view drawn by itself.
local function cells(width, height)
  local shot = api.ui_view_snapshot("pianoroll", width, height)
  local roll = paw.ui.views:get("pianoroll")
  local at = function(beat, pitch)
    local x = roll.geometry.keys + math.floor((beat - roll.scroll) * paw.opt.note_zoom + 0.5)
    -- Under the title, the chord row when it shows, and the ruler.
    local y = (roll.head or 2) + roll.top - pitch
    for _, run in ipairs(shot.rows[y + 1] or {}) do
      if x >= run.x and x < run.x + run.w then
        local chars = {}
        for ch in run.text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
          chars[#chars + 1] = ch
        end
        return { ch = chars[x - run.x + 1] or " ", fg = run.fg, bg = run.bg, text = run.text }
      end
    end
  end
  local lines = {}
  for i, row in ipairs(shot.rows) do
    local parts = {}
    for _, run in ipairs(row) do
      parts[#parts + 1] = run.text
    end
    lines[i] = table.concat(parts)
  end
  return at, table.concat(lines, "\n")
end

local function faint(colour) return paw.draw.mix(require("paw.theme").palette.bg, colour, 0.20) end

test("the terminal's piano roll draws other parts' notes dashed in their colours, its own solid and named", function()
  local s = song()
  local roll = paw.ui.views:get("pianoroll")
  local zoom = paw.opt.note_zoom
  paw.opt.note_zoom = 8
  roll:edit(s.keys)
  roll:set(64, 0)
  roll.top = 76
  local at, text = cells(120, 30)
  local pad_colour = paw.draw.part_colour(api.part_get(s.parts.pad.id))
  local bass_colour = paw.draw.part_colour(api.part_get(s.parts.bass.id))
  local keys_colour = paw.draw.part_colour(api.part_get(s.parts.keys.id))
  local pad = at(1, 72)
  eq(pad.ch, "╌", "a pad note behind: a dashed line")
  eq(pad.bg, faint(pad_colour), "on a faint shade of the pad's colour")
  eq(at(1.5, 64).bg, keys_colour, "the clip's own note in its part's full colour")
  eq(text:find("▏E4", 1, true) ~= nil, true, "and named")
  eq(at(0.5, 76) and at(0.5, 76).ch ~= "╌", true, "nothing where no note sounds")
  roll:set(36, 2)
  at, text = cells(120, 30)
  eq(at(2.5, 36).ch, "╌", "the bass note two beats in, dashed")
  eq(at(2.5, 36).bg, faint(bass_colour), "in the bass's colour, not the pad's")
  eq(text:find("render failed", 1, true), nil, "drawn without an error")
  -- The keys sounding at the cursor are marked on the keyboard.
  local shot = api.ui_snapshot(120, 30)
  eq(table.concat(shot, "\n"):find("•", 1, true) ~= nil, true, "a dot on a key sounding at the cursor")
  paw.opt.note_zoom = zoom
end)

test("the terminal's piano roll draws every clip edited, says which is active and how many, and switches", function()
  local s = song()
  local roll = paw.ui.views:get("pianoroll")
  local zoom = paw.opt.note_zoom
  paw.opt.note_zoom = 8
  rc.open({ s.keys.id, s.bass.id }, s.keys.id)
  roll:set(36, 2)
  local at, text = cells(120, 30)
  local bass_colour = paw.draw.part_colour(api.part_get(s.parts.bass.id))
  local first = text:match("^[^\n]*")
  eq(
    first:find(" chords ", 1, true) ~= nil and first:find("Keys  +1 clip", 1, true) ~= nil,
    true,
    "the title: the active clip and one more"
  )
  local note = at(3.5, 43) -- not the one under the cursor, which is drawn as the cursor
  eq(note.ch ~= "╌" and note.bg == bass_colour, true, "a bass note drawn as a note, in the bass's colour")
  eq(text:find("▏C2", 1, true) ~= nil, true, "and named")
  keys("ga")
  at, text = cells(120, 30)
  first = text:match("^[^\n]*")
  eq(
    first:find(" line ", 1, true) ~= nil and first:find("Bass  +1 clip", 1, true) ~= nil,
    true,
    "ga: the bass clip is active"
  )
  eq(at(1.5, 43).bg, bass_colour, "its notes where they were, a beat in now")
  -- A stretch of time across both, deleted, in the terminal.
  roll:set(40, -0.5)
  keys("v")
  roll:set(40, 1.5)
  at = cells(120, 30)
  eq(at(0.5, 36).bg ~= bass_colour, true, "the selection shows over a bass note")
  keys("d")
  eq(melody(s.keys) .. " | " .. melody(s.bass), "60@0+1 64@1+1 | 40@2+1", "the stretch took notes of both clips")
  at = cells(120, 30)
  eq(at(1.5, 43).bg ~= bass_colour, true, "and the roll shows them gone")
  keys("u")
  at = cells(120, 30)
  eq(at(1.5, 43).bg, bass_colour, "u brings them back, in one step")
  paw.opt.note_zoom = zoom
end)

test(
  "several clips are edited at once, new notes go to the active one, the cursor keeps its place in the song",
  function()
    local s = song()
    local roll = paw.ui.views:get("pianoroll")
    rc.open({ s.keys.id, s.bass.id }, s.keys.id)
    eq(rc.active() .. " " .. #rc.ids(), s.keys.id .. " 2", "keys active, two clips editable")
    eq(pitches(rc.context()), "72@0 76@4", "the bass is no longer context")
    eq(pitches(roll:ordered()), "36@2 40@4 43@3 60@0 64@1 67@2", "motions see the notes of both, in the roll's beats")
    keys("gg")
    eq(roll.pitch, 67, "gg: the highest of both")
    keys("G")
    eq(roll.pitch, 36, "G: the lowest of both")
    roll:set(nil, 0)
    keys("ww")
    eq(roll.pitch .. "@" .. roll.beat, "36@2", "w goes from note to note across the clips, the lowest of a chord first")
    keys("w")
    eq(roll.pitch .. "@" .. roll.beat, "43@3", "then the next bass note")
    keys("<CR>")
    eq(melody(s.bass), "36@0+1 40@2+1", "Enter on a bass note removes it from the bass clip")
    keys("u")
    roll:set(50, 0.5)
    keys("<CR>")
    eq(melody(s.keys):find("50@0.5", 1, true) ~= nil, true, "a new note goes into the active clip")
    roll:set(52, 6.5)
    keys("<CR>")
    eq(melody(s.keys):find("52@6.5", 1, true) ~= nil, true, "inside both, still into the active one")
    roll:set(nil, 3)
    rc.activate(s.bass.id)
    eq(
      rc.active() .. " " .. #rc.ids() .. " " .. roll.beat,
      s.bass.id .. " 2 1",
      "the bass active: the cursor is one beat into it"
    )
    keys("gn")
    eq(rc.active(), s.keys.id, "gn: the next clip edited is active")
    eq(roll.beat, 3, "and the cursor where it was")
    roll:set(72, 0)
    keys("gE")
    eq(#rc.ids() .. " " .. tostring(rc.editable(s.pad.id)), "3 true", "gE on a context note edits its clip too")
    keys("gE")
    eq(#rc.ids() .. " " .. tostring(rc.editable(s.pad.id)), "2 false", "and again no longer")
    keys("ga")
    eq(
      rc.active() .. " " .. #rc.ids(),
      s.pad.id .. " 2",
      "ga makes the clip of the note under the cursor active, in the old one's place"
    )
    eq(rc.editable(s.bass.id) and not rc.editable(s.keys.id), true, "the others stay")
    paw.ui.views:get("pianoroll"):edit(s.keys)
    eq(#rc.ids(), 1, "opening a clip edits it alone")
  end
)

test("operators, yank and paste act on every clip edited, each note staying in its own, one undo step each", function()
  local s = song()
  local roll = paw.ui.views:get("pianoroll")
  rc.open({ s.keys.id, s.bass.id }, s.keys.id)
  roll:set(60, 1)
  keys("v")
  roll:set(60, 3)
  keys("d")
  eq(
    melody(s.keys) .. " | " .. melody(s.bass),
    "60@0+1 | 43@1+1 40@2+1",
    "beats 1 to 3: E and G of the keys, the first bass note"
  )
  keys("u")
  eq(melody(s.keys) .. " | " .. melody(s.bass), "60@0+1 64@1+1 67@2+1 | 36@0+1 43@1+1 40@2+1", "one u brings both back")
  keys("0y$")
  local value = paw.keymap.getreg()
  eq(#value.notes, 6, "y$ yanks the notes of both")
  eq(value.notes[4].clip ~= nil, true, "each note says which clip it came from")
  roll:set(60, 0)
  keys("vjd")
  eq(melody(s.keys), "64@1+1 67@2+1", "a delete of the keys' first note")
  keys("P")
  eq(melody(s.keys) .. " | " .. melody(s.bass), "60@0+1 64@1+1 67@2+1 | 36@0+1 43@1+1 40@2+1", "pasting puts it back")
  keys("u")
  keys("u")
  roll:set(60, 0)
  keys("vG$>")
  eq(
    melody(s.keys) .. " | " .. melody(s.bass),
    "60@0.25+1 64@1.25+1 67@2.25+1 | 36@0.25+1 43@1.25+1 40@2.25+1",
    "> moves the notes of both"
  )
  keys("u")
  roll:set(60, 2)
  keys("v$<C-a>")
  eq(
    melody(s.keys) .. " | " .. melody(s.bass),
    "60@0+1 64@1+1 68@2+1 | 37@0+1 44@1+1 41@2+1",
    "<C-a> on a selection over both"
  )
  keys("u")
  keys("0yie")
  eq(#paw.keymap.getreg().notes, 6, "ie is every note of the clips edited")
  -- A note moved by a key stays in its clip: the bass's first note cannot go before the bass clip.
  roll:set(36, 2)
  keys("H")
  eq(melody(s.bass):sub(1, 6), "36@0+1", "H does not move a note out of its clip")
  roll:set(36, 2)
  keys("L")
  eq(melody(s.bass):sub(1, 9), "36@0.25+1", "L moves the bass note within the bass clip")
end)

test("the pointer chooses, drags and deletes notes in several clips as one step", function()
  local s = song()
  local act = paw.frontend.act
  rc.open({ s.keys.id, s.bass.id }, s.keys.id)
  eq(
    act.select_notes_box(s.keys.id, 2.5, 30, 3.5, 70),
    3,
    "a box over beats 2.5 to 3.5 takes the keys' G and two bass notes"
  )
  local refs = paw.frontend.chosen_refs()
  eq(#refs, 3, "chosen in both clips")
  eq(paw.frontend.chosen_text(s.keys.id):match("^3 notes in 2 clips") ~= nil, true, "said in words")
  -- Drag the keys' G one beat later and two semitones up: the bass notes follow.
  act.drag_notes(s.keys.id, 3, 1, 2)
  api.undo_checkpoint()
  eq(
    melody(s.keys) .. " | " .. melody(s.bass),
    "60@0+1 64@1+1 69@3+1 | 38@1+1 40@2+1 45@2+1",
    "both clips' notes moved, each in its own clip"
  )
  eq(#paw.frontend.chosen_refs(), 3, "and are still chosen")
  paw.undo()
  eq(
    melody(s.keys) .. " | " .. melody(s.bass),
    "60@0+1 64@1+1 67@2+1 | 36@0+1 43@1+1 40@2+1",
    "one undo puts both back"
  )
  act.select_notes_box(s.keys.id, 2.5, 30, 3.5, 70)
  act.drag_notes(s.keys.id, 3, -10, 0)
  eq(melody(s.bass):sub(1, 6), "36@0+1", "a drag stops where a note would leave its clip")
  act.select_notes_box(s.keys.id, 2.5, 30, 3.5, 70)
  eq(act.remove_chosen_notes(s.keys.id), true, "Delete takes the chosen notes")
  eq(melody(s.keys) .. " | " .. melody(s.bass), "60@0+1 64@1+1 | 40@2+1", "from both clips")
  paw.undo()
  act.select_note(s.bass.id, 1, "only")
  act.select_note(s.keys.id, 1, "add")
  eq(#paw.frontend.chosen_refs(), 2, "Shift and a click adds a note of another clip")
  act.set_velocity(s.keys.id, 1, 30)
  eq(s.bass:notes()[1].velocity .. " " .. s.keys:notes()[1].velocity, "30 30", "a velocity reaches the chosen of both")
  act.clear_note_selection()
  eq(#paw.frontend.chosen_refs(), 0, "let go of all")
  -- The window names a bass note by its own clip and place.
  act.drag_notes(s.bass.id, 2, 0, 1)
  eq(melody(s.bass), "36@0+1 44@1+1 40@2+1", "a note of another clip dragged alone")
end)

test("a click on a note behind the roll's own edits its clip, Ctrl and a click edits it too", function()
  local s = song()
  local act = paw.frontend.act
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(s.keys)
  local before = #s.keys:notes()
  act.add_note(s.keys.id, 43, 3.2, 0)
  eq(rc.active() .. " " .. #s.keys:notes(), s.bass.id .. " " .. before, "the bass clip is active, no note added")
  eq(#rc.ids(), 1, "in the keys' place")
  act.context_click(s.bass.id, -1.5, 72)
  eq(#rc.ids() .. " " .. tostring(rc.editable(s.pad.id)), "2 true", "Ctrl and a click: the pad is edited too")
  act.context_click(s.bass.id, -0.5, 64)
  eq(#rc.ids(), 3, "and the keys")
  act.roll_toggle_clip(s.bass.id, s.pad.id)
  eq(#rc.ids(), 2, "the side panel's toggle takes one out")
  act.roll_activate(s.bass.id, s.keys.id)
  eq(rc.active(), s.keys.id, "and makes one active")
  act.roll_show_part(s.keys.id, s.parts.pad.id)
  eq(pitches(rc.context()), "", "and hides a part's notes")
  act.roll_show_part(s.keys.id, s.parts.pad.id)
  eq(pitches(rc.context()), "72@0 76@4", "or shows them")
end)

test("several chosen clips open together: Enter on a selection, or a double click in the window", function()
  local s = song()
  local act = paw.frontend.act
  act.select_clip(s.keys.id, 0)
  act.select_clip(s.bass.id, 2, "toggle")
  eq(paw.keymap.mode, "x", "two chosen clips are a selection")
  keys("<CR>")
  eq(paw.ui.focused .. " " .. #rc.ids(), "pianoroll 2", "Enter opens both in the piano roll")
  paw.ui.focus("arrange")
  -- A double click: its first click chooses the clip alone.
  act.select_clip(s.keys.id, 0)
  act.select_clip(s.pad.id, 0, "toggle")
  act.select_clip(s.pad.id, 1)
  act.open_clip(s.pad.id)
  eq(rc.active() .. " " .. #rc.ids(), s.pad.id .. " 2", "a double click on one of them opens both, that one active")
  paw.ui.focus("arrange")
  act.select_clip(s.keys.id, 0)
  act.open_clip(s.keys.id)
  eq(#rc.ids(), 1, "on a clip alone, that clip alone")
end)

test(
  "a window is sent the notes of every clip edited as notes on the roll's plane, each in its own clip and colour",
  function()
    local s = song()
    rc.open({ s.keys.id, s.bass.id }, s.keys.id)
    paw.ui.show("pianoroll")
    local roll = paw.ui.views:get("pianoroll")
    roll.top, roll.scroll = 80, 0
    paw.frontend.act.select_notes_box(s.keys.id, 2.5, 30, 3.5, 70)
    api.scene_forget(0)
    api.scene_roles(0, { "note" })
    paw.ui.render_scene("pianoroll", 140, 90, { w = 8, h = 16 })
    local patch = api.json_decode(api.scene_end(0, "multipart"))
    api.scene_forget(0)
    local keys, bass, chosen = 0, nil, 0
    for _, n in ipairs(patch.set) do
      if n.role == "note" then
        if n.hit.clip == s.keys.id then keys = keys + 1 end
        if n.hit.clip == s.bass.id and n.hit.place == 1 then bass = n end
        if n.props.selected then chosen = chosen + 1 end
      end
    end
    eq(keys, 3, "the active clip's notes")
    eq(
      bass ~= nil and bass.r[1] .. " " .. bass.props.color,
      "2 " .. paw.draw.part_colour(api.part_get(s.parts.bass.id)),
      "a bass note in the keys' beats, in the bass's colour, named by its clip and place"
    )
    eq(chosen, 3, "the chosen notes of both")
    paw.ui.hide("pianoroll")
  end
)

test("the layers of the piano roll draw back to front, the same for both frontends", function()
  local s = song()
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(s.keys)
  local before = #roll.layers
  roll.layer("test-marks", 35, function(p) p.roll:text(0, 0, "over", "Bright") end)
  roll.layer("test-under", 5, function(p) p.roll:text(0, 0, "under", "Bright") end)
  local orders = {}
  for _, layer in ipairs(roll.layers) do
    if layer.name:match("^test") or layer.name == "context" or layer.name == "notes" then
      orders[#orders + 1] = layer.name
    end
  end
  eq(table.concat(orders, " "), "test-under context notes test-marks", "back to front")
  paw.ui.show("pianoroll")
  local text = table.concat(api.ui_snapshot(140, 40), "\n")
  eq(text:find("render failed", 1, true), nil, "the roll draws its layers")
  paw.ui.hide("pianoroll")
  roll.layer("test-marks", nil)
  roll.layer("test-under", nil)
  eq(#roll.layers, before, "and they can be taken away")
end)

test("musicops operators work on every clip the piano roll edits", function()
  local s = song()
  paw.ext.load("extensions/musicops")
  assert(paw.ext.loaded.musicops.ok, paw.ext.loaded.musicops.error)
  local roll = paw.ui.views:get("pianoroll")
  rc.open({ s.keys.id, s.bass.id }, s.keys.id)
  roll:set(60, 0)
  paw.ui.focus("pianoroll")
  keys("vG$gzt")
  eq(
    melody(s.keys) .. " | " .. melody(s.bass),
    "60@0+0.5 64@1+0.5 67@2+0.5 | 36@0+0.5 43@1+0.5 40@2+0.5",
    "staccato on both clips"
  )
end)
