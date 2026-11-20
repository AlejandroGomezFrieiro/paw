-- Singing tests.
local T = ...
local test, eq, near, fresh, render, tone, scratch, read_file = T.test, T.eq, T.near, T.fresh, T.render, T.tone, T.scratch, T.read_file
local channel_peaks, keys = T.channel_peaks, T.keys
local paw = require("paw")
local api = paw.api
local fixtures = "tests/fixtures/"

-- extensions/utau sings with paw-utau-engine; its own device and what it plays
-- are tested in its tests.lua. The tests that sing need the engine
-- (PAW_UTAU_ENGINE or paw-utau-engine on the PATH) and the voicebank below in
-- OpenUtau's folder, and are skipped without them.

local SINGER = os.getenv("PAW_UTAU_TEST_SINGER") or "Kitane sno act5 VCV"
local SYLLABLES = { "- あ", "- い", "- う", "- え", "- お" }

--- The pitch of the left channel of a 16-bit render between two times, by
--- autocorrelation: the shortest lag that correlates nearly as well as the best.
local function pitch(info, from, to)
  local data = read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local rate = info.sample_rate
  local x = {}
  local first = at + math.floor(from * rate) * 4
  for i = 0, math.floor((to - from) * rate) - 1 do
    local lo, hi = data:byte(first + i * 4, first + i * 4 + 1)
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    x[i + 1] = v / 32768
  end
  local min_lag, max_lag = math.floor(rate / 1000), math.floor(rate / 60)
  local w = math.min(#x - max_lag - 1, 4096)
  local r = {}
  local best = 0
  for lag = min_lag, max_lag do
    local s, e1, e2 = 0, 0, 0
    for i = 1, w do
      local a, b = x[i], x[i + lag]
      s, e1, e2 = s + a * b, e1 + a * a, e2 + b * b
    end
    r[lag] = s / math.sqrt(e1 * e2 + 1e-12)
    best = math.max(best, r[lag])
  end
  for lag = min_lag + 1, max_lag - 1 do
    if r[lag] >= 0.9 * best and r[lag] >= r[lag - 1] and r[lag] >= r[lag + 1] then return rate / lag end
  end
end

local function midi_hz(note) return 440 * 2 ^ ((note - 69) / 12) end

local utau

local function load_utau()
  if not utau then
    paw.ext.load("extensions/utau")
    utau = require("utau")
  end
  -- The vocal editor's own keys: musicops maps some of them again (`ip`,
  -- `(` `)`) when it loads after utau.
  if paw.ext.loaded.musicops then paw.ext.unload("musicops") end
  return utau
end

