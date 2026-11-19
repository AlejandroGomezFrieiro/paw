-- The how-to guides of the user guide about rendering and sharing, and about
-- projects and files, each driven with the keys and commands that it gives.
-- Loaded by tests/suite.lua with its helpers. The guides that load an
-- extension run last (`T.last`), so that its commands do not reach the other tests.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api

local keys = T.keys

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  paw.ui.focus("arrange")
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

--- Wait for a render started in the background.
local function rendered(path)
  local deadline = api.now() + 30000
  while (api.render_status() or not exists(path)) and api.now() < deadline do paw.wait(20) end
  eq(exists(path), true, "the file " .. path)
end

local function dir(name)
  local d = T.scratch .. "/" .. name
  os.execute("mkdir -p '" .. d .. "'")
  return d
end

test("guide: export a song as WAV, FLAC or MP3", function()
  start()
  T.tone("Lead", 8)
  local d = dir("export")
  paw.project.save(d .. "/song")
  keys(":render<CR>")
  rendered(d .. "/song/song.wav")
  eq(paw.render_tags().title, nil, "no tags set")
  keys(":render " .. d .. "/mix.flac<CR>")
  rendered(d .. "/mix.flac")
  -- A name alone goes into the folder of the project.
  keys(":render guide-export-test.wav<CR>")
  rendered(d .. "/song/guide-export-test.wav")
  keys(":render.tags artist=Ana album=\"First one\" year=2026<CR>")
  eq(paw.render_tags().artist .. "/" .. paw.render_tags().album, "Ana/First one", ":render.tags sets the tags")
  local mp3
  for _, f in ipairs(api.render_formats()) do
    if f.name == "MP3" then mp3 = f.available end
  end
  if mp3 then
    keys(":render " .. d .. "/mix.mp3 quality=best<CR>")
    rendered(d .. "/mix.mp3")
  end
end)

--- The length of a WAV file in seconds.
local function seconds(path)
  local data = T.read_file(path)
  local function u32(at) local a, b, c, d = data:byte(at, at + 3) return a + b * 256 + c * 65536 + d * 16777216 end
  local rate, bytes = u32(25), u32(29)
  local at = data:find("data", 37, true)
  return u32(at + 4) / bytes, rate
end

test("guide: export part of the song or a loop", function()
  start()
  paw.project.tempo = 120
  T.tone("Lead", 32)
  local d = dir("part")
  paw.project.save(d .. "/song")
  paw.ui.focus("arrange")
  paw.cursor.set_track(paw.tracks()[1])
  keys("3|gl2W")
  eq(paw.transport.loop_start .. "-" .. paw.transport.loop_end, "8-16", "gl2W loops two bars")
  keys(":render " .. d .. "/loop.wav range=loop tail=0<CR>")
  rendered(d .. "/loop.wav")
  near(seconds(d .. "/loop.wav"), 4, 0.01, "range=loop renders the loop")
  keys("5|v2W")
  keys(":render " .. d .. "/sel.wav range=selection tail=0<CR>")
  rendered(d .. "/sel.wav")
  near(seconds(d .. "/sel.wav"), 4, 0.01, "range=selection renders the selection")
  keys("<Esc>5|v2W")
  keys(":region Verse<CR>")
  local region = paw.markers.list()[1]
  eq(region.name .. " " .. region.beat .. "+" .. region.length, "Verse 16+8", ":region names the selection")
  keys("<Esc>")
  keys(":render " .. d .. "/verse.wav range=Verse tail=0<CR>")
  rendered(d .. "/verse.wav")
  near(seconds(d .. "/verse.wav"), 4, 0.01, "range=Verse renders the region")
  keys(":render.regions " .. d .. "/regions<CR>")
  rendered(d .. "/regions/01 Verse.wav")
end)

