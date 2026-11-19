-- Tests of the DAWproject extension, run by tests/suite.lua (`paw --clean -l tests/suite.lua dawproject`).
local T = ...
local paw = require("paw")
local api = paw.api
local test, eq, near = T.test, T.eq, T.near

local HERE = "extensions/dawproject"
local FIXTURES = HERE .. "/fixtures/"

local dp
local function load()
  if not dp then
    paw.ext.load(HERE)
    dp = require("dawproject")
  end
  return dp
end

local function has(kind)
  for _, t in ipairs(api.device_types()) do
    if t.kind == kind then return true end
  end
  return false
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

local folders = 0
local function scratch_dir()
  folders = folders + 1
  local dir = T.scratch .. "/dawproject" .. folders
  api.fs_mkdir(dir .. "/media")
  return dir
end

--- A mono 16-bit WAV of a sine, `seconds` long.
local function write_wav(path, seconds, freq)
  local rate = 22050
  local n = math.floor(seconds * rate)
  local samples = {}
  for i = 0, n - 1 do
    local v = math.floor(math.sin(2 * math.pi * freq * i / rate) * 0.5 * 32767 + 0.5)
    if v < 0 then v = v + 65536 end
    samples[#samples + 1] = string.char(v % 256, math.floor(v / 256))
  end
  local data = table.concat(samples)
  local b64 = paw.bytes
  local function u16(x) return string.char(x % 256, math.floor(x / 256) % 256) end
  T.write_file(path, "RIFF" .. b64.le32(36 + #data) .. "WAVEfmt " .. b64.le32(16) .. u16(1) .. u16(1)
    .. b64.le32(rate) .. b64.le32(rate * 2) .. u16(2) .. u16(16) .. "data" .. b64.le32(#data) .. data)
end

--- xmllint's verdict on a file against a schema of the format, or nil when
--- there is no xmllint.
local function validate(path, schema)
  if os.execute("command -v xmllint >/dev/null 2>&1") ~= 0 and os.execute("command -v xmllint >/dev/null 2>&1") ~= true then
    return nil
  end
  local out = path .. ".lint"
  local code = os.execute(string.format("xmllint --noout --schema '%s/schema/%s' '%s' > '%s' 2>&1", HERE, schema, path, out))
  return code == 0 or code == true, T.read_file(out)
end

-- The pieces ---------------------------------------------------------------------------

test("dawproject: XML reads and writes back", function()
  local d = load()
  local root = d.xml.parse([==[<?xml version="1.0"?>
<!-- a comment -->
<Project version="1.0"><Track name="Bass &amp; Drums" id='t1'><Note time="0" key="60"/></Track>
<Title>A &lt;b&gt; &#233;t&#xE9;<![CDATA[ & raw ]]></Title></Project>]==])
  eq(root.name, "Project", "root")
  eq(root:child("Track").attr.name, "Bass & Drums", "entity in an attribute")
  eq(root:child("Track").attr.id, "t1", "single quotes")
  eq(root:child("Track"):child("Note").attr.key, "60", "a child")
  eq(root:child("Title").text, "A <b> été & raw ", "text with entities, references and CDATA")
  local again = d.xml.parse(d.xml.write(root))
  eq(again:child("Track").attr.name, "Bass & Drums", "written and read again")
  eq(again:child("Title").text, "A <b> été & raw ", "text written and read again")
  eq(pcall(d.xml.parse, "<a><b></a>"), false, "a bad document is refused")
end)

-- Import -------------------------------------------------------------------------------

test("dawproject: import, track by track and clip by clip", function()
  local d = load()
  local dir = scratch_dir()
  T.write_file(dir .. "/studio.dawproject", T.read_file(FIXTURES .. "studio.dawproject"))
  local result = d.import(dir .. "/studio.dawproject")
  local report = result.report
  paw.flush()
  local p = paw.project.get()
  eq(p.name, "Studio Song", "the title of metadata.xml")
  eq(p.tempo, 120, "tempo")
  local points = paw.tempo.points()
  eq(#points, 2, "a tempo change")
  near(points[2].beat, 16, 1e-9, "at its beat")
  eq(points[2].bpm, 90, "to 90")
  eq(paw.tempo.bar_of(17), 5, "bar 5 starts the 3/4")
  local num, den = paw.tempo.signature_at(17)
  eq(num .. "/" .. den, "3/4", "the time signature changes")
  near(paw.master.volume, -6.0206, 1e-3, "master volume")

  local names = {}
  for i, t in ipairs(paw.tracks()) do names[i] = t.name end
  eq(table.concat(names, ","), "Group,Bass,Drumloop,Reverb", "tracks in order, the nested one after its group")
  local group, bass, drums, verb = paw.track("Group"), paw.track("Bass"), paw.track("Drumloop"), paw.track("Reverb")
  eq(bass.output, group.id, "Bass goes into its group")
  eq(group.output, nil, "the group to the master")
  eq(group.color, "#334455", "colour")
  near(bass.volume, 20 * math.log10(0.65914), 1e-3, "volume from a linear value")
  near(bass.pan, -0.5, 1e-9, "pan from a normalized value")
  eq(bass.solo, true, "solo")
  eq(drums.mute, true, "mute")
  eq(#bass.sends, 1, "a send")
  eq(bass.sends[1].target, verb.id, "to the reverb")
  near(bass.sends[1].level, -12.0412, 1e-3, "its level")
  eq(bass.sends[1].pre, true, "before the fader")

  -- Bass: notes, controllers, a looped clip.
  local clips = bass:clips()
  eq(#clips, 2, "two clips")
  local a = clips[1]:get()
  eq(a.name, "Bassline", "name")
  near(a.length, 8, 1e-9, "length")
  local notes = clips[1]:notes()
  eq(#notes, 2, "notes")
  eq(notes[1].velocity, 100, "velocity 0.787 is 100")
  eq(notes[2].meta.channel, 2, "MIDI channel 1 (from 0) is channel 2")
  near(notes[2].length, 0.5, 1e-9, "length")
  local moves = clips[1]:controls()
  eq(#moves, 3, "two controller points and a bend")
  eq(moves[1].type .. moves[1].number, "cc74", "CC 74")
  near(moves[1].value, 0.25, 1e-9, "its value")
  eq(moves[3].type, "bend", "the pitch wheel")
  near(moves[3].value, 0.5, 1e-9, "0.75 normalized is half up")
  local b = clips[2]:get()
  eq(b.muted, true, "a clip that is not enabled is muted")
  eq(b["loop"], true, "loops")
  near(b.loop_length, 2, 1e-9, "every 2 beats")
  near(b.loop_start, 0, 1e-9, "from its start")

  -- Drumloop: audio in a clip of clips, stretched by its warps.
  local dc = drums:clips()
  eq(#dc, 2, "two audio clips")
  local w = dc[1]:get()
  eq(w.name, "Drumfunk", "the outer clip's name")
  near(w.start, 4, 1e-9, "start")
  near(w.length, 4, 1e-9, "length")
  near(w.stretch, 2, 1e-9, "1 s of the file over 4 beats at 120 BPM: twice as long")
  near(w.offset, 0, 1e-9, "from the file's start")
  near(w.fade_in, 0.5, 1e-9, "the outer clip's fade in")
  near(w.fade_out, 0.25, 1e-9, "and fade out")
  eq(w.file:match("loop%.wav$") ~= nil, true, "the file taken out of the archive: " .. w.file)
  eq(T.read_file(w.file), T.read_file(FIXTURES .. "studio/audio/loop.wav"), "with the same bytes")
  local plain = dc[2]:get()
  near(plain.offset, 0.25, 1e-9, "playStart in seconds is the offset")
  near(plain.length, 2, 1e-9, "length")

  -- Automation: Bass volume, with a held stretch; the master's pan.
  local vol = bass:lane("volume")
  local pts = vol:points()
  eq(#pts, 3, "volume points")
  near(pts[2][2], -6.0206, 1e-3, "linear 0.5 is -6 dB")
  local shapes = api.lane_shapes(vol.id)
  eq(#shapes, 1, "the point without interpolation holds")
  near(shapes[1].beat, 4, 1e-9, "at beat 4")
  local mp = paw.master:lane("pan"):points()
  near(mp[1][2], -1, 1e-9, "master pan from normalized 0")

  -- Markers.
  local marks = paw.markers.list()
  eq(#marks, 2, "markers")
  eq(marks[1].name, "Intro", "name")
  eq(marks[1].color, "#ff0000", "colour")
  near(marks[2].beat, 8, 1e-9, "beat")

  -- What did not come across.
  eq(has_item(report, "Plugins and devices left as placeholders", "Nowhere Synth (not installed here)"), true, "CLAP left behind")
  eq(has_item(report, "Plugins and devices left as placeholders", "Nowhere Verb"), true, "VST3 left behind")
  eq(has_item(report, "Note-off velocities", "Bass"), true, "a release velocity")
  local holders = bass.meta.dawproject_placeholders
  eq(holders[1].name, "Nowhere Synth", "the placeholder keeps the plugin")
  eq(paw.bytes.decode(holders[1].state), "nowhere-state-bytes", "and its state")
end)

-- Export -------------------------------------------------------------------------------

--- The project as plain data, for comparing two projects.
local function describe()
  local p = paw.project.get()
  local out = {
    tempo = p.tempo, sig = p.sig_num .. "/" .. p.sig_den,
    master = string.format("%.4f %.4f %s", paw.master.volume, paw.master.pan, tostring(paw.master.mute)),
    tracks = {},
  }
  local name_of = {}
  for _, t in ipairs(paw.tracks()) do name_of[t.id] = t.name end
  local map = paw.tempo.points()
  local tempo = {}
  for _, tp in ipairs(map) do tempo[#tempo + 1] = string.format("%.4f:%g:%s", tp.beat, tp.bpm, tostring(tp.ramp)) end
  out.map = table.concat(tempo, " ")
  local lists = { paw.tracks() }
  table.insert(lists[1], paw.master)
  for _, t in ipairs(lists[1]) do
    local g = t:get()
    local d = {
      string.format("%s vol %.4f pan %.4f mute %s solo %s out %s colour %s",
        g.name, g.volume, g.pan, tostring(g.mute), tostring(g.solo), tostring(name_of[g.output]), tostring(g.color)),
    }
    for _, s in ipairs(g.sends or {}) do d[#d + 1] = string.format("send %s %.4f pre %s", name_of[s.target], s.level, tostring(s.pre)) end
    for _, lane in ipairs(t:lanes()) do
      local l = lane:get()
      local pts = {}
      for _, pt in ipairs(lane:points()) do pts[#pts + 1] = string.format("%.6f:%.4f", pt[1], pt[2]) end
      for _, s in ipairs(api.lane_shapes(l.id)) do pts[#pts + 1] = string.format("%s@%.6f", s.shape, s.beat) end
      d[#d + 1] = string.format("lane %s %s %s", l.target, tostring(l.param), table.concat(pts, " "))
    end
    for _, dev in ipairs(t:devices()) do
      local keys = {}
      for k in pairs(dev.params) do keys[#keys + 1] = k end
      table.sort(keys)
      local params = {}
      for _, k in ipairs(keys) do params[#params + 1] = string.format("%s=%.4f", k, dev.params[k]) end
      d[#d + 1] = string.format("device %s bypass %s %s", dev.kind, tostring(dev.bypass), table.concat(params, ","))
    end
    for _, c in ipairs(t.id ~= 0 and t:clips() or {}) do
      local cg = c:get()
      local line = string.format("clip %s %s %.6f+%.6f muted %s", cg.kind, cg.name, cg.start, cg.length, tostring(cg.muted))
      if cg["loop"] then line = line .. string.format(" loop %.6f+%.6f", cg.loop_start, cg.loop_length) end
      if cg.kind == "audio" then
        line = line .. string.format(" %s offset %.6f gain %.4f fades %.6f %.6f stretch %.6f", cg.file:match("[^/]+$"),
          cg.offset, cg.gain, cg.fade_in, cg.fade_out, cg.stretch)
      else
        for _, n in ipairs(c:notes()) do
          line = line .. string.format(" [%d %.6f %.6f %d %s]", n.pitch, n.start, n.length, n.velocity,
            tostring(n.meta and n.meta.channel))
        end
        for _, m in ipairs(c:controls()) do
          line = line .. string.format(" {%s %s %s %.6f %.4f}", m.type, tostring(m.number or m.program),
            tostring(m.key), m.start, m.value)
        end
      end
      d[#d + 1] = line
    end
    out.tracks[#out.tracks + 1] = table.concat(d, "\n  ")
  end
  local marks = {}
  for _, m in ipairs(paw.markers.list()) do
    marks[#marks + 1] = string.format("%s@%.4f+%s %s", m.name, m.beat, tostring(m.length), tostring(m.color))
  end
  out.markers = table.concat(marks, ", ")
  return out
end

local function same(a, b)
  for _, key in ipairs({ "tempo", "sig", "master", "map", "markers" }) do eq(b[key], a[key], key) end
  eq(#b.tracks, #a.tracks, "number of tracks")
  for i = 1, #a.tracks do eq(b.tracks[i], a.tracks[i], "track " .. i) end
end

local function build(dir)
  T.fresh()
  paw.project.tempo = 100
  paw.project.sig_num = 3
  paw.project.sig_den = 4
  paw.tempo.set(12, 100, { ramp = true })
  paw.tempo.set(24, 80)
  paw.tempo.set_signature(10, 4, 4)
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
  keys.color = "#3a7bd5"
  bus.color = "#e04020"
  keys:send(verb, -9)
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
    { start = 0, type = "cc", number = 1, value = 0.5 },
    { start = 0.5, type = "program", program = 5 },
    { start = 1, type = "bend", value = -0.5 },
    { start = 1.5, type = "pressure", value = 0.75 },
    { start = 2, type = "pressure", key = 64, value = 0.25 },
  })
  local quiet = keys:add_clip({ name = "muted", start = 12, length = 3, notes = { { pitch = 72, start = 0, length = 1 } } })
  quiet.muted = true
  api.clip_add(kick.id, { name = "loop", start = 4, length = 5, notes = {
    { pitch = 38, start = -0.5, length = 0.25, velocity = 100 }, { pitch = 42, start = 0.5, length = 0.25, velocity = 70 },
  }, ["loop"] = true, loop_length = 2, loop_start = -0.5 })
  local wav = dir .. "/media/tone.wav"
  local audio = gtr:add_clip({ name = "tone", start = 1, file = wav, offset = 0.25, gain = 0 })
  audio.length = 2
  api.clip_set(audio.id, "fade_in", 0.25)
  api.clip_set(audio.id, "fade_out", 0.5)
  api.clip_add(gtr.id, { name = "slow", start = 4, file = wav, offset = 0.5, length = 2, stretch = 2 })
  api.clip_add(gtr.id, { name = "looped", start = 6, file = wav, offset = 0.75, length = 6, ["loop"] = true,
    loop_length = 2.5, loop_start = -0.4166666666666667 })
  keys:automate("volume"):set_points({ { 0, -10 }, { 4, 0 }, { 8, -120 } })
  api.lane_set_shapes(keys:lane("volume").id, { { beat = 0, shape = "hold", tension = 0 } })
  gtr:automate("pan"):set_points({ { 0, -1 }, { 6, 0.5 } })
  paw.master:automate("volume"):set_points({ { 0, 0 }, { 16, -6 } })
  local synth = verb:add_device("synth", { cutoff = 1200 })
  synth.bypass = true
  synth:automate("cutoff"):set_points({ { 0, 300 }, { 8, 3000 } })
  paw.markers.add(0, "Intro")
  paw.markers.add(9, "Drop", { color = "#ff8000" })
  paw.markers.add(3, "Verse", { length = 6 })
  paw.flush()
end

test("dawproject: export, then import, gives the same project", function()
  local d = load()
  local dir = scratch_dir()
  write_wav(dir .. "/media/tone.wav", 2, 440)
  build(dir)
  local before = describe()
  local path = dir .. "/built.dawproject"
  local result = d.export(path)
  local report = result.report
  eq(has_item(report, "Devices of paw (written as built-in devices that only paw reads)", "Verb: synth"), true,
    "paw's own devices are listed: " .. report:text())
  eq(has_item(report, "Regions written as markers at their start (paw reads them back as regions)", "regions"), true,
    "regions are listed")
  -- The archive holds the project, the metadata and the audio, once.
  local files, names = paw.zip.read(T.read_file(path))
  eq(table.concat(names, ","), "project.xml,metadata.xml,audio/tone.wav", "the files of the archive")
  eq(files["audio/tone.wav"], T.read_file(dir .. "/media/tone.wav"), "the audio file in it")
  -- Both XML files are valid by the official schemas.
  T.write_file(dir .. "/project.xml", files["project.xml"])
  T.write_file(dir .. "/metadata.xml", files["metadata.xml"])
  local ok, why = validate(dir .. "/project.xml", "Project.xsd")
  if ok ~= nil then
    eq(ok, true, "project.xml is valid: " .. tostring(why))
    eq((validate(dir .. "/metadata.xml", "MetaData.xsd")), true, "metadata.xml is valid")
  end
  -- And it comes back.
  d.import(path, { media_dir = dir .. "/back" })
  local after = describe()
  same(before, after)
  return ok == nil and "skipped the schema check: no xmllint (it is in the dev shell)" or nil
end)

test("dawproject: the official schema accepts what paw writes of an imported project", function()
  local d = load()
  local dir = scratch_dir()
  T.write_file(dir .. "/studio.dawproject", T.read_file(FIXTURES .. "studio.dawproject"))
  d.import(dir .. "/studio.dawproject")
  d.export(dir .. "/again.dawproject")
  local files = paw.zip.read(T.read_file(dir .. "/again.dawproject"))
  T.write_file(dir .. "/project.xml", files["project.xml"])
  local ok, why = validate(dir .. "/project.xml", "Project.xsd")
  if ok == nil then return "skipped: no xmllint (it is in the dev shell)" end
  eq(ok, true, "valid: " .. tostring(why))
  -- The plugins that stayed behind go out again, with their states.
  local root = d.xml.parse(files["project.xml"])
  local clap = root:child("Structure"):child("Track"):child("Track"):child("Channel"):child("Devices"):child("ClapPlugin")
  eq(clap.attr.deviceID, "com.nowhere.synth", "the placeholder is written back")
  eq(files[clap:child("State").attr.path], "nowhere-state-bytes", "with its state")
  d.import(dir .. "/again.dawproject", { media_dir = dir .. "/back" })
  eq(paw.track("Bass").meta.dawproject_placeholders[1].name, "Nowhere Synth", "and comes back again")
end)

test("dawproject: plugins go out and come back with their settings", function()
  local d = load()
  local clap = "clap:in.lsp-plug.gate_mono"
  local vst3 = "vst3:Gate Mono"
  if not (has(clap) and has(vst3)) then return "skipped: LSP plugins not installed" end
  T.fresh()
  local t = paw.add_track({ name = "FX" })
  local a = t:add_device(clap)
  a:set("output_gain", -6)
  local v = t:add_device(vst3)
  v:set("sidechain_reactivity", 0.2)
  a:automate("output_gain"):set_points({ { 0, -12 }, { 4, 0 } })
  T.next_block(3) -- plugins take new values with their next audio block
  local want = api.device_get(v.id).params.sidechain_reactivity
  local path = T.scratch .. "/fx.dawproject"
  local result = d.export(path)
  eq(has_item(result.report, "VST3 plugins written without their class id (not installed here; a DAW finds them by name)",
    "FX: Gate Mono"), false, "the VST3 class id is known")
  local files = paw.zip.read(T.read_file(path))
  local cid = api.device_get(v.id).plugin.id
  eq(files["project.xml"]:find('<Vst3Plugin id="[^"]*" name="Gate Mono" deviceID="' .. cid .. '"') ~= nil, true,
    "written as deviceID")
  eq(files["plugins/001.clap-preset"] ~= nil, true, "the CLAP state")
  eq(files["plugins/002.vstpreset"]:sub(1, 4), "VST3", "the VST3 state as a .vstpreset")
  d.import(path)
  local devs = paw.track("FX"):devices()
  eq(#devs, 2, "both plugins")
  eq(devs[1].kind, clap, "CLAP back")
  near(devs[1].params.output_gain, -6, 1e-3, "CLAP setting from its state")
  eq(devs[2].kind, vst3, "VST3 back")
  near(devs[2].params.sidechain_reactivity, want, 1e-6, "VST3 setting from its .vstpreset")
  local lane = devs[1]:lane("output_gain")
  eq(lane ~= nil, true, "the parameter's automation")
  near(lane:points()[1][2], -12, 1e-3, "its first point")
end)

-- Commands -------------------------------------------------------------------------------

test("dawproject: commands, and edit and write on .dawproject files", function()
  load()
  local dir = scratch_dir()
  local file = dir .. "/studio.dawproject"
  T.write_file(file, T.read_file(FIXTURES .. "studio.dawproject"))
  paw.project.new()
  paw.cmd("dawproject.import", { file })
  eq(#paw.tracks(), 4, "dawproject.import")
  paw.project.new()
  paw.commands.exec("e " .. file)
  eq(#paw.tracks(), 4, "e song.dawproject")
  paw.commands.exec("dawproject.import " .. file .. " merge=true")
  eq(#paw.tracks(), 8, "merge adds the tracks")
  paw.commands.exec("dawproject.import! " .. file)
  eq(#paw.tracks(), 4, "dawproject.import! replaces the project")
  paw.commands.exec("dawproject.export " .. dir .. "/out.dawproject")
  eq(T.read_file(dir .. "/out.dawproject"):sub(1, 2), "PK", "dawproject.export")
  paw.commands.exec("w " .. dir .. "/out2.dawproject")
  eq(T.read_file(dir .. "/out2.dawproject"):sub(1, 2), "PK", "w song.dawproject")
  paw.commands.exec("dawproject.export " .. dir .. "/ref.dawproject embed=false")
  local files = paw.zip.read(T.read_file(dir .. "/ref.dawproject"))
  eq(files["audio/loop.wav"], nil, "embed=false leaves the audio out")
  eq(files["project.xml"]:find('external="true"', 1, true) ~= nil, true, "and refers to it")
  paw.commands.exec("w " .. dir .. "/song")
  eq(#T.read_file(dir .. "/song/project.toml") > 0, true, "w song saves as before")
  T.write_file(dir .. "/broken.dawproject", "not a zip")
  paw.commands.exec("dawproject.import! " .. dir .. "/broken.dawproject")
  eq(#paw.tracks(), 4, "a broken file leaves the project alone")
end)

test("dawproject: the README names every command of the extension", function()
  local readme = T.read_file(HERE .. "/README.md")
  local source = T.read_file(HERE .. "/init.lua")
  local names = {}
  for name in source:gmatch('paw%.command%("([^"]+)"') do names[#names + 1] = name end
  for name, alias in source:gmatch('hook%("([^"]+)", "([^"]+)"') do
    names[#names + 1] = name
    names[#names + 1] = alias
  end
  eq(#names, 6, "the commands and the hooked ones")
  for _, name in ipairs(names) do
    eq(readme:find("`:" .. name .. " ", 1, true) ~= nil, true, "README names :" .. name)
  end
  eq(source:find("paw.keymap.set", 1, true), nil, "no keys of its own, as the README says")
end)

test("dawproject: a plugin's id of a parameter is written signed, as DAWs write it", function()
  load()
  local own = require("dawproject.export").own_param_id
  eq(own({ id = "12" }), 12, "a small id as it is")
  eq(own({ id = "2683833795" }), -1611133501, "one of 2^31 and above below 0")
  eq(own({ id = "wet" }), nil, "the host's own parameters have none")
end)

for _, format in ipairs({ "clap", "vst3" }) do
  test("dawproject: " .. format .. " plugin lanes and ids go out with the plugin's own ids, and come back", function()
    local d = load()
    local kind
    for _, t in ipairs(api.device_types()) do
      if not kind and t.format == format and t.name == "Limiter Stereo" then kind = t.kind end
    end
    if not kind then return "skipped: test plugins not found" end
    T.fresh()
    local track = paw.add_track({ name = "Lim" })
    track:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 4 } } })
    local fx = track:add_device(kind)
    local gain = api.device_param(fx.id, "input_gain")
    api.lane_add(track.id, { target = "param", device = fx.id, param = "input_gain", points = { { 0, gain.min }, { 4, gain.max } } })
    local dir = scratch_dir()
    d.export(dir .. "/ids.dawproject")
    local xml = paw.zip.read(T.read_file(dir .. "/ids.dawproject"))["project.xml"]
    local n = tonumber(gain.id)
    local signed = string.format("%d", n >= 2 ^ 31 and n - 2 ^ 32 or n)
    eq(xml:find('name="Input gain" parameterID="' .. signed .. '"', 1, true) ~= nil, true, "the plugin's own id of the parameter")
    local plugin = fx:get().plugin
    eq(xml:find('deviceID="' .. plugin.id .. '"', 1, true) ~= nil, true, "and of the plugin: " .. plugin.id)
    T.write_file(dir .. "/project.xml", xml)
    local ok, why = validate(dir .. "/project.xml", "Project.xsd")
    if ok ~= nil then eq(ok, true, "project.xml is valid: " .. tostring(why)) end
    T.fresh()
    d.import(dir .. "/ids.dawproject", { media_dir = dir .. "/back" })
    local lanes = api.lane_list(paw.tracks()[1].id)
    eq(#lanes, 1, "the lane comes back")
    eq(lanes[1].param, "input_gain", "on the same parameter")
  end)
end
