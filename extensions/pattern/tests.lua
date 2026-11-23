-- Tests of the pattern extension; tests/suite.lua runs them.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local pattern
local function load()
  if not pattern then
    paw.ext.load("extensions/pattern")
    pattern = require("pattern")
  end
  return pattern
end

--- A time in cycles as a fraction: 0, 1/3, 5/4, 2.
local function frac(x)
  for d = 1, 192 do
    local n = x * d
    if math.abs(n - math.floor(n + 0.5)) < 1e-6 then
      n = math.floor(n + 0.5)
      return d == 1 and tostring(n) or (n .. "/" .. d)
    end
  end
  return tostring(x)
end

--- Events as "start-stop word" with fractions of a cycle, in order.
local function ev(text, cycles, opts)
  local out = {}
  for _, e in ipairs(load().events(text, cycles or 1, opts)) do
    out[#out + 1] = frac(e.start) .. "-" .. frac(e.stop) .. " " .. e.text
  end
  return table.concat(out, ", ")
end

--- Just the words, in order: "a b a c".
local function words(text, cycles, opts)
  local out = {}
  for _, e in ipairs(load().events(text, cycles or 1, opts)) do
    out[#out + 1] = e.text
  end
  return table.concat(out, " ")
end

--- Pitches of each event: "60,64,67 62".
local function pitches(text, cycles)
  local out = {}
  for _, e in ipairs(load().events(text, cycles or 1)) do
    out[#out + 1] = table.concat(e.pitches, ",")
  end
  return table.concat(out, " ")
end

--- A clip's notes: "36@0+1v100".
local function notes_of(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = string.format("%d@%g+%gv%d", n.pitch, n.start, n.length, n.velocity)
  end
  return table.concat(out, " ")
end

local function err_of(text)
  local ok, err = load().parse(text)
  eq(ok, nil, "`" .. text .. "` fails")
  return tostring(err)
end

-- The language ---------------------------------------------------------------

test("pattern: sequences, rests and subdivision", function()
  eq(ev("bd sn hh hh"), "0-1/4 bd, 1/4-1/2 sn, 1/2-3/4 hh, 3/4-1 hh", "a sequence shares the cycle")
  eq(ev("bd ~ sn ~"), "0-1/4 bd, 1/2-3/4 sn", "rests")
  eq(ev("[bd bd] sn"), "0-1/4 bd, 1/4-1/2 bd, 1/2-1 sn", "subdivision")
  eq(ev("bd [~ [sn sn]]"), "0-1/2 bd, 3/4-7/8 sn, 7/8-1 sn", "nested")
  eq(ev("a b . c d e"), "0-1/4 a, 1/4-1/2 b, 1/2-2/3 c, 2/3-5/6 d, 5/6-1 e", "`.` groups")
  eq(ev("bd sn", 2), "0-1/2 bd, 1/2-1 sn, 1-3/2 bd, 3/2-2 sn", "every cycle the same")
end)

test("pattern: repetition, replication, slowing and elongation", function()
  eq(ev("hh*4"), "0-1/4 hh, 1/4-1/2 hh, 1/2-3/4 hh, 3/4-1 hh", "`*` repeats within the step")
  eq(ev("bd [hh sn]*2"), "0-1/2 bd, 1/2-5/8 hh, 5/8-3/4 sn, 3/4-7/8 hh, 7/8-1 sn", "`*` on a group")
  eq(ev("bd!3 sn"), "0-1/4 bd, 1/4-1/2 bd, 1/2-3/4 bd, 3/4-1 sn", "`!` replicates steps")
  eq(ev("bd ! sn"), "0-1/3 bd, 1/3-2/3 bd, 2/3-1 sn", "a lone `!` repeats the step before")
  eq(ev("[a b c]/2", 2), "0-2/3 a, 2/3-4/3 b, 4/3-2 c", "`/` slows over cycles")
  eq(ev("a/2", 4), "0-2 a, 2-4 a", "a slowed note starts every other cycle")
  eq(ev("a@3 b"), "0-3/4 a, 3/4-1 b", "`@` weights a step")
  eq(ev("a _ _ b"), "0-3/4 a, 3/4-1 b", "`_` lengthens the step before")
  eq(ev("a*1.5", 2), "0-2/3 a, 2/3-4/3 a, 4/3-2 a", "fractional speeds")
  eq(ev("hh*<2 3>", 2), "0-1/2 hh, 1/2-1 hh, 1-4/3 hh, 4/3-5/3 hh, 5/3-2 hh", "a speed that alternates")
  eq(ev("0 .. 3"), "0-1/4 0, 1/4-1/2 1, 1/2-3/4 2, 3/4-1 3", "`..` counts")
end)

test("pattern: alternation and polymeter over several cycles", function()
  eq(words("<c e g>", 6), "c e g c e g", "one step per cycle")
  eq(ev("<c e> g", 2), "0-1/2 c, 1/2-1 g, 1-3/2 e, 3/2-2 g", "inside a sequence")
  eq(words("<a <b c>>", 6), "a b a c a b", "nested alternation")
  eq(words("<a!2 b>", 6), "a a b a a b", "replicated within alternation")
  eq(ev("<a@3 b>", 4), "0-3 a, 3-4 b", "weighted alternation holds a step")
  eq(words("<[a a] b>", 2), "a a b", "a group as a step")
  eq(
    ev("{a b c}%4", 2),
    "0-1/4 a, 1/4-1/2 b, 1/2-3/4 c, 3/4-1 a, 1-5/4 b, 5/4-3/2 c, 3/2-7/4 a, 7/4-2 b",
    "polymeter steps"
  )
  eq(
    ev("{a b c, d e}", 2),
    "0-1/3 a, 0-1/3 d, 1/3-2/3 b, 1/3-2/3 e, 2/3-1 c, 2/3-1 d, 1-4/3 a, 1-4/3 e, 4/3-5/3 b, 4/3-5/3 d, 5/3-2 c, 5/3-2 e",
    "polymeter layers at the first layer's steps"
  )
  eq(words("<a b, c d e>", 6), "a c b d a e b c a d b e", "alternation layers each at their own length")
  eq(words("[a, <b c>]", 2), "a b a c", "stack with alternation")
end)

test("pattern: stacks, Euclidean rhythms and chords", function()
  eq(ev("[bd, hh*2]"), "0-1 bd, 0-1/2 hh, 1/2-1 hh", "a stack")
  eq(ev("bd*2, ~ sn"), "0-1/2 bd, 1/2-1 bd, 1/2-1 sn", "a stack at the top level")
  eq(ev("bd(3,8)"), "0-1/8 bd, 3/8-1/2 bd, 3/4-7/8 bd", "three in eight")
  eq(ev("bd(3,8,2)"), "1/8-1/4 bd, 1/2-5/8 bd, 3/4-7/8 bd", "rotated left two steps")
  eq(ev("bd(5,8)"), "0-1/8 bd, 1/4-3/8 bd, 3/8-1/2 bd, 5/8-3/4 bd, 3/4-7/8 bd", "Bjorklund's (5,8)")
  eq(ev("bd(-3,8)"), "1/8-1/4 bd, 1/4-3/8 bd, 1/2-5/8 bd, 5/8-3/4 bd, 7/8-1 bd", "negative hits: the rests")
  eq(ev("[bd sn](2,4)"), "0-1/8 bd, 1/8-1/4 sn, 1/2-5/8 bd, 5/8-3/4 sn", "a group on each hit")
  eq(words("bd(<3 5>,8)", 2), "bd bd bd bd bd bd bd bd", "hits that alternate: 3 then 5")
  local bj = {}
  for _, hit in ipairs(load().bjorklund(7, 16)) do
    bj[#bj + 1] = hit and "x" or "."
  end
  eq(table.concat(bj), "x..x.x.x..x.x.x.", "(7,16) as Tidal has it")
  eq(pitches("c'maj e3'min7 c'maj'ii g3'dom7'o"), "60,64,67 52,55,59,62 67,72,76 43,50,59,65", "chords, inverted, open")
  eq(pitches("c'maj'5 60'm"), "60,64,67,72,76 60,63,67", "a chord over more notes; from a number")
  eq(pitches("c4 eb3 f# Bb2 cs ef 61"), "60 51 66 46 61 63 61", "note names and numbers")
  eq(pitches("bd sn cp sn2 hh ph oh"), "36 38 39 40 42 44 46", "drums the built-in drum device plays")
end)

test("pattern: degrees in a key, and parameters", function()
  eq(pitches("1 3 5 8 # key a3 # scale minor"), "57 60 64 69", "degrees of A minor")
  eq(pitches("1 2 # scale dorian"), "60 62", "a scale alone is rooted on C4")
  eq(pitches("1 3 # key <c4 g3>", 2), "60 64 55 59", "a key that changes per cycle")
  eq(pitches("1'maj 2'm # key d3"), "50,54,57 52,55,59", "chords on degrees")
  eq(pitches("c e # add 2 # oct -1"), "50 54", "transposed")
  eq(pitches("1 2 # key c4 # add 2"), "64 65", "`add` moves degrees along the scale")
  eq(pitches("bd # add 5"), "36", "drums are not transposed")
  local p = load()
  local function vel(text)
    local out = {}
    for _, n in ipairs(p.notes(text, 1, { beats = 4 })) do
      out[#out + 1] = n.velocity .. "/" .. n.length
    end
    return table.concat(out, " ")
  end
  eq(vel("bd*4 # vel 1 0.6 0.8 0.6"), "127/1 76/1 102/1 76/1", "velocity per step")
  eq(vel("bd*4 # vel <1 0.5>"), "127/1 127/1 127/1 127/1", "a velocity per cycle")
  eq(vel("bd*4 # vel 100 ~"), "100/1 100/1 100/1 100/1", "above 1 a MIDI velocity, a rest leaves the default")
  eq(vel("bd sn # legato 0.5"), "100/1 100/1", "legato halves")
  eq(vel("bd*4 # vel 1 0"), "127/1 127/1", "velocity 0 drops the note")
  eq(vel("c d # legato 0.25 2"), "100/0.5 100/2", "legato over the event")
  local notes = p.notes("c # ch 2", 1, { beats = 4 })
  eq(notes[1].meta.channel, 2, "a channel in the note's meta")
end)

test("pattern: random choices and drops follow the seed", function()
  local p = load()
  local first = words("a|b|c", 16)
  eq(words("a|b|c", 16), first, "the same text and seed, the same choices")
  eq(#first, 31, "one choice per cycle")
  eq(first:find("a") ~= nil and first:find("b") ~= nil and first:find("c") ~= nil, true, "each chosen sometimes")
  eq(words("a|b|c", 16, { seed = 1 }) ~= first, true, "another seed, other choices")
  local kept = #p.events("hh*16?", 4)
  eq(kept > 16 and kept < 48, true, "`?` drops about half: kept " .. kept)
  eq(#p.events("hh*16?", 4), kept, "the same ones every time")
  eq(#p.events("hh*16?0.9", 4) < 20, true, "`?0.9` drops most")
  local both = ev("hh*8? hh*8?")
  local half = ev("hh*8?")
  eq(both ~= "" and half ~= "", true, "something kept")
  eq(words("[a | b c] d", 4), words("[a | b c] d", 4), "choices between sequences")
  -- Two `?` in one text decide independently.
  local a, b = {}, {}
  for _, e in ipairs(p.events("[hh*16?, sn*16?]", 1)) do
    local list = e.text == "hh" and a or b
    list[#list + 1] = frac(e.start)
  end
  eq(table.concat(a, " ") ~= table.concat(b, " "), true, "independent drops")
end)

test("pattern: errors say where they are", function()
  eq(err_of("bd [sn hh"), "col 4: missing `]` for the bracket at col 4", "unclosed")
  eq(err_of("bd sn]"), "col 6: `]` without an opening bracket", "stray closer")
  eq(err_of("bd zz sn"), "col 4: unknown name `zz`: not a note, a number or a drum", "unknown word")
  eq(err_of("c'nope"), "col 3: unknown chord `nope`", "unknown chord")
  eq(
    err_of("bd(3)"),
    "col 3: a Euclidean rhythm takes 2 or 3 numbers: (hits,steps) or (hits,steps,rotation)",
    "euclid arity"
  )
  eq(err_of("bd*x"), "col 4: expected a number, not `x`", "speed")
  eq(err_of("bd # vel"), "col 9: `vel` needs a value", "empty parameter")
  eq(
    err_of("bd # pan 1"),
    "col 6: unknown parameter `pan` (add, ch, key, legato, oct, scale, vel)",
    "unknown parameter"
  )
  eq(err_of("1 # scale nope"), "col 11: unknown scale `nope`", "unknown scale")
  eq(err_of("bd 1.5"), "col 4: a note number must be whole, not `1.5`", "fraction")
  eq(err_of("bd [sn ~] {hh"), "col 11: missing `}` for the bracket at col 11", "the right bracket")
  eq(err_of("bd sn$"), "col 6: unexpected `$` (steps are separated by spaces)", "junk")
  eq(err_of(""), "col 1: the pattern is empty", "empty")
  eq(err_of("bd?2"), "col 4: a probability is between 0 and 1", "probability")
  local _, err = load().parse("bd zz")
  eq(load().caret(err), "bd zz\n   ^", "a caret under the place")
end)

-- Clips ----------------------------------------------------------------------

local function drum_track()
  local track = paw.add_track({ name = "Drums" })
  track:add_device("drums")
  return track
end

test("pattern: a clip follows its text through edits", function()
  fresh()
  local p = load()
  local track = drum_track()
  local clip = track:add_clip({ start = 0, length = 4 })
  local notes = assert(p.set(clip, "bd sn"))
  eq(#notes, 2, "notes returned")
  paw.flush()
  eq(notes_of(clip), "36@0+2v100 38@2+2v100", "one cycle is one bar")
  eq(clip.meta.pattern.text, "bd sn", "the text is in the clip's meta")
  eq(clip.name, "≈ bd sn", "named after its text")
  clip.length = 8
  paw.flush()
  eq(notes_of(clip), "36@0+2v100 38@2+2v100 36@4+2v100 38@6+2v100", "a longer clip plays more cycles")
  eq(p.get(clip).text, "bd sn", "still linked")
  p.set(clip, "<bd cp> hh")
  paw.flush()
  eq(notes_of(clip), "36@0+2v100 42@2+2v100 39@4+2v100 42@6+2v100", "new text, new notes")
  eq(clip.name, "≈ <bd cp> hh", "and a new name")
  clip.length = 6
  paw.flush()
  eq(notes_of(clip), "36@0+2v100 42@2+2v100 39@4+2v100", "shorter: notes past the end go")
  p.set(clip, "bd", { beats = 2 })
  paw.flush()
  eq(notes_of(clip), "36@0+2v100 36@2+2v100 36@4+2v100", "a cycle of two beats")
  clip.meta = { pattern = { text = "sn*2" }, other = "kept" }
  paw.flush()
  eq(notes_of(clip), "38@0+2v100 38@2+2v100 38@4+2v100", "text written straight into the meta is followed")
  eq(clip.meta.other, "kept", "other meta stays")
  -- The time signature changes how long a bar, and so a cycle, is.
  p.set(clip, "bd sn", { beats = false })
  paw.project.sig_num = 3
  paw.flush()
  eq(notes_of(clip), "36@0+1.5v100 38@1.5+1.5v100 36@3+1.5v100 38@4.5+1.5v100", "a bar of 3/4")
  paw.project.sig_num = 4
  paw.flush()
  -- Moving the clip leaves its notes alone.
  clip.start = 8
  paw.flush()
  eq(p.get(clip) ~= nil, true, "moving keeps the link")
  -- Editing the notes by hand detaches it, keeping the edit.
  local hand = clip:notes()
  hand[1].pitch = 40
  clip:set_notes(hand)
  paw.flush()
  eq(p.get(clip), nil, "detached")
  eq(clip.meta.pattern_detached, "bd sn", "the text is kept for later")
  eq(notes_of(clip):sub(1, 9), "40@0+2v10", "the hand edit stays")
  clip.length = 8
  paw.flush()
  eq(#clip:notes(), 3, "a detached clip no longer follows")
end)

test("pattern: splitting a clip keeps the left part linked", function()
  fresh()
  local p = load()
  local track = drum_track()
  local clip = track:add_clip({ start = 0, length = 8 })
  p.set(clip, "bd hh sn hh")
  paw.flush()
  paw.cursor.set_track(track)
  paw.cursor.set_beat(4)
  paw.cmd("clip.split")
  paw.flush()
  eq(p.get(clip) ~= nil, true, "the left part still follows its text")
  eq(notes_of(clip), "36@0+1v100 42@1+1v100 38@2+1v100 42@3+1v100", "with the first bar")
end)

test("pattern: undo and redo bring text and notes back together", function()
  fresh()
  local p = load()
  local track = drum_track()
  local clip = track:add_clip({ start = 0, length = 4 })
  api.undo_checkpoint()
  p.set(clip, "bd*2")
  paw.flush()
  api.undo_checkpoint()
  p.set(clip, "sn*4")
  paw.flush()
  api.undo_checkpoint()
  clip.length = 8
  paw.flush()
  api.undo_checkpoint()
  eq(#clip:notes(), 8, "lengthened")
  paw.undo()
  paw.flush()
  eq(clip.length, 4, "length undone")
  eq(notes_of(clip), "38@0+1v100 38@1+1v100 38@2+1v100 38@3+1v100", "with the notes of the shorter clip")
  paw.undo()
  paw.flush()
  eq(p.get(clip).text, "bd*2", "text undone")
  eq(notes_of(clip), "36@0+2v100 36@2+2v100", "notes undone with it")
  paw.redo()
  paw.flush()
  eq(p.get(clip).text, "sn*4", "redone")
  eq(#clip:notes(), 4, "notes redone")
  -- A hand edit that detached it is undone in one step, link and all.
  clip:set_notes({ { pitch = 50, start = 0 } })
  paw.flush()
  api.undo_checkpoint()
  eq(p.get(clip), nil, "detached by the edit")
  paw.undo()
  paw.flush()
  eq(p.get(clip).text, "sn*4", "undoing the edit links it again")
  eq(#clip:notes(), 4, "with its notes")
end)

test("pattern: saved and loaded with the project", function()
  fresh()
  local p = load()
  local track = drum_track()
  local clip = track:add_clip({ start = 0, length = 4 })
  p.set(clip, "bd? sn*2 hh*4?", { seed = 3 })
  paw.flush()
  local before = notes_of(clip)
  local path = paw.project.save(T.scratch .. "/pattern.json")
  fresh()
  paw.project.load(path)
  paw.flush()
  local loaded = paw.tracks()[1]:clips()[1]
  local count = #loaded:notes()
  eq(p.get(loaded).text, "bd? sn*2 hh*4?", "the text is back")
  eq(p.get(loaded).seed, 3, "and the seed")
  eq(notes_of(loaded), before, "the same notes")
  loaded.length = 8
  paw.flush()
  eq(#loaded:notes() > count, true, "still follows")
  eq(p.get(loaded) ~= nil, true, "linked after loading")
end)

test("pattern: commands and keys on the clip under the cursor", function()
  fresh()
  load()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  local track = drum_track()
  paw.cursor.set_track(track)
  paw.cursor.set_beat(4)
  paw.cmd("pattern.set", { "bd*2 sn" })
  paw.flush()
  local clip = track:clips()[1]
  eq(clip.start, 4, "a new clip at the cursor")
  eq(clip.length, 4 * paw.opt.pattern_cycles, "four cycles long")
  eq(#clip:notes(), 12, "with the notes")
  paw.commands.exec("pattern.set hh*4")
  paw.flush()
  eq(#track:clips(), 1, "the clip under the cursor is changed, no new one")
  eq(#clip:notes(), 16, "to the new text")
  -- Errors leave everything alone and say where.
  paw.commands.exec("pattern.set hh [")
  paw.flush()
  eq(paw.ui.message.text, "pattern: col 4: missing `]` for the bracket at col 4", "the error is shown")
  eq(pattern.get(clip).text, "hh*4", "unchanged")
  -- Too many notes is an error too.
  paw.commands.exec("pattern.set bd*100000")
  eq(paw.ui.message.text, "pattern: col 3: at most 256 repeats in a step", "a repeat past 256")
  paw.commands.exec("pattern.set [bd*256]*256")
  paw.flush()
  eq(paw.ui.message.text:find("more than 20000 notes", 1, true) ~= nil, true, "too many notes: " .. paw.ui.message.text)
  eq(pattern.get(clip).text, "hh*4", "still unchanged")
  -- The prompt holds the current text.
  paw.keymap.feed("<localleader>tt")
  local state = require("paw.views.cmdline").state()
  eq(state and state.before, "hh*4", "the prompt starts from the text")
  paw.keymap.feed("<C-u>bd ~ sn ~<CR>")
  paw.flush()
  eq(pattern.get(clip).text, "bd ~ sn ~", "typed into the prompt")
  eq(#clip:notes(), 8, "two notes a bar")
  -- A mistake in the prompt opens it again, keeping the text.
  paw.keymap.feed("<localleader>tt<C-u>bd [<CR>")
  state = require("paw.views.cmdline").state()
  eq(state and state.before, "bd [", "the prompt is back with the text")
  eq(require("paw.views.cmdline").state() ~= nil, true, "still open")
  paw.keymap.feed("sn]<CR>")
  paw.flush()
  eq(pattern.get(clip).text, "bd [sn]", "fixed and set")
  -- Seeds from the keyboard.
  pattern.set(clip, "hh*16?")
  paw.flush()
  local first = notes_of(clip)
  paw.keymap.feed("<localleader>tr")
  paw.flush()
  eq(pattern.get(clip).seed, 1, "next seed")
  eq(notes_of(clip) ~= first, true, "other notes")
  paw.keymap.feed("<localleader>tR")
  paw.flush()
  eq(notes_of(clip), first, "the previous seed gives the first notes back")
  paw.cmd("pattern.cycle", { 8 })
  paw.flush()
  eq(pattern.get(clip).beats, 8, "a cycle of 8 beats")
  paw.cmd("pattern.cycle", { "bar" })
  eq(pattern.get(clip).beats, nil, "back to a bar")
  paw.keymap.feed("<localleader>ti")
  eq(paw.ui.message.text:find("hh*16?", 1, true) == 1, true, "info shows the text")
  -- The text is on the clip in the arrange view.
  local screen = table.concat(api.ui_snapshot(120, 30), "\n")
  eq(screen:find("≈ hh*16?", 1, true) ~= nil, true, "shown in the arrange view")
  paw.keymap.feed("<localleader>td")
  paw.flush()
  eq(pattern.get(clip), nil, "detached from the keyboard")
  eq(#clip:notes() > 0, true, "notes kept")
  paw.keymap.feed("<localleader>tt")
  eq(require("paw.views.cmdline").state().before, "hh*16?", "the prompt offers the detached text")
  paw.keymap.feed("<CR>")
  paw.flush()
  eq(pattern.get(clip).text, "hh*16?", "linked again")
  -- A new clip after this one.
  paw.keymap.feed("<localleader>tnc e g<CR>")
  paw.flush()
  eq(#track:clips(), 2, "a second clip")
  eq(track:clips()[2].start, clip.start + clip.length, "right after the first")
end)

test("pattern: a render sounds where the pattern has notes and is silent where it rests", function()
  fresh()
  local p = load()
  paw.project.tempo = 120
  local track = paw.add_track({ name = "Tone" })
  track:add_device("synth", { attack = 0.001, release = 0.01 })
  local clip = track:add_clip({ start = 0, length = 4 })
  p.set(clip, "a3 ~ [~ a3] ~")
  paw.flush()
  local info = T.render({ bits = 16, tail = 0 })
  -- A beat is half a second: notes at 0-0.5 s and 1.25-1.5 s.
  eq(T.channel_peaks(info, 0.05, 0.45) > 0.05, true, "the first step sounds")
  eq(T.channel_peaks(info, 0.6, 1.2) < 0.002, true, "the rest is silent")
  eq(T.channel_peaks(info, 1.3, 1.45) > 0.05, true, "the second half of the third step sounds")
  eq(T.channel_peaks(info, 1.6, 2.0) < 0.002, true, "the last step is silent")
  local f = T.frequency(info, 0.05, 0.45)
  eq(math.abs(f - 220) < 10, true, "at A3: " .. f)
end)

test("pattern: a changed pattern is heard on the next pass of the loop, without stopping", function()
  fresh()
  local p = load()
  paw.project.tempo = 240
  local track = paw.add_track({ name = "Tone" })
  track:add_device("synth", { attack = 0.001, release = 0.01 })
  local clip = track:add_clip({ start = 0, length = 8 })
  p.set(clip, "a3 ~ ~ ~ ~ ~ ~ ~", { beats = 8 })
  paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 8, true
  paw.flush()
  paw.transport.seek(0)
  paw.transport.play()
  -- The loudest the track gets in two windows of each pass: around beat 0 and beat 4.
  local passes, pass, last, changed, stopped = { { 0, 0 } }, 1, 0, false, false
  T.until_(function()
    local pos = paw.transport.position
    if pos < last - 1 then
      pass = pass + 1
      passes[pass] = { 0, 0 }
    end
    last = pos
    if pass > 3 then return true end
    local level = math.max(track:meter())
    if pos >= 0.2 and pos < 0.9 then passes[pass][1] = math.max(passes[pass][1], level) end
    if pos >= 4.2 and pos < 4.9 then passes[pass][2] = math.max(passes[pass][2], level) end
    if pass == 2 and not changed and pos >= 1.5 and pos < 3 then
      p.set(clip, "~ ~ ~ ~ a3 ~ ~ ~")
      paw.flush()
      changed = true
    end
    if not paw.transport.playing then stopped = true end
    return false
  end, "three passes of the loop")
  paw.transport.stop()
  paw.transport.loop_enabled = false
  eq(stopped, false, "the transport never stopped")
  local loud, quiet = passes[1][1], passes[1][2]
  eq(loud > 0.05, true, "first pass: the note at beat 0 sounds (" .. loud .. ")")
  eq(quiet < loud * 0.25, true, "first pass: nothing at beat 4 (" .. quiet .. ")")
  eq(passes[3][2] > loud * 0.5, true, "after the change: the note at beat 4 sounds (" .. passes[3][2] .. ")")
  eq(passes[3][1] < loud * 0.25, true, "after the change: nothing at beat 0 (" .. passes[3][1] .. ")")
  -- And what the engine was given is what the clip holds.
  eq(notes_of(clip), "57@4+1v100", "the clip's notes")
end, { live = "the meter of the track is read while the engine plays the loop in real time" })
