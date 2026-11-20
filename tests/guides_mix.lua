-- The how-to guides of the user guide about mixing, each driven with the
-- keys that it gives (docs/how-to/set-levels-and-pan.md and the others).
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

--- Keys that end in a prefix of a longer mapping (`]` and `]g`): they run
--- after the wait for the rest, as at the keyboard.
local function timed(text)
  local wait = paw.opt.timeoutlen
  paw.opt.timeoutlen = 20
  paw.keymap.feed(text)
  paw.wait(150)
  paw.opt.timeoutlen = wait
  api.undo_checkpoint()
end

local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 30), "\n") end

test("guide: set levels and pan, and keep the master out of the red", function()
  start()
  local guitar, bass = T.tone("Guitar", 8, "A3"), T.tone("Bass", 8, "A2")
  guitar.volume, bass.volume = 6, 6
  paw.flush()
  keys("<Space>m")
  eq(paw.ui.focused, "mixer", "Space m shows the mixer")
  keys("0")
  eq(paw.cursor.track_id(), guitar.id, "0 goes to the first strip")
  keys("2-")
  eq(guitar.volume, 4, "- lowers the fader a dB, a count gives the dB")
  keys("grv-4<CR>")
  eq(guitar.volume, -4, "grv types the level, -4 is -4 dB")
  keys("grv-=2<CR>")
  eq(guitar.volume, -6, "and -=2 steps from it")
  timed("3]")
  near(guitar.pan, 0.3, 1e-9, "] pans to the right")
  keys("grpL30<CR>")
  near(guitar.pan, -0.3, 1e-9, "grp types the pan")
  keys("l")
  eq(paw.cursor.track_id(), bass.id, "l goes to the next strip")

  -- The master in the red, then every fader lower.
  for _, t in ipairs({ guitar, bass }) do
    local synth = t:devices()[1]
    for _, p in ipairs(synth:info().params) do
      if p.key == "gain" then synth:set("gain", p.max) end
    end
  end
  keys("grv6<CR>")
  guitar.volume = 6
  paw.flush()
  local loud = T.render({ tail = 0, bits = 32 }).peak
  eq(loud > 1, true, "both faders up: the master goes over full scale (" .. loud .. ")")
  keys("0V$6-")
  eq(guitar.volume .. " " .. bass.volume, "0 0", "V$ selects every strip, and 6- lowers each fader")
  local quiet = T.render({ tail = 0, bits = 32 }).peak
  near(quiet, loud / 2, loud * 0.02, "the master is 6 dB lower (" .. quiet .. ")")
  keys("$")
  eq(paw.cursor.track_id(), 0, "$ goes to the Master strip")
  keys("aLimiter<CR>")
  eq(paw.master:devices()[1].kind, "limiter", "a adds a limiter on the master")
  keys("0V$6+")
  local limited = T.render({ tail = 0, bits = 32 }).peak
  eq(limited < 0.9, true, "keeps the peaks below its ceiling of -1 dB (" .. limited .. ")")
  keys("<Esc>")

  -- The same keys in the arrange view.
  paw.ui.focus("arrange")
  paw.cursor.set_track(bass)
  local level = bass.volume
  keys("3-")
  eq(bass.volume, level - 3, "- in the arrange view lowers the track")
  timed("2[")
  near(bass.pan, -0.2, 1e-9, "[ pans to the left")
end)

