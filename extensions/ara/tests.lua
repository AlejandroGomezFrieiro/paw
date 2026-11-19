-- Tests of the ara extension; tests/suite.lua runs them. They host the ARA
-- SDK's test plug-in ($PAW_TEST_ARA, the package that holds
-- lib/clap/ARATestPlugIn.clap) through the attachment ($PAW_ARA_BRIDGE);
-- the dev shell sets both. Elsewhere they are skipped.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api

local KIND = "clap:org.ara-audio.examples.testplugin.clap"

local ara
local function ready()
  local dir = os.getenv("PAW_TEST_ARA")
  if not dir or not os.getenv("PAW_ARA_BRIDGE") then return nil, "PAW_TEST_ARA and PAW_ARA_BRIDGE are not set" end
  if not ara then
    paw.ext.load("extensions/ara")
    ara = require("ara")
    paw.plugins.add_dir(dir .. "/lib/clap")
  end
  local ok, err = ara.attach()
  if not ok then return nil, err end
  return ara
end

--- A mono WAV at the engine's rate: four bursts of a sine 0.25 s long,
--- with silence between them, as the test plug-in finds notes.
local function bursts(path, rate)
  local frames = rate * 2
  local out = {}
  for i = 0, frames - 1 do
    local t = i / rate
    local on = (t % 0.5) < 0.25
    local v = on and math.floor(0.5 * math.sin(2 * math.pi * 440 * t) * 32767) or 0
    if on and v == 0 then v = 1 end
    out[#out + 1] = string.char(v % 256, math.floor(v / 256) % 256)
  end
  local data = table.concat(out)
  local function u32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256) end
  local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
  T.write_file(path, "RIFF" .. u32(36 + #data) .. "WAVEfmt " .. u32(16) .. u16(1) .. u16(1) .. u32(rate) .. u32(rate * 2)
    .. u16(2) .. u16(16) .. "data" .. u32(#data) .. data)
end

--- A track with the bursts as a clip from beat 0, quiet in paw (its gain
--- at -60 dB), so that what sounds loud was read by the plugin.
local function vocal_track()
  local rate = api.engine_get().sample_rate or 48000
  local file = T.scratch .. "/bursts.wav"
  bursts(file, rate)
  local track = paw.add_track({ name = "Vox" })
  local clip = track:add_clip({ file = file, start = 0, gain = -60 })
  return track, clip
end

test("ara: \\aa puts the ARA plugin on the track, and a render plays the clip as the plugin read it", function()
  local a, why = ready()
  if not a then return why end
  fresh()
  local track, clip = vocal_track()
  paw.ui.focus("arrange")
  paw.cursor.set_track(track.id)
  T.keys(paw.opt.localleader .. "aa")
  T.keys("<CR>")
  local devices = a.devices(track.id)
  eq(#devices, 1, "the plugin is on the track")
  eq(#a.status(devices[1]).clips, 1, "with the clip")
  local info = T.render({ ["end"] = 4, tail = 0, bits = 16 })
  local loud = T.channel_peaks(info, 0, 0.25)
  near(loud, 0.5, 0.05, "the burst sounds at the level of the file, not the clip's -60 dB")
  local quiet = T.channel_peaks(info, 0.3, 0.45)
  near(quiet, 0, 0.01, "silence between the bursts")
  -- The clip moves: the plugin plays it where it is now.
  api.clip_set(clip.id, "start", 2)
  paw.flush()
  info = T.render({ ["end"] = 4, tail = 0, bits = 16 })
  near(T.channel_peaks(info, 0, 0.9), 0, 0.01, "nothing before the clip")
  -- Undo puts the clip back where it was, and the plugin with it.
  paw.undo()
  paw.flush()
  info = T.render({ ["end"] = 4, tail = 0, bits = 16 })
  near(T.channel_peaks(info, 0, 0.25), 0.5, 0.05, "after undo, the burst is at the start again")
end)

test("ara: a plugin that is not ARA is refused and leaves no undo step", function()
  local a, why = ready()
  if not a then return why end
  fresh()
  local track = paw.add_track({ name = "Keys" })
  api.undo_checkpoint()
  local before = api.undo_current()
  local id, err = a.add(track.id, "synth")
  eq(id, nil, "not added")
  eq(err:find("not an ARA plugin", 1, true) ~= nil, true, "says why")
  eq(api.undo_current(), before, "no undo step")
  eq(#api.track_get(track.id).devices, 0, "the chain is as it was")
end)

test("ara: the plugin's archive is saved beside its state and given back when the project opens", function()
  local a, why = ready()
  if not a then return why end
  fresh()
  local track = vocal_track()
  local device = assert(a.add(track.id, KIND))
  -- The plugin analyzes the clip; its archive then holds the notes.
  for _ = 1, 200 do
    if a.notes(device) then break end
    paw.wait(50)
  end
  local dir = T.scratch .. "/ara-song"
  paw.project.save(dir)
  local files = api.read_dir(dir .. "/tracks/Vox")
  local found
  for _, f in ipairs(files) do if f.name:match("%.ara$") then found = f.name end end
  eq(found ~= nil, true, "a .ara file beside the state")
  -- A new session: the plugin is made again from the files.
  fresh()
  paw.project.load(dir)
  paw.flush()
  local again = a.devices(paw.track("Vox").id)[1]
  eq(again ~= nil, true, "the plugin is there again")
  local status = a.status(again)
  eq(status.restored, true, "it took its archive back")
  eq(status.error, "", "without an error")
  eq(a.notes(again) ~= nil, true, "the notes are there without a new analysis")
end)

test("ara: \\an makes a MIDI clip of the notes the plugin heard, as one undo step", function()
  local a, why = ready()
  if not a then return why end
  fresh()
  local track = vocal_track()
  assert(a.add(track.id, KIND))
  paw.ui.focus("arrange")
  paw.cursor.set_track(track.id)
  local tracks = #api.track_list()
  T.keys(paw.opt.localleader .. "an")
  for _ = 1, 200 do
    if #api.track_list() > tracks then break end
    paw.wait(50)
  end
  local notes = paw.track("Vox notes")
  eq(notes ~= nil, true, "a track for the notes")
  local clip = notes:clips()[1]
  local got = clip:notes()
  eq(#got, 4, "a note for each burst")
  near(got[2].start + clip.start, 1, 0.01, "the second burst is at beat 1 (0.5 s at 120 bpm)")
  near(got[1].length, 0.5, 0.01, "a quarter of a second long")
  api.undo_checkpoint()
  paw.undo()
  eq(paw.track("Vox notes"), nil, "one undo takes the track and the clip away")
end)
