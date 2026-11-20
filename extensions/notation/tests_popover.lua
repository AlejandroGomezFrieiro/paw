-- Tests of the popovers: a prompt at the caret for what is not a note,
-- previewed as a trial, written as one undo step. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation"), require("notation.doc")
end

local function N(pitch, start, length, velocity) return { pitch = pitch, start = start, length = length, velocity = velocity or 80 } end

local keys = T.keys

--- A track with a clip open as notation, written as a score.
local function song(notes, length)
  fresh()
  local view = load()
  local track = paw.add_track({ name = "Lead" })
  track:add_device("synth")
  local clip = track:add_clip({ start = 0, length = length or 8, name = "tune", notes = notes or {} })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  view.value, view.dot, view.voice, view.triplets, view.tuplet = 1, false, 1, false, nil
  api.undo_checkpoint()
  return view, clip, track
end

local function score_of(clip) return require("notation").score_of(clip:get()) end

local function marks_of(clip, kind)
  local out = {}
  for _, mk in ipairs(score_of(clip).marks) do
    if mk.kind == kind then out[#out + 1] = mk end
  end
  return out
end

local function velocities(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do out[#out + 1] = n.velocity end
  return table.concat(out, " ")
end

--- Eight quarter notes, C D E F G A B C.
local function scale()
  local notes = {}
  for i, p in ipairs({ 60, 62, 64, 65, 67, 69, 71, 72 }) do notes[i] = N(p, i - 1, 1) end
  return notes
end

local function screen() return table.concat(api.ui_snapshot(140, 110), "\n") end

-- The framework ---------------------------------------------------------------------------------

test("popover: Enter writes the dynamic at the cursor as one undo step", function()
  local view, clip = song(scale())
  view:set(nil, 2)
  keys("<localleader>dmp<CR>")
  local dyn = marks_of(clip, "dynamic")
  eq(#dyn, 1, "one dynamic")
  eq(dyn[1].value, "mp", "mp")
  eq(clip:notes()[3].velocity, 66, "the notes from there play mp")
  eq(paw.keymap.mode, "n", "back in normal mode")
  keys("u")
  eq(#marks_of(clip, "dynamic"), 0, "one undo takes it away")
  eq(clip:notes()[3].velocity, 80, "and the loudness with it")
end)

test("popover: while typing the page shows the result as a ghost, and Esc leaves no trace", function()
  local view, clip = song(scale())
  local before, state = velocities(clip), api.undo_current()
  local meta = paw.api.json_encode(clip:get().meta)
  keys("<localleader>dff")
  eq(require("notation.popover").active(), true, "the popover is open")
  eq(#marks_of(clip, "dynamic"), 1, "the dynamic is there while typed")
  eq(clip:notes()[1].velocity, 112, "and heard")
  eq(view.ghost ~= nil and next(view.ghost.marks) ~= nil, true, "the new mark is a ghost")
  local m = view:layout().measures[1]
  eq(m.marks[1].ghost, true, "drawn as one")
  eq(m.ghost, nil, "the notes as they are")
  keys("<Esc>")
  eq(require("notation.popover").active(), false, "closed")
  eq(#marks_of(clip, "dynamic"), 0, "nothing written")
  eq(velocities(clip), before, "nothing heard")
  eq(paw.api.json_encode(clip:get().meta), meta, "what the clip keeps as it was")
  eq(api.undo_current(), state, "no undo step")
  eq(view.ghost, nil, "no ghost")
  eq(view:layout().measures[1].marks[1], nil, "nor on the page")
end)

test("popover: a wrong text says why and writes nothing", function()
  local _, clip = song(scale())
  keys("<localleader>dxyz")
  local st = require("paw.views.cmdline").state()
  eq(st.note_level, "error", "the line says it is wrong")
  eq(st.note:find("not a dynamic", 1, true) ~= nil, true, st.note)
  keys("<CR>")
  eq(#marks_of(clip, "dynamic"), 0, "nothing written")
end)

test("popover: completion lists what can be typed with what it means", function()
  song(scale())
  keys("<localleader>dm")
  local st = require("paw.views.cmdline").state()
  local labels = {}
  for _, c in ipairs(st.matches or {}) do labels[#labels + 1] = c.label .. "=" .. tostring(c.desc) end
  local text = table.concat(labels, ";")
  eq(text:find("mp=moderately soft", 1, true) ~= nil, true, text)
  eq(text:find("mf=moderately loud", 1, true) ~= nil, true, text)
  keys("<Tab>")
  st = require("paw.views.cmdline").state()
  eq(st.before, "mp", "Tab chooses the first")
  keys("<Esc>")
end)

test("popover: each has its own history, and the prompt is drawn at the caret", function()
  local view = song(scale())
  keys("<localleader>dmf<CR>")
  view:set(nil, 3)
  keys("<localleader>d<Up>")
  eq(require("paw.views.cmdline").state().before, "mf", "Up brings back the dynamic typed last")
  local text = screen()
  local rows = api.ui_snapshot(140, 110)
  local found
  for i, row in ipairs(rows) do
    if row:find("dynamic mf", 1, true) then found = i end
  end
  eq(found ~= nil and found < #rows, true, "drawn over the staff, not on the bottom row:\n" .. text)
  keys("<Esc>")
  keys("<localleader>t<Up>")
  eq(require("paw.views.cmdline").state().before, "", "the tempo popover has its own")
  keys("<Esc>")
end)

test("popover: in visual mode it is for the selection, as :'<,'> is", function()
  local view, clip = song(scale())
  view:set(nil, 0)
  keys("v3l<localleader>dmp<lt>f<CR>")
  local dyn = marks_of(clip, "dynamic")
  eq(#dyn, 2, "a dynamic at each end")
  local pins = marks_of(clip, "hairpin")
  eq(#pins, 1, "a hairpin between")
  eq(pins[1].value, "cresc", "a crescendo")
  local v = {}
  for i, n in ipairs(clip:notes()) do v[i] = n.velocity end
  eq(v[1], 66, "mp at the start")
  eq(v[2] > v[1] and v[3] > v[2], true, "rising: " .. velocities(clip))
  eq(v[5], 96, "f from the end")
  eq(paw.state.last_cmdline, "'<,'>notation.dyn mp<f", "the line it ran, for @:")
  keys("u")
  eq(#marks_of(clip, "dynamic") + #marks_of(clip, "hairpin"), 0, "one undo step")
end)

test("popover: a hairpin alone reaches the next dynamic", function()
  local view, clip = song(scale())
  view:set(nil, 6)
  keys("<localleader>df<CR>")
  view:set(nil, 1)
  keys("<localleader>d<lt><CR>")
  local pin = marks_of(clip, "hairpin")[1]
  local midi = require("notation.midi")
  local sc = score_of(clip)
  local D = require("notation.doc")
  eq(midi.at_of(sc, D.frame(sc), pin.to) / D.Q, 6, "to the f on beat 7")
end)

test("popover: sfz, fp and subito play as they say", function()
  local view, clip = song(scale())
  keys("<localleader>dp<CR>")
  view:set(nil, 2)
  keys("<localleader>dsfz<CR>")
  view:set(nil, 4)
  keys("<localleader>dfp<CR>")
  local v = {}
  for i, n in ipairs(clip:notes()) do v[i] = n.velocity end
  eq(v[2], 52, "p")
  eq(v[3], 82, "an sfz is an accent over p")
  eq(v[4], 52, "p again after it")
  eq(v[5], 96, "fp: loud on the note")
  eq(v[6], 52, "then soft")
  view:set(nil, 6)
  keys("<localleader>dff subito<CR>")
  local last = marks_of(clip, "dynamic")
  local sub
  for _, mk in ipairs(last) do
    if mk.value == "ff" then sub = mk end
  end
  eq(sub and sub.subito, true, "ff subito")
end)

test("popover: in insert mode Ctrl-o opens one, and entering goes on after", function()
  local _, clip = song(nil)
  keys("icd<C-o><localleader>dpp<CR>")
  eq(paw.keymap.mode, "i", "still entering notes")
  eq(marks_of(clip, "dynamic")[1].value, "pp", "pp written at the caret")
  keys("e")
  eq(#clip:notes(), 3, "the next letter enters a note")
  eq(clip:notes()[3].velocity, 38, "at pp")
  keys("<C-o><localleader>dmf<Esc>")
  eq(paw.keymap.mode, "i", "Esc in the popover goes back to entering")
  eq(#marks_of(clip, "dynamic"), 1, "and wrote nothing")
  keys("<Esc>")
end)

test("popover: a dot repeats it, @: repeats its line, and the leader with a dot opens it again", function()
  local view, clip = song(scale())
  keys("<localleader>dp<CR>")
  view:set(nil, 4)
  keys(".")
  eq(#marks_of(clip, "dynamic"), 2, ". wrote it again at the cursor")
  view:set(nil, 6)
  keys("@:")
  eq(#marks_of(clip, "dynamic"), 3, "@: too")
  view:set(nil, 7)
  keys("<localleader>.")
  eq(require("paw.views.cmdline").state().before, "p", "\\. opens the last popover with its text")
  keys("<CR>")
  eq(#marks_of(clip, "dynamic"), 4, "Enter writes it")
end)

test("popover: Ex ranges say the same as the popover", function()
  local _, clip = song(scale())
  keys(":2notation.dyn f<CR>")
  local sc = score_of(clip)
  local D = require("notation.doc")
  local mk = marks_of(clip, "dynamic")[1]
  eq(mk.from.measure, sc.measures[2].id, "in bar 2")
  eq(D.ticks(mk.from.at), 0, "at its start")
  keys(":1,2notation.bar 1.<CR>")
  sc = score_of(clip)
  eq(sc.measures[1].volta, 1, "a first ending over bars 1")
  eq(sc.measures[2].volta, 1, "and 2")
end)

-- The popovers ------------------------------------------------------------------------------

test("popover: a tempo mark plays, rit. slows to the end of the selection, a tempo goes back", function()
  local view, clip = song(scale())
  keys("<localleader>tAllegro q=132<CR>")
  eq(marks_of(clip, "tempo")[1].value, "Allegro q=132", "written")
  eq(paw.tempo.at(0), 132, "and the song plays at 132")
  view:set(nil, 4)
  keys("v3l<localleader>trit.<CR>")
  eq(paw.tempo.at(4), 132, "rit. starts from the tempo there")
  eq(paw.tempo.at(7.9) < 132 and paw.tempo.at(8) <= 106, true, "slowing to the end of the selection: " .. paw.tempo.at(8))
  view:set(nil, 8)
  keys("<localleader>ta tempo<CR>")
  eq(paw.tempo.at(8), 132, "a tempo")
  view:set(nil, 2)
  keys("<localleader>tAndante<CR>")
  eq(paw.tempo.at(2), 92, "a word alone has its tempo")
  keys("u")
  eq(paw.tempo.at(2), 132, "undone with the mark")
end)

test("popover: a time signature writes the bars again, the music where it was", function()
  local view, clip = song(scale())
  local before = {}
  for i, n in ipairs(clip:notes()) do before[i] = n.start .. ":" .. n.pitch end
  keys("<localleader>m6/8<CR>")
  local sc = score_of(clip)
  eq(sc.measures[1].meter[1] .. "/" .. sc.measures[1].meter[2], "6/8", "6/8 from bar 1")
  local after = {}
  for i, n in ipairs(clip:notes()) do after[i] = n.start .. ":" .. n.pitch end
  eq(table.concat(after, " "), table.concat(before, " "), "every note where it was")
  eq(require("notation.model").text(view:layout()):match("^[^|]*"), "q C4 e~ D4 e D4 q E4 ", "bar 1 holds three quarters, D tied over the half bar")
  eq(paw.time.signature_at(0), 6, "the song's bars follow")
  keys("<localleader>m3+3+2/8<CR>")
  sc = score_of(clip)
  eq(table.concat(sc.measures[1].groups, "+"), "3+3+2", "an additive metre keeps its groups")
  eq(view:layout().measures[1].meter.groups ~= nil, true, "and is beamed by them")
  keys("u")
  keys("u")
  eq(score_of(clip).measures[1].meter[1] .. "/" .. score_of(clip).measures[1].meter[2], "4/4", "undone")
end)

test("popover: a key change at a bar, written and spelled by it", function()
  local view, clip = song(scale(), 12)
  view:set(nil, 4)
  keys("<localleader>kEb<CR>")
  local sc = score_of(clip)
  eq(sc.measures[2].key.fifths, -3, "E flat from bar 2")
  local layout = view:layout()
  eq(layout.measures[2].fifths, -3, "laid out in it")
  eq(layout.measures[2].key_change, true, "a change there")
  eq(layout.measures[1].fifths, 0, "bar 1 as before")
  -- B natural in E flat needs its natural sign.
  local b
  for _, ev in ipairs(layout.measures[2].staves[1]) do
    for _, n in ipairs(ev.notes or {}) do
      if n.pitch == 71 then b = n end
    end
  end
  eq(b.acc, 0, "B natural shows its sign")
  keys("<localleader>kf#m<CR>")
  eq(score_of(clip).measures[2].key.fifths, 3, "f#m: three sharps")
  keys("<localleader>kD dorian<CR>")
  eq(score_of(clip).measures[2].key.fifths, 0, "D dorian: none")
  eq(view:layout().measures[2].key_change, nil, "the same key as before is no change")
  keys("<localleader>kA<CR>")
  view:set(nil, 8)
  keys("<localleader>kC<CR>")
  eq(view:layout().measures[3].key_change, true, "back to C at bar 3")
  eq(screen():find("♮", 1, true) ~= nil, true, "its naturals are drawn")
end)

test("popover: a clef change at a bar, and alto on the first", function()
  local view, clip = song(scale(), 8)
  view:set(nil, 4)
  keys("<localleader>Cbass<CR>")
  local sc = score_of(clip)
  eq(sc.measures[2].clef[sc.staves[1].id], "bass", "bass from bar 2")
  local layout = view:layout()
  eq(layout.measures[2].clefs[1], "bass", "laid out so")
  local g = layout.measures[2].staves[1][1].notes[1]
  eq(g.pos, 14, "G4 on the bass staff is three ledger lines above it")
  view:set(nil, 0)
  keys("<localleader>Calto<CR>")
  eq(score_of(clip).staves[1].clef, "alto", "the staff's own clef in bar 1")
end)

test("popover: barlines, repeats and endings", function()
  local view, clip = song(scale(), 16)
  view:set(nil, 2)
  keys("<localleader>b||<CR>")
  local sc = score_of(clip)
  eq(sc.measures[1].barline, "||", "a double barline after the cursor's bar")
  view:set(nil, 4)
  keys("<localleader>b|:<CR>")
  eq(score_of(clip).measures[2].repeat_start, true, "a start repeat")
  view:set(nil, 4)
  keys("<localleader>b:|<CR>")
  eq(score_of(clip).measures[1].barline, ":|", "at a bar's start the barline before it")
  view:set(nil, 13)
  keys("<localleader>b|.<CR>")
  eq(score_of(clip).measures[4].barline, "|.", "the final barline")
  keys("v<localleader>b2.<CR>")
  eq(score_of(clip).measures[4].volta, 2, "a second ending")
end)

test("popover: text, rehearsal marks with song markers, techniques", function()
  local view, clip = song(scale(), 16)
  keys("<localleader>Xdolce<CR>")
  eq(marks_of(clip, "text")[1].value, "dolce", "text")
  keys("<localleader>r<CR>")
  view:set(nil, 8)
  keys("<localleader>r<CR>")
  local sc = score_of(clip)
  eq(sc.measures[1].rehearsal, "A", "A first")
  eq(sc.measures[3].rehearsal, "B", "B next")
  local names = {}
  for _, m in ipairs(paw.markers.list()) do names[#names + 1] = m.name .. "@" .. m.beat end
  eq(table.concat(names, " "), "A@0 B@8", "song markers")
  keys("<localleader>ppizz.<CR>")
  eq(marks_of(clip, "technique")[1].value, "pizz.", "a technique")
end)

test("popover: intervals add a note to each chord of the selection", function()
  local view, clip = song({ N(60, 0, 1), N(62, 1, 1), N(64, 2, 1) }, 4)
  keys("v2l<localleader>i3<CR>")
  local pitches = {}
  for _, n in ipairs(clip:notes()) do pitches[#pitches + 1] = n.pitch end
  eq(table.concat(pitches, " "), "60 64 62 65 64 67", "a third above each, in the key")
  view:set(nil, 0)
  keys("<Esc><localleader>i-6<CR>")
  eq(clip:notes()[1].pitch, 52, "a sixth below the lowest: E3")
  view:set(nil, 1)
  keys("<localleader>iP5<CR>")
  local top = 0
  for _, n in ipairs(clip:notes()) do
    if n.start == 1 then top = math.max(top, n.pitch) end
  end
  eq(top, 72, "a perfect fifth above F4")
end)

test("popover: tuplets, on a beat and while entering", function()
  local view, clip = song(nil, 4)
  keys("i<C-o><localleader>35<CR>")
  eq(view.tuplet and view.tuplet[1], 5, "entering quintuplets")
  eq(paw.keymap.mode, "i", "still entering")
  keys("cdefg<Esc>")
  local starts = {}
  for _, n in ipairs(clip:notes()) do starts[#starts + 1] = string.format("%.2f", n.start) end
  eq(table.concat(starts, " "), "0.00 0.80 1.60 2.40 3.20", "five in the time of four quarters")
  view = song({ N(60, 0, 0.5), N(62, 0.5, 0.5) }, 4)
  view:set(nil, 0)
  keys("<localleader>33<CR>")
  local layout = view:layout()
  eq(layout.measures[1].staves[1][1].tuplet ~= nil, true, "the beat as a triplet")
end)

test("popover: a selection into another voice", function()
  local view, clip = song({ N(67, 0, 1), N(69, 1, 1) }, 4)
  view:set(nil, 0)
  keys("vl<localleader>v2<CR>")
  local voices = {}
  local D = require("notation.doc")
  D.each(score_of(clip), function(ev, _, _, v)
    if ev.kind == "chord" then voices[#voices + 1] = v end
  end)
  eq(table.concat(voices, " "), "2 2", "both chords in voice 2")
  eq(view.voice, 2, "and entering there")
end)

test("popover: lyrics go note by note with Space, hyphens and a second verse", function()
  local view, clip = song(scale(), 8)
  keys("<localleader>lHal-le-lu<Space>jah<CR>")
  local layout = view:layout()
  local words = {}
  for _, ev in ipairs(require("notation.model").events(layout)) do
    if ev.source and ev.source.lyric then words[#words + 1] = ev.source.lyric end
  end
  eq(table.concat(words, " "), "Hal- le- lu jah", "syllable by syllable")
  view:set(nil, 0)
  keys("<localleader>lverse=2 A<Space>men<CR>")
  local sc = score_of(clip)
  local second = {}
  require("notation.doc").each(sc, function(ev)
    if ev.lyrics then second[#second + 1] = ev.lyrics[1] end
  end)
  eq(table.concat(second, " "), "A men", "verse 2")
  -- Tall enough for the lyrics under the staff whatever other panels are open.
  local shown = table.concat(api.ui_snapshot(140, 110), "\n")
  eq(shown:find("men", 1, true) ~= nil, true, "drawn:\n" .. shown)
end)

test("popover: chord symbols with Space to the next beat and Tab from what sounds", function()
  local view, clip = song({ N(60, 0, 2), N(64, 0, 2), N(67, 0, 2) }, 4)
  keys("<localleader>qCmaj7<Space>G/B<CR>")
  local list = marks_of(clip, "chord")
  local values = {}
  for _, mk in ipairs(list) do values[#values + 1] = mk.value end
  eq(table.concat(values, " "), "Cmaj7 G/B", "one a beat")
  view:set(nil, 0)
  keys("<localleader>q")
  local cands = require("notation.write").chord_candidates("")
  eq(cands[1].text, "C", "what sounds there comes first: " .. tostring(cands[1].text))
  keys("<Esc>")
  eq(screen():find("G/B", 1, true) ~= nil, true, "drawn")
end)

test("popover: ornaments and fermatas on the chord", function()
  local view, clip = song(scale(), 8)
  keys("<localleader>otr<CR>")
  local D = require("notation.doc")
  local first
  D.each(score_of(clip), function(ev) if ev.kind == "chord" and not first then first = ev end end)
  eq(first.orn, "trill", "a trill")
  view:set(nil, 7)
  keys("<localleader>ofermata<CR>")
  local last
  D.each(score_of(clip), function(ev) if ev.kind == "chord" then last = ev end end)
  eq(last.art and last.art.fermata, true, "a fermata")
  eq(clip:notes()[8].length, 1, "held its whole length")
end)

test("popover: the engraved page draws the popover at the caret", function()
  song(scale())
  keys("<localleader>dmp")
  local drawing = paw.canvas.paint("notation", 900, 500, {})
  local found
  for _, op in ipairs(drawing and drawing.ops or {}) do
    for _, x in ipairs(op) do
      if x == "dynamic " then found = true end
    end
  end
  eq(found, true, "the prompt is painted")
  keys("<Esc>")
end)

test("popover: the engraved page draws what the popovers wrote", function()
  local view = song(scale(), 16)
  keys("<localleader>tAllegro q=132<CR>")
  keys("<localleader>r<CR>")
  keys("<localleader>qCmaj7<CR>")
  keys("<localleader>otr<CR>")
  view:set(nil, 4)
  keys("<localleader>kD<CR>")
  view:set(nil, 6)
  keys("<localleader>ofermata<CR>")
  view:set(nil, 8)
  keys("<localleader>Calto<CR>")
  keys("<localleader>b1.<CR>")
  local drawing = paw.canvas.paint("notation", 1400, 600, { glyphs = true })
  local glyphs, texts = {}, {}
  for _, op in ipairs(drawing.ops) do
    if op[1] == "g" then glyphs[op[5]] = true end
    if op[1] == "t" then texts[op[4]] = true end
  end
  local font = require("notation.smufl").font()
  for _, name in ipairs({ "metNoteQuarterUp", "ornamentTrill", "fermataAbove", "cClef", "accidentalSharp" }) do
    eq(glyphs[font.glyphs[name].cp], true, name .. " is drawn")
  end
  for _, text in ipairs({ "Allegro", "= 132", "A", "Cmaj7", "1." }) do
    eq(texts[text], true, text .. " is drawn")
  end
end)

test("score: after an undo the page names the score's own chords, not ones an edit changed since", function()
  local view, clip = song({ N(67, 0, 1), N(69, 1, 1) }, 4)
  local D = require("notation.doc")
  view:layout()
  view:set(nil, 0)
  keys("vl:notation.voice 2<CR>")
  local moved = 0
  D.each(score_of(clip), function(ev, _, _, v) if ev.kind == "chord" and v == 2 then moved = moved + 1 end end)
  eq(moved, 2, "both chords moved into voice 2")
  view:layout()
  keys("u")
  local sc = score_of(clip)
  local bad = {}
  for _, m in ipairs(view:layout().measures) do
    for _, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do
        if ev.source and ev.source.id ~= "" then
          local _, _, _, _, found = D.find(sc, ev.source.id)
          if found ~= ev.source then bad[#bad + 1] = ev.source.id end
        end
      end
    end
  end
  eq(table.concat(bad, " "), "", "every event's source is the score's")
  -- And an edit through them reaches the score.
  view:set(nil, 0)
  keys("<localleader>otr<CR>")
  local first
  D.each(score_of(clip), function(ev) if ev.kind == "chord" and not first then first = ev end end)
  eq(first.orn, "trill", "the chord under the cursor took the trill")
end)
