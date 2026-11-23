-- Tests of hearing what is under a picker's selection (`paw.audition`, the
-- `audition` hook of `paw.pick`): the rest before it plays, what plays,
-- and that cancelling leaves the project and its undo history as they
-- were. Loaded by tests/suite.lua with its helpers.
local T = ...
local advance = T.advance
local test, eq, fresh, after = T.test, T.eq, T.fresh, T.after
local api = paw.api

local function start()
  fresh()
  api.engine_restart({})
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  paw.audition.stop()
  paw.audition.heard = {}
  for _, key in ipairs({ "presets", "devices", "files", "drums.beat", "snippets", "Sounds" }) do
    paw.state["pick.audition." .. key] = nil
  end
end

local keys = T.keys

local function heard() return paw.pick.state() and paw.pick.state().audition end

--- A track with a synth and a bar of notes from beat 0.
local function keys_track()
  local t = paw.add_track({ name = "Keys" })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  t:add_clip({
    start = 0,
    length = 4,
    notes = {
      { pitch = "C4", start = 0, length = 1 },
      { pitch = "E4", start = 1, length = 1 },
      { pitch = "G4", start = 2, length = 2 },
    },
  })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  return t
end

local function pitches(notes)
  local out = {}
  for i, n in ipairs(notes or {}) do
    out[i] = paw.music.name(n.pitch)
  end
  return table.concat(out, " ")
end

-- The picker -------------------------------------------------------------------

