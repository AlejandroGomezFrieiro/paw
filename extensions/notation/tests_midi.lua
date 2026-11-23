-- Notation is a view of the clip's MIDI: tests of what is kept where, and
-- of what a notation edit writes. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation"), require("notation.model")
end

local keys = T.keys

--- A part with a clip open as notation.
local function song(notes, length)
  fresh()
  local view = load()
  local part = paw.add_part({ name = "Lead" })
  part:add_device("synth")
  local clip = part:add_clip({ start = 0, length = length or 4, name = "tune", notes = notes or {} })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  paw.ui.focus("notation")
  view.value, view.dot, view.voice, view.triplets = 1, false, 1, false
  api.undo_checkpoint()
  return view, clip, part
end

--- The clip's notes as "C4@0+1/80".
local function played(clip, with_velocity)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = string.format(
      "%s@%g+%g",
      paw.music.name(n.pitch),
      math.floor(n.start * 1e6 + 0.5) / 1e6,
      math.floor(n.length * 1e6 + 0.5) / 1e6
    ) .. (with_velocity and ("/" .. n.velocity) or "")
  end
  return table.concat(out, " ")
end

--- The written text of the open clip's staff and voice: "q C4 q D4 hr | R".
local function written(view, staff, voice) return require("notation.model").text(view:layout(), staff, voice) end

