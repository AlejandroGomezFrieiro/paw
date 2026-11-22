-- Tests of the articulations extension; tests/suite.lua runs them.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local EXAMPLE = "extensions/articulations/articulations/examples/violin-section.art.toml"

local art
local function load()
  if not art then
    paw.ext.load("extensions/articulations")
    art = require("articulations")
  end
  return art
end

local keys = T.keys

local function ex(line)
  paw.commands.exec(line)
  api.undo_checkpoint()
end

local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 40), "\n") end

--- The notes' articulations as "pitch:code", in order ("-" for none).
local function codes(clip)
  local out = {}
  for i, n in ipairs(clip:notes()) do out[i] = n.pitch .. ":" .. (art.m2.code(art.attr_of(n)) or "-") end
  return table.concat(out, " ")
end

--- A track with a synth and a clip of four notes, bound to the example map,
--- open in the piano roll with the cursor on the first note.
local function strings(notes)
  load()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  local track = paw.add_track({ name = "Violins" })
  track:add_device("synth")
  local clip = track:add_clip({ start = 0, length = 8, name = "line", notes = notes or {
    { pitch = 67, start = 0, length = 1 }, { pitch = 69, start = 1, length = 1 },
    { pitch = 71, start = 2, length = 1 }, { pitch = 72, start = 3, length = 1 },
  } })
  paw.flush()
  art.bind(track.id, EXAMPLE)
  api.undo_checkpoint()
  local roll = paw.ui.views.pianoroll
  roll:edit(clip)
  roll:set(67, 0)
  return track, clip, roll
end

-- Reading ------------------------------------------------------------------------------

test("articulations: M2-123 codes are read and written, with the profile's fallback and the words libraries use", function()
  local m2 = load().m2
  local a = m2.parse("11.A")
  eq(a.type .. " " .. a.data, "17 40960", "11.A is classification 0x11, subclass A in the top four bits")
  eq(m2.code(m2.parse("11.a3")), "11.A3", "a variation")
  eq(m2.describe(a), "pizzicato (11.A)", "in words")
  eq(select(2, m2.parse("21.0")), "`21.0`: a classification runs from 10 to 1F", "out of the profile")
  local f = m2.fallbacks(m2.parse("11.A3"))
  eq(f[1] .. " " .. f[2] .. " " .. f[4] .. " " .. f[5], "11.A3 11.A 11.0 10.0", "variation, subclass, classification, sustain")
  eq(m2.guess("Trill M2") .. " " .. m2.guess("trill m2"), "13.2 13.0", "a capital tells a major second from a minor one")
  eq(m2.guess("Spicc short") .. " " .. m2.guess("Legato fast") .. " " .. (m2.guess("rach") or "nil"), "11.5 10.2 nil", "words")
  eq(m2.modifier("Con Sord Long"), "mute=straight", "a modifier the profile makes a controller")
end)

