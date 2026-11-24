-- The test project ruler-everything: a song with each row and mark of the
-- ruler that paw and its bundled extensions give. tests/ruler.lua draws it
-- at three zoom levels and in a narrow window, and tests/time_axis.lua
-- checks that each sign of it is in the column of its time.
--
-- Use: `local everything = dofile("tests/fixtures/ruler_everything.lua")`,
-- then `local song = everything(T)` in a test. It gives the beats of the
-- marks, for the checks.
--
-- 4/4 at 120 bpm. Bars 1 to 8 are 4/4 (beats 0 to 32), bars 9 to 14 are
-- 6/8 (3 beats a bar, beats 32 to 50), and 4/4 again from beat 50.
return function(T)
  local api = paw.api
  T.start()
  paw.ui.focus("arrange")
  paw.project.tempo = 120
  paw.opt.grid = 1
  api.signature_set(32, 6, 8)
  api.signature_set(50, 4, 4)
  api.tempo_set(12, 90)
  api.tempo_set(40, 100)
  api.tempo_set(58, 110)
  -- A chord progression for the chords of rulerplus: C, F, G, then Am.
  local piano = paw.add_part({ name = "Piano" })
  local notes = {}
  for i, chord in ipairs({ { 60, 64, 67 }, { 65, 69, 72 }, { 67, 71, 74 }, { 69, 72, 76 } }) do
    for _, pitch in ipairs(chord) do
      notes[#notes + 1] = { pitch = pitch, start = (i - 1) * 8, length = 8 }
    end
  end
  piano:add_clip({ name = "chords", start = 0, length = 32, notes = notes })
  local bass = paw.add_part({ name = "Bass" })
  bass:add_clip({ name = "bass", start = 16, length = 34, notes = { { pitch = 40, start = 0, length = 2 } } })
  -- Regions three levels deep, and two cues.
  paw.markers.add(0, "Intro", { length = 16 })
  paw.markers.add(16, "Verse", { length = 34 })
  paw.markers.add(16, "Verse A", { length = 16 })
  paw.markers.add(32, "Pre", { length = 18 })
  paw.markers.add(40, "Hit", { length = 4 })
  paw.markers.add(50, "Chorus", { length = 32 })
  paw.markers.add(12, "mk")
  paw.markers.add(46, "drop")
  -- The loop and the punch range overlap.
  paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 16, 32, true
  paw.transport.punch_start, paw.transport.punch_end, paw.transport.punch_enabled = 24, 36, true
  paw.transport.seek(21)
  -- A time fold, the tempo lane, and the counts of relativebar.
  paw.folds.make({ kind = "range", from = 64, to = 72 })
  paw.tempolane.show(true)
  paw.opt.relativebar = true
  -- rulerplus and sections, the extensions that add to the ruler.
  paw.ext.load("extensions/rulerplus")
  paw.ext.load("extensions/sections")
  local sections = require("sections")
  sections.add("Intro", 0)
  sections.add("Verse", 16)
  T.after(function()
    paw.transport.loop_enabled, paw.transport.punch_enabled = false, false
    paw.tempolane.show(false)
    paw.opt.relativebar = false
    for _, name in ipairs({ "rulerplus", "sections" }) do
      if paw.ext.loaded[name] then paw.ext.unload(name) end
    end
  end)
  paw.flush()
  T.advance_until(function() return paw.harmony.fresh() end, "the chords to be read", 2000)
  paw.cursor.set_part(piano.id)
  paw.cursor.set_beat(8)
  paw.opt.zoom = 1
  paw.ui.views:get("arrange").scroll = 0
  return {
    piano = piano,
    bass = bass,
    meter = { 32, 50 },
    tempo = { 12, 40, 58 },
    cues = { 12, 46 },
    loop = { 16, 32 },
    punch = { 24, 36 },
    playhead = 21,
  }
end
