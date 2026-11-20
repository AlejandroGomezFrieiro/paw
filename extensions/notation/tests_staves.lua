-- Tests of the score as lines to edit (`notation.staves`): moving between
-- staves, every edit going to the staff under the cursor as an ordinary
-- MIDI edit of its clip, selections and operators over several staves in
-- one undo step, Ex over staves, scores of a group or a selection, and
-- the pages to check, read only. Driven with real keys. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api
local keymap = paw.keymap

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation")
end

local function ok(cond, what) eq(cond and true or false, true, what) end

local function N(pitch, start, length) return { pitch = pitch, start = start, length = length or 1, velocity = 80 } end

--- Four quarters a bar from `pitch` up the C major scale, for `bars` bars.
local function line(pitch, bars)
  local out, scale = {}, { 0, 2, 4, 5 }
  for b = 0, bars - 1 do
    for k = 0, 3 do out[#out + 1] = N(pitch + scale[k + 1], b * 4 + k, 1) end
  end
  return out
end

local keys = T.keys

--- A score of four instruments in three groups: flutes and a clarinet
--- (Woodwinds), a piano on a grand staff, a cello (Strings). Opened on the
--- first flute, the full score shown.
local function quartet()
  fresh()
  local view = load()
  local tracks, clips = {}, {}
  local specs = {
    { "Flute 1", line(72, 4) }, { "Flute 2", line(67, 4) }, { "Clarinet", line(60, 4) },
    { "Piano", (function()
      local notes = line(72, 4)
      for _, n in ipairs(line(48, 4)) do notes[#notes + 1] = n end
      return notes
    end)() },
    { "Violoncello", line(48, 4) },
  }
  for _, spec in ipairs(specs) do
    local t = paw.add_track({ name = spec[1] })
    t:add_device("synth")
    tracks[spec[1]] = t
    clips[spec[1]] = t:add_clip({ start = 0, length = 16, name = spec[1], notes = spec[2] })
  end
  paw.groups.make({ tracks["Flute 1"], tracks["Flute 2"], tracks["Clarinet"] }, "Woodwinds")
  paw.groups.make({ tracks["Violoncello"] }, "Strings")
  paw.flush()
  api.undo_checkpoint()
  keymap.set_mode("n")
  view:edit(clips["Flute 1"])
  view.value, view.dot = 1, false
  paw.commands.exec("score all")
  api.undo_checkpoint()
  return view, clips, tracks
end

--- The track of the staff under the cursor.
local function active(view) return api.track_get(view:clip():get().track).name end

local function names(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do out[#out + 1] = paw.music.name(n.pitch) .. "@" .. n.start end
  return table.concat(out, " ")
end

local function count(clip) return #clip:notes() end

test("a score's staves are lines: Ctrl-j Ctrl-k, ]] [[, ]s [s, [{ ]} move the cursor between them, with counts", function()
  local view = quartet()
  local F = view:frame()
  eq(#F.layout.staves, 6, "flutes, clarinet, the piano's two, the cello")
  eq(active(view), "Flute 1", "the open clip's staff is the active one")
  keys("<C-j>")
  eq(active(view), "Flute 2", "Ctrl-j: the staff below")
  keys("2<C-j>")
  eq(active(view) .. " " .. view:frame().base, "Piano 3", "a count: two staves on, the piano's upper staff")
  keys("<C-j>")
  eq(active(view) .. " " .. view:cursor_staff(), "Piano 2", "a grand staff's two are two staves: its lower one")
  keys("<C-k><C-k>")
  eq(active(view), "Clarinet", "Ctrl-k up into the instrument above")
  keys("]]")
  eq(active(view), "Piano", "]]: the next instrument")
  keys("]]")
  eq(active(view), "Violoncello", "a grand staff is one instrument")
  keys("3[[")
  eq(active(view), "Flute 2", "[[ with a count")
  keys("]s")
  eq(active(view), "Clarinet", "]s: the next in the group")
  keys("]s")
  eq(active(view), "Clarinet", "and not out of it")
  keys("[{")
  eq(active(view), "Flute 1", "[{: the group's first")
  keys("]}")
  eq(active(view), "Clarinet", "]}: its last")
  keys("]}")
  eq(active(view), "Piano", "again: the last of the group after")
  local text = table.concat(api.ui_snapshot(140, 60), "\n")
  ok(text:find("Piano", 1, true) and text:find("the full score, staff 4 of 6", 1, true), "the title names the active track and its staff")
  ok(text:find("▶", 1, true), "a mark at the active staff's start")
end)

test("every edit in a score goes to the staff under the cursor, as an ordinary MIDI edit of its clip", function()
  local view, clips = quartet()
  local before = {}
  for name, clip in pairs(clips) do before[name] = names(clip) end
  keys("2]]")
  eq(active(view), "Clarinet", "on the clarinet")
  view:set(nil, 0)
  keys("x")
  eq(count(clips["Clarinet"]), 15, "x deleted one of the clarinet's notes")
  for _, name in ipairs({ "Flute 1", "Flute 2", "Piano", "Violoncello" }) do
    eq(names(clips[name]), before[name], name .. " is untouched")
  end
  keys("u")
  eq(names(clips["Clarinet"]), before["Clarinet"], "one undo puts it back")
  -- Entering notes by letter on the cello's staff.
  keys("]]]]")
  eq(active(view), "Violoncello", "on the cello, past the piano")
  view:set(nil, 12)
  keys("icdef<Esc>")
  local found = {}
  for _, n in ipairs(clips["Violoncello"]:notes()) do
    if n.start >= 12 then found[#found + 1] = paw.music.name(n.pitch) end
  end
  eq(table.concat(found, " "), "C3 D3 E3 F3", "the letters wrote the cello's MIDI, in its octave")
  eq(names(clips["Flute 1"]), before["Flute 1"], "the flute's clip is untouched")
  -- A popover on the active staff.
  keys("[[")
  view:set(nil, 0)
  paw.commands.exec("notation.dyn f")
  api.undo_checkpoint()
  local marks = (clips["Piano"]:get().meta.notation or {}).marks or {}
  eq(#marks, 1, "the dynamic is kept with the piano's clip")
  eq(((clips["Violoncello"]:get().meta.notation or {}).marks or {})[1], nil, "and not the cello's")
end)

test("a block over staves (Ctrl-v, Ctrl-j) deletes, moves and transposes on each staff's clip, one undo step", function()
  local view, clips = quartet()
  local before = {}
  for name, clip in pairs(clips) do before[name] = names(clip) end
  view:set(nil, 0)
  -- Bar 1 of the two flutes and the clarinet.
  keys("<C-v><C-j><C-j>3l")
  local sel = keymap.selection()
  ok(sel and sel.kind == "block", "a block")
  keys("x")
  eq(count(clips["Flute 1"]) .. " " .. count(clips["Flute 2"]) .. " " .. count(clips["Clarinet"]), "12 12 12", "bar 1 gone from each")
  eq(names(clips["Piano"]), before["Piano"], "the piano is outside the block")
  keys("u")
  for _, name in ipairs({ "Flute 1", "Flute 2", "Clarinet" }) do eq(names(clips[name]), before[name], name .. ": one undo for the three") end
  -- V over staves takes them whole.
  keys("gg")
  view:set(nil, 0)
  keys("V2]]d")
  eq(count(clips["Flute 1"]) + count(clips["Flute 2"]) + count(clips["Clarinet"]), 0, "V and 2]]: the woodwinds' staves whole")
  keys("u")
  eq(names(clips["Clarinet"]), before["Clarinet"], "undone in one step")
  -- An operator on a block: up a step of the key on both flutes.
  view:activate(clips["Flute 1"].id)
  view:set(nil, 0)
  keys("<C-v><C-j>3lgU")
  eq(names(clips["Flute 1"]):sub(1, 7), "D5@0 E5", "the first flute a step up")
  eq(names(clips["Flute 2"]):sub(1, 7), "A4@0 B4", "the second too")
  eq(names(clips["Clarinet"]), before["Clarinet"], "the clarinet is outside it")
end)

test("a passage yanked from one staff pastes into another instrument's", function()
  local view, clips = quartet()
  view:set(nil, 4)
  keys("yib")
  keys("4]]")
  eq(active(view), "Violoncello", "on the cello")
  view:set(nil, 8)
  keys("P")
  local found = {}
  for _, n in ipairs(clips["Violoncello"]:notes()) do
    if n.start >= 8 and n.start < 12 then found[#found + 1] = paw.music.name(n.pitch) end
  end
  eq(table.concat(found, " "), "C5 D5 E5 F5", "the flute's bar in the cello's clip")
  eq(count(clips["Flute 1"]), 16, "and still in the flute's")
end)

test("Ex in a score: staves by number, by group, before or after the bars", function()
  local view, clips = quartet()
  local before = {}
  for name, clip in pairs(clips) do before[name] = names(clip) end
  paw.commands.exec("2 s3 d")
  api.undo_checkpoint()
  eq(count(clips["Clarinet"]), 12, ":2 s3 d deletes bar 2 of the third staff")
  eq(names(clips["Flute 1"]), before["Flute 1"], "and nothing else")
  keys("u")
  paw.commands.exec("s1,s2 1 d")
  api.undo_checkpoint()
  eq(count(clips["Flute 1"]) .. " " .. count(clips["Flute 2"]) .. " " .. count(clips["Clarinet"]), "12 12 16", "staves first, then bars")
  keys("u")
  paw.commands.exec("1 Woodwinds notation.transpose 12")
  api.undo_checkpoint()
  eq(names(clips["Clarinet"]):sub(1, 6), "C5@0 D", "a group by name: the clarinet an octave up")
  eq(names(clips["Flute 2"]):sub(1, 6), "G5@0 A", "and the flutes")
  eq(names(clips["Violoncello"]), before["Violoncello"], "the strings are not woodwinds")
  keys("u")
  eq(names(clips["Flute 1"]), before["Flute 1"], "one undo for the group")
  paw.commands.exec("s1,s2 g/c5/d")
  api.undo_checkpoint()
  eq(count(clips["Flute 1"]) .. " " .. count(clips["Flute 2"]) .. " " .. count(clips["Clarinet"]), "12 12 16", ":s1,s2 g/c5/d: the C5s of the two flutes")
  keys("u")
  paw.commands.exec("5 s3 d")
  api.undo_checkpoint()
  eq(count(clips["Clarinet"]), 16, "a bar past the clip's end holds nothing")
end)

test(":score shows a group's score, or the arrange view's selected tracks; a click on a staff makes it active", function()
  local view, clips, tracks = quartet()
  paw.commands.exec("score Strings")
  eq(#view:frame().layout.staves, 1, "the strings' score: the cello alone")
  eq(active(view), "Violoncello", "and its staff active")
  paw.commands.exec("score all")
  -- The tracks of a selection in the arrange view.
  paw.ui.focus("arrange")
  paw.cursor.set_track(tracks["Clarinet"])
  keys("V")
  paw.cursor.set_track(tracks["Piano"])
  paw.commands.exec("score selection")
  keymap.set_mode("n")
  eq(#view:frame().layout.units, 2, "the clarinet and the piano")
  paw.commands.exec("score all")
  -- A click on another staff in the terminal.
  view:activate(clips["Flute 1"].id)
  api.ui_snapshot(140, 60)
  local g = view.geometry
  local sys = g.systems[1]
  local placed = sys.measures[2]
  local y = sys.rows[6].above(4)
  view:on_mouse({ kind = "down", button = "left", x = placed.x + 2, y = y })
  eq(active(view), "Violoncello", "a click on the cello's staff")
end)

test("the pages to check before export are read only, and say so", function()
  local view, clips = quartet()
  paw.commands.exec("score.check")
  api.undo_checkpoint()
  view:set(nil, 0)
  keys("x")
  eq(count(clips["Flute 1"]), 16, "x deletes nothing")
  ok((paw.ui.message and paw.ui.message.text or ""):find("to check before export", 1, true), "and says why")
  keys("zp")
  keys("x")
  eq(count(clips["Flute 1"]), 15, "zp back to editing")
end)

for _, case in ipairs({
  -- The key, and what `c` `d` `e` `f` typed in the part sound. A letter
  -- is the written key's (in D major for a part in B flat, `c` is C
  -- sharp), and the MIDI sounds that far below.
  { "Bb", "B3 C4 D4 E4" },
  { "A", "A3 B3 C4 D4" },
  { "F", "F3 G3 A3 B3" },
  { "Eb", "E3 F3 G3 A3" },

}) do
  local key, sounds = case[1], case[2]
  test("a part in " .. key .. " is edited as written: the letters typed are written so, and its MIDI sounds at concert pitch", function()
    local view, clips = quartet()
    local clip = clips["Clarinet"]
    view:activate(clip.id)
    paw.commands.exec("part.transpose " .. key)
    paw.commands.exec("part Clarinet")
    api.undo_checkpoint()
    eq(active(view), "Clarinet", "the part's track is the one edited")
    -- Bar 3 emptied, then the letters typed there from the part's C4.
    paw.commands.exec("3 s. d")
    api.undo_checkpoint()
    eq(#clip:notes(), 12, "bar 3 emptied")
    view:set(35 - view:frame().dstep, 8)
    keys("icdef<Esc>")
    local found = {}
    for _, n in ipairs(clip:notes()) do
      if n.start >= 8 and n.start < 12 then found[#found + 1] = paw.music.name(n.pitch) end
    end
    eq(table.concat(found, " "), sounds, "the clip's MIDI at concert pitch")
    local model = require("notation.model")
    local written = {}
    for _, m in ipairs(view:frame().layout.measures) do
      if m.number == 3 then
        -- On whichever staff: a low part may be on a grand staff.
        for _, evs in ipairs(m.staves) do
          for _, ev in ipairs(evs) do
            for _, n in ipairs(ev.notes or {}) do written[#written + 1] = model.name(n):sub(1, 1) end
          end
        end
      end
    end
    eq(table.concat(written, " "), "C D E F", "written in the part as typed")
    keys("u")
    eq(#clip:notes(), 12, "one undo takes the letters back")
    paw.commands.exec("part.transpose off")
  end)
end

test("a condensed staff: voice 2 is the second player, an edit where they play a2 is made for both, :score.split parts them", function()
  local view, clips = quartet()
  -- The flutes play the same in bar 4.
  local f2 = clips["Flute 2"]
  local notes = {}
  for _, n in ipairs(f2:notes()) do
    if n.start < 12 then notes[#notes + 1] = { pitch = n.pitch, start = n.start, length = n.length, velocity = 80 } end
  end
  for _, n in ipairs(line(72, 4)) do
    if n.start >= 12 then notes[#notes + 1] = n end
  end
  f2:set_notes(notes)
  api.undo_checkpoint()
  paw.commands.exec("part.condense on")
  api.undo_checkpoint()
  local F = view:frame()
  eq(#F.layout.staves, 5, "the flutes share a staff")
  eq(F.layout.units[1].condensed[4], "a2", "bar 4 is a2")
  eq(active(view), "Flute 1", "voice 1 is the first flute")
  keys("]v")
  eq(active(view), "Flute 2", "]v: voice 2, the second flute")
  keys("[v")
  eq(active(view), "Flute 1", "and back")
  view:set(42, 12)
  keys("x")
  eq(count(clips["Flute 1"]) .. " " .. count(clips["Flute 2"]), "15 15", "x in an a2 bar: the note gone from both players")
  keys("u")
  eq(count(clips["Flute 1"]) .. " " .. count(clips["Flute 2"]), "16 16", "one undo for both")
  view:set(42, 12)
  paw.commands.exec("score.split")
  api.undo_checkpoint()
  eq(view:frame().layout.units[1].condensed[4], "div.", "split: two voices, though the same")
  view:set(42, 12)
  keys("x")
  eq(count(clips["Flute 1"]) .. " " .. count(clips["Flute 2"]), "15 16", "an edit there is the first player's alone")
  paw.commands.exec("part.condense off")
end)

test(":help notation-scores finds the score's section, and :help :score the command", function()
  load()
  local tag = paw.help.lookup("notation-scores")
  eq(tag and (tag.source.name .. " " .. tag.name), "notation/doc/reference.md notation-scores", "the reference's section")
  eq(paw.help.lookup(":score") ~= nil, true, "the command")
end)

test("a staff is every clip of its track: pasted clips in a row, a gap as rests, the cursor and edits going to the clip there", function()
  fresh()
  local view = load()
  local violin = paw.add_track({ name = "Violin" })
  violin:add_device("synth")
  -- Four one-bar clips, as pasted in the arrange view, the fourth after a bar of nothing.
  local clips = {}
  for i, at in ipairs({ 0, 4, 8, 16 }) do
    clips[i] = violin:add_clip({ start = at, length = 4, name = "v" .. i, notes = line(72 + 2 * (i - 1), 1) })
  end
  local cello = paw.add_track({ name = "Violoncello" })
  cello:add_clip({ start = 0, length = 20, name = "vc", notes = line(48, 5) })
  paw.flush()
  api.undo_checkpoint()
  keymap.set_mode("n")
  view:edit(clips[1])
  paw.commands.exec("score all")
  api.undo_checkpoint()
  local F = view:frame()
  eq(#F.layout.units[1].clips, 4, "the violin's staff shows its four clips")
  local model = require("notation.model")
  local function bar(i)
    local out = {}
    for _, ev in ipairs(F.layout.measures[i].staves[1]) do
      for _, n in ipairs(ev.notes or {}) do out[#out + 1] = model.name(n) end
    end
    return table.concat(out, " ")
  end
  eq(bar(1), "C5 D5 E5 F5", "bar 1 from the first clip")
  eq(bar(3), "E5 F#5 G#5 A5", "bar 3 from the third")
  eq(bar(4), "", "bar 4, where no clip plays, rests")
  eq(bar(5), "F#5 G#5 Bb5 B5", "bar 5 from the fourth")
  -- The cursor goes on from clip to clip.
  view:set(nil, 3)
  keys("l")
  eq(view.clip_id, clips[2].id, "l past the first clip's end: into the second")
  keys("k")
  keys("x")
  eq(#clips[2]:notes() .. " " .. #clips[1]:notes(), "3 4", "x there deletes in the second clip")
  keys("u")
  keys("W")
  eq(view.clip_id, clips[3].id, "W into the third")
  keys("B")
  eq(view.clip_id, clips[2].id, "B back into the second")
  -- In the gap: what is entered goes into the clip before, which grows.
  view:activate(clips[3].id)
  view:set(nil, 4)
  keys("ic<Esc>")
  ok(clips[3]:get().length > 4, "the third clip grows into the gap")
  eq(#clips[3]:notes(), 5, "with the note entered there")
  keys("u")
  -- The part and MusicXML export are made of every clip.
  local P = require("notation.parts")
  local part = P.part_layout(violin.id)
  local notes = 0
  for _, m in ipairs(part.measures) do
    for _, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do notes = notes + #(ev.notes or {}) end
    end
  end
  eq(notes, 16, "the violin's part has the four clips' sixteen notes")
  local path = T.scratch .. "/pasted.musicxml"
  P.musicxml(path)
  local file = require("notation.musicxml").read(path)
  local written = 0
  for _, m in ipairs(file.parts[1].score.measures) do
    for _, entry in ipairs(m.voices or {}) do
      for _, ev in ipairs(entry.events) do
        if ev.kind == "chord" then written = written + #ev.notes end
      end
    end
  end
  eq(written, 16, "and so has its MusicXML")
end)