--- Every note of a clip by its id, as text: what a note is, all of it.
local function snapshot(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[n.id] =
      string.format("%d@%.9g+%.9g/%d %s", n.pitch, n.start, n.length, n.velocity, api.json_encode(n.meta or {}))
  end
  return out
end

--- The ids of the notes that differ between two snapshots (added, removed
--- or changed), in order.
local function changed(a, b)
  local out = {}
  for id, text in pairs(a) do
    if b[id] ~= text then out[#out + 1] = id end
  end
  for id in pairs(b) do
    if a[id] == nil then out[#out + 1] = id end
  end
  table.sort(out)
  return table.concat(out, " ")
end

--- The id of the clip's note on `pitch` starting at `start`.
local function id_at(clip, pitch, start)
  for _, n in ipairs(clip:notes()) do
    if n.pitch == paw.music.pitch(pitch) and math.abs(n.start - start) < 1e-6 then return n.id end
  end
end

--- How the note on `pitch` at `start` is written ("E#4"), from the layout.
local function spelled(view, clip, pitch, start)
  local model = require("notation.model")
  local id = id_at(clip, pitch, start)
  for _, ev in ipairs(model.events(view:layout())) do
    for _, n in ipairs(ev.notes or {}) do
      if not n.tied and n.index and clip:notes()[n.index].id == id then return model.name(n) end
    end
  end
end

-- The owner's question ---------------------------------------------------------------------------

test(
  "midi: written in notation, edited in the piano roll without notation, shown again; a notation edit writes only what it changes",
  function()
    local view, clip = song(nil, 8)
    keys("icdefgabc<Esc>")
    -- What notation decides: F spelled E sharp, a staccato C, p, a slur over bar 2.
    view:set(38, 3)
    keys("g~in")
    view:set(35, 0)
    keys("g'")
    paw.cmd("notation.dyn", { "p" })
    api.undo_checkpoint()
    paw.commands.exec("2notation.slur")
    api.undo_checkpoint()
    eq(
      played(clip, true),
      "C4@0+0.5/52 D4@1+1/52 E4@2+1/52 F4@3+1/52 G4@4+1/52 A4@5+1/52 B4@6+1/52 C5@7+1/52",
      "written as MIDI notes: the staccato half as long, the p as velocity"
    )
    local path, out = T.scratch .. "/written.paw", T.scratch .. "/rolled.paw"
    os.remove(out)
    api.project_save(path)
    -- A kernel of its own, without the notation extension, edits it in the
    -- piano roll as plain MIDI and saves it.
    local cmd = "PLAIN_IN='"
      .. path
      .. "' PLAIN_OUT='"
      .. out
      .. '\' exec "$(readlink /proc/$PPID/exe)" --clean --no-plugins --no-listen'
      .. " --audio null -l extensions/notation/fixtures/plain_roll.lua 2>&1"
    local said = io.popen(cmd):read("*a")
    eq(
      said:match("done%s*$") ~= nil and not said:find("wrong:", 1, true),
      true,
      "the piano roll's edits ran without notation:\n" .. said
    )
    api.project_load(out)
    paw.flush()
    clip = paw.parts()[1]:clips()[1]
    view:edit(clip)
    eq(
      played(clip, true),
      "C4@0+0.5/52 D4@1.25+1/52 F4@2+1/52 F4@3+1/100 A4@5+1/52 B4@6+1/52 G5@6+1/"
        .. paw.opt.velocity
        .. " F4@7+1/100 C5@7+1/52",
      "the roll's edits are the MIDI"
    )
    -- The score shows the MIDI, with what notation decided on the notes that are left.
    eq(spelled(view, clip, "F4", 3), "E#4", "the F kept its spelling")
    eq(spelled(view, clip, "F4", 7), "E#4", "and the copy took it along")
    eq(spelled(view, clip, "F4", 2), "F4", "the E raised in the roll is spelled as the key has it")
    eq(spelled(view, clip, "D4", 1.25), "D4", "the D moved later is written where it plays")
    eq(spelled(view, clip, "G5", 6), "G5", "the note drawn in the roll is written")
    eq(written(view):find("G4", 1, true), nil, "the G deleted in the roll is gone, its notation with it")
    local m1, m2 = view:layout().measures[1], view:layout().measures[2]
    eq(m1.marks[1] and m1.marks[1].kind .. " " .. m1.marks[1].value, "dyn p", "the dynamic keeps its beat")
    local slurred = false
    for _, ev in ipairs(m2.staves[1]) do
      slurred = slurred or ev.slurs ~= nil
    end
    eq(slurred, true, "and the slur its bar")
    -- Notation edits, each writing only what it changes.
    local before = snapshot(clip)
    view:set(41, 6)
    keys("<C-a>")
    eq(changed(before, snapshot(clip)), tostring(id_at(clip, "C5", 6)), "a note sharpened: that note and no other")
    eq(spelled(view, clip, "C5", 6), "B#4", "spelled as sharpened")
    before = snapshot(clip)
    view:set(nil, 4)
    paw.cmd("notation.dyn", { "f" })
    api.undo_checkpoint()
    local loud = {}
    for _, n in ipairs(clip:notes()) do
      if n.start >= 4 then loud[#loud + 1] = n.id end
    end
    table.sort(loud)
    eq(
      changed(before, snapshot(clip)),
      table.concat(loud, " "),
      "a dynamic: the velocities of the notes it reaches, no others"
    )
    eq(clip:notes()[#clip:notes()].velocity, 96, "f")
    -- The roll changes one of them; taking the f away leaves that one.
    local a4 = id_at(clip, "A4", 5)
    for i, n in ipairs(clip:notes()) do
      if n.id == a4 then clip:set_note(i, { velocity = 33 }) end
    end
    api.undo_checkpoint()
    before = snapshot(clip)
    view:set(nil, 4)
    paw.cmd("notation.dyn", { "off" })
    api.undo_checkpoint()
    local v = {}
    for _, n in ipairs(clip:notes()) do
      v[n.id] = n.velocity
    end
    eq(v[a4], 33, "the velocity the roll gave after the f is kept")
    eq(v[id_at(clip, "B#4", 6)] or v[id_at(clip, "C5", 6)], 52, "the others are as before the f: the p again")
    eq(v[id_at(clip, "F4", 7)], 100, "and the copy's own 100")
    eq(v[id_at(clip, "G5", 6)], paw.opt.velocity, "and the drawn note's")
    local early = {}
    for _, n in ipairs(clip:notes()) do
      if n.start < 4 then early[n.id] = true end
    end
    local touched = {}
    for id in changed(before, snapshot(clip)):gmatch("%d+") do
      if early[tonumber(id)] then touched[#touched + 1] = id end
    end
    eq(table.concat(touched, " "), "", "nothing before bar 2 is touched")
  end
)

-- What is kept, and where -----------------------------------------------------------------------

test(
  "midi: entered notes are MIDI notes at the written place and length, with what was decided; undo, save and load keep them",
  function()
    local view, clip = song(nil, 8)
    keys("icde<Esc>")
    eq(written(view), "q C4 q D4 q E4 qr | R", "written as entered")
    eq(played(clip), "C4@0+1 D4@1+1 E4@2+1", "each a MIDI note as long as its value")
    eq(clip:get().meta.score, nil, "the clip keeps no score")
    local own = clip:notes()[2].meta.notation
    eq(own.voice .. " " .. own.letter .. " " .. own.pitch, "1 1 62", "a note keeps its voice and spelling")
    eq(clip:get().meta.notation.version, 1, "and the clip the version of how it is kept")
    local xml_path = T.scratch .. "/midi-ids.musicxml"
    require("notation.files").export(xml_path, { clip })
    local f = io.open(xml_path)
    local xml = f:read("*a")
    f:close()
    eq(xml:find('<note id="n' .. clip:notes()[2].id .. '">', 1, true) ~= nil, true, "MusicXML carries each note's id")
    view:set(36, 1)
    keys("<C-a>")
    eq(written(view), "q C4 q D#4 q E4 qr | R", "sharpened")
    keys("u")
    eq(played(clip), "C4@0+1 D4@1+1 E4@2+1", "undo: one step")
    keys("u")
    eq(played(clip), "", "the notes entered in one go, one step")
    keys("<C-r><C-r>")
    local path = T.scratch .. "/midi-roundtrip.paw"
    api.project_save(path)
    api.project_load(path)
    paw.flush()
    local again = paw.parts()[1]:clips()[1]
    view:edit(again)
    eq(played(again), "C4@0+1 D#4@1+1 E4@2+1", "saved and loaded")
    eq(written(view), "q C4 q D#4 q E4 qr | R", "and written the same")
  end
)

test(
  "midi: what notation decided follows each note through roll moves, copies and undo, and goes with a deleted note",
  function()
    local view, clip = song(nil, 4)
    keys("icdef<Esc>")
    view:set(37, 2)
    keys("g~in")
    view:set(35, 0)
    keys("g>")
    eq(written(view), "q C4 q D4 q Fb4 q Fn4", "E spelled F flat")
    local fb = id_at(clip, "E4", 2)
    -- The roll moves the E, copies it, and deletes the C.
    for i, n in ipairs(clip:notes()) do
      if n.id == fb then clip:set_note(i, { start = 2.5, length = 0.5 }) end
    end
    api.undo_checkpoint()
    eq(written(view):find("Fb4", 1, true) ~= nil, true, "moved: still F flat " .. written(view))
    local e = clip:notes()[3]
    clip:add_note({ pitch = e.pitch, start = 3.5, length = 0.5, meta = e.meta })
    api.undo_checkpoint()
    eq(spelled(view, clip, "E4", 3.5), "Fb4", "copied with it")
    keys("u")
    eq(spelled(view, clip, "E4", 2.5), "Fb4", "undo: the copy goes, the spelling stays")
    local accent_before = view:layout().measures[1].staves[1][1].art
    eq(accent_before and accent_before.accent, true, "the C's accent")
    clip:remove_note(1)
    api.undo_checkpoint()
    eq(written(view):find("C4", 1, true), nil, "the C deleted")
    local any_accent = false
    for _, ev in ipairs(view:layout().measures[1].staves[1]) do
      any_accent = any_accent or (ev.art and ev.art.accent) or false
    end
    eq(any_accent, false, "and its accent with it")
    eq(spelled(view, clip, "E4", 2.5), "Fb4", "a roll edit loses no other note's spelling")
  end
)

-- Marks write MIDI -------------------------------------------------------------------------------

test(
  "midi: marks write MIDI when they are written; the roll's edits after are kept; taking one away puts back only untouched notes",
  function()
    local view, clip = song(nil, 8)
    keys("icdefgabc<Esc>")
    view:set(35, 0)
    paw.cmd("notation.dyn", { "p" })
    api.undo_checkpoint()
    view:set(nil, 4)
    paw.cmd("notation.dyn", { "f" })
    api.undo_checkpoint()
    local function vel()
      local v = {}
      for i, n in ipairs(clip:notes()) do
        v[i] = n.velocity
      end
      return table.concat(v, " ")
    end
    eq(vel(), "52 52 52 52 96 96 96 96", "p, then f from bar 2")
    paw.commands.exec("1notation.cresc")
    api.undo_checkpoint()
    local ramp = {}
    for i, n in ipairs(clip:notes()) do
      ramp[i] = n.velocity
    end
    eq(
      ramp[1] == 52 and ramp[2] > 52 and ramp[3] > ramp[2] and ramp[4] > ramp[3] and ramp[4] < 96,
      true,
      "a crescendo over bar 1 ramps to the f: " .. vel()
    )
    keys("u")
    eq(vel(), "52 52 52 52 96 96 96 96", "undone")
    -- Accents and staccatos.
    view:set(36, 1)
    keys("g>")
    eq(clip:notes()[2].velocity, 72, "an accent: 20 louder")
    keys("g'")
    eq(played(clip):match("D4@1%+[%d.]+"), "D4@1+0.5", "staccato: half as long")
    eq(
      written(view):match("q D4'") ~= nil or written(view):find("D4", 1, true) ~= nil,
      true,
      "still written a quarter: " .. written(view)
    )
    eq(written(view):sub(1, 9), "q C4 q D4", "a quarter, not an eighth and a rest")
    -- The roll lengthens the D: the staccato is a label now, the MIDI the roll's.
    clip:set_note(2, { length = 0.75 })
    api.undo_checkpoint()
    view:set(36, 1)
    keys("g'")
    eq(played(clip):match("D4@1%+[%d.]+"), "D4@1+0.75", "taking the staccato away leaves the roll's length")
    keys("g>")
    eq(clip:notes()[2].velocity, 52, "and the accent's 20 come off a velocity still as the accent left it")
    -- The roll's own velocity is not overwritten by taking a mark away.
    view:set(37, 2)
    keys("g>")
    clip:set_note(3, { velocity = 40 })
    api.undo_checkpoint()
    view:set(37, 2)
    keys("g>")
    eq(clip:notes()[3].velocity, 40, "an accent taken away from a note the roll changed since leaves it")
  end
)

-- Scores kept the old way -------------------------------------------------------------------------

test(
  "midi: a clip kept as a score the old way reads as its notes and marks, and the first edit keeps them as notation data",
  function()
    local view = load()
    local D = require("notation.doc")
    fresh()
    local part = paw.add_part({ name = "Old" })
    -- Notes as the old rendering left them: 90% of their values, each naming its written note.
    local notes = {}
    for i, p in ipairs({ 60, 62, 65, 65 }) do
      notes[i] =
        { pitch = p, start = i - 1, length = 0.9, velocity = 52, meta = { score = { e = "e" .. i, n = "n" .. i } } }
    end
    local clip = part:add_clip({ start = 0, length = 4, name = "old", notes = notes })
    -- Its score: the third note E sharp, voice 2 for the last, a p, a staccato on the D.
    local sc = D.new({ { start = 0, num = 4, den = 4 } }, { "treble" })
    local m = sc.measures[1]
    local function chord(id, step, alter, art)
      return {
        id = "e" .. id,
        kind = "chord",
        dur = { 1, 4 },
        dots = 0,
        art = art,
        notes = { { id = "n" .. id, step = step, alter = alter, octave = 4 } },
      }
    end
    m.voices = {
      {
        staff = "s1",
        voice = 1,
        events = {
          chord(1, 0, 0),
          chord(2, 1, 0, { staccato = true }),
          chord(3, 2, 1),
          { id = "r1", kind = "rest", dur = { 1, 4 }, dots = 0 },
        },
      },
      { staff = "s1", voice = 2, events = { { id = "r2", kind = "rest", dur = { 3, 4 }, dots = 0 }, chord(4, 3, 0) } },
    }
    sc.marks = { { id = "k1", kind = "dynamic", value = "p", from = { measure = m.id, at = { 0, 1 } } } }
    local stored = {
      version = 1,
      rev = "old",
      origin = { 0, 1 },
      staves = sc.staves,
      marks = sc.marks,
      next = 9,
      measures = { api.json_encode(m) },
    }
    clip.meta = { score = stored }
    paw.flush()
    paw.keymap.set_mode("n")
    view:edit(clip)
    api.undo_checkpoint()
    eq(written(view, 1, 1), "q C4 q D4' q E#4 qr", "read as the score said: E sharp, a staccato")
    eq(written(view, 1, 2), "hr qr q F4", "the second voice")
    eq(view:layout().measures[1].marks[1].value, "p", "the dynamic")
    eq(clip:get().meta.score ~= nil, true, "reading it writes nothing")
    view:set(35, 0)
    keys("<C-a>")
    eq(clip:get().meta.score, nil, "the first edit keeps it the new way")
    eq(clip:notes()[1].pitch, 61, "and is made")
    eq(written(view, 1, 1), "q C#4 q D4' q E#4 qr", "the rest written as it was")
    eq(written(view, 1, 2), "hr qr q F4", "voices too")
    eq(clip:notes()[3].meta.notation.letter, 2, "the spelling is on the note")
    eq(clip:notes()[2].meta.score, nil, "and the notes name no written note")
    eq(clip:get().meta.notation.marks[1].kind, "dynamic", "the dynamic is the clip's")
    keys("u")
    eq(clip:get().meta.score ~= nil, true, "one undo step takes the edit and the keeping back")
  end
)

-- The piano roll beside -------------------------------------------------------------------------------

test(
  "midi: the piano roll is a plain MIDI editor; with timebind the note under one window's cursor is outlined in the other",
  function()
    local view, clip = song(nil, 4)
    keys("icdef<Esc>")
    local roll = paw.ui.views:get("pianoroll")
    roll:edit(clip)
    local rollscore = require("notation.roll")
    local rows = {}
    for _, row in ipairs(api.ui_view_snapshot("pianoroll", 140, 40).rows) do
      local parts = {}
      for _, run in ipairs(row) do
        parts[#parts + 1] = run.text
      end
      rows[#rows + 1] = table.concat(parts)
    end
    local text = table.concat(rows, "\n")
    eq(text:find("notation", 1, true), nil, "the roll says nothing of notation")
    eq(rollscore.partner("pianoroll"), nil, "not bound: no outline")
    T.after(function()
      for _, win in ipairs(paw.layout.windows(paw.ui.layout)) do
        if win.view == "pianoroll" or win.view == "notation" then paw.layout.set_option(win, "timebind", false) end
      end
      paw.ui.hide("notation")
      paw.ui.hide("pianoroll")
    end)
    paw.ui.show("pianoroll")
    paw.ui.show("notation")
    for _, win in ipairs(paw.layout.windows(paw.ui.layout)) do
      if win.view == "pianoroll" or win.view == "notation" then paw.layout.set_option(win, "timebind", true) end
    end
    eq(rollscore.bound(clip.id), true, "bound")
    view:set(36, 1)
    eq(rollscore.partner("pianoroll"), clip:notes()[2].id, "the roll outlines the note under notation's cursor")
    local screen = ""
    for _, row in ipairs(paw.api.ui_view_snapshot("pianoroll", 120, 30).rows) do
      for _, run in ipairs(row) do
        screen = screen .. run.text
      end
      screen = screen .. "\n"
    end
    eq(screen:find(paw.opt.ascii and "[" or "⟦", 1, true) ~= nil, true, "drawn on the roll, for both frontends")
    roll:set(64, 2)
    eq(rollscore.partner("notation"), clip:notes()[3].id, "notation outlines the note under the roll's cursor")
    eq(rollscore.partner_place(), 3, "by its place among the clip's notes")
  end
)

-- Speed ------------------------------------------------------------------------------------------

test(
  "midi: a notation edit in a 64 bar clip costs at most half again the paint after a MIDI edit, and writes and lays out only the bars it changed",
  function()
    load()
    local bench = require("notation.bench")
    local opts = { glyphs = true, surface = true, cell = { w = 13, h = 27 } }
    -- A MIDI edit and a notation edit on one clip, one after the other, each
    -- round: a busy machine slows both alike, and the ratio is what is held.
    local r = bench.pair(64, opts, 9)
    eq(
      r.ratio <= 1.5,
      true,
      string.format(
        "notation edit and paint %.1f ms; MIDI edit's paint %.1f ms; ratio %.2f",
        r.notation,
        r.plain,
        r.ratio
      )
    )
    local view = song(nil, 64)
    keys("i")
    for _ = 1, 16 do
      keys("cdedcdec")
    end
    keys("<Esc>")
    view:layout()
    local L, midi = require("notation.layout"), require("notation.midi")
    local laid, written = L.stats.measures, midi.stats.measures
    view:set(36, 33)
    keys("<C-a>")
    view:layout()
    eq(
      midi.stats.measures - written <= 3,
      true,
      "a note sharpened in bar nine writes its bar again, and the ones beside it ("
        .. (midi.stats.measures - written)
        .. ")"
    )
    eq(L.stats.measures - laid <= 3, true, "and lays them out again (" .. (L.stats.measures - laid) .. ")")
  end
)

-- The score written measure by measure ------------------------------------------------------------

test(
  "midi: the score of a 64 bar clip written measure by measure is the score written whole, edit after edit",
  function()
    load()
    local midi = require("notation.midi")
    local seed = 5
    local function rnd(n)
      seed = (seed * 1103515245 + 12345) % 2147483648
      return seed % n
    end
    local function chance(k) return rnd(k) == 0 end
    -- 64 bars, 3/4 from bar 20 and 6/8 from bar 40 for four bars each.
    local bars, at = {}, 0
    for i = 1, 64 do
      local num, den = 4, 4
      if i >= 20 and i < 24 then num = 3 end
      if i >= 40 and i < 44 then
        num, den = 6, 8
      end
      bars[i] = { start = at, num = num, den = den, number = i }
      at = at + num * 4 / den
    end
    local length = at
    local notes, next_id = {}, 1
    local function add(n)
      n.id, n.velocity, next_id = next_id, 80, next_id + 1
      notes[#notes + 1] = n
    end
    -- Chords, notes held over barlines, triplets and quintuplets, notes played
    -- off the beat, grace notes, and held notes under the melody (a second
    -- voice, and a grand staff).
    for _, b in ipairs(bars) do
      local len, t = b.num * 4 / b.den, 0
      while t < len - 1e-9 do
        local d = ({ 0.25, 0.5, 0.5, 1, 1, 1.5, 2 })[rnd(7) + 1]
        if b.den == 4 and chance(8) and t + 1 <= len then
          local n = chance(2) and 3 or 5
          for k = 0, n - 1 do
            add({ pitch = 64 + rnd(12), start = b.start + t + k / n, length = 1 / n })
          end
          d = 1
        else
          local p = 62 + rnd(18)
          add({
            pitch = p,
            start = math.max(0, b.start + t + (chance(4) and (rnd(5) - 2) * 0.015 or 0)),
            length = math.min(d, len - t) + (chance(8) and (1 + rnd(3)) or 0),
          })
          if chance(4) then add({ pitch = p - 3 - rnd(4), start = b.start + t, length = math.min(d, len - t) }) end
          if chance(10) and t > 0 then add({ pitch = p + 2, start = b.start + t - 0.06, length = 0.04 }) end
        end
        t = t + d
      end
      if chance(3) then add({ pitch = 45 + rnd(10), start = b.start, length = len * (chance(2) and 1 or 0.75) }) end
    end
    -- What notation decides about some notes.
    local function decide(n)
      local own = ({
        { voice = 2 },
        { letter = n.pitch % 7, alter = 1, pitch = n.pitch },
        { art = { staccato = true } },
        { beam = "break" },
        { orn = "trill" },
        { staff = 1 },
        {},
      })[rnd(7) + 1]
      n.meta = next(own) and { notation = own } or nil
      if chance(12) then n.meta = { notation = own, lyric = "la" } end
    end
    for _, n in ipairs(notes) do
      if chance(6) then decide(n) end
    end
    local own = {
      tuplets = {
        { start = bars[10].start + 1, length = 1, n = 5, normal = 4 },
        { start = bars[12].start, length = 1, plain = true },
      },
      marks = { { kind = "dynamic", at = 4, value = "p" } },
    }
    local opts = { length = length, offset = 0, bars = bars, fifths = -1, tempo = 100, grid = 0.25 }
    local function score(memo)
      table.sort(
        notes,
        function(a, b)
          return a.start < b.start
            or (a.start == b.start and (a.pitch < b.pitch or (a.pitch == b.pitch and a.id < b.id)))
        end
      )
      midi.memo = memo
      local sc = midi.derive(notes, own, opts)
      midi.memo = true
      local out = {}
      for k, v in pairs(sc) do
        if k ~= "rev" and k ~= "_frame" and k ~= "_transcribed" then out[k] = v end
      end
      return midi.serial(out)
    end
    eq(score(true) == score(false), true, "as written")
    local written, edits = midi.stats.measures, 0
    for round = 1, 60 do
      local k = rnd(#notes) + 1
      local n = notes[k]
      local what = ({ "pitch", "move", "nudge", "length", "delete", "add", "decide", "tuplet", "held" })[rnd(9) + 1]
      if what == "pitch" then
        n.pitch = n.pitch + (chance(2) and 1 or -1)
      elseif what == "move" then
        n.start = math.max(0, n.start + (chance(2) and 0.25 or -0.25))
      elseif what == "nudge" then
        n.start = math.max(0, n.start + (rnd(3) - 1) * 0.02)
      elseif what == "length" then
        n.length = math.max(0.1, n.length + (chance(2) and 0.5 or -0.5))
      elseif what == "delete" then
        table.remove(notes, k)
      elseif what == "add" then
        add({ pitch = 60 + rnd(20), start = rnd(math.floor(length * 4)) / 4, length = 0.25 * (1 + rnd(8)) })
      elseif what == "decide" then
        decide(n)
      elseif what == "tuplet" then
        own.tuplets[#own.tuplets + 1] =
          { start = bars[rnd(64) + 1].start + rnd(3), length = 1, n = ({ 3, 5, 6, 7 })[rnd(4) + 1] }
      else
        add({ pitch = 40 + rnd(10), start = rnd(math.floor(length)), length = 2 + rnd(6) })
      end
      -- Two notes of one pitch at one time are one.
      for i = #notes, 2, -1 do
        local a, b = notes[i], notes[i - 1]
        if a.pitch == b.pitch and math.abs(a.start - b.start) < 1e-6 then table.remove(notes, i) end
      end
      local memo = score(true)
      edits = edits + 1
      eq(memo == score(false), true, "after edit " .. round .. " (" .. what .. ")")
    end
    local per = (midi.stats.measures - written) / edits
    eq(per < 4, true, string.format("each edit wrote %.1f of 64 measures again", per))
  end
)