test("guide: add an effect and change its settings", function()
  start()
  local vocal = T.tone("Vocal", 8)
  paw.ui.focus("arrange")
  paw.cursor.set_track(vocal)
  keys("aCompressor<CR>")
  local comp = vocal:devices()[2]
  eq(comp.kind, "compressor", "a adds the device at the end of the chain")
  keys("<Space>d")
  eq(paw.ui.focused, "devices", "Space d shows the device panel")
  keys("w")
  local function row()
    local device, r = paw.ui.views.devices:selected()
    return (r and r.param and r.param.key) or (r and r.device and "device " .. r.device.kind) or tostring(device)
  end
  eq(row(), "device compressor", "w goes to the next device")
  keys("fThreshold<CR>")
  eq(row(), "threshold", "f finds a parameter by name")
  keys("c=-24<CR>")
  eq(comp.params.threshold, -24, "c types its value")
  keys("j")
  eq(row(), "ratio", "j goes to the next parameter")
  keys("c4<CR>")
  eq(comp.params.ratio, 4, "c4 sets the ratio to 4:1")
  keys("5+")
  eq(comp.params.ratio > 4, true, "+ raises it, by the count")
  keys("x")
  eq(comp.params.ratio, 2, "x puts it back at its default")
  keys("b")
  eq(row(), "device compressor", "b goes to the row of the device")
  keys("cVocal<CR>")
  eq(comp.params.threshold .. " " .. comp.params.ratio, "-20 3", "c on the device chooses a preset")
  keys("]p")
  eq(comp.params.threshold, -18, "]p loads the next preset")
  keys("gcc")
  eq(comp:get().bypass, true, "gcc bypasses the device")
  keys("gcc")
  eq(comp:get().bypass, false, "and gcc again brings it back")
  keys("x")
  eq(#vocal:devices(), 1, "x on the device removes it")
  keys("u")
  eq(#vocal:devices(), 2, "and u brings it back")
end)

test("guide: send several tracks to one reverb", function()
  start()
  local guitar, keys_track, pad = T.tone("Guitar", 8), T.tone("Keys", 8, "E4"), T.tone("Pad", 8, "C4")
  paw.ui.focus("arrange")
  paw.cursor.set_track(pad)
  keys("o")
  keys("grnReverb<CR>")
  local reverb = paw.track("Reverb")
  eq(reverb.index, 4, "o adds the reverb track below")
  keys("aReverb<CR>")
  eq(reverb:devices()[1].kind, "reverb", "a puts a reverb on it")
  keys("<Space>d")
  keys("fMix<CR>")
  keys("c100<CR>")
  eq(reverb:devices()[1].params.mix, 100, "the reverb gives only the wet sound")
  keys("<Space>d")
  eq(paw.ui.focused, "arrange", "back in the arrange view")
  keys("gg")
  eq(paw.cursor.track_id(), guitar.id, "gg goes to the first track")
  keys("<Space>sReverb<CR>")
  local sends = guitar:get().sends
  eq(#sends, 1, "Space s sends the track")
  eq(sends[1].target, reverb.id, "to the reverb track")
  eq(sends[1].level, paw.opt.send_level, "at the level of a new send")
  keys("j")
  keys(":send Reverb -9<CR>")
  eq(keys_track:get().sends[1].level, -9, ":send gives the level")
  keys("j@:")
  eq(pad:get().sends[1].level, -9, "j@: sends the next track the same way")
  keys("u")
  eq(#pad:get().sends, 0, "u takes the send away")
  keys("@:")
  -- Many tracks in one step, and a new level for a send that is there.
  keys("ggVjj:send Reverb -9<CR>")
  eq(guitar:get().sends[1].level .. " " .. #pad:get().sends, "-9 1", "V selects the tracks, :send sends each")
  keys("<Esc>gg:send Reverb -12<CR>")
  eq(guitar:get().sends[1].level, -12, ":send again with a level changes the send")

  -- The level of a send in the mixer.
  keys("<Space>m")
  keys("0")
  eq(paw.cursor.track_id(), guitar.id, "the strip of the guitar")
  keys("k")
  eq(paw.mixer_rows.current().kind, "send", "k goes up from the fader to the send")
  keys("3+")
  eq(guitar:get().sends[1].level, -9, "+ raises the send by a dB, by the count")
  keys("x")
  eq(#guitar:get().sends, 0, "x removes the send")
  keys("u")
  keys("<Esc>")

  local with = T.render({ tail = 1 }).peak
  reverb.mute = true
  local without = T.render({ tail = 1 }).peak
  eq(with > without, true, "the reverb track adds to the mix")
end)

T.last("guide: check the mix", function()
  start()
  local pad = T.tone("Pad", 16)
  paw.ui.focus("arrange")
  paw.cursor.set_track(pad)
  -- A stereo effect with one side upside down: it cancels in mono.
  keys("aUtility<CR>")
  pad:devices()[2]:set("invert_r", 1)
  paw.flush()

  -- The meters while the song plays.
  keys("<Space>m")
  keys("<Space><Space>")
  local loudest = 0
  T.until_(function()
    loudest = math.max(loudest, (api.track_meter(0)))
    return loudest >= 0.01
  end, "the master meter to move while the song plays")
  keys("<Space><Space>")
  eq(loudest > 0.01, true, "the master strip meters the mix")
  keys("<Esc>")
  paw.ui.focus("arrange")

  keys(":ext.load mixdiag<CR>")
  local mixdiag = require("mixdiag")
  keys("<Space>xa")
  eq(mixdiag.job ~= nil, true, "Space xa measures the song")
  T.until_(function()
    mixdiag.poll()
    return not mixdiag.job
  end, "the measurement to end", 60000)
  eq(mixdiag.job, nil, "the measurement ends")
  eq(mixdiag.line:find("LUFS", 1, true) ~= nil, true, "the message gives the loudness: " .. mixdiag.line)
  local rules = {}
  for _, f in ipairs(mixdiag.findings) do rules[f.rule] = f end
  eq(rules.mono ~= nil, true, "a finding says the mix cancels in mono")
  eq(rules.phase ~= nil and rules.phase.beat ~= nil, true, "and a phase finding has its place")
  paw.cursor.set_beat(12)
  timed("]d")
  eq(paw.cursor.beat, rules.phase.beat, "]d goes to it")
  keys("<Space>xs")
  eq(mixdiag.summary():find("mono loss", 1, true) ~= nil, true, "Space xs gives the mono loss too")
  keys("<Space>xr")
  eq(screen(120, 40):find("mono", 1, true) ~= nil, true, "Space xr opens the report with the findings")
  keys("q")
  mixdiag.clear()
end)