test("articulations: the example map reads, in file order, with its ranges and keyswitch rows", function()
  local maps = load().maps
  local map = assert(maps.load(EXAMPLE))
  local ids = {}
  for i, a in ipairs(map.arts) do ids[i] = a.id .. "=" .. a.code end
  eq(table.concat(ids, " "), "sustain=10.0 legato=10.2 staccato=11.0 spiccato=11.5 pizzicato=11.A col-legno=11.C tremolo=12.0 trill-min=13.0 trill-maj=13.2 harmonics=14.0", "the articulations")
  eq(table.concat({ map.range[1], map.range[2], map.keyswitches[1], map.keyswitches[2] }, " "), "55 105 24 33", "G3-A7, C1-A1")
  eq(map.by_id.harmonics.out .. " | " .. maps.out_text(map.by_id.harmonics.events), "ks=A1 cc1=96 | ks=A1 cc1=96", "an out line, read and written")
  eq(#map.mods .. " " .. map.mods[1].id, "2 con-sord", "the modifiers")
  local bad = select(2, maps.parse('format = 1\n[art]\nx = { m2 = "11.0", out = "ks=H9" }\n', "bad.art.toml"))
  eq(bad, "bad.art.toml: articulation `x`: `ks=H9`: `H9` is not a key (D1, C#1, 26)", "a wrong key is named")
end)

-- Binding and setting ------------------------------------------------------------------------

test("articulations: binding keeps the map on the track and hands the core its downgrade map", function()
  local track = strings()
  local info = art.info(track.id)
  eq(info.map .. " " .. info.default .. " " .. info.names["11.A"], "violin-section sustain pz", "the binding")
  local am = art.attr_map(track.id)
  eq(am.send .. " " .. am.default .. " " .. am.arts["11.A"].out .. " " .. table.concat(am.chase, ","), "change 10.0 ks=E1 1,11,64", "attr_map")
  paw.cmd("art.default", { "staccato" })
  eq(art.attr_map(track.id).default, "11.0", "the default compiles into it")
end)

test("articulations: :art sets the note under the cursor, a range, a selection and :g's matches, each one undo step", function()
  local _, clip, roll = strings()
  paw.ui.focus("pianoroll")
  ex("art stc")
  eq(codes(clip), "67:11.0 69:- 71:- 72:-", "the note under the cursor")
  ex("%art pizz")
  eq(codes(clip), "67:11.A 69:11.A 71:11.A 72:11.A", "the whole clip")
  roll:set(71, 2)
  keys("v$")
  keys("<Esc>")
  ex("'<,'>art trem")
  eq(codes(clip), "67:11.A 69:11.A 71:12.0 72:12.0", "a selection")
  ex("g/art=pz/art none")
  eq(codes(clip), "67:- 69:- 71:12.0 72:12.0", ":g with the art field")
  keys("u")
  eq(codes(clip), "67:11.A 69:11.A 71:12.0 72:12.0", "undone in one step")
  ex("%art 13.2")
  eq(codes(clip), "67:13.2 69:13.2 71:13.2 72:13.2", "a code")
end)

test("articulations: a track with no map takes codes and the words libraries use", function()
  load()
  fresh()
  local track = paw.add_track({ name = "Any" })
  local clip = track:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.flush()
  local roll = paw.ui.views.pianoroll
  roll:edit(clip)
  roll:set(60, 0)
  paw.commands.exec("art pizz")
  eq(codes(clip), "60:11.A", "pizz is 11.A")
  eq(art.tag_of(track.id, clip:notes()[1]), "11.A", "shown by its code")
end)

-- The roll -----------------------------------------------------------------------------

test("articulations: the roll labels keyswitch rows, tags notes, shows the band and the pen", function()
  local track, _, roll = strings()
  paw.ui.focus("pianoroll")
  paw.commands.exec("%art stc")
  roll:set(69, 1)
  paw.commands.exec("art pz")
  paw.cmd("art.pen", { "trm" })
  paw.opt.note_zoom = 8
  roll.top = 72
  local s = screen(120, 44)
  eq(s:find("art ", 1, true) ~= nil, true, "the band's title:\n" .. s)
  eq(s:find("│stc", 1, true) ~= nil and s:find("│pz", 1, true) ~= nil, true, "the band names the runs:\n" .. s)
  eq(s:find("pen trm", 1, true) ~= nil, true, "the pen")
  eq(s:find("▏stc", 1, true) ~= nil or s:find("stc", 1, true) ~= nil, true, "the notes' tags")
  roll.top = 35
  roll:set(30, 0)
  s = screen(120, 44)
  eq(s:find("sus", 1, true) ~= nil and s:find("hrm", 1, true) ~= nil, true, "the keyswitch rows named:\n" .. s)
  eq(roll.row_look(40, track.id).shade, "ArtOutOfRange", "below the range")
  eq(roll.row_look(103, track.id).shade, "ArtUncomfortable", "above the comfortable range")
  eq(roll.row_look(28, track.id).label, "pz", "E1 is pizzicato's keyswitch")
  -- A window is sent the rows named as the terminal draws them.
  api.scene_forget(0)
  api.scene_roles(0, { "note" })
  paw.ui.render_scene("pianoroll", 120, 44, { w = 8, h = 16 })
  local patch = api.json_decode(api.scene_end(0, "articulations"))
  api.scene_forget(0)
  local texts = {}
  for _, n in ipairs(patch.set) do
    if n.t == "run" then texts[#texts + 1] = n.text end
  end
  local said = table.concat(texts, "|")
  eq(said:find("sus", 1, true) ~= nil and said:find("hrm", 1, true) ~= nil, true, "the keyswitch rows: " .. said)
end)

test("articulations: K on a note says its articulation and how it is sent", function()
  local _, _, roll = strings()
  paw.ui.focus("pianoroll")
  paw.commands.exec("art pz")
  local lines = roll:describe()
  local text = {}
  for i, l in ipairs(lines) do text[i] = type(l) == "table" and l.text or l end
  eq(table.concat(text, "\n"):find("articulation  Pizzicato (11.A), sent as ks=E1", 1, true) ~= nil, true, table.concat(text, "\n"))
  roll:set(69, 1)
  text = {}
  for i, l in ipairs(roll:describe()) do text[i] = type(l) == "table" and l.text or l end
  eq(table.concat(text, "\n"):find("none: the track's default plays, Sustain", 1, true) ~= nil, true, table.concat(text, "\n"))
end)

test("articulations: notes entered in insert mode and with the mouse take the pen", function()
  local _, clip, roll = strings({})
  paw.ui.focus("pianoroll")
  paw.cmd("art.pen", { "spc" })
  roll:set(60, 0)
  paw.opt.octave = 4
  keys("I")
  keys("a")
  keys("s")
  keys("<Esc>")
  eq(codes(clip), "60:11.5 62:11.5", "insert mode, the keys way")
  roll:set(67, 2)
  keys("i")
  keys("l")
  keys("<Esc>")
  eq(codes(clip), "60:11.5 62:11.5 67:11.5", "insert mode, drawing")
  paw.frontend.act.add_note(clip.id, 64, 4)
  eq(codes(clip), "60:11.5 62:11.5 67:11.5 64:11.5", "a click")
  paw.cmd("art.pen", { "none" })
  paw.frontend.act.add_note(clip.id, 65, 5)
  eq(codes(clip), "60:11.5 62:11.5 67:11.5 64:11.5 65:-", "no pen")
end)

test("articulations: the popover lists the map's articulations and writes the one chosen", function()
  local _, clip = strings()
  paw.ui.focus("pianoroll")
  keys("\\a")
  eq(paw.ui.float ~= nil, true, "a list opened")
  local s = screen(120, 40)
  eq(s:find("5 pz   Pizzicato", 1, true) ~= nil, true, "numbered, with tags, names and codes:\n" .. s)
  keys("col<CR>")
  eq(codes(clip), "67:11.C 69:- 71:- 72:-", "col legno written")
  keys("u")
  eq(codes(clip), "67:- 69:- 71:- 72:-", "one undo step")
end)

test("articulations: the highlight resting on an articulation tries it on the notes, and Escape takes it back", function()
  local _, clip = strings()
  paw.ui.focus("pianoroll")
  keys("\\a")
  keys("<Down>")
  local tried
  for _ = 1, 40 do
    paw.wait(50)
    if codes(clip) == "67:10.2 69:- 71:- 72:-" then tried = true break end
  end
  eq(tried, true, "legato tried on the note: " .. codes(clip))
  keys("<Esc>")
  eq(codes(clip), "67:- 69:- 71:- 72:-", "taken back")
  eq(api.trial_active(), false, "no trial left")
end)

test("articulations: in insert mode \\a sets the pen", function()
  local track = strings({})
  paw.ui.focus("pianoroll")
  keys("I")
  keys("\\a")
  keys("pz<CR>")
  eq(paw.keymap.mode, "i", "still entering")
  eq(art.info(track.id).pen, "pizzicato", "the pen")
  keys("<Esc>")
end)

test("articulations: a sampler's describe makes a map", function()
  local gen = (load() and require("articulations.gen"))
  local spec = assert(gen.describe({ name = "Cello KS", format = "sfz", range = { lo = 36, hi = 84 },
    keyswitches = { { pitch = 24, name = "Sustain" }, { pitch = 25, name = "Pizz" } },
    articulations = { { name = "Sustain" }, { name = "Pizz", m2 = "11.A" }, { name = "Air" } } }))
  local out = {}
  for i, a in ipairs(spec.arts) do out[i] = a.name .. "=" .. a.m2 .. "/" .. a.out end
  eq(table.concat(out, " "), "Sustain=10.0/ks=C1 attr Pizz=11.A/ks=C#1 attr Air=1A.0/attr", "named, coded, keyswitched")
  eq(spec.range .. " " .. spec.keyswitches, "C2-C6 C1-C#1", "range and rows")
end)

test("articulations: ia is the run of notes with the articulation under the cursor", function()
  local _, clip, roll = strings({
    { pitch = 67, start = 0, length = 1 }, { pitch = 69, start = 1, length = 1 },
    { pitch = 71, start = 2, length = 1 }, { pitch = 72, start = 3, length = 1 },
  })
  paw.ui.focus("pianoroll")
  paw.commands.exec("%art stc")
  roll:set(72, 3)
  paw.commands.exec("art pz")
  roll:set(69, 1)
  keys("dia")
  eq(codes(clip), "72:11.A", "the staccatos went")
end)

-- Diagnostics -------------------------------------------------------------------------

test("articulations: notes out of range and on keyswitch rows are diagnosed, with fixes", function()
  local _, clip = strings({ { pitch = 43, start = 0, length = 1 }, { pitch = 26, start = 1, length = 1 }, { pitch = 72, start = 2, length = 1 } })
  local diags = require("articulations.diagnostics")
  local list = diags.of_clip(clip.id)
  local rules = {}
  for i, d in ipairs(list) do rules[i] = d.rule end
  table.sort(rules)
  eq(table.concat(rules, " "), "keyswitch-row out-of-range", "two things wrong")
  diags.check()
  local found = paw.diagnostic.get({ clip = clip.id }, { namespace = "articulations" })
  eq(#found, 2, "published")
  for _, d in ipairs(found) do
    if d.rule == "out-of-range" then paw.diagnostic.apply(d, d.fixes[1]) end
  end
  eq(clip:notes()[1].pitch, 55, "G2 moved an octave up into the range")
  found = paw.diagnostic.get({ clip = clip.id }, { namespace = "articulations" })
  for _, d in ipairs(found) do
    if d.rule == "keyswitch-row" then paw.diagnostic.apply(d, d.fixes[1]) end
  end
  eq(codes(clip), "55:- 72:11.0", "the keyswitch D1 became the staccato of the note after it")
end)

-- Making maps ---------------------------------------------------------------------------

test("articulations: an SFZ's keyswitches make a map, through #define and #include", function()
  local gen = (load() and require("articulations.gen"))
  local spec, stats = gen.sfz("extensions/articulations/fixtures/sfz/violins.sfz")
  assert(spec, stats)
  local out = {}
  for i, a in ipairs(spec.arts) do out[i] = a.name .. "=" .. a.m2 .. "/" .. a.out .. "/" .. a.range end
  eq(table.concat(out, " "), "Sustain=10.0/ks=C1/G3-E7 Staccato=11.0/ks=C#1/G3-E7 Pizz=11.A/ks=D1/G3-C7 Tremolo=12.0/ks=D#1/G3-C7 Trill m2=13.0/ks=E1/G3-A6 Col legno=11.C/ks=F1/G3-C7", "the articulations")
  eq(spec.keyswitches .. " " .. spec.default .. " " .. stats.coded, "C1-F1 sustain 6", "rows, default, coded")
  local map = assert(art.maps.parse(gen.text(spec), "violins.art.toml"))
  -- What the library does not say, from the profile.
  local filled = {}
  for _, a in ipairs(map.arts) do
    filled[#filled + 1] = a.tag .. "/" .. tostring(a.class) .. "/" .. tostring(a.mark or a.text)
  end
  eq(table.concat(filled, " "), "nor/long/nil stc/short/staccato pz/short-light/pizz. trm/long-dark/trem. trm2/long-dark/nil clb/short/col legno",
    "tags as the README writes them, classes, marks and texts")
  eq(#map.linked .. " " .. map.linked[1].id .. " " .. table.concat(map.linked[1].cc, ","), "1 dynamics 1,11", "dynamics linked on CC1 and CC11")
end)

test("articulations: :query and :select find notes by their attribute's tag, name and code", function()
  local _, clip = strings()
  paw.ui.focus("pianoroll")
  ex("%art pizz")
  ex("art stc")
  local function count(q) return #paw.query(q) end
  eq(count("note[art=pz]") .. " " .. count("note[art=pizzicato]") .. " " .. count("note[art=11.A]"), "3 3 3", "pizzicato by tag, name and code")
  eq(count("note[art=stc]") .. " " .. count("note[art=staccato]"), "1 1", "the staccato, by tag and by its first word")
  eq(#clip:notes(), 4, "nothing else changed")
end)

test("articulations: a Decent Sampler preset's keyswitch bindings make a map", function()
  local gen = (load() and require("articulations.gen"))
  local spec = assert(gen.ds("extensions/articulations/fixtures/ds/cello.dspreset"))
  local out = {}
  for i, a in ipairs(spec.arts) do out[i] = a.name .. "=" .. a.m2 .. "/" .. a.out end
  eq(table.concat(out, " "), "Sustain=10.0/ks=C1 Spiccato=11.5/ks=C#1 Harmonics=14.0/ks=D1", "the articulations")
  eq(spec.range .. " " .. spec.keyswitches, "C3-C7 C1-D1", "the range and the rows")
end)

test("articulations: a folder of samples named by articulation makes a map played by the attribute", function()
  local gen = (load() and require("articulations.gen"))
  local dir = T.scratch .. "/vsco/Violin"
  for _, f in ipairs({ "Spiccato/Vln_Spic_A4_v1_rr1.wav", "Spiccato/Vln_Spic_C5_v1_rr1.wav", "Sustain/Vln_sus_G3_v1.wav",
    "Sustain/Vln_sus_E7_v1.wav", "Pizzicato/Vln_pizz_D4_v1.wav", "Notes/readme.txt" }) do
    os.execute("mkdir -p '" .. (dir .. "/" .. f):match("^(.*)/") .. "'")
    T.write_file(dir .. "/" .. f, "")
  end
  local spec = assert(gen.folder(dir))
  local out = {}
  for i, a in ipairs(spec.arts) do out[i] = a.name .. "=" .. a.m2 .. "/" .. a.out .. "/" .. tostring(a.range) end
  eq(table.concat(out, " "), "Pizzicato=11.A/attr/D4-D4 Spiccato=11.5/attr/A4-C5 Sustain=10.0/attr/G3-E7", "the folders that hold samples")
  eq(spec.default, "sustain", "sustain by default")
end)

test("articulations: every bank of Reaticulate's factory file reads, nine in ten articulations get a code, and a map goes back to a bank", function()
  local gen = (load() and require("articulations.gen"))
  local text = T.read_file("extensions/articulations/fixtures/reaticulate/factory.reabank")
  local specs, stats = gen.reabank(text)
  eq(stats.banks .. " " .. stats.articulations, "218 1426", "banks and articulations")
  -- 1283 of 1426: 89.97 %, as the design's experiment measured.
  eq(stats.coded >= 0.899 * stats.articulations, true, "coded: " .. stats.coded)
  local bad = {}
  for _, spec in ipairs(specs) do
    local map, err = art.maps.parse(gen.text(spec), spec.file .. ".art.toml")
    if not map then bad[#bad + 1] = err end
  end
  eq(table.concat(bad, "\n"), "", "every map reads")
  local first = assert(art.maps.parse(gen.text(specs[1]), "x.art.toml"))
  eq(first.by_id.pizz.out .. " " .. first.by_id.pizz.code .. " " .. first.by_id["trill-m2-2"].code, "cc32=56 11.A 13.2", "Spitfire's UACC, and the major trill by its icon")
  local back = gen.reabank(gen.to_reabank(first))[1]
  local names = {}
  for i, a in ipairs(back.arts) do names[i] = a.program .. " " .. a.name .. " " .. a.out end
  eq(table.concat(names, ", "):sub(1, 60), "20 legato cc32=20, 1 long cc32=1, 42 spiccato cc32=42, 40 st", "exported and read back")
end)

test("articulations: :art.from-keyswitches turns keyswitch notes and UACC moves into the notes' articulations", function()
  local _, clip = strings({
    { pitch = 26, start = 0, length = 0.25 }, { pitch = 67, start = 0, length = 1 }, { pitch = 69, start = 1, length = 1 },
    { pitch = 28, start = 2, length = 0.25 }, { pitch = 71, start = 2, length = 1 }, { pitch = 72, start = 3, length = 1 },
  })
  paw.ui.focus("pianoroll")
  paw.cmd("art.from-keyswitches")
  eq(codes(clip), "67:11.0 69:11.0 71:11.A 72:11.A", "D1 staccato, E1 pizzicato")
end)

test("articulations: :art.import writes a map per bank, and :art.map binds one by name", function()
  load()
  fresh()
  local track = paw.add_track({ name = "Strings" })
  paw.cursor.set_track(track)
  paw.commands.exec("art.import extensions/articulations/fixtures/reaticulate/factory.reabank")
  local found = art.maps.find("spitfire-chamber-strings/basic-articulations")
  eq(found and found.name, "Basic Articulations", "found by its id")
  paw.commands.exec("art.map spitfire-chamber-strings/basic-articulations")
  eq(art.info(track.id).map, "reaticulate/spitfire-chamber-strings/basic-articulations", "bound by the end of its id")
  eq(art.attr_map(track.id).arts["11.A"].out, "cc32=56", "pizz by UACC")
end)

-- Notation ------------------------------------------------------------------------------

test("articulations: the score shows the articulations as marks and technique text, and marks written in it set them", function()
  local track, clip = strings()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  require("articulations.notation")
  local map = art.map_of(track.id)
  art.set({ { clip = clip.id, place = 1 } }, { attr = map.by_id.staccato.attr })
  art.set({ { clip = clip.id, place = 3 }, { clip = clip.id, place = 4 } }, { attr = map.by_id.pizzicato.attr })
  api.undo_checkpoint()
  local view = require("notation")
  view:edit(clip)
  paw.ui.focus("notation")
  view.cache = nil
  local m = view:layout().measures[1]
  eq(m.staves[1][1].art and m.staves[1][1].art.staccato, true, "a staccato's dot")
  local texts = {}
  for _, mk in ipairs(m.marks) do
    if mk.kind == "technique" then texts[#texts + 1] = mk.value .. "@" .. mk.at end
  end
  eq(table.concat(texts, " "), "pizz.@2", "pizz. where the run starts")
  view:set(nil, 1)
  keys("g'")
  eq(codes(clip), "67:11.0 69:11.0 71:11.A 72:11.A", "a staccato written on the second note makes it staccato")
  keys("g'")
  eq(codes(clip), "67:11.0 69:- 71:11.A 72:11.A", "and taken away, not")
  view:set(nil, 2)
  paw.cmd("notation.tech", { "arco" })
  api.undo_checkpoint()
  eq(codes(clip), "67:11.0 69:- 71:- 72:-", "arco: the default from there")
  paw.ui.hide("notation")
end)

-- Delays and linked controllers ------------------------------------------------------------

test("articulations: delays go from the map into the downgrade map, and K says them", function()
  local track, _, roll = strings()
  local am = art.attr_map(track.id)
  eq(table.concat({ am.delay, am.arts["10.2"].delay, am.arts["11.0"].delay }, " "), "-30 -80 -30", "the instrument's, legato's own, the instrument's again")
  paw.ui.focus("pianoroll")
  paw.commands.exec("art leg")
  local text = {}
  for i, l in ipairs(roll:describe()) do text[i] = type(l) == "table" and l.text or l end
  eq(table.concat(text, "\n"):find("delay         -80ms", 1, true) ~= nil, true, table.concat(text, "\n"))
end)

-- An instrument that starts each articulation's sound late: 20 ms for each
-- key above C1 its last keyswitch was (C1 0, C#1 20, D1 40).
local LATE = [[
local dsp = require("paw.dsp")
local dev = dsp.device { name = "Late", category = "instrument", params = {} }
local sr, art, wait, on, phase = 48000, 0, nil, false, 0
function dev.init(rate) sr = rate end
function dev.process(b)
  for k = 0, b.nevents - 1 do
    local e = b.events[k]
    if e.type == dsp.NOTE_ON and e.key < 36 then
      art = e.key - 24
    elseif e.type == dsp.NOTE_ON then
      wait, on = e.frame + math.floor(art * 20 * sr / 1000), false
    elseif e.type == dsp.NOTE_OFF and e.key >= 36 then
      wait, on = nil, false
    end
  end
  for i = 0, b.frames - 1 do
    if wait and i >= wait then on, wait = true, nil end
    if on then
      phase = phase + 2 * math.pi * 220 / sr
      local v = 0.5 * math.sin(phase)
      b.left[i] = b.left[i] + v
      b.right[i] = b.right[i] + v
    end
  end
  if wait then wait = wait - b.frames end
end
return dev
]]

test("articulations: :art.measure renders each articulation, finds how late it sounds, and :art.measure! writes the delays", function()
  load()
  fresh()
  local dir = T.scratch .. "/art-late"
  os.execute("mkdir -p '" .. dir .. "/devices'")
  T.write_file(dir .. "/devices/late.lua", LATE)
  paw.luadev.add_dir(dir .. "/devices")
  local file = dir .. "/late.art.toml"
  T.write_file(file, table.concat({
    "format = 1", 'name = "Late"', 'range = "C4-C5"', "", "[art]",
    'sustain = { m2 = "10.0", out = "ks=C1" }  # long',
    'staccato = { m2 = "11.0", out = "ks=C#1" }',
    'pizzicato = { m2 = "11.A", out = "ks=D1", delay = "-5ms" }', "" }, "\n"))
  local track = paw.add_track({ name = "Late" })
  track:add_device("lua:late")
  paw.flush()
  art.maps.forget()
  art.bind(track.id, file)
  api.undo_checkpoint()
  paw.cursor.set_track(track)
  local measure = require("articulations.measure")
  local results = measure.measure(track.id)
  -- To the millisecond block the onset falls in: one either way.
  for i, want in ipairs({ 0, 20, 40 }) do
    T.near(results[i].onset or -100, want, 1, results[i].art.id .. "'s onset in ms")
  end
  eq(#api.clip_list(track.id), 0, "the rendering left nothing behind")
  paw.commands.exec("art.measure")
  paw.ui.close()
  paw.commands.exec("art.measure!")
  local text = T.read_file(file)
  local sent = art.attr_map(track.id).arts
  T.near(sent["11.0"].delay, -20, 1, "staccato's delay sent")
  local function written(code) return 'delay = "' .. art.maps.delay_text(sent[code].delay) .. '" }' end
  eq(text:find('staccato = { m2 = "11.0", out = "ks=C#1", ' .. written("11.0"), 1, true) ~= nil, true, text)
  eq(text:find('pizzicato = { m2 = "11.A", out = "ks=D1", ' .. written("11.A"), 1, true) ~= nil, true, "a delay replaced:\n" .. text)
  eq(text:find(written("10.0") .. "  # long", 1, true) ~= nil, true, "a comment kept:\n" .. text)
end)

test("articulations: linked controllers are one lane, written through their curves into every controller", function()
  local track, clip = strings()
  local linked = require("articulations.linked")
  local entry = linked.entry(track.id)
  eq(entry.id .. " " .. table.concat(entry.cc, ","), "dynamics 1,11", "from the map")
  local t = assert(paw.curves.target(linked.uri(clip.id, entry)))
  eq(t.name(), "Dynamics (CC1 CC11) · line", "one lane")
  eq(t.flat(), 0.7, "standing at the instrument's default")
  t.write({ { beat = 2, value = 0.5 }, { beat = 4, value = 1 } })
  api.undo_checkpoint()
  local moves = {}
  for _, c in ipairs(clip:controls()) do moves[#moves + 1] = string.format("%g:cc%d=%d", c.start, c.number, math.floor(c.value * 127 + 0.5)) end
  eq(table.concat(moves, " "), "0:cc1=89 0:cc11=104 2:cc1=64 2:cc11=89 4:cc1=127 4:cc11=127", "both controllers, from the default at the start")
  local back = {}
  for i, q in ipairs(t.points()) do back[i] = string.format("%g=%.2f", q.beat, q.value) end
  eq(table.concat(back, " "), "0=0.70 2=0.50 4=1.00", "read back as one")
  paw.ui.focus("pianoroll")
  keys("u")
  eq(#clip:controls(), 0, "one undo step")
  keys("\\c")
  eq(paw.ui.focused, "curve", "\\c opens it in the curve view")
  paw.ui.hide("curve")
end)

test("articulations: K on a note with an articulation says it once, in the map's words or the attribute's", function()
  local track, clip, roll = strings()
  local map = art.map_of(track.id)
  art.set({ { clip = clip.id, place = 1 } }, { attr = map.by_id.staccato.attr })
  api.undo_checkpoint()
  roll:set(67, 0)
  local function said()
    local out = {}
    for _, line in ipairs(roll:describe()) do
      local text = type(line) == "table" and line.text or line
      if text:find("articulation", 1, true) then out[#out + 1] = text end
    end
    return out
  end
  local lines = said()
  eq(#lines, 1, "one line about it with a map: " .. table.concat(lines, " | "))
  eq(lines[1]:find(map.by_id.staccato.name, 1, true) ~= nil, true, "the map's name for it")
  art.unbind(track.id)
  api.undo_checkpoint()
  lines = said()
  eq(#lines, 1, "and one without: " .. table.concat(lines, " | "))
end)

-- Plugin instruments ------------------------------------------------------------------------

test("articulations: every map shipped with paw reads, and the core takes what it sends", function()
  load()
  fresh()
  local track = paw.add_track({ name = "Any" })
  paw.flush()
  local n = 0
  for _, f in ipairs(art.maps.list()) do
    if f.file:find("extensions/articulations/articulations/", 1, true) then
      local map, err = art.maps.load(f.file, f.id)
      eq(err, nil, f.id .. " reads")
      local ok, why = pcall(api.track_set, track.id, "attr_map", art.compile(map))
      eq(ok, true, f.id .. ": the core takes its downgrade map: " .. tostring(why))
      n = n + 1
    end
  end
  eq(n >= 6, true, "the maps found: " .. n)
end)

test("articulations: a plugin's map binds itself, names keys as its vendor does, and :art.shift moves its keyswitches", function()
  local track, clip, roll = strings()
  art.unbind(track.id)
  api.undo_checkpoint()
  local commands = require("articulations.commands")
  -- What device_get says of MODO BASS 2 through yabridge.
  local modo = { name = "MODO BASS 2", plugin = { format = "vst3", id = "ABCDEF0123", name = "MODO BASS 2", vendor = "IK Multimedia" } }
  eq(art.maps.plugin_matches("clap:MODO BASS 2", modo), false, "another format does not match")
  commands.auto_map(track.id, modo)
  eq(commands.auto_map(track.id, modo), nil, "a track with a map keeps it")
  paw.ui.focus("pianoroll")
  keys("u")
  eq(art.info(track.id), nil, "the binding is its own undo step")
  keys(":art.map sine-cc<CR>")
  eq(art.attr_map(track.id).arts["11.A"].out, "cc58=71", "a range of values sends its middle")

  -- A vendor whose middle C is C3: its C0 is paw's C1.
  local file = T.scratch .. "/c3.art.toml"
  T.write_file(file, 'format = 1\nmiddle_c = "C3"\nrange = "C3-C6"\n[art]\nsustain = { m2 = "10.0", out = "ks=C0" }\npizzicato = { m2 = "11.A", out = "ks=D0:127" }\n')
  art.maps.forget()
  keys(":art.map " .. file .. "<CR>")
  eq(art.attr_map(track.id).arts["11.A"].out, "ks=D1:127", "sent in paw's names")
  eq(table.concat(art.map_of(track.id).range, "-"), "60-96", "its range read the same way")
  roll:set(67, 0)
  keys(":art pizzicato<CR>")
  keys(":art.shift -2<CR>")
  eq(art.attr_map(track.id).arts["11.A"].out, "ks=C1:127", "shifted two keys down")
  local text = {}
  for i, l in ipairs(roll:describe()) do text[i] = type(l) == "table" and l.text or l end
  eq(table.concat(text, "\n"):find("sent as ks=C1:127 (ks=D0:127 in the map)", 1, true) ~= nil, true, table.concat(text, "\n"))
  keys("u")
  eq(art.attr_map(track.id).arts["11.A"].out, "ks=D1:127", "u takes the shift back")
  eq(codes(clip):sub(1, 7), "67:11.A", "and leaves the note")
end)

test("articulations: :art.from-keyswitches reads a controller whose values choose articulations, by ranges", function()
  local track, clip = strings()
  art.bind(track.id, "sine-cc")
  api.undo_checkpoint()
  clip:set_controls({
    { start = 0, type = "cc", number = 58, value = 70 / 127 },   -- pizzicato, 64-79
    { start = 2, type = "cc", number = 58, value = 33 / 127 },   -- staccato, 32-47
    { start = 0, type = "cc", number = 1, value = 0.5 },         -- dynamics stay
  })
  api.undo_checkpoint()
  paw.ui.focus("pianoroll")
  keys(":art.from-keyswitches<CR>")
  eq(codes(clip), "67:11.A 69:11.A 71:11.0 72:11.0", "the notes after each move")
  eq(#clip:controls(), 1, "the switches go, the dynamics stay")
end)

test("articulations: a in insert mode gives the note under the pencil an articulation of the map", function()
  local _, clip = strings()
  keys("iastaccato<CR><Esc>")
  eq(codes(clip):match("^%S+"), "67:" .. art.m2.code(art.lookup(art.map_of(clip:get().track), "staccato").attr), "the first note, by the map's name")
  keys("u")
  eq(codes(clip):match("^%S+"), "67:-", "one undo step")
end)