test("a picker hears the item the selection rests on, once, after the delay", function()
  start()
  local calls = {}
  paw.pick({
    title = "Sounds",
    items = { "one", "two", "three", "four" },
    audition = function(item)
      calls[#calls + 1] = item
      return "hearing " .. item
    end,
    on_choose = function() end,
  })
  eq(#calls, 0, "nothing is heard before the selection has rested")
  keys("<C-n><C-n>")
  eq(#calls, 0, "moving on before the delay hears nothing")
  T.advance_until(function() return #calls > 0 end, "then it is heard", 5000)
  advance(paw.opt.audition_delay + 100)
  eq(table.concat(calls, " "), "three", "only the item rested on")
  eq(heard().label, "hearing three", "the label the pane shows")
  local screen = table.concat(api.ui_snapshot(120, 30), "\n")
  eq(screen:find("♪ hearing three", 1, true) ~= nil, true, "the pane says what plays")
  eq(screen:find("C-Space hear", 1, true) ~= nil, true, "the footer names the key")
  keys("<Esc>")
end)

test("Ctrl-Space turns hearing off and on, and the picker remembers it", function()
  start()
  local calls = 0
  local spec = {
    title = "Sounds",
    items = { "one", "two" },
    audition = function() calls = calls + 1 end,
    on_choose = function() end,
  }
  paw.pick(spec)
  keys("<C-Space>")
  eq(heard().on, false, "off")
  keys("<C-n>")
  advance(paw.opt.audition_delay + 100)
  eq(calls, 0, "nothing is heard while it is off")
  eq(
    table.concat(api.ui_snapshot(120, 30), "\n"):find("off · Ctrl-Space hears", 1, true) ~= nil,
    true,
    "the pane says it is off"
  )
  keys("<Esc>")
  paw.pick(spec)
  eq(heard().on, false, "still off when opened again")
  keys("<C-Space>")
  T.advance_until(function() return calls == 1 end, "on again, it hears the item under the selection", 5000)
  keys("<Esc>")
end)

-- Presets ----------------------------------------------------------------------

test("a preset is heard as a trial over the track's own bar, and Escape leaves no trace", function()
  start()
  local t = keys_track()
  local device = t:devices()[1]
  local before = api.device_get(device.id).params.cutoff
  local undo = api.undo_current()
  paw.fx.pick(device)
  keys("Pluck")
  T.advance_until(function() return heard() and heard().item ~= nil end, "it is heard", 5000)
  eq(api.device_get(device.id).params.cutoff, 3000, "the preset is loaded")
  eq(api.trial_active(), true, "as a trial")
  local now = paw.audition.state()
  eq(now.kind .. " " .. pitches(now.notes), "phrase C4 E4 G4", "the track's bar plays")
  eq(heard().label, "Pluck · loop bar 1", "and the pane says so")
  T.advance_until(function() return #paw.audition.heard >= 3 end, "its notes reach the track", 5000)
  eq(paw.audition.heard[1].track, t.id, "through the track")
  keys("<Esc>")
  eq(api.device_get(device.id).params.cutoff, before, "Escape puts the device back")
  eq(api.trial_active(), false, "the trial is over")
  eq(api.undo_current(), undo, "no undo step was made")
  eq(paw.audition.state(), nil, "and nothing plays")
end)

test("choosing the preset heard keeps it as one undo step", function()
  start()
  local t = keys_track()
  local device = t:devices()[1]
  local before = api.device_get(device.id).params.cutoff
  paw.fx.pick(device)
  keys("Sub bass")
  T.advance_until(function() return heard() and heard().item ~= nil end, "the selection to be heard", 5000)
  keys("<CR>")
  eq(api.device_get(device.id).params.cutoff, 400, "the preset stays")
  eq(api.trial_active(), false, "the trial is over")
  keys("u")
  eq(api.device_get(device.id).params.cutoff, before, "one undo takes it back")
end)

test("moving through presets keeps the bar going and swaps only the sound", function()
  start()
  local t = keys_track()
  local device = t:devices()[1]
  paw.fx.pick(device)
  keys("Pluck")
  T.advance_until(function() return heard() and heard().item ~= nil end, "the selection to be heard", 5000)
  local first = paw.audition.state()
  keys("<C-u>Saw")
  T.advance_until(
    function() return heard() and heard().label == "Saw bass · loop bar 1" end,
    "the next preset is heard",
    5000
  )
  eq(api.device_get(device.id).params.cutoff, 900, "and loaded")
  eq(paw.audition.state().notes == first.notes, true, "over the same phrase, not started again")
  keys("<Esc>")
end)

-- Devices ----------------------------------------------------------------------

test("an instrument tried from the device picker plays a phrase, and is gone again on cancel", function()
  start()
  local t = paw.add_track({ name = "Empty" })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_track(t)
  local undo = api.undo_current()
  paw.pick("devices", { query = "synth @instrument" })
  T.advance_until(function() return heard() and heard().item ~= nil end, "it is heard", 5000)
  eq(#t:devices(), 1, "the instrument is on the track while it is heard")
  local now = paw.audition.state()
  eq(now.kind, "phrase", "a phrase plays")
  eq(#now.notes > 0, true, "a built-in one, the track having no notes")
  eq(heard().label:find("built-in phrase", 1, true) ~= nil, true, "the pane says so: " .. heard().label)
  keys("<Esc>")
  eq(#t:devices(), 0, "cancelling takes it away")
  eq(api.undo_current(), undo, "and no undo step was made")
end)

test("choosing the instrument heard keeps that one, as one undo step", function()
  start()
  local t = paw.add_track({ name = "Empty" })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_track(t)
  paw.pick("devices", { query = "synth @instrument" })
  T.advance_until(function() return heard() and heard().item ~= nil end, "the selection to be heard", 5000)
  local id = t:devices()[1].id
  keys("<CR>")
  eq(#t:devices(), 1, "one instrument")
  eq(t:devices()[1].id, id, "the very one heard, not another made")
  keys("u")
  eq(#t:devices(), 0, "one undo takes it away")
end)

-- Files ------------------------------------------------------------------------

test("a sound file in the file picker plays on its own, with its outline in the pane", function()
  start()
  after(function() paw.opt.audition_level = -12 end)
  local undo = api.undo_current()
  paw.opt.audition_level = -6
  paw.pick.file({ dir = "tests/fixtures", extensions = { "wav" }, on_choose = function() end })
  keys("tone-mono-8k")
  T.advance_until(function()
    local s = paw.audition.state()
    return s and s.kind == "file" and s.state ~= "loading"
  end, "it is read and played", 5000)
  local s = paw.audition.state()
  eq(s.file:match("[^/]*$"), "tone-mono-8k.wav", "that file")
  eq(s.level, -6, "at the audition level")
  eq(#s.outline, 256, "with its outline")
  eq(s.length > 0, true, "and its length")
  local screen = table.concat(api.ui_snapshot(120, 30), "\n")
  eq(screen:find("tone-mono-8k.wav", 1, true) ~= nil, true, "the pane names it")
  eq(screen:find("[▁▂▃▄▅▆▇█]") ~= nil, true, "and draws its outline")
  T.until_(function() return paw.audition.state().state == "ended" end, "the file played to its end")
  keys("<Esc>")
  eq(paw.audition.state(), nil, "Escape stops it")
  eq(api.undo_current(), undo, "the project never knew")
  eq(#api.track_list(), 0, "nothing was added")
end)

test("a MIDI file in the file picker plays its first bars through an instrument tried for it", function()
  start()
  local path = T.scratch .. "/audition-tune.mid"
  local src = paw.add_track({ name = "Src" })
  src:add_clip({
    start = 0,
    length = 16,
    notes = {
      { pitch = "C4", start = 0, length = 1 },
      { pitch = "D4", start = 4, length = 1 },
      { pitch = "E4", start = 12, length = 1 },
    },
  })
  paw.midifile.export(path, {})
  fresh()
  api.undo_checkpoint()
  local undo = api.undo_current()
  paw.pick.file({ dir = T.scratch, extensions = { "mid" }, on_choose = function() end })
  keys("audition-tune")
  T.advance_until(function() return heard() and heard().item ~= nil end, "it is heard", 5000)
  local now = paw.audition.state()
  eq(pitches(now.notes), "C4 D4", "its first two bars")
  eq(heard().label, "first 2 bars at 120 BPM", "the pane says so")
  eq(#api.track_list(), 1, "through an instrument added for it")
  keys("<Esc>")
  eq(#api.track_list(), 0, "taken away again")
  eq(api.undo_current(), undo, "without an undo step")
end)

-- Beats and snippets -----------------------------------------------------------

test("a beat is written into the clip as a trial and its first bar played; Escape gives the notes back", function()
  start()
  if not paw.ext.loaded.drums then paw.ext.load("extensions/drums") end
  paw.cmd("drums.track")
  local t = paw.cursor.track()
  paw.cursor.set_beat(0)
  local clip = paw.cursor.clip() or t:add_clip({ start = 0, length = 8 })
  clip.length = 8
  for i = #clip:notes(), 1, -1 do
    clip:remove_note(i)
  end
  clip:add_note({ pitch = 81, start = 0, length = 0.25 })
  paw.flush()
  api.undo_checkpoint()
  local undo = api.undo_current()
  paw.commands.exec("drums.beat")
  keys("rock")
  T.advance_until(function() return heard() and heard().item ~= nil end, "it is heard", 5000)
  eq(#clip:notes(), 2 * (8 + 2 + 3), "the beat is in the clip while it is heard")
  local now = paw.audition.state()
  eq(#now.notes, 8 + 2 + 3, "one bar of it plays")
  eq(now.length, 4, "over and over")
  eq(heard().label, "rock · its first bar", "the pane says so")
  keys("<Esc>")
  eq(#clip:notes(), 1, "Escape gives the clip its notes back")
  eq(api.undo_current(), undo, "and makes no undo step")
end)

test("a snippet is heard over the harmony around it, and nothing is written until it is chosen", function()
  start()
  -- A snippet of the test's own: the extension's would be left loaded for
  -- the tests after this one.
  paw.snippet.add({
    name = "dominant",
    source = "config",
    expand = function(ctx)
      return { notes = { { pitch = 67, start = ctx.at, length = 4 }, { pitch = 71, start = ctx.at, length = 4 } } }
    end,
  })
  after(function() paw.snippet.remove("dominant") end)
  local strings = paw.add_track({ name = "Strings" })
  strings:add_device("synth")
  strings:add_clip({
    start = 0,
    length = 8,
    notes = {
      { pitch = "C3", start = 4, length = 4 },
      { pitch = "E3", start = 4, length = 4 },
      { pitch = "G3", start = 4, length = 4 },
    },
  })
  local piano = paw.add_track({ name = "Piano" })
  piano:add_device("synth")
  local clip = piano:add_clip({ start = 0, length = 8, notes = {} })
  paw.flush()
  api.undo_checkpoint()
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(clip)
  roll:set(60, 0)
  paw.ui.focus("pianoroll")
  keys("<C-s>")
  keys("dominant")
  T.advance_until(function() return heard() and heard().item ~= nil end, "it is heard", 5000)
  local now = paw.audition.state()
  local tracks = {}
  for _, n in ipairs(now.notes) do
    tracks[n.track] = true
  end
  eq(tracks[piano.id], true, "its notes, through the piano")
  eq(#clip:notes(), 0, "nothing written yet")
  eq(heard().label:find("^dominant") ~= nil, true, "the pane says what plays: " .. heard().label)
  keys("<Esc>")
  eq(#clip:notes(), 0, "nor after Escape")
  paw.ui.focus("arrange")
end)

-- Trials -----------------------------------------------------------------------

test("a trial taken back leaves a saved project unmodified, and undo during one calls it off", function()
  start()
  local t = keys_track()
  local device = t:devices()[1]
  t.volume = -3
  api.undo_checkpoint()
  paw.project.save(T.scratch .. "/audition.json")
  eq(api.project_get().modified, false, "saved")
  local before = api.device_get(device.id).params.cutoff
  paw.audition.try(function() paw.fx.load(device, "Pluck") end)
  paw.flush()
  api.undo_checkpoint()
  eq(api.project_get().modified, true, "modified while the trial stands")
  paw.audition.revert()
  paw.flush()
  api.undo_checkpoint()
  eq(api.project_get().modified, false, "not after it is taken back")
  eq(api.device_get(device.id).params.cutoff, before, "the device as it was")
  paw.audition.try(function() paw.fx.load(device, "Pluck") end)
  paw.undo()
  eq(api.trial_active(), false, "undo calls the trial off")
  eq(api.device_get(device.id).params.cutoff, before, "the preset is gone with it")
  eq(t.volume, 0, "and the step before is what is undone")
end)