--- A vocal track with a clip of `pitches`, a beat each, sung on SYLLABLES.
local function vocal(pitches)
  local track = paw.add_track({ name = "Vocal" })
  track:add_device(load_utau().DEVICE)
  local list = {}
  for i, p in ipairs(pitches) do
    list[i] = { pitch = p, start = i - 1, length = 1, meta = { lyric = SYLLABLES[(i - 1) % #SYLLABLES + 1] } }
  end
  local clip = track:add_clip({ start = 0, length = #pitches + 1, notes = list })
  return track, clip
end

--- Skip unless the engine runs and has the test voicebank.
local function need_singer()
  load_utau()
  -- The voicebanks are read where PAW_UTAU_OPENUTAU_DIR says, never from
  -- a home folder the test did not name.
  if paw.opt.utau_openutau_dir == "" and not os.getenv("PAW_UTAU_OPENUTAU_DIR") then
    return "skipped: set PAW_UTAU_OPENUTAU_DIR to the OpenUtau folder with the test voicebank"
  end
  if not utau.engine.find() then return "skipped: paw-utau-engine not found (set PAW_UTAU_ENGINE)" end
  utau.engine.start()
  if not utau.wait(function() return #utau.singers > 0 end, 60) then
    return "skipped: paw-utau-engine did not start: " .. tostring(utau.engine.reason)
  end
  if not utau.find_singer(SINGER) or utau.find_singer(SINGER).id ~= SINGER then
    return "skipped: voicebank " .. SINGER .. " is not installed"
  end
end

test("vocal tracks keep lyrics, properties and curves through undo and saving", function()
  fresh()
  load_utau()
  local notes = require("utau.notes")
  local track, clip = vocal({ 60, 62, 64 })
  local other = vocal({ 60 })
  paw.flush()
  local device = utau.device_of(track.id)
  local voice = api.device_get(device).params.voice
  eq(voice >= 1, true, "the device gets a voice of its own")
  eq(api.device_get(utau.device_of(other.id)).params.voice ~= voice, true, "each device its own")
  other:remove()
  utau.configure(track.id, { singer = "Someone", phonemizer = "Some.Phonemizer" })
  eq(utau.config(track.id).phonemizer, "Some.Phonemizer", "config")
  utau.configure(track.id, { singer = "Someone else" })
  eq(utau.config(track.id).phonemizer, nil, "a new singer starts from its own defaults")
  api.undo_checkpoint()
  notes.set_lyric(clip.id, 2, "ら")
  api.undo_checkpoint()
  notes.change_props(clip.id, function(p) p.vb = { 75, 175, 25, 10, 10, 0, 0, 0 }; return true end, { [1] = true })
  notes.bend(track.id, device, "pitd", 1.5, 50, 0.25)
  api.undo_checkpoint()
  eq(clip:notes()[2].meta.lyric, "ら", "lyric")
  eq(clip:notes()[1].meta.utau.vb[2], 175, "vibrato")
  eq(notes.curve_at(track.id, device, "pitd", 1.5), 50, "pitch bend")
  eq(notes.curve_at(track.id, device, "pitd", 1), 0, "only where it was bent")
  -- The engine sees all of it.
  local snap = utau.snapshot()
  eq(#snap.parts, 1, "one part")
  eq(snap.parts[1].notes[2].payload:find("ら", 1, true) ~= nil, true, "the lyric is in the payload")
  eq(snap.parts[1].notes[1].payload:find("vb", 1, true) ~= nil, true, "and the vibrato")
  local pitd
  for _, c in ipairs(snap.parts[1].curves) do
    if c.abbr == "pitd" then pitd = c end
  end
  local peak = 0
  for _, k in ipairs(pitd.knots) do peak = math.max(peak, k[2]) end
  eq(peak, 50, "and the curve")
  paw.undo()
  eq(notes.lane(track.id, device, "pitd"), nil, "undo takes the curve away")
  eq(clip:notes()[1].meta and clip:notes()[1].meta.utau, nil, "and the vibrato")
  eq(clip:notes()[2].meta.lyric, "ら", "but not the lyric before them")
  paw.undo()
  eq(clip:notes()[2].meta.lyric, "- い", "and then the lyric")
  paw.redo()
  paw.redo()
  local path = paw.project.save(scratch .. "/vocal.json")
  fresh()
  paw.project.load(path)
  track = paw.tracks()[1]
  device = utau.device_of(track.id)
  clip = track:clips()[1]
  eq(clip:notes()[2].meta.lyric, "ら", "the lyric is loaded")
  eq(clip:notes()[1].meta.utau.vb[1], 75, "the vibrato is loaded")
  eq(utau.config(track.id).singer, "Someone else", "the singer is loaded")
  eq(notes.lane(track.id, device, "pitd") ~= nil, true, "the curve is loaded")
  eq(notes.curve_at(track.id, device, "pitd", 1.5), 50, "with its points")
end)

test("lyrics are typed note by note, from text, and by batch edits", function()
  fresh()
  load_utau()
  local editor = require("utau.editor").editor
  local track, clip = vocal({ 60, 62, 64, 65 })
  paw.cursor.set_track(track)
  paw.cursor.set_beat(0)
  paw.ui.focus("arrange")
  paw.keymap.feed("<CR>")
  eq(paw.ui.focused, "utau", "Enter on a vocal clip opens the vocal editor")
  eq(editor.clip_id, clip.id, "on that clip")
  paw.keymap.feed("cka<Tab>ki<Tab>ku<Esc>")
  local function lyrics()
    local out = {}
    for i, n in ipairs(clip:notes()) do out[i] = n.meta and n.meta.lyric or "" end
    return table.concat(out, " ")
  end
  eq(lyrics(), "ka ki - う - え", "typing replaces the lyric, Tab keeps it and moves on, Esc drops it")
  paw.cmd("utau.lyrics", { "ra ri" })
  eq(lyrics(), "ka ki ra ri", "words fill the notes from the cursor on")
  paw.cmd("utau.batch", { "romaji_to_hiragana" })
  eq(lyrics(), "か き ら り", "a batch edit")
  paw.cmd("utau.batch", { "replace", find = "り", replace = "る" })
  eq(lyrics(), "か き ら る", "find and replace")
  paw.cmd("utau.preset", { "vib_pop" })
  eq(clip:notes()[1].meta.utau.vb[2], 150, "a tuning preset sets vibrato")
  paw.cmd("utau.preset", { "raspy" })
  local notes = require("utau.notes")
  eq(notes.curve_at(track.id, utau.device_of(track.id), "tenc", 1.5), 40, "and curves")
  local sheet = require("utau.lyrics")
  local text = sheet.sheet(clip.id)
  eq(text, "か き ら る", "the lyric sheet reads one line per phrase")
  eq(#sheet.tokens("きょうは", true), 3, "kana per note keeps small kana with the one before")
  paw.ui.hide("utau")
  paw.ui.focus("arrange")
end)

test("the vocal editor takes operators, and notes keep their lyrics", function()
  fresh()
  load_utau()
  local editor = require("utau.editor").editor
  local track, clip = vocal({ 60, 62, 64 })
  paw.cursor.set_track(track)
  paw.cursor.set_beat(0)
  paw.ui.focus("arrange")
  paw.keymap.feed("<Esc><CR>")
  local function sung()
    local notes = clip:notes()
    table.sort(notes, function(a, b) return a.start < b.start end)
    for i, n in ipairs(notes) do notes[i] = string.format("%s:%d@%g", n.meta and n.meta.lyric or "?", n.pitch, n.start) end
    return table.concat(notes, " ")
  end
  local first = clip:notes()[1].meta.lyric
  local before = sung()
  paw.keymap.feed("yin$P")
  eq(sung(), before .. " " .. first .. ":60@4", "a yanked note is pasted with its lyric")
  eq(clip.length, 5, "and the clip grows to hold it")
  paw.keymap.feed("0wdw")
  eq(#clip:notes(), 3, "dw deletes a note")
  paw.keymap.feed("0vWy")
  eq(#paw.keymap.getreg().notes, 2, "a selection yanks the notes in a bar")
  local second = clip:notes()[2]
  paw.keymap.feed("0/" .. second.meta.lyric .. "<CR>")
  eq(editor.pitch .. "@" .. editor.beat, second.pitch .. "@" .. second.start, "/ finds a note by its lyric")
  paw.keymap.feed("<Esc>")
  eq(paw.ui.focused, "utau", "Escape stays in the vocal editor")
  paw.keymap.feed("<C-w>p")
  eq(paw.ui.focused, "arrange", "Ctrl-w p goes back to the arrange view")
  paw.ui.hide("utau")
end)

test("the vocal editor paints itself in a pane and is worked with the pointer", function()
  fresh()
  load_utau()
  local editor = require("utau.editor").editor
  local gui = require("utau.gui")
  local track, clip = vocal({ 60, 64 })
  -- Where a beat and a pitch are in the window (see utau/gui.lua).
  local function at(beat, pitch) return 64 + (beat - gui.scroll) * gui.zoom, 38 + 24 + (gui.top - pitch) * gui.row + gui.row / 2 end
  local function pointer(kind, beat, pitch, extra)
    local x, y = at(beat, pitch)
    paw.canvas.pointer("utau", paw.util.merge({ kind = kind, x = x, y = y, button = "left" }, extra or {}))
  end
  local function texts()
    local out = {}
    for _, op in ipairs(paw.canvas.paint("utau", 1100, 600).ops) do
      if op[1] == "t" then out[#out + 1] = op[4] end
    end
    return table.concat(out, "|")
  end

  paw.frontend.act.open_clip(clip.id)
  eq(#paw.frontend.state(-1).modal.windows, 0, "a double click on a vocal clip opens the vocal editor docked, in no window of its own")
  eq(paw.ui.visible("utau") and paw.ui.focused, "utau", "with the keyboard")
  eq(paw.ui.visible("pianoroll"), false, "and not the piano roll")
  local first = clip:notes()[1].meta.lyric
  eq(texts():find(first, 1, true) ~= nil, true, "the notes are painted with their lyrics")
  eq(texts():find("Notes", 1, true) ~= nil and texts():find("Pitch", 1, true) ~= nil, true, "with a toolbar")

  pointer("down", 2.1, 67)
  pointer("move", 2.9, 67)
  pointer("up", 2.9, 67)
  local notes = clip:notes()
  eq(#notes, 3, "a drag over empty space draws a note")
  eq(notes[3].pitch .. "@" .. notes[3].start .. "+" .. notes[3].length, "67@2+1", "on the grid, as long as the drag")

  pointer("down", 0.5, 60)
  pointer("move", 0.5, 62)
  pointer("up", 0.5, 62)
  local moved = clip:notes()[1]
  eq(moved.pitch .. "@" .. moved.start, "62@0", "a dragged note moves in time and pitch")
  eq(moved.meta.lyric, first, "and keeps its lyric")
  pointer("down", 1.97, 64)
  pointer("move", 1.45, 64)
  pointer("up", 1.45, 64)
  eq(clip:notes()[2].length, 0.5, "its right edge stretches it")

  pointer("double", 0.5, 62)
  eq(editor.entry ~= nil, true, "a double click starts typing the note's lyric")
  paw.keymap.feed("la<CR>")
  eq(clip:notes()[1].meta.lyric, "la", "which the keyboard finishes")

  -- The pitch tool, from its button in the toolbar.
  paw.canvas.paint("utau", 1100, 600)
  for _, b in ipairs(gui.buttons) do
    if b.label == "Pitch" then paw.canvas.pointer("utau", { kind = "down", x = b.x + 4, y = b.y + 4, button = "left" }) end
  end
  eq(gui.tool, "pitch", "a click on a toolbar button")
  pointer("down", 0.1, 62.3)
  pointer("move", 0.4, 62.6)
  pointer("move", 0.8, 62.2)
  pointer("up", 0.8, 62.2)
  local device = utau.device_of(track.id)
  local lane = require("utau.notes").lane(track.id, device, "pitd")
  eq(lane ~= nil and #api.lane_points(lane) >= 3, true, "the pitch tool draws how the pitch bends away from the note")
  pointer("down", 0.5, 62, { button = "right" })
  local flat = true
  for _, p in ipairs(api.lane_points(lane)) do
    if p[1] >= clip.start + 0.05 and p[1] <= clip.start + 0.95 and math.abs(p[2]) > 1 then flat = false end
  end
  eq(flat, true, "and a right click puts a note's pitch back")

  gui.tool = "notes"
  pointer("down", 2.5, 67, { button = "right" })
  eq(#clip:notes(), 2, "with the notes tool, a right click removes a note")
  local zoom = gui.zoom
  paw.canvas.pointer("utau", { kind = "wheel", x = 300, y = 300, dx = 0, dy = 60, ctrl = true })
  eq(gui.zoom > zoom, true, "the wheel with Ctrl zooms")
  paw.canvas.close("utau")
  eq(#paw.frontend.state(-1).modal.windows, 0, "closing the window")
  eq(paw.ui.focused, "arrange", "gives the keyboard back to the arrange view")
end)

test("the vocal editor shows notes, lyrics, phonemes, render state and the lyric sheet", function()
  fresh()
  load_utau()
  local editor = require("utau.editor").editor
  local track, clip = vocal({ 60, 64 })
  utau.configure(track.id, { singer = "Nobody" })
  editor:edit(clip.id)
  -- What the engine reports, as it would report it.
  utau.phonemes[clip.id] = { seq = 1, notes = { { { phoneme = "- あC4", alias = "", start = 0, stop = 480, flags = 0 } },
    { { phoneme = "xyz", alias = "", start = 480, stop = 960, flags = 1 } } } }
  utau.pitch[clip.id] = { step = 5, ticks = { [0] = 6000, [240] = 6000, [480] = 6390 } }
  paw.ui.show("utau_lyrics")
  local text = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(text:find("Vocal  Nobody", 1, true) ~= nil, true, "the header names the track and singer")
  eq(table.concat(paw.ui.keybar.check(), ", "), "", "the keys the bottom line shows for it are all mapped")
  eq(text:find("C4   - あ", 1, true) ~= nil, true, "notes show their lyric on their row")
  -- The keyboard names the Cs and the cursor's pitch; E4 is four rows above C4.
  local lines = api.ui_snapshot(120, 40)
  for i, line in ipairs(lines) do
    if line:find("C4   - あ", 1, true) then
      eq(lines[i - 4]:find("│       - い", 1, true) ~= nil, true, "the second note too, four keys up")
    end
  end
  eq(text:find("phon - あC4  xyz", 1, true) ~= nil, true, "the phonemes are under the notes")
  eq(text:find("─", 1, true) ~= nil, true, "the sung pitch is drawn")
  eq(text:find("- あ - い", 1, true) ~= nil, true, "the lyric sheet")
  eq(text:find("traceback", 1, true), nil, "no view raised an error")
  paw.ui.hide("utau_lyrics")
  paw.ui.hide("utau")
  paw.ui.focus("arrange")
  utau.phonemes[clip.id], utau.pitch[clip.id] = nil, nil
end)

-- The vocal editor's window, worked as the pointer works it: `win.at(beat,
-- pitch)` is where a beat and a pitch are, `win.press(kind, x, y, extra)`
-- passes an event at a place of the window.
local function vocal_window(pitches)
  fresh()
  load_utau()
  local editor = require("utau.editor").editor
  local gui = require("utau.gui")
  local track, clip = vocal(pitches)
  paw.flush()
  paw.frontend.act.open_clip(clip.id)
  -- Popped out into a window of its own, where Ctrl+V pastes.
  paw.canvas.open("utau", { window = true })
  gui.tool, gui.curves, gui.inspector = "notes", true, true
  local win = { editor = editor, gui = gui, track = track, clip = clip }
  function win.paint() return paw.canvas.paint("utau", 1180, 620) end
  function win.at(beat, pitch)
    return 64 + (beat - gui.scroll) * gui.zoom, 38 + 24 + (gui.top - pitch) * gui.row + gui.row / 2
  end
  function win.press(kind, x, y, extra)
    paw.canvas.pointer("utau", paw.util.merge({ kind = kind, x = x, y = y, button = "left" }, extra or {}))
  end
  function win.note(kind, beat, pitch, extra)
    local x, y = win.at(beat, pitch)
    win.press(kind, x, y, extra)
  end
  --- Drag from one place to another, in a few steps.
  function win.drag(x0, y0, x1, y1, extra)
    win.press("down", x0, y0, extra)
    for i = 1, 4 do win.press("move", x0 + (x1 - x0) * i / 4, y0 + (y1 - y0) * i / 4, extra) end
    win.press("up", x1, y1, extra)
  end
  function win.button(label)
    win.paint()
    for _, b in ipairs(gui.buttons) do
      if b.label:sub(1, #label) == label then return win.press("down", b.x + 4, b.y + 4) end
    end
    error("no button " .. label)
  end
  function win.close()
    if editor.entry then editor:close_entry() end
    paw.canvas.close("utau")
    paw.ui.hide("utau")
    paw.ui.focus("arrange")
  end
  return win
end

local function shape_of(clip)
  local out = {}
  for i, n in ipairs(clip:notes()) do
    out[i] = string.format("%s:%d@%g+%g", n.meta and n.meta.lyric or "?", n.pitch, n.start, n.length)
  end
  return table.concat(out, " ")
end

test("the vocal editor's window selects several notes, and moves, stretches, copies and deletes them", function()
  local win = vocal_window({ 60, 62, 64, 65 })
  local editor, clip = win.editor, win.clip
  local x0, y0 = win.at(0.2, 66)
  local x1, y1 = win.at(2.5, 61)
  win.drag(x0, y0, x1, y1, { ctrl = true })
  eq(#editor:selected(), 2, "a box drawn with Ctrl over empty space selects the notes in it")
  win.note("down", 0.5, 60, { shift = true })
  win.note("up", 0.5, 60, { shift = true })
  eq(table.concat(editor:selected(), ","), "1,2,3", "Shift+click adds a note")
  win.paint()
  eq(win.gui.S.selected[1] and win.gui.S.selected[3] and not win.gui.S.selected[4], true, "selected notes are painted as such")
  local xa, ya = win.at(1.5, 62)
  local xb, yb = win.at(1.5, 63)
  win.drag(xa, ya, xb, yb)
  eq(shape_of(clip), "- あ:61@0+1 - い:63@1+1 - う:65@2+1 - え:65@3+1", "dragging one moves them all, with their lyrics")
  local xe, ye = win.at(1.98, 63)
  local xf = win.at(1.48, 63)
  win.drag(xe, ye, xf, ye)
  eq(shape_of(clip), "- あ:61@0+0.5 - い:63@1+0.5 - う:65@2+0.5 - え:65@3+1", "its right edge stretches them all")
  paw.keymap.feed("<C-c>")
  editor.beat = 5
  paw.keymap.feed("<C-v>")
  eq(#clip:notes(), 7, "Ctrl+C copies them and Ctrl+V pastes them at the cursor")
  eq(shape_of(clip):find("- あ:61@5+0.5 - い:63@6+0.5 - う:65@7+0.5", 1, true) ~= nil, true, "keeping pitches, lyrics and spacing")
  eq(#editor:selected(), 3, "the pasted notes are selected")
  paw.keymap.feed("x")
  eq(#clip:notes(), 4, "x removes the selection")
  paw.canvas.key("utau", "<C-a>")
  eq(#editor:selected(), 4, "Ctrl+A in its window selects every note")
  paw.keymap.feed("<Esc>")
  eq(#editor:selected() .. paw.ui.focused, "0utau", "Escape forgets the selection first")
  -- Visual mode in the keys is the same selection.
  editor.pitch, editor.beat = 61, 0
  paw.keymap.feed("vW")
  eq(#editor:selected(), 4, "a visual selection selects the notes in it")
  win.paint()
  eq(win.gui.S.selected[1] == true, true, "and the window shows them selected")
  paw.keymap.feed("<Esc>")
  win.close()
end)

test("the vocal editor selects a phrase, from the window and with a text object", function()
  local win = vocal_window({ 60, 62, 64, 65, 67 })
  local editor, clip = win.editor, win.clip
  require("utau.notes").set_lyric(clip.id, 3, "R")
  win.note("double", 0.5, 70)
  eq(table.concat(editor:selected(), ","), "1,2", "a double click on empty space selects the phrase there")
  win.note("double", 3.5, 70)
  eq(table.concat(editor:selected(), ","), "4,5", "a rest ends a phrase")
  paw.keymap.feed("<Esc>")
  editor.pitch, editor.beat = 60, 0
  paw.keymap.feed("yip")
  eq(#paw.keymap.getreg().notes, 2, "`ip` is the phrase at the cursor")
  win.close()
end)

test("the vocal editor draws and erases expression curves under the notes", function()
  local win = vocal_window({ 60, 62, 64 })
  local editor, track, clip = win.editor, win.track, win.clip
  local notes = require("utau.notes")
  local device = utau.device_of(track.id)
  win.paint()
  eq(win.gui.S.curve.info.key, "pitd", "the panel starts on the pitch")
  win.button("Dynamics")
  win.paint()
  eq(editor.curve .. " " .. win.gui.S.curve.info.key, "dyn dyn", "a tab chooses the curve")
  local S = win.gui.S.curve
  local function y_for(v) return S.top + (1 - (v - S.info.min) / (S.info.max - S.info.min)) * S.h end
  local xa = win.at(0.2, 60)
  local xb = win.at(2.6, 60)
  win.drag(xa, y_for(60), xb, y_for(60))
  local lane = notes.lane(track.id, device, "dyn")
  eq(lane ~= nil, true, "drawing makes the curve's lane on the device's parameter")
  near(notes.curve_at(track.id, device, "dyn", 1.5), 60, 3, "with the value drawn")
  near(notes.curve_at(track.id, device, "dyn", 2.9), 0, 1e-6, "and only where it was drawn")
  local xc, xd = win.at(1, 60), win.at(2, 60)
  win.drag(xc, y_for(0), xd, y_for(0), { button = "right" })
  near(notes.curve_at(track.id, device, "dyn", 1.5), 0, 1e-6, "a right drag puts it back to its default")
  near(notes.curve_at(track.id, device, "dyn", 0.5), 60, 3, "there only")
  -- A frontend may pass a right drag on as its press and its release only.
  win.press("down", win.at(0.25, 60), y_for(0), { button = "right" })
  win.press("up", win.at(0.45, 60), y_for(0), { button = "right" })
  near(notes.curve_at(track.id, device, "dyn", 0.35), 0, 1e-6, "a right drag is erased from its press to its release")
  near(notes.curve_at(track.id, device, "dyn", 0.6), 60, 3, "and no further")
  eq(notes.curve_at(track.id, device, "pitd", 1.5), 0, "other curves are left alone")
  -- In the terminal: the chosen curve under the notes, raised at the cursor.
  paw.ui.focus("utau")
  editor.curve, editor.beat, editor.pitch = "pitd", 2, 64
  paw.keymap.feed("]c]c")
  eq(editor.curve, "tenc", "]c shows the next curve")
  paw.keymap.feed("3}")
  eq(notes.curve_at(track.id, device, "tenc", clip.start + 2), 15, "} raises it at the cursor")
  local text = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(text:find("tenc", 1, true) ~= nil and text:find("15", 1, true) ~= nil, true, "the terminal shows the curve and its value at the cursor")
  eq(text:find("[\240][\159][\172-\175]") ~= nil or text:find("[▌▐█]") ~= nil, true, "drawn in sextants under the notes")
  paw.keymap.feed("=")
  eq(notes.curve_at(track.id, device, "tenc", clip.start + 2), 0, "= puts it back under the note")
  win.close()
end)

test("the vocal editor edits transition points and vibrato with the pointer", function()
  local win = vocal_window({ 60, 64, 62 })
  local editor, clip, gui = win.editor, win.clip, win.gui
  local shapes = require("utau.shapes")
  gui.tool = "pitch"
  gui.zoom = 240
  win.paint()
  local function handle(list, fn)
    for _, h in ipairs(gui.S[list]) do
      if fn(h) then return 64 + h.x, 62 + h.y end
    end
  end
  -- The second note's transition: two points by default, the first at the note before.
  local hx, hy = handle("pp_handles", function(h) return h.index == 2 and h.k == 2 end)
  eq(hx ~= nil, true, "each note shows its transition points")
  win.drag(hx, hy, hx + 30, hy - 9)
  local pp = clip:notes()[2].meta.utau.pp
  eq(pp ~= nil and #pp.pts, 2, "dragging a point gives the note a transition of its own")
  eq(pp.pts[2][1] > 60 and pp.pts[2][2] > 0, true, "the point went later and up")
  win.note("double", 1.3, 64.5)
  eq(#clip:notes()[2].meta.utau.pp.pts, 3, "a double click on a note adds a point")
  local added
  for _, p in ipairs(clip:notes()[2].meta.utau.pp.pts) do
    if p[1] > 100 then added = p end
  end
  near(added and added[2] or 0, 5, 0.6, "where the pointer is: half a semitone up is 5 tenths")
  win.paint()
  hx, hy = handle("pp_handles", function(h) return h.index == 2 and h.k == 2 end)
  win.press("down", hx, hy, { ctrl = true })
  win.press("up", hx, hy, { ctrl = true })
  eq(clip:notes()[2].meta.utau.pp.pts[2][3], 1, "Ctrl+click changes how the line leaves a point")
  win.press("down", hx, hy, { button = "right" })
  eq(#clip:notes()[2].meta.utau.pp.pts, 2, "a right click removes a point")
  -- Drawn pitch is measured from the middle of the note's row.
  local x0, y0 = win.at(0.4, 61)
  local x1 = win.at(0.7, 61)
  win.drag(x0, y0, x1, y0)
  local notes_ = require("utau.notes")
  near(notes_.curve_at(win.track.id, utau.device_of(win.track.id), "pitd", 0.55), 100, 6, "a line drawn a row above a note bends it up a semitone")
  -- Vibrato: Ctrl+click switches it on, its handles change it.
  win.note("down", 2.5, 62, { ctrl = true })
  win.note("up", 2.5, 62, { ctrl = true })
  eq(shapes.vb(clip:notes()[3]) ~= nil, true, "Ctrl+click a note switches its vibrato on")
  win.paint()
  hx, hy = handle("vb_handles", function(h) return h.which == "depth" end)
  eq(hx ~= nil, true, "its handles show")
  win.drag(hx, hy, hx, hy - gui.row / 2)
  near(shapes.vb(clip:notes()[3])[3], 75, 1, "the depth handle sets the depth")
  win.paint()
  hx, hy = handle("vb_handles", function(h) return h.which == "length" end)
  win.drag(hx, hy, hx - gui.zoom * 0.25, hy)
  near(shapes.vb(clip:notes()[3])[1], 100, 0.5, "the start handle the length")
  win.paint()
  hx, hy = handle("vb_handles", function(h) return h.which == "period" end)
  local before = shapes.vb(clip:notes()[3])[2]
  win.drag(hx, hy, hx + 20, hy)
  eq(shapes.vb(clip:notes()[3])[2] > before, true, "the period handle the period")
  for _, which in ipairs({ "in", "out", "shift", "drift" }) do
    eq(handle("vb_handles", function(h) return h.which == which end) ~= nil, true, "and there is a handle for " .. which)
  end
  win.note("down", 2.5, 62, { ctrl = true })
  win.note("up", 2.5, 62, { ctrl = true })
  eq(shapes.vb(clip:notes()[3]), nil, "Ctrl+click again switches it off")
  win.close()
end)

test("the vocal editor moves and replaces phonemes, in the window and with keys", function()
  local win = vocal_window({ 60, 62 })
  local editor, clip, gui = win.editor, win.clip, win.gui
  utau.phonemes[clip.id] = { seq = 1, notes = {
    { { phoneme = "- あ", alias = "", start = 0, stop = 480, flags = 0 } },
    { { phoneme = "a", alias = "", start = 400, stop = 480, flags = 0 }, { phoneme = "い", alias = "", start = 480, stop = 960, flags = 1 } },
  } }
  win.paint()
  local box
  for _, b in ipairs(gui.S.phoneme_boxes) do
    if b.note == 2 and b.k == 2 then box = b end
  end
  local y = gui.geo.ph_y + 15
  win.drag(64 + box.x0, y, 64 + box.x0 + gui.zoom * 0.25, y)
  local ph = clip:notes()[2].meta.utau.ph
  eq(ph and ph[1].index .. ":" .. ph[1].offset, "1:120", "dragging a phoneme's start sets its offset, in ticks")
  win.press("double", 64 + box.x0 + 20, y)
  eq(editor.entry and editor.entry.kind, "phoneme", "a double click types the phoneme")
  paw.keymap.feed("<C-u>xi<CR>")
  eq(clip:notes()[2].meta.utau.ph[1].phoneme, "xi", "which is then sung instead")
  win.press("down", 64 + box.x0 + 20, y, { button = "right" })
  eq(clip:notes()[2].meta.utau, nil, "a right click puts it back")
  -- The keys: ( and ) choose a phoneme, [ and ] move it, gr types it.
  paw.ui.focus("utau")
  editor.pitch, editor.beat, editor.ph = 62, 1, nil
  paw.keymap.feed(")")
  paw.keymap.feed(")")
  eq(editor.ph.note .. ":" .. editor.ph.k, "2:2", ") goes on to the next phoneme")
  paw.keymap.feed("2])")
  eq(clip:notes()[2].meta.utau.ph[1].offset, 10, "] starts it later")
  paw.keymap.feed("grya<CR>")
  eq(clip:notes()[2].meta.utau.ph[1].phoneme, "ya", "gr types the phoneme to sing")
  local text = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(text:find("[a (!い)]", 1, true) ~= nil, true, "the chosen phoneme is marked in the terminal")
  paw.keymap.feed("gR")
  eq(clip:notes()[2].meta.utau, nil, "gR puts it back")
  paw.keymap.feed("(")
  eq(editor.ph.k, 1, "( goes back")
  utau.phonemes[clip.id] = nil
  win.close()
end)

test("the vocal editor's inspector sets properties of every selected note", function()
  local win = vocal_window({ 60, 62, 64 })
  local editor, clip, gui = win.editor, win.clip, win.gui
  utau.phonemizers = { { id = "OpenUtau.Plugin.Builtin.JapaneseVCVPhonemizer", name = "JA VCV", tag = "JA VCV" } }
  editor:select({ 1, 2 })
  win.paint()
  local function field(label)
    win.paint()
    for _, f in ipairs(gui.fields) do
      if f.field.label == label then return f.x + 10, f.y + 8 end
    end
    error("no field " .. label)
  end
  local fx, fy = field("Tuning")
  win.drag(fx, fy, fx + 20, fy)
  local n = clip:notes()
  eq((n[1].meta.utau or {}).tu .. " " .. (n[2].meta.utau or {}).tu, "20 20", "a value dragged goes to every selected note")
  eq(n[3].meta.utau, nil, "and no other")
  win.press("down", fx, fy)
  win.press("up", fx, fy)
  eq(editor.entry and editor.entry.kind, "field", "a click types the value")
  paw.keymap.feed("<C-u>-15<CR>")
  n = clip:notes()
  eq(n[1].meta.utau.tu .. " " .. n[2].meta.utau.tu, "-15 -15", "which goes to all of them")
  fx, fy = field("Vibrato")
  win.press("down", fx, fy)
  eq(require("utau.shapes").vb(clip:notes()[2]) ~= nil, true, "the vibrato switch")
  fx, fy = field("Depth")
  win.drag(fx, fy, fx + 10, fy)
  eq(clip:notes()[1].meta.utau.vb[3] .. " " .. clip:notes()[2].meta.utau.vb[3], "35 35", "and its numbers")
  fx, fy = field("Phonemizer")
  win.press("down", fx, fy)
  eq(gui.popup ~= nil, true, "the phonemizer opens a list")
  win.paint()
  win.press("down", gui.popup.left + 20, gui.popup.y + 6 + 20 + 5)
  eq(clip:notes()[1].meta.utau.po, "OpenUtau.Plugin.Builtin.JapaneseVCVPhonemizer", "a phonemizer for these notes")
  fx, fy = field("Velocity")
  win.drag(fx, fy, fx + 30, fy)
  local ex = clip:notes()[2].meta.utau.ex
  eq(ex and ex[1][1] .. "=" .. ex[1][2], "vel=130", "a per-note expression")
  fx, fy = field("Tuning")
  win.press("down", fx, fy, { button = "right" })
  eq(clip:notes()[1].meta.utau.tu, nil, "a right click puts a value back")
  fx, fy = field("Lyric")
  win.press("down", fx, fy)
  paw.keymap.feed("<C-u>")
  editor:entry_key("la li", true)
  paw.keymap.feed("<CR>")
  eq(clip:notes()[1].meta.lyric .. " " .. clip:notes()[2].meta.lyric, "la li", "several words go to the notes in order")
  -- The same from the command line.
  paw.cmd("utau.note", { tuning = "7", depth = "40" })
  eq(clip:notes()[1].meta.utau.tu .. " " .. clip:notes()[2].meta.utau.vb[3], "7 40", "`utau.note` sets them too")
  utau.phonemizers = {}
  win.close()
end)

test("the vocal editor plays notes as they are placed, follows the playhead, and plays from the cursor", function()
  local win = vocal_window({ 60, 62 })
  local editor, clip, gui = win.editor, win.clip, win.gui
  local audition = require("utau.audition")
  audition.last, audition.heard, audition.error = 0, {}, nil
  win.note("down", 2.1, 67)
  win.note("up", 2.1, 67)
  eq(#clip:notes(), 3, "a note placed")
  eq(audition.heard[#audition.heard], "tone", "is heard, as a tone without the engine")
  eq(audition.error, nil, "through the vocal device")
  clip.length = 64
  paw.keymap.feed("<Space>")
  eq(paw.transport.playing, true, "Space plays")
  near(paw.transport.position, clip.start + editor.beat, 1e-6, "from the cursor")
  paw.transport.seek(40)
  win.paint()
  eq(gui.scroll > 30, true, "the window follows the playhead")
  paw.keymap.feed("<Space>")
  eq(paw.transport.playing, false, "Space again stops")
  win.close()
end)

test("OpenUtau projects import as vocal tracks", function()
  fresh()
  load_utau()
  if not utau.engine.find() then return "skipped: paw-utau-engine not found (set PAW_UTAU_ENGINE)" end
  local ok, ids = pcall(require("utau.import").file, fixtures .. "vocal.ustx")
  eq(ok, true, "imported: " .. tostring(ids))
  local track = paw.track(ids[1])
  eq(track.name, "Imported vocal", "a vocal track per OpenUtau track")
  eq(utau.config(track.id).singer, "Kitane sno act5 VCV", "with its singer")
  eq(paw.project.tempo, 100, "the tempo")
  local clip = track:clips()[1]
  eq(clip.start .. "/" .. clip.length, "2/5", "a clip per part")
  local notes = clip:notes()
  eq(#notes, 3, "notes")
  eq(notes[2].meta.lyric .. "/" .. notes[2].start .. "/" .. notes[2].length .. "/" .. notes[2].pitch, "- い/1/2/64", "a note")
  eq(notes[1].meta.utau.tu, 15, "tuning")
  eq(notes[2].meta.utau.vb[1], 60, "vibrato")
  local n = require("utau.notes")
  eq(n.curve_at(track.id, utau.device_of(track.id), "dyn", 3), -60, "curves become lanes")
end)

test("a phrase with lyrics is sung at the notes' pitch, and offline renders wait for it", function()
  fresh()
  local why = need_singer()
  if why then return why end
  paw.project.tempo = 120
  local track, clip = vocal({ 57, 60, 64 })
  utau.configure(track.id, { singer = SINGER })
  -- Rendering waits until the singing is final, so no waiting here.
  local info = render({ bits = 16, tail = 0 })
  eq(utau.rendered(track.id), true, "the render waited for the engine")
  eq(channel_peaks(info, 0.1, 0.4) > 0.05, true, "the vocal is in the render")
  for i, note in ipairs({ 57, 60, 64 }) do
    local f = pitch(info, (i - 1) * 0.5 + 0.15, (i - 1) * 0.5 + 0.45)
    near(f or 0, midi_hz(note), midi_hz(note) * 0.03, "note " .. i .. " is sung at its pitch")
  end
  -- The same project renders the same audio.
  local again = render({ bits = 16, tail = 0 })
  eq(read_file(again.path) == read_file(info.path), true, "offline renders are deterministic")
  -- And it plays in real time.
  paw.transport.seek(0)
  paw.transport.play()
  local loudest, deadline = 0, api.now() + 3000
  while paw.transport.position < 1.5 and api.now() < deadline do
    loudest = math.max(loudest, track:meter())
    api.sleep(5)
  end
  paw.transport.stop()
  eq(loudest > 0.05, true, "heard while playing")
  require("utau.editor").editor:edit(clip.id)
  local text = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(text:find("ready", 1, true) ~= nil, true, "the editor says the track is rendered")
  eq(text:find("- あ", 1, true) ~= nil, true, "and shows phonemes from the voicebank")
  paw.ui.hide("utau")
  paw.ui.focus("arrange")
end)

test("changing a lyric or a note sings it again", function()
  fresh()
  local why = need_singer()
  if why then return why end
  paw.project.tempo = 120
  local track, clip = vocal({ 60, 60 })
  local device = utau.device_of(track.id)
  utau.configure(track.id, { singer = SINGER })
  local function hashes()
    eq(utau.finish(120), true, "the engine finished")
    local out = {}
    for _, p in ipairs(utau.voices.list(device)) do out[#out + 1] = p.hash end
    table.sort(out)
    return table.concat(out, " ")
  end
  local first = hashes()
  eq(first ~= "", true, "phrases are with the device")
  local notes = require("utau.notes")
  notes.set_lyric(clip.id, 2, "- お")
  paw.flush()
  local second = hashes()
  eq(second ~= first, true, "a new lyric is sung again")
  local list = clip:notes()
  list[2].pitch = 67
  clip:set_notes(list)
  paw.flush()
  eq(hashes() ~= second, true, "so is a new pitch")
  local info = render({ bits = 16, tail = 0 })
  near(pitch(info, 0.65, 0.95) or 0, midi_hz(67), midi_hz(67) * 0.03, "at the new pitch")
end)
