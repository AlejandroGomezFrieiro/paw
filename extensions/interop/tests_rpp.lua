-- Tests of interop's REAPER projects, and of the commands both formats go
-- through, run by tests/suite.lua (`paw --clean -l tests/suite.lua rpp`).
local T = ...
local paw = require("paw")
local api = paw.api
local test, eq, near, fails = T.test, T.eq, T.near, T.fails

local HERE = "extensions/interop"
local FIXTURES = HERE .. "/fixtures/rpp/"

local rpp
local function load()
  if not rpp then
    paw.ext.load(HERE)
    rpp = require("interop.rpp")
  end
  return rpp
end

local function has(kind)
  for _, t in ipairs(api.device_types()) do
    if t.kind == kind then return true end
  end
  return false
end

--- A mono 16-bit WAV of a sine.
local function write_wav(path, seconds, freq, level)
  local rate = 44100
  local n = math.floor(seconds * rate)
  local samples = {}
  for i = 0, n - 1 do
    local v = math.floor(math.sin(2 * math.pi * freq * i / rate) * (level or 0.5) * 32767 + 0.5)
    if v < 0 then v = v + 65536 end
    samples[#samples + 1] = string.char(v % 256, math.floor(v / 256))
  end
  local data = table.concat(samples)
  local b64 = paw.bytes
  local function u16(x) return string.char(x % 256, math.floor(x / 256) % 256) end
  T.write_file(path, "RIFF" .. b64.le32(36 + #data) .. "WAVEfmt " .. b64.le32(16) .. u16(1) .. u16(1)
    .. b64.le32(rate) .. b64.le32(rate * 2) .. u16(2) .. u16(16) .. "data" .. b64.le32(#data) .. data)
end

--- A folder in the scratch directory holding a copy of a fixture, with the
--- media it refers to made beside it.
local folders = 0
local function project_dir(fixture)
  folders = folders + 1
  local dir = T.scratch .. "/rpp" .. folders
  os.execute("mkdir -p '" .. dir .. "/media'")
  T.write_file(dir .. "/" .. fixture, T.read_file(FIXTURES .. fixture))
  write_wav(dir .. "/media/tone.wav", 2, 440)
  local midi = require("interop.rpp.midi")
  T.write_file(dir .. "/media/riff.mid", midi.write_smf({
    { tick = 0, length = 240, pitch = 50, velocity = 90 },
    { tick = 480, length = 480, pitch = 52, velocity = 70 },
  }, 480, 100))
  return dir
end

local function by_name(name)
  local t = paw.track(name)
  assert(t, "no track " .. name)
  return t
end

local function items_of(report, group)
  for _, g in ipairs(report:data()) do
    if g.name == group then return g.items end
  end
  return {}
end

local function has_item(report, group, pattern)
  for _, text in ipairs(items_of(report, group)) do
    if text:find(pattern, 1, true) then return true end
  end
  return false
end

-- The format ------------------------------------------------------------------------

test("rpp: a file parses and writes back byte for byte", function()
  local fmt = load().format
  local text = T.read_file(FIXTURES .. "format.rpp")
  eq(fmt.write(fmt.parse(text)), text, "LF file")
  local crlf = text:gsub("\n", "\r\n")
  eq(fmt.write(fmt.parse(crlf)), crlf, "CRLF file")
  -- Odd spacing, a missing last line ending, an unclosed block.
  local odd = "<A  1   \"two  words\"\n\t B\t'x y' ``\n   >  \n<C\n  D 1"
  eq(fmt.write(fmt.parse(odd)), odd, "odd spacing")
end)

test("rpp: tokens, quotes and numbers", function()
  local fmt = load().format
  local doc = fmt.parse(T.read_file(FIXTURES .. "format.rpp"))
  local p = doc.project
  eq(p:arg(1), "0.1", "header")
  eq(p:arg(2), "7.55/linux-x86_64", "quoted header token")
  eq(p:getn("TEMPO", 1), 135, "TEMPO")
  local markers = p:all("MARKER")
  eq(markers[2]:arg(3), "Two words", "double quotes")
  eq(markers[3]:arg(3), 'Say "hi"', "single quotes")
  eq(markers[4]:arg(3), [[It's "both"]], "backticks")
  eq(markers[1]:arg(3), "", "empty string")
  local track = p:child("TRACK")
  eq(track:get("NAME"), "Lead Guitar", "track name")
  eq(track:child("AUXRECV"):arg(10), "-1:U", "bare token with a colon")
  eq(track:child("AUXRECV"):arg(13), "", "'' is an empty string")
  -- Writing: quoting only what needs it, numbers as REAPER does.
  eq(fmt.quote("abc"), "abc", "bare")
  eq(fmt.quote("a b"), '"a b"', "spaces")
  eq(fmt.quote(""), '""', "empty")
  eq(fmt.quote('say "hi"'), "'say \"hi\"'", "double quote inside")
  eq(fmt.quote([[it's "x"]]), "`it's \"x\"`", "both quotes inside")
  eq(fmt.number(4), "4", "integer")
  eq(fmt.number(0.70794578438414), "0.70794578438414", "14 decimals")
  eq(fmt.number(441.6), "441.6", "shortest form")
  eq(fmt.number(1 / 3), "0.33333333333333", "rounded")
  eq(fmt.number(-0.5), "-0.5", "negative")
end)

test("rpp: a changed line is rewritten, the rest stays as read", function()
  local fmt = load().format
  local text = T.read_file(FIXTURES .. "format.rpp")
  local doc = fmt.parse(text)
  doc.project:set("TEMPO", 96, 3, 4, 0)
  local track = doc.project:child("TRACK")
  track:set("NAME", "Rhythm Guitar")
  track:add(fmt.line("MUTESOLO", 1, 0, 0), 2)
  local out = fmt.write(doc)
  local want = text:gsub("  TEMPO 135 4 4 0\n", "  TEMPO 96 3 4 0\n")
    :gsub('    NAME "Lead Guitar"\n', '    NAME "Rhythm Guitar"\n    MUTESOLO 1 0 0\n')
  eq(out, want, "only the changed lines differ")
  -- A tree built from nothing.
  local new = fmt.document()
  local root = new:add(fmt.block("REAPER_PROJECT", 0.1, "7.0/x", 0))
  root:add(fmt.line("NAME", "two words"))
  root:add(fmt.block("SOURCE", "WAVE")):add(fmt.line("FILE", "a.wav")):quoted(1)
  eq(fmt.write(new), '<REAPER_PROJECT 0.1 7.0/x 0\n  NAME "two words"\n  <SOURCE WAVE\n    FILE "a.wav"\n  >\n>\n', "new tree")
  -- And it reads back as the same tree.
  local again = fmt.parse(fmt.write(new))
  eq(again.project:child("SOURCE"):get("FILE"), "a.wav", "read back")
end)

test("rpp: base64 blocks and plugin chunks", function()
  local r = load()
  local b64 = paw.bytes
  local fx = require("interop.rpp.fx")
  for _, s in ipairs({ "", "a", "ab", "abc", "abcd", string.rep("\0\255\128", 100) }) do
    eq(b64.unbase64(b64.base64(s)), s, "base64 round trip of " .. #s .. " bytes")
  end
  local doc = r.parse(T.read_file(FIXTURES .. "format.rpp"))
  local vst = doc.project:child("TRACK"):child("FXCHAIN"):child("VST")
  local groups = vst:data_groups()
  eq(#groups, 3, "header, state, trailer")
  local parts = assert(fx.vst_parts(vst))
  eq(#parts.data, 24, "state size from the header")
  local state = assert(fx.vst3_state_from_reaper(parts.data))
  eq(state, b64.le32(4) .. "abcd" .. b64.le32(4) .. "wxyz", "paw's VST3 state")
  eq(fx.vst3_state_to_reaper(state), parts.data, "and back")
  -- Data lines are rewritten in groups of 128 characters.
  local block = r.block("STATE")
  block:set_data({ string.rep("A", 300), "QUJD" })
  eq(#block.children, 4, "lines")
  eq(#block.children[1].tokens[1], 128, "first line width")
  eq(block:data_groups()[1], string.rep("A", 300), "first group")
  eq(block:data_groups()[2], "QUJD", "second group")
  -- MIDI events in the source, sysex included.
  local midi = require("interop.rpp.midi")
  local src = midi.read_source(doc.project:child("TRACK"):child("ITEM"):child("SOURCE"))
  eq(#src.notes, 1, "one note")
  eq(src.notes[1].length, 480, "note length in ticks")
  eq(src.length, 960, "source length")
  eq(src.other["sysex and text events"], 1, "the sysex is counted")
  eq(fx.split_display("VSTi: Ugritone Drums (Ugritone) (32 out)") == "VSTi", true, "prefix")
  local _, name, vendor = fx.split_display("VSTi: Ugritone Drums (Ugritone) (32 out)")
  eq(name .. "|" .. vendor, "Ugritone Drums|Ugritone", "name and vendor")
end)

-- Import ------------------------------------------------------------------------------

test("rpp: import, track by track and clip by clip", function()
  local r = load()
  local dir = project_dir("song.rpp")
  local result = r.import(dir .. "/song.rpp")
  local report = result.report
  paw.flush()
  local p = paw.project.get()
  eq(p.tempo, 90, "first tempo")
  eq(p.sig_num .. "/" .. p.sig_den, "3/4", "time signature")
  -- The tempo envelope: 90 for 100 seconds (150 beats), then 120.
  local points = paw.tempo.points()
  eq(#points, 2, "the tempo change comes in")
  near(points[2].beat, 150, 1e-9, "at its beat")
  eq(points[2].bpm, 120, "with its tempo")
  eq(p.name, "song", "name")
  local tr = paw.transport.get()
  eq(tr.loop_enabled, true, "loop on")
  near(tr.loop_start, 3, 1e-9, "loop start (2 s at 90 BPM)")
  near(tr.loop_end, 9, 1e-9, "loop end")
  near(paw.master.volume, -6.0206, 1e-3, "master volume")

  local names = {}
  for i, t in ipairs(paw.tracks()) do names[i] = t.name end
  eq(table.concat(names, ","), "Band,Keys,Gtr DI,Verb", "tracks in order")
  local band, keys, gtr, verb = by_name("Band"), by_name("Keys"), by_name("Gtr DI"), by_name("Verb")

  -- Band: a folder with automation and plugins.
  near(band.volume, -3, 1e-3, "Band volume")
  near(band.pan, 0.25, 1e-9, "Band pan")
  eq(band.output, nil, "Band to the master")
  eq(band.input, "1", "Band input")
  eq(band.monitor, true, "Band monitoring")
  local vol = band:lane("volume")
  local pts = vol:points()
  eq(#pts, 4, "volume points")
  near(pts[1][1], 0, 1e-9, "point 1 beat")
  near(pts[1][2], 0, 1e-3, "point 1 is 0 dB (amplitudes, whatever VOLTYPE says)")
  near(pts[2][1], 6, 1e-9, "point 2 beat (4 s)")
  near(pts[2][2], -24.08, 0.01, "point 2 dB")
  eq(vol.enabled, true, "volume lane on")
  local vshapes = api.lane_shapes(vol.id)
  eq(#vshapes, 1, "one stretch that is not straight")
  near(vshapes[1].beat, 9, 1e-9, "from the point at 6 s")
  eq(vshapes[1].shape, "smooth", "REAPER's slow start and end is smooth")
  local pan = band:lane("pan")
  eq(pan.enabled, false, "pan lane off, as in REAPER")
  local pp = pan:points()
  eq(#pp, 2, "pan points")
  near(pp[1][2], -0.5, 1e-9, "pan +0.5 in REAPER's envelope is left")
  near(pp[2][1], 3, 1e-9, "the next point")
  near(pp[2][2], 0.5, 1e-9, "the next value")
  eq(api.lane_shapes(pan.id)[1].shape, "hold", "a square point holds until the next")
  eq(band.color, "#418000", "track colour from PEAKCOL")
  if has("lv2:http://lsp-plug.in/plugins/lv2/gate_mono") then
    local gate = band:devices()[1]
    eq(gate.kind, "lv2:http://lsp-plug.in/plugins/lv2/gate_mono", "LV2 plugin")
    eq(gate.bypass, true, "bypassed as in REAPER")
    near(gate.params.at, 7.5, 1e-4, "parameter by port symbol")
    near(gate.params.rt, 120, 1e-3, "another parameter")
    eq(has_item(report, "Plugin settings", "not_a_port"), true, "unknown parameter reported")
  else
    eq(has_item(report, "Plugins left as placeholders", "LSP Gate Mono"), true, "gate left behind")
  end
  local holders = band.meta.rpp_placeholders
  local amp = holders[#holders]
  eq(amp.name, "VST3: Nowhere Amp (Nobody)", "placeholder named after the plugin")
  eq(amp.reason, "not installed here", "and why")
  eq(amp.rpp:find("<VST", 1, true) ~= nil, true, "its REAPER text is kept")
  eq(has_item(report, "Plugin parameter automation", "Band"), true, "parameter envelope reported")

  -- Keys: in the folder; MIDI clips.
  eq(keys.output, band.id, "Keys feeds the folder")
  local clips = keys:clips()
  eq(#clips, 3, "Keys clips")
  local a = clips[1]:get()
  eq(a.name, "Chords A", "clip name")
  near(a.start, 3, 1e-9, "clip start (2 s)")
  near(a.length, 6, 1e-9, "clip length (4 s)")
  local notes = clips[1]:notes()
  eq(#notes, 2, "muted note left out")
  eq(notes[1].pitch, 60, "first pitch")
  near(notes[1].start, 0, 1e-9, "first start")
  near(notes[1].length, 0.5, 1e-9, "first length")
  eq(notes[1].velocity, 100, "first velocity")
  eq(notes[2].pitch, 64, "second pitch")
  near(notes[2].start, 1, 1e-9, "second start")
  near(notes[2].length, 1, 1e-9, "second length")
  eq(notes[2].meta.channel, 2, "MIDI channel kept with the note")
  local moves = clips[1]:controls()
  eq(#moves, 2, "a controller and the pitch wheel")
  eq(moves[1].type .. moves[1].number, "cc7", "CC 7")
  near(moves[1].value, 100 / 127, 1e-9, "its value")
  eq(moves[2].type, "bend", "the pitch wheel")
  near(moves[2].start, 2.25, 1e-9, "at tick 2160")
  near(moves[2].value, 0.25, 1e-9, "a quarter up")
  local b = clips[2]:get()
  near(b.start, 12, 1e-9, "looped clip start")
  near(b.length, 6, 1e-9, "looped clip length")
  eq(b["loop"], true, "a looped item is a looped clip")
  near(b.loop_length, 0.75, 1e-9, "a pass is 960 ticks at 120 BPM = 0.75 beats at 90")
  near(b.loop_start, 0, 1e-9, "from the clip's start")
  local looped = clips[2]:notes()
  eq(#looped, 1, "the source once")
  near(looped[1].length, 0.375, 1e-9, "note length at the source's own tempo")
  local c = clips[3]:get()
  eq(c.muted, true, "muted item")
  near(c.start, 18, 1e-9, "MIDI file clip start")
  local riff = clips[3]:notes()
  eq(#riff, 2, "notes from the .mid file")
  near(riff[2].start, 1, 1e-9, "ticks of the .mid file are beats")
  near(riff[2].length, 1, 1e-9, "and lengths")

  -- Gtr DI: the last child; audio clips.
  eq(gtr.output, band.id, "Gtr DI feeds the folder")
  eq(gtr.mute, true, "muted")
  eq(gtr.solo, true, "soloed")
  eq(gtr.armed, true, "armed")
  near(gtr.pan, -1, 1e-9, "panned left")
  local g = gtr:clips()
  eq(#g, 2, "an audio clip and a looped one")
  local di = g[1]:get()
  eq(di.name, "DI take", "the active take")
  eq(di.file:match("media/tone%.wav$") ~= nil, true, "file relative to the project")
  near(di.offset, 0.5, 1e-9, "start in source")
  near(di.gain, -12.0412, 1e-3, "item volume times take volume")
  near(di.start, 1.5, 1e-9, "start")
  near(di.length, 1.5, 1e-9, "length")
  near(di.fade_in, 0.015, 1e-9, "a fade in of 10 ms at 90 BPM")
  near(di.fade_out, 0.015, 1e-9, "and a fade out")
  local l = g[2]:get()
  eq(l.file:match("media/tone%.wav$") ~= nil, true, "found in the recording folder")
  near(l.start, 6, 1e-9, "looped clip start")
  near(l.length, 4.5, 1e-9, "the whole item")
  near(l.offset, 1, 1e-9, "1 s into the file")
  eq(l["loop"], true, "it loops")
  near(l.loop_length, 3, 1e-9, "the whole file (2 s) again and again")
  near(l.loop_start, -1.5, 1e-9, "which starts 1 s before the clip")
  eq(l.muted, true, "muted")

  -- Verb: receives become sends on the senders.
  near(verb.volume, -6.0206, 1e-3, "Verb volume")
  local bs = band.sends
  eq(#bs, 1, "Band sends")
  eq(bs[1].target, verb.id, "to Verb")
  near(bs[1].level, -6.0206, 1e-3, "send level")
  eq(#keys.sends, 1, "Keys send")
  near(keys.sends[1].level, -12.0412, 1e-3, "pre-fader send level")
  eq(keys.sends[1].pre, true, "before the fader")
  eq(#gtr.sends, 0, "a muted send is left out")

  -- Markers and regions, as paw.markers has them.
  local marks = paw.markers.list()
  eq(#marks, 2, "a marker and a region")
  eq(marks[1].name, "Verse", "marker")
  near(marks[1].beat, 6, 1e-9, "marker beat")
  eq(marks[1].length, nil, "a marker has no length")
  eq(marks[2].name, "Big Chorus", "region")
  near(marks[2].beat, 12, 1e-9, "region start")
  near(marks[2].length, 6, 1e-9, "region length")
  -- The master's JSFX is a placeholder.
  eq(paw.master.meta.rpp_placeholders[1].format, "JSFX", "master placeholder")
end)

test("rpp: what is not carried over is reported, grouped", function()
  local r = load()
  local dir = project_dir("song.rpp")
  local report = r.import(dir .. "/song.rpp").report
  local function check(group, pattern)
    eq(has_item(report, group, pattern), true, group .. ": " .. pattern)
  end
  check("Envelope curve shapes (fast start, fast end and Bezier made straight or smooth)", "Band volume")
  check("Plugins left as placeholders", "Nowhere Amp")
  check("Plugins left as placeholders", "JS: loser/masterLimiter")
  check("Plugin parameter automation", "Band: 2 (its plugin did not come across)")
  check("MIDI other than notes", "sysex")
  eq(has_item(report, "MIDI other than notes", "CC"), false, "controllers come across")
  check("Muted MIDI notes (left out)", "Chords A")
  check("Play rate of MIDI items (played at 1x)", "rate 1.5")
  check("Item volume on MIDI items", "riff.mid")
  check("Takes other than the active one (left out)", "Gtr DI")
  check("Missing media", "/nonexistent/folder/lost.wav")
  check("Tracks with the master/parent send off (here they still play through their output)", "Verb")
  check("Muted sends (left out)", "Gtr DI -> Verb")
  local text = report:text()
  eq(text:find("Not carried over from song.rpp", 1, true) ~= nil, true, "titled")
  eq(report:text(1):find("%.%.%. and %d+ more") ~= nil, true, "long groups are shortened")
end)

test("rpp: MIDI timing follows the project tempo", function()
  local r = load()
  local fmt = r.format
  -- The same item at three tempos: 1.5 s in, a note on beat 2 of the item.
  for _, bpm in ipairs({ 60, 90, 137 }) do
    local doc = fmt.parse(table.concat({
      "<REAPER_PROJECT 0.1 \"7.55\" 0",
      "  TEMPO " .. bpm .. " 4 4",
      "  <TRACK",
      "    NAME M",
      "    <ITEM",
      "      POSITION 1.5",
      "      LENGTH 3",
      "      SOFFS 0.25",
      "      <SOURCE MIDI",
      "        HASDATA 1 480 QN",
      "        E 480 90 3c 64",
      "        E 240 80 3c 00",
      "        E 2000 b0 7b 00",
      "      >",
      "    >",
      "  >",
      ">",
    }, "\n"))
    r.format.save(doc, T.scratch .. "/tempo.rpp")
    r.import(T.scratch .. "/tempo.rpp")
    local clip = paw.track("M"):clips()[1]
    local beats = bpm / 60
    near(clip.start, 1.5 * beats, 1e-9, bpm .. " BPM: item start")
    near(clip.length, 3 * beats, 1e-9, bpm .. " BPM: item length")
    local n = clip:notes()[1]
    -- Tick 480 is beat 1 of the source; the take starts 0.25 s into it.
    near(n.start, 1 - 0.25 * beats, 1e-9, bpm .. " BPM: note start")
    near(n.length, 0.5, 1e-9, bpm .. " BPM: note length")
  end
end)

test("rpp: an envelope's points become an automation lane", function()
  local r = load()
  local doc = r.parse(table.concat({
    "<REAPER_PROJECT 0.1 \"7.55\" 0",
    "  TEMPO 120 4 4",
    "  <TRACK",
    "    NAME E",
    "    <VOLENV2",
    "      ACT 1 -1",
    "      PT 0 1 0",
    "      PT 1 0.5 0",
    "      PT 2 0 0",
    "    >",
    "  >",
    ">",
  }, "\n"))
  r.format.save(doc, T.scratch .. "/env.rpp")
  r.import(T.scratch .. "/env.rpp")
  local lane = paw.track("E"):lane("volume")
  local pts = lane:points()
  eq(#pts, 3, "points")
  near(pts[2][1], 2, 1e-9, "1 s is beat 2 at 120")
  near(pts[2][2], -6.0206, 1e-3, "amplitude 0.5 is -6 dB")
  eq(pts[3][2], -120, "silence is the bottom of the range")
end)

test("rpp: a parameter envelope finds its parameter by the plugin's own id", function()
  load()
  local param_of = require("interop.rpp.import").param_of
  local params = { { key = "a", id = "10" }, { key = "b", id = "2683833795" }, { key = "c", id = "c" } }
  eq(param_of("1", params).key, "b", "by place, from 0")
  eq(param_of("0:-1611133501", params).key, "b", "REAPER's signed id wins over the place")
  eq(param_of("1:10", params).key, "a", "an id that is not where it was is still found")
  eq(param_of("2:c", params).key, "c", "a name after the colon that matches")
  eq(param_of("2:wet", params), nil, "REAPER's own parameter is none of the plugin's")
  eq(param_of("7", params), nil, "a place past the end")
end)

test("rpp: plugin parameter lanes go to REAPER with the plugin's own ids, and come back", function()
  local r = load()
  local kind
  for _, t in ipairs(api.device_types()) do
    if not kind and t.format == "clap" and t.name == "Limiter Stereo" then kind = t.kind end
  end
  if not kind then return "skipped: test plugins not found" end
  T.fresh()
  local track = paw.add_track({ name = "Lim" })
  track:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 4 } } })
  local fx = track:add_device(kind)
  local gain = api.device_param(fx.id, "input_gain")
  api.lane_add(track.id, { target = "param", device = fx.id, param = "input_gain", points = { { 0, gain.min }, { 4, gain.max } } })
  r.export(T.scratch .. "/ids.rpp")
  local n = tonumber(gain.id)
  local ident = string.format("%d", n >= 2 ^ 31 and n - 2 ^ 32 or n)
  local text = T.read_file(T.scratch .. "/ids.rpp")
  eq(text:find("<PARMENV " .. (gain.index - 1) .. ":" .. ident .. " ", 1, true) ~= nil, true,
    "the place and the signed id, as REAPER writes them")
  T.fresh()
  r.import(T.scratch .. "/ids.rpp")
  local lanes = api.lane_list(paw.track("Lim").id)
  eq(#lanes, 1, "the lane comes back")
  eq(lanes[1].param, "input_gain", "on the same parameter")
end)

-- Commands --------------------------------------------------------------------------

test("interop: :import, :e, :export and :w take REAPER and DAWproject files, their ending choosing the format", function()
  load()
  local dir = project_dir("song.rpp")
  T.write_file(dir .. "/studio.dawproject", T.read_file(HERE .. "/fixtures/dawproject/studio.dawproject"))
  for _, f in ipairs({ { "song.rpp", "rpp", "<REAPER_PROJECT" }, { "studio.dawproject", "dawproject", "PK" } }) do
    local file, ext, head = dir .. "/" .. f[1], f[2], f[3]
    paw.project.new()
    paw.commands.exec("import " .. file)
    eq(#paw.tracks(), 4, ":import " .. ext)
    paw.commands.exec("import " .. file)
    eq(#paw.tracks(), 8, ":import adds the tracks of " .. ext)
    paw.commands.exec("e " .. file)
    eq(#paw.tracks(), 8, ":e leaves an unsaved project alone")
    paw.project.new()
    paw.commands.exec("e " .. file)
    eq(#paw.tracks(), 4, ":e " .. ext .. " opens it as the project")
    paw.commands.exec("export " .. dir .. "/out." .. ext)
    eq(T.read_file(dir .. "/out." .. ext):sub(1, #head), head, ":export " .. ext)
    paw.commands.exec("w " .. dir .. "/out2." .. ext)
    eq(T.read_file(dir .. "/out2." .. ext):sub(1, #head), head, ":w " .. ext)
  end
  paw.commands.exec("export " .. dir .. "/ref.dawproject embed=false")
  local files = paw.zip.read(T.read_file(dir .. "/ref.dawproject"))
  eq(files["audio/loop.wav"], nil, "embed=false leaves the audio out")
  -- Other files still go to the original commands.
  paw.commands.exec("w " .. dir .. "/song")
  eq(#T.read_file(dir .. "/song/project.toml") > 0, true, "w song saves as before")
  T.write_file(dir .. "/broken.dawproject", "not a zip")
  paw.commands.exec("import " .. dir .. "/broken.dawproject")
  eq(#paw.tracks(), 4, "a broken file leaves the project alone")
  eq(paw.formats.get("rpp").project and paw.formats.get("dawproject").project, true, "both are formats of whole projects")
end)

-- Export ------------------------------------------------------------------------------

--- The project as plain data, for comparing two projects.
local function describe()
  local p = paw.project.get()
  local tr = paw.transport.get()
  local out = {
    tempo = p.tempo, sig = p.sig_num .. "/" .. p.sig_den,
    loop = tr.loop_enabled and string.format("%.6f-%.6f", tr.loop_start, tr.loop_end) or "off",
    master = string.format("%.4f %.4f %s", paw.master.volume, paw.master.pan, tostring(paw.master.mute)),
    tracks = {},
  }
  local name_of = {}
  for _, t in ipairs(paw.tracks()) do name_of[t.id] = t.name end
  for _, t in ipairs(paw.tracks()) do
    local g = t:get()
    local d = {
      string.format("%s vol %.4f pan %.4f mute %s solo %s armed %s out %s input %s monitor %s colour %s",
        g.name, g.volume, g.pan, tostring(g.mute), tostring(g.solo), tostring(g.armed),
        tostring(name_of[g.output]), tostring(g.input), tostring(g.monitor), tostring(g.color)),
    }
    for _, s in ipairs(g.sends) do d[#d + 1] = string.format("send %s %.4f pre %s", name_of[s.target], s.level, tostring(s.pre)) end
    for _, lane in ipairs(t:lanes()) do
      local l = lane:get()
      local pts = {}
      for _, pt in ipairs(lane:points()) do pts[#pts + 1] = string.format("%.6f:%.4f", pt[1], pt[2]) end
      for _, s in ipairs(api.lane_shapes(l.id)) do pts[#pts + 1] = string.format("%s@%.6f", s.shape, s.beat) end
      d[#d + 1] = string.format("lane %s %s %s %s", l.target, tostring(l.param), tostring(l.enabled), table.concat(pts, " "))
    end
    for _, dev in ipairs(t:devices()) do
      local keys = {}
      for k in pairs(dev.params) do keys[#keys + 1] = k end
      table.sort(keys)
      local params = {}
      for _, k in ipairs(keys) do params[#params + 1] = string.format("%s=%.4f", k, dev.params[k]) end
      d[#d + 1] = string.format("device %s bypass %s %s", dev.kind, tostring(dev.bypass), table.concat(params, ","))
    end
    for _, c in ipairs(t:clips()) do
      local cg = c:get()
      local line = string.format("clip %s %s %.6f+%.6f muted %s", cg.kind, cg.name, cg.start, cg.length, tostring(cg.muted))
      if cg["loop"] then line = line .. string.format(" loop %.6f+%.6f", cg.loop_start, cg.loop_length) end
      if cg.kind == "audio" then
        line = line .. string.format(" %s offset %.6f gain %.4f fades %.6f %.6f stretch %.6f pitch %.4f", cg.file,
          cg.offset, cg.gain, cg.fade_in, cg.fade_out, cg.stretch, cg.pitch)
      else
        for _, n in ipairs(c:notes()) do
          line = line .. string.format(" [%d %.6f %.6f %d %s]", n.pitch, n.start, n.length, n.velocity,
            tostring(n.meta and n.meta.channel))
        end
        for _, m in ipairs(c:controls()) do
          line = line .. string.format(" {%s %s %s %s %.6f %.3f}", m.type, tostring(m.number or m.program),
            tostring(m.key), tostring(m.bank), m.start, m.value)
        end
      end
      d[#d + 1] = line
    end
    out.tracks[#out.tracks + 1] = table.concat(d, "\n  ")
  end
  return out
end

local function same(a, b)
  for _, key in ipairs({ "tempo", "sig", "loop", "master" }) do eq(b[key], a[key], key) end
  eq(#b.tracks, #a.tracks, "number of tracks")
  for i = 1, #a.tracks do eq(b.tracks[i], a.tracks[i], "track " .. i) end
end

local function build(dir)
  T.fresh()
  paw.project.tempo = 100
  paw.project.sig_num = 3
  paw.project.sig_den = 4
  paw.transport.loop_start, paw.transport.loop_end = 3, 12
  paw.transport.loop_enabled = true
  paw.master.volume = -2
  paw.master.pan = 0.1
  local bus = paw.add_track({ name = "Drum Bus", volume = -1.5 })
  local kick = paw.add_track({ name = "Kick", output = bus, pan = -0.2 })
  local snare = paw.add_track({ name = "Snare", output = bus, volume = -4 })
  local keys = paw.add_track({ name = "Keys", volume = -6, pan = 0.3 })
  local verb = paw.add_track({ name = "Verb" })
  local gtr = paw.add_track({ name = "Gtr" })
  kick.mute = true
  snare.solo = true
  keys.armed = true
  keys.color = "#3a7bd5"
  bus.color = "#e04020"
  keys:send(verb, -9)
  snare:send(verb, -15.5)
  api.track_set(snare.id, "sends", { { target = verb.id, level = -15.5, pre = true } })
  kick:add_clip({ name = "kick", start = 0, length = 3, notes = {
    { pitch = 36, start = 0, length = 0.25, velocity = 120 },
    { pitch = 36, start = 1.5, length = 0.25, velocity = 90, meta = { channel = 10 } },
  } })
  local chords = keys:add_clip({ name = "chords", start = 3, length = 6, notes = {
    { pitch = 60, start = 0, length = 2, velocity = 80 }, { pitch = 64, start = 0, length = 2, velocity = 80 },
    { pitch = 67, start = 2.5, length = 0.125, velocity = 64 },
  } })
  chords:set_controls({
    { start = 0, type = "cc", number = 1, value = 64 / 127 },
    { start = 0.5, type = "program", program = 5, bank = 130 },
    { start = 1, type = "bend", value = -0.5 },
    { start = 1.5, type = "pressure", value = 100 / 127 },
    { start = 2, type = "pressure", key = 64, value = 20 / 127 },
    { start = 2.5, type = "cc", number = 64, value = 1 },
  })
  local quiet = keys:add_clip({ name = "muted", start = 12, length = 3, notes = { { pitch = 72, start = 0, length = 1 } } })
  quiet.muted = true
  -- A looped MIDI clip whose repeated stretch begins half a beat before it.
  api.clip_add(kick.id, { name = "loop", start = 4, length = 5, notes = {
    { pitch = 38, start = -0.5, length = 0.25, velocity = 100 }, { pitch = 42, start = 0.5, length = 0.25, velocity = 70 },
  }, controls = { { start = 0, type = "cc", number = 7, value = 64 / 127 } }, ["loop"] = true, loop_length = 2, loop_start = -0.5 })
  local wav = dir .. "/media/tone.wav"
  local audio = gtr:add_clip({ start = 1, file = wav, offset = 0.25, gain = -3.5 })
  audio.length = 2
  api.clip_set(audio.id, "fade_in", 0.25)
  api.clip_set(audio.id, "fade_out", 0.5)
  -- Faster and higher; and a looped clip of the part of the file after 0.5 s.
  api.clip_add(gtr.id, { name = "fast", start = 4, file = wav, offset = 0, length = 1, stretch = 0.5, pitch = 3 })
  api.clip_add(gtr.id, { name = "looped", start = 6, file = wav, offset = 0.75, length = 6, ["loop"] = true,
    loop_length = 2.5, loop_start = -0.4166666666666667 })
  keys:automate("volume"):set_points({ { 0, -10 }, { 4, 0 }, { 8, -120 } })
  local vol = keys:lane("volume")
  api.lane_set_shapes(vol.id, { { beat = 0, shape = "hold", tension = 0 }, { beat = 4, shape = "smooth", tension = 0 } })
  local pan = gtr:automate("pan")
  pan:set_points({ { 0, -1 }, { 6, 0.5 } })
  pan.enabled = false
  bus:automate("volume"):set_points({ { 2, 3 } })
  paw.markers.add(0, "Intro")
  paw.markers.add(9, "Drop", { color = "#ff8000" })
  paw.markers.add(3, "Verse", { length = 6 })
  paw.flush()
end

test("rpp: export, then import, gives the same project", function()
  local r = load()
  local dir = project_dir("song.rpp")
  build(dir)
  local before = describe()
  local result = r.export(dir .. "/built.rpp")
  eq(result.report:empty(), true, "nothing left out: " .. result.report:text())
  -- It is a REAPER project by our own reading of it, laid out as REAPER's.
  local doc = r.read(dir .. "/built.rpp")
  local p = doc.project
  eq(p:child("TEMPO"):arg(1), "100", "TEMPO")
  eq(#p:blocks("TRACK"), 6, "tracks")
  local kick = p:blocks("TRACK")[2]
  eq(kick:get("ISBUS"), "0", "Kick in the folder")
  eq(p:blocks("TRACK")[1]:child("ISBUS"):arg(2), "1", "Drum Bus opens the folder")
  eq(p:blocks("TRACK")[3]:child("ISBUS"):arg(2), "-1", "Snare closes it")
  local verb = p:blocks("TRACK")[5]
  eq(#verb:all("AUXRECV"), 2, "Verb receives from Keys and Snare")
  eq(T.read_file(dir .. "/built.rpp"):find("\r\n", 1, true) ~= nil, true, "CRLF as REAPER writes")
  local file = p:blocks("TRACK")[6]:child("ITEM"):child("SOURCE"):get("FILE")
  eq(file, "media/tone.wav", "media path relative to the project")
  r.import(dir .. "/built.rpp")
  local after = describe()
  same(before, after)
  local marks = paw.markers.list()
  eq(#marks, 3, "markers and the region")
  eq(marks[3].name, "Drop", "marker")
  near(marks[3].beat, 9, 1e-9, "marker beat")
  eq(marks[3].color, "#ff8000", "marker colour")
  eq(marks[2].name, "Verse", "region")
  near(marks[2].length, 6, 1e-9, "region length")
end)

test("rpp: plugins go out and come back with their settings", function()
  local r = load()
  local dir = project_dir("song.rpp")
  local clap = "clap:in.lsp-plug.gate_mono"
  local lv2 = "lv2:http://lsp-plug.in/plugins/lv2/gate_mono"
  local vst3 = "vst3:Gate Mono"
  if not (has(clap) and has(lv2) and has(vst3)) then return "skipped: LSP plugins not installed" end
  T.fresh()
  local t = paw.add_track({ name = "FX" })
  local a = t:add_device(clap)
  a:set("output_gain", -6)
  a:automate("output_gain"):set_points({ { 0, -12 }, { 4, 0 } })
  local b = t:add_device(lv2)
  b:set("scr", 37)
  b.bypass = true
  t:add_device(vst3)
  T.next_block(3) -- plugins take new values with their next audio block
  local result = r.export(dir .. "/fx.rpp")
  eq(has_item(result.report, "Plugins not written", "vst3:Gate Mono"), true, "a VST3 made here is not written")
  local chain = r.read(dir .. "/fx.rpp").project:child("TRACK"):child("FXCHAIN")
  eq(chain:child("CLAP"):arg(2), "in.lsp-plug.gate_mono", "CLAP id")
  eq(chain:child("CLAP"):child("STATE") ~= nil, true, "CLAP state")
  eq(chain:child("LV2"):arg(2), "http://lsp-plug.in/plugins/lv2/gate_mono", "LV2 uri")
  r.import(dir .. "/fx.rpp")
  local devs = paw.track("FX"):devices()
  eq(#devs, 2, "the CLAP and the LV2 plugin")
  eq(devs[1].kind, clap, "CLAP back")
  near(devs[1].params.output_gain, -6, 1e-3, "CLAP setting from its state")
  eq(chain:child("PARMENV") ~= nil, true, "the parameter's envelope is written")
  local lane = devs[1]:lane("output_gain")
  eq(lane ~= nil, true, "and comes back as a lane")
  near(lane:points()[1][2], -12, 1e-3, "its first point")
  near(lane:points()[2][2], 0, 1e-3, "its last point")
  eq(devs[2].kind, lv2, "LV2 back")
  near(devs[2].params.scr, 37, 1e-3, "LV2 setting from its parameters")
  eq(devs[2].bypass, true, "bypass")
  -- A VST3 that came from REAPER goes back with its state.
  local vdoc = r.parse(table.concat({
    "<REAPER_PROJECT 0.1 \"7.55\" 0", "  TEMPO 120 4 4", "  <TRACK", "    NAME V", "    <FXCHAIN", "      BYPASS 0 0 0",
    '      <VST "VST3: Gate Mono (LSP VST3)" lsp-plugins.vst3 0 "" 1{00000000000000000000000000000000} ""',
    "      >", "      WAK 0 0", "    >", "  >", ">",
  }, "\n"))
  -- REAPER's chunk around the state of a gate made here.
  local fx = require("interop.rpp.fx")
  local b64 = paw.bytes
  T.fresh()
  local g = paw.add_track({ name = "tmp" }):add_device(vst3)
  local key = "sidechain_reactivity"
  g:set(key, 0.2)
  -- A VST3 takes a new value with its next audio block; its saved state
  -- only has it after that.
  T.next_block(3)
  local state = api.device_state(g.id)
  -- The plugin rounds the value it saves; what paw's own copy of the
  -- state gives is what the import must give.
  local want = api.device_get(api.device_add(g:track().id, vst3, { state = state })).params[key]
  local default = api.device_get(api.device_add(g:track().id, vst3, {})).params[key]
  eq(math.abs(want - default) > 0.05, true, "the setting is not the default")
  local reaper_state = fx.vst3_state_to_reaper(b64.unbase64(state))
  local header = b64.unbase64("9mZpeO5e7f4CAAAAAQAAAAAAAAACAAAAAAAAAAIAAAABAAAAAAAAAAIAAAAAAAAAGAAAAAEAAAD//wAA")
  header = header:sub(1, #header - 12) .. b64.le32(#reaper_state) .. header:sub(#header - 7)
  vdoc.project:child("TRACK"):child("FXCHAIN"):child("VST"):set_data({ b64.base64(header), b64.base64(reaper_state), "AAAAAAAA" })
  r.save(vdoc, dir .. "/vst3.rpp")
  r.import(dir .. "/vst3.rpp")
  local v = paw.track("V"):devices()[1]
  eq(v.kind, vst3, "VST3 found by name")
  near(v.params[key], want, 1e-6, "VST3 setting from REAPER's chunk")
  r.export(dir .. "/vst3-out.rpp")
  local out = r.read(dir .. "/vst3-out.rpp").project:child("TRACK"):child("FXCHAIN"):child("VST")
  eq(out:arg(1), "VST3: Gate Mono (LSP VST3)", "written back under REAPER's name for it")
  eq(b64.unbase64(out:data_groups()[1]):sub(1, 8), header:sub(1, 8), "with REAPER's header")
  r.import(dir .. "/vst3-out.rpp")
  near(paw.track("V"):devices()[1].params[key], want, 1e-6, "and back again")
end)

test("rpp: routing a folder cannot hold is written as a send", function()
  local r = load()
  T.fresh()
  local bus = paw.add_track({ name = "Bus" })
  paw.add_track({ name = "Between" })
  paw.add_track({ name = "Late", output = bus })
  paw.flush()
  local result = r.export(T.scratch .. "/route.rpp")
  eq(has_item(result.report, "Routing written as a send (REAPER folders need the child right after its parent)", "Late -> Bus"), true, "reported")
  local late = r.read(T.scratch .. "/route.rpp").project:blocks("TRACK")[3]
  eq(late:child("MAINSEND"):arg(1), "0", "no parent send")
  local bus_block = r.read(T.scratch .. "/route.rpp").project:blocks("TRACK")[1]
  eq(bus_block:child("AUXRECV"):arg(1), "2", "the bus receives from it")
end)

test("rpp: an imported project with audio and MIDI renders", function()
  local r = load()
  local dir = project_dir("render.rpp")
  local result = r.import(dir .. "/render.rpp", { instrument = "synth" })
  eq(has_item(result.report, "Plugins left as placeholders", "ReaSynth"), true, "ReaSynth stays behind")
  eq(paw.track("Synth"):devices()[1].kind, "synth", "a synth for the MIDI track")
  local info = T.render({ bits = 16, tail = 0 })
  local audio = T.channel_peaks(info, 0.2, 1.8)
  local notes = T.channel_peaks(info, 2.2, 3.8)
  eq(audio > 0.1, true, "the audio clip is heard: " .. audio)
  eq(notes > 0.05, true, "the MIDI clip is heard: " .. notes)
  near(T.frequency(info, 0.2, 1.8), 440, 5, "the WAV's pitch")
  near(T.frequency(info, 2.2, 3.8), 220, 5, "the MIDI note's pitch (A3)")
end)

test("rpp: the tempo map goes out as TEMPOENVEX and comes back", function()
  local r = load()
  T.fresh()
  paw.project.tempo = 120
  paw.tempo.set(8, 120, { ramp = true })
  paw.tempo.set(16, 90)
  paw.tempo.set_signature(9, 6, 8)
  local track = paw.add_track({ name = "Keys" })
  track:add_clip({ start = 34, length = 3, notes = { { pitch = 60, start = 0, length = 1 } } })
  local path = T.scratch .. "/map.rpp"
  r.export(path)
  local text = T.read_file(path)
  eq(text:find("<TEMPOENVEX", 1, true) ~= nil, true, "a tempo envelope is written")
  eq(text:find("PT 4.000000000000 120 0", 1, true) ~= nil, true, "the ramp starts at 4 s, shape 0")
  eq(text:find(" 524294 0 1", 1, true) ~= nil, true, "6/8 packed as 6 + 8 * 65536")
  local seconds = paw.tempo.beats_to_seconds(34)
  T.fresh()
  r.import(path)
  local points = paw.tempo.points()
  eq(#points, 4, "three tempo points and one where the 6/8 starts")
  eq(points[2].ramp, true, "the ramp")
  near(points[3].beat, 16, 1e-6, "the ramp's end lands on its beat")
  eq(paw.tempo.bar_of(32), 9, "the 6/8 starts bar 9")
  local num, den = paw.tempo.signature_at(33)
  eq(num .. "/" .. den, "6/8", "in 6/8")
  local clip = paw.tracks()[1]:clips()[1]
  near(clip.start, 34, 1e-6, "the clip at its beat")
  near(paw.tempo.beats_to_seconds(clip.start), seconds, 1e-6, "and its time")
end)

test("rpp: sections go out as regions and note attributes are listed as left out", function()
  local r = load()
  paw.ext.load("extensions/sections")
  T.fresh()
  local t = paw.add_track({ name = "Strings" })
  local clip = t:add_clip({ start = 0, length = 8, notes = { { pitch = 60, start = 0, length = 1, velocity = 90 } } })
  local notes = clip:notes()
  notes[1].attr = paw.attr.m2("11.A")
  clip:set_notes(notes)
  require("sections").add("Verse", 0)
  require("sections").add("Chorus", 4)
  paw.flush()
  local result = r.export(T.scratch .. "/sections.rpp")
  eq(has_item(result.report, "Note attributes (MIDI 2.0 articulations)", "Strings"), true, "attributes listed: " .. result.report:text())
  eq(has_item(result.report, "Sections written as regions (they come back as regions)", "sections"), true, "sections listed")
  r.import(T.scratch .. "/sections.rpp")
  local regions = paw.markers.regions()
  eq(regions[1].name .. " " .. regions[2].name, "Verse Chorus", "the sections are REAPER regions")
  near(regions[1].length, 4, 1e-9, "a section runs to the next")
end)

-- The real REAPER ------------------------------------------------------------------------

--- What REAPER read from a project (tools/reaper-dump.lua): tables of the
--- dump's lines by kind, each line a list of its values.
local function reaper_open(path, build)
  local reaper = os.getenv("PAW_REAPER")
  if not reaper or reaper == "" then return nil, "skipped: set PAW_REAPER to the reaper program to open the file in REAPER" end
  local dump = path .. ".dump"
  local code = os.execute(string.format("'%s/tools/reaper-open.sh' '%s' '%s' %s 2>&1", HERE, path, dump,
    build and ("'" .. build .. "'") or ""))
  if code ~= 0 and code ~= true then error("reaper-open.sh failed: " .. tostring(code)) end
  local out = {}
  for line in T.read_file(dump):gmatch("[^\n]+") do
    local fields = {}
    for f in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = tonumber(f) or f end
    local kind = table.remove(fields, 1)
    out[kind] = out[kind] or {}
    table.insert(out[kind], fields)
  end
  eq(out["end"] ~= nil, true, "REAPER read the whole project")
  return out
end

test("rpp: REAPER opens an exported project with the same tracks, items, notes and controllers", function()
  local r = load()
  local dir = project_dir("song.rpp")
  build(dir)
  local path = dir .. "/built.rpp"
  r.export(path)
  local got, why = reaper_open(path)
  if not got then return why end
  local sec = paw.tempo.beats_to_seconds
  eq(got.tempo[1][1], 100, "tempo")
  eq(got.tempo[1][2] .. "/" .. got.tempo[1][3], "3/4", "time signature")
  -- Tracks: the master first, then each track in order.
  local tracks = paw.tracks()
  eq(#got.track, #tracks + 1, "number of tracks")
  near(got.track[1][3], 10 ^ (-2 / 20), 1e-4, "master volume")
  local index = {}
  for i, t in ipairs(tracks) do
    index[t.id] = i
    local row = got.track[i + 1]
    eq(row[2], t.name, "track " .. i .. " name")
    near(row[3], 10 ^ (t.volume / 20), 1e-4, t.name .. " volume")
    near(row[4], t.pan, 1e-4, t.name .. " pan")
    eq(row[5] == 1, t.mute, t.name .. " mute")
    eq(row[6] ~= 0, t.solo, t.name .. " solo")
    eq(row[8], t.color or "none", t.name .. " colour")
  end
  eq(got.track[2][7], 1, "Drum Bus opens a folder")
  eq(got.track[4][7], -1, "Snare closes it")
  -- Sends, from the sender.
  local sends = {}
  for _, s in ipairs(got.send or {}) do sends[#sends + 1] = string.format("%d>%d %.2f", s[1], s[2], 20 * math.log10(s[3])) end
  table.sort(sends)
  eq(table.concat(sends, ", "), "3>5 -15.50, 4>5 -9.00", "sends")
  -- Items and their notes.
  local items = {}
  for _, it in ipairs(got.item or {}) do
    items[it[1]] = items[it[1]] or {}
    items[it[1]][it[2]] = it
  end
  local notes, ccs = {}, {}
  for _, n in ipairs(got.note or {}) do
    local key = n[1] .. ":" .. n[2]
    notes[key] = notes[key] or {}
    table.insert(notes[key], n)
  end
  for _, c in ipairs(got.cc or {}) do
    local key = c[1] .. ":" .. c[2]
    ccs[key] = ccs[key] or {}
    table.insert(ccs[key], c)
  end
  local checked = 0
  for _, t in ipairs(tracks) do
    local clips = t:clips()
    for k, c in ipairs(clips) do
      local cg = c:get()
      local it = (items[index[t.id]] or {})[k]
      local what = t.name .. ": " .. cg.name
      eq(it ~= nil, true, what .. " is an item")
      near(it[3], sec(cg.start), 1e-6, what .. " position")
      near(it[4], sec(cg.start + cg.length) - sec(cg.start), 1e-6, what .. " length")
      eq(it[5] == 1, cg["loop"] == true, what .. " loop")
      eq(it[9] == 1, cg.muted, what .. " mute")
      if cg.kind == "audio" then
        near(it[6], sec(cg.start + cg.fade_in) - sec(cg.start), 1e-6, what .. " fade in")
        near(it[7], sec(cg.start + cg.length) - sec(cg.start + cg.length - cg.fade_out), 1e-6, what .. " fade out")
        near(20 * math.log10(it[8]), cg.gain, 1e-3, what .. " gain")
        near(it[11], 1 / cg.stretch, 1e-6, what .. " rate")
        near(it[12], cg.pitch, 1e-6, what .. " pitch")
        eq(tostring(it[13]):match("tone%.wav$") ~= nil, true, what .. " file: " .. tostring(it[13]))
        if not cg["loop"] then near(it[10], cg.offset, 1e-6, what .. " offset") end
      else
        local want = {}
        for _, n in ipairs(c:notes()) do
          if cg["loop"] then
            if n.start >= cg.loop_start and n.start < cg.loop_start + cg.loop_length then
              -- REAPER gives the first pass, which begins where the repeat does.
              want[#want + 1] = { cg.start + n.start, n }
            end
          elseif n.start >= 0 then
            want[#want + 1] = { cg.start + n.start, n }
          end
        end
        local list = notes[index[t.id] .. ":" .. k] or {}
        eq(#list, #want, what .. " notes")
        for j, w in ipairs(want) do
          local n = list[j]
          near(n[3], sec(w[1]), 1e-6, what .. " note " .. j .. " start")
          near(n[4] - n[3], sec(w[1] + w[2].length) - sec(w[1]), 1e-6, what .. " note " .. j .. " length")
          eq(n[5], w[2].pitch, what .. " note " .. j .. " pitch")
          eq(n[6], w[2].velocity, what .. " note " .. j .. " velocity")
          eq(n[7], (w[2].meta and w[2].meta.channel or 1) - 1, what .. " note " .. j .. " channel")
        end
        local moves = ccs[index[t.id] .. ":" .. k] or {}
        local wantc = 0
        for _, m in ipairs(c:controls()) do wantc = wantc + (m.type == "program" and m.bank and 3 or 1) end
        eq(#moves, wantc, what .. " controller events")
      end
      checked = checked + 1
    end
  end
  eq(checked, 7, "every clip was checked")
  -- The controllers of the chords, as REAPER reads them.
  local chords = ccs[index[paw.track("Keys").id] .. ":1"]
  local text = {}
  for _, c in ipairs(chords) do text[#text + 1] = string.format("%d:%d,%d", c[4], c[6], c[7]) end
  eq(table.concat(text, " "), "176:1,64 176:0,1 176:32,2 192:5,0 224:0,32 208:100,0 160:64,20 176:64,127",
    "CC 1, bank and program, pitch bend, pressure, key pressure, sustain")
  -- Envelopes: the volume of Keys with its hold and smooth shapes.
  local shapes = {}
  for _, p in ipairs(got.point or {}) do
    if p[1] == index[paw.track("Keys").id] and p[2] == "Volume" then shapes[#shapes + 1] = string.format("%.3f:%d", p[3], p[5]) end
  end
  eq(table.concat(shapes, " "), string.format("0.000:1 %.3f:2 %.3f:0", sec(4), sec(8)), "Keys volume points and shapes")
  -- Markers and the region.
  eq(#got.marker, 2, "markers")
  eq(got.marker[2][2], "Drop", "marker name")
  near(got.marker[2][1], sec(9), 1e-6, "marker time")
  eq(#got.region, 1, "region")
  near(got.region[1][2], sec(9), 1e-6, "region end")
end)

test("rpp: a project that REAPER made and saved comes into paw as REAPER has it", function()
  local r = load()
  local dir = project_dir("song.rpp")
  local path = dir .. "/made.rpp"
  local got, why = reaper_open(path, HERE .. "/tools/reaper-build.lua")
  if not got then return why end
  local result = r.import(path)
  local sec = paw.tempo.beats_to_seconds
  eq(paw.project.tempo, got.tempo[1][1], "tempo")
  eq(paw.project.sig_num .. "/" .. paw.project.sig_den, got.tempo[1][2] .. "/" .. got.tempo[1][3], "time signature")
  local tracks = paw.tracks()
  eq(#tracks, #got.track - 1, "tracks")
  local parents = {}
  for i, t in ipairs(tracks) do
    local row = got.track[i + 1]
    eq(t.name, row[2], "name " .. i)
    near(t.volume, 20 * math.log10(row[3]), 1e-6, t.name .. " volume")
    near(t.pan, row[4], 1e-6, t.name .. " pan")
    eq(t.mute, row[5] == 1, t.name .. " mute")
    eq(t.color or "none", row[8], t.name .. " colour")
    parents[i] = t.output and paw.track(t.output) and paw.track(t.output).name or "-"
  end
  eq(table.concat(parents, ","), "-,Bus,Bus,-", "the folder holds Keys and Gtr")
  local keys = paw.track("Keys")
  eq(#keys.sends, 1, "the send of Keys")
  near(keys.sends[1].level, 20 * math.log10(got.send[1][3]), 1e-6, "its level")
  eq(keys.sends[1].pre, true, "before the fader, as REAPER's mode 3")
  -- Items, notes and controllers at the times REAPER gives.
  local n = 0
  for i, t in ipairs(tracks) do
    for k, c in ipairs(t:clips()) do
      local it
      for _, row in ipairs(got.item) do
        if row[1] == i and row[2] == k then it = row end
      end
      local cg = c:get()
      near(sec(cg.start), it[3], 1e-6, t.name .. " item position")
      near(sec(cg.start + cg.length) - sec(cg.start), it[4], 1e-6, t.name .. " item length")
      if cg.kind == "audio" then
        near(cg.offset, it[10], 1e-6, "offset")
        near(sec(cg.start + cg.fade_in) - sec(cg.start), it[6], 1e-6, "fade in")
      else
        local list = {}
        for _, row in ipairs(got.note) do
          if row[1] == i and row[2] == k then list[#list + 1] = row end
        end
        local notes = c:notes()
        eq(#notes, #list, "notes")
        for j, row in ipairs(list) do
          near(sec(cg.start + notes[j].start), row[3], 1e-6, "note " .. j .. " start")
          eq(notes[j].pitch .. " " .. notes[j].velocity, row[5] .. " " .. row[6], "note " .. j)
          eq((notes[j].meta and notes[j].meta.channel or 1) - 1, row[7], "note " .. j .. " channel")
        end
        local moves = c:controls()
        eq(#moves, #got.cc, "controller events")
        eq(moves[1].type .. moves[1].number, "cc1", "CC 1")
        near(moves[1].value, 64 / 127, 1e-9, "its value")
        near(sec(cg.start + moves[2].start), got.cc[2][3], 1e-6, "the bend's time")
        near(moves[2].value, (96 * 128 - 8192) / 8192, 1e-9, "the bend's value")
      end
      n = n + 1
    end
  end
  eq(n, 2, "the MIDI item and the audio item")
  -- The envelope and the markers.
  local pts = keys:lane("volume"):points()
  local want = {}
  for _, p in ipairs(got.point) do
    if p[1] == 2 and p[2] == "Volume" then want[#want + 1] = p end
  end
  eq(#pts, #want, "volume points")
  for j, p in ipairs(want) do
    near(sec(pts[j][1]), p[3], 1e-6, "point " .. j .. " time")
    near(pts[j][2], 20 * math.log10(p[4]), 1e-6, "point " .. j .. " value")
  end
  eq(api.lane_shapes(keys:lane("volume").id)[1].shape, "hold", "the square point holds")
  local marks = paw.markers.list()
  eq(#marks, 2, "a marker and a region")
  near(sec(marks[1].beat), got.marker[1][1], 1e-6, "marker time")
  eq(marks[2].name, got.region[1][3], "region name")
  near(sec(marks[2].beat + marks[2].length), got.region[1][2], 1e-6, "region end")
  eq(result.report:empty(), true, "everything came across: " .. result.report:text())
end)