test("guide: export MIDI for another program", function()
  start()
  local lead = T.tone("Lead", 8, "A4")
  local bass = T.tone("Bass", 8, "A2")
  bass:clips()[1]:add_note({ pitch = "E2", start = 4, length = 2 })
  local d = dir("midiout")
  paw.ui.focus("arrange")
  paw.cursor.set_track(lead)
  keys(":export " .. d .. "/song.mid<CR>")
  eq(exists(d .. "/song.mid"), true, ":export writes the song")
  keys(":open! " .. d .. "/song.mid<CR>")
  eq(paw.project.path, nil, "the MIDI file opens as a new project")
  eq(#paw.tracks(), 2, "with its two tracks")
  eq(#paw.tracks()[2]:clips()[1]:notes(), 2, "and their notes")
  paw.ui.focus("arrange")
  paw.cursor.set_track(paw.tracks()[2])
  paw.cursor.set_beat(0)
  keys(":export " .. d .. "/riff.mid clip<CR>")
  local function parts(path)
    local out = {}
    for _, part in ipairs(paw.midifile.parts(paw.midifile.read(path))) do out[#out + 1] = part.name .. ":" .. #part.notes end
    return table.concat(out, " ")
  end
  eq(parts(d .. "/riff.mid"), "Bass:2", ":export clip writes the clip at the cursor")
  keys("ggVj")
  keys(":export " .. d .. "/part.mid selection<CR>")
  keys("<Esc>")
  eq(parts(d .. "/part.mid"), "Lead:1 Bass:2", ":export selection writes the selected tracks")
end)

T.last("guide: move a song between paw and REAPER", function()
  start()
  T.tone("Lead", 8)
  local d = dir("reaper")
  paw.project.save(d .. "/song")
  keys(":ext.load rpp<CR>")
  keys(":w " .. d .. "/song.rpp<CR>")
  eq(exists(d .. "/song.rpp"), true, ":w song.rpp writes a REAPER project")
  local page = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(page:find("Not written to song.rpp", 1, true) ~= nil, true, "a page lists what REAPER cannot take")
  keys("q")
  eq(paw.ui.focused, "arrange", "q closes the page")
  eq(paw.project.path, d .. "/song/project.toml", "the project stays where it was")
  keys(":e " .. d .. "/song.rpp<CR>")
  eq(paw.project.path, nil, ":e song.rpp opens the REAPER project as a new project")
  eq(#paw.tracks(), 1, "with its tracks")
  eq(paw.tracks()[1].name .. " " .. #paw.tracks()[1]:clips()[1]:notes(), "Lead 1", "with its tracks and notes")
  keys(":w " .. d .. "/from-reaper<CR>")
  eq(exists(d .. "/from-reaper/project.toml"), true, ":w saves it as a project of paw")
  eq(#paw.tracks()[1]:devices(), 0, "the synth stayed behind")
  keys(":rpp.import " .. d .. "/song.rpp merge=true<CR>")
  eq(#paw.tracks(), 2, "merge=true adds the tracks to the project")
  keys(":w<CR>")
  keys(":rpp.import " .. d .. "/song.rpp instrument=synth<CR>")
  eq(#paw.tracks(), 1, "rpp.import replaces the project")
  eq(paw.tracks()[1]:devices()[1].kind, "synth", "instrument=synth gives the MIDI track an instrument")
end)

--- `q` closes the page of what did not come across, when there is one.
local function close_page()
  if paw.ui.float then keys("q") end
end

T.last("guide: move a song between paw and REAPER, many times: placeholders return", function()
  start()
  local d = dir("reaper-again")
  T.write_file(d .. "/song.rpp", T.read_file("extensions/rpp/fixtures/render.rpp"))
  keys(":ext.load rpp<CR>")
  keys(":e " .. d .. "/song.rpp<CR>")
  close_page()
  eq(paw.track("Synth") ~= nil, true, "the song is open")
  keys(":w " .. d .. "/again.rpp<CR>")
  close_page()
  local text = T.read_file(d .. "/again.rpp")
  eq(text:find("VSTi: ReaSynth (Cockos)", 1, true) ~= nil, true, "the plugin paw could not use returns for REAPER")
  eq(text:find("eXNlcu9e7f4AAAAAAgAAAAEAAAAAAAAAAgAAAAAAAAA8AAAAAAAAAAAAEAA=", 1, true) ~= nil, true, "with its settings")
end)

T.last("guide: move a song between paw and other DAWs", function()
  start()
  T.tone("Lead", 8)
  local d = dir("dawproject")
  paw.project.save(d .. "/song")
  keys(":ext.load dawproject<CR>")
  T.write_file(d .. "/from-bitwig.dawproject", T.read_file("extensions/dawproject/fixtures/studio.dawproject"))
  keys(":e " .. d .. "/from-bitwig.dawproject<CR>")
  eq(paw.project.path, nil, ":e song.dawproject opens the song as a new project")
  eq(#paw.tracks(), 4, "with its tracks")
  eq(exists(d .. "/from-bitwig media/loop.wav"), true, "the audio goes into a folder beside the file")
  local page = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(page:find("Not carried over from from-bitwig.dawproject", 1, true) ~= nil, true, "a page lists what paw could not bring across")
  keys("q")
  eq(paw.ui.focused, "arrange", "q closes the page")
  keys(":w " .. d .. "/from-bitwig<CR>")
  eq(exists(d .. "/from-bitwig/project.toml"), true, ":w song keeps it as a project of paw")
  keys(":dawproject.import " .. d .. "/from-bitwig.dawproject merge=true<CR>")
  close_page()
  eq(#paw.tracks(), 8, "merge=true adds the tracks to the project")
  keys(":e! " .. d .. "/song<CR>")
  eq(paw.project.path, d .. "/song/project.toml", "back to the song")
  keys(":w " .. d .. "/song.dawproject<CR>")
  eq(T.read_file(d .. "/song.dawproject"):sub(1, 2), "PK", ":w song.dawproject writes one file")
  local page2 = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(page2:find("Not written to song.dawproject", 1, true) ~= nil, true, "a page lists what paw could not write")
  keys("q")
  eq(paw.project.path, d .. "/song/project.toml", "the project stays the folder song")
  -- With an audio clip, embed=false leaves the file out and refers to it.
  local wav = d .. "/take.wav"
  T.write_file(wav, T.read_file("extensions/dawproject/fixtures/studio/audio/loop.wav"))
  paw.tracks()[1]:add_clip({ start = 8, file = wav })
  keys(":dawproject.export " .. d .. "/small.dawproject embed=false<CR>")
  close_page()
  local files = require("dawproject").zip.read(T.read_file(d .. "/small.dawproject"))
  eq(files["audio/take.wav"], nil, "embed=false keeps the audio outside")
  eq(files["project.xml"]:find(wav, 1, true) ~= nil, true, "and refers to it where it is")
end)
