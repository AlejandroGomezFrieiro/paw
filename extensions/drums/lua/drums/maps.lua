-- Drum maps: which notes are which pieces of a kit, in the order the grid
-- shows them, top to bottom. A map is a plain table; `init.lua` can add one
-- or replace one:
--
--   local maps = require("drums").maps
--   maps.mykit = { label = "My kit", rows = { { note = 36, name = "Kick" }, { note = 40, name = "Snare" } } }
--   maps.gm.rows[2].name = "Snare (top)"
--
-- A track keeps a copy of the rows it was given, so a project opens the
-- same wherever it goes.
local M = {}

-- What a beat needs, in the General MIDI drum map. The built-in `drums`
-- device plays every one of these, and so does any kit that follows the
-- General MIDI map (MT-PowerDrumKit among them).
M.gm = {
  label = "General MIDI: the pieces a beat needs",
  rows = {
    { note = 36, name = "Kick" },
    { note = 38, name = "Snare" },
    { note = 37, name = "Rim" },
    { note = 39, name = "Clap" },
    { note = 42, name = "Closed hat" },
    { note = 44, name = "Pedal hat" },
    { note = 46, name = "Open hat" },
    { note = 50, name = "High tom" },
    { note = 47, name = "Mid tom" },
    { note = 45, name = "Low tom" },
    { note = 49, name = "Crash" },
    { note = 51, name = "Ride" },
    { note = 53, name = "Ride bell" },
    { note = 56, name = "Cowbell" },
    { note = 54, name = "Tambourine" },
  },
}

-- Every note of the General MIDI percussion map, 35 to 81, in order.
local gm_names = {
  [35] = "Acoustic kick", [36] = "Kick", [37] = "Side stick", [38] = "Snare", [39] = "Clap",
  [40] = "Electric snare", [41] = "Low floor tom", [42] = "Closed hat", [43] = "High floor tom",
  [44] = "Pedal hat", [45] = "Low tom", [46] = "Open hat", [47] = "Low-mid tom", [48] = "High-mid tom",
  [49] = "Crash", [50] = "High tom", [51] = "Ride", [52] = "China", [53] = "Ride bell",
  [54] = "Tambourine", [55] = "Splash", [56] = "Cowbell", [57] = "Crash 2", [58] = "Vibraslap",
  [59] = "Ride 2", [60] = "High bongo", [61] = "Low bongo", [62] = "Mute high conga",
  [63] = "Open high conga", [64] = "Low conga", [65] = "High timbale", [66] = "Low timbale",
  [67] = "High agogo", [68] = "Low agogo", [69] = "Cabasa", [70] = "Maracas", [71] = "Short whistle",
  [72] = "Long whistle", [73] = "Short guiro", [74] = "Long guiro", [75] = "Claves",
  [76] = "High wood block", [77] = "Low wood block", [78] = "Mute cuica", [79] = "Open cuica",
  [80] = "Mute triangle", [81] = "Open triangle",
}
M.gm_names = gm_names

local full = {}
for note = 35, 81 do full[#full + 1] = { note = note, name = gm_names[note] } end
M["gm-full"] = { label = "General MIDI: all 47 percussion notes", rows = full }

-- A kit of toms and cymbals as a drummer sets one up, for kits such as
-- MT-PowerDrumKit that have floor toms and two crashes.
M["gm-kit"] = {
  label = "General MIDI: a full drum kit, floor toms and two crashes",
  rows = {
    { note = 36, name = "Kick" },
    { note = 38, name = "Snare" },
    { note = 37, name = "Side stick" },
    { note = 40, name = "Snare 2" },
    { note = 42, name = "Closed hat" },
    { note = 44, name = "Pedal hat" },
    { note = 46, name = "Open hat" },
    { note = 48, name = "Tom 1" },
    { note = 47, name = "Tom 2" },
    { note = 45, name = "Tom 3" },
    { note = 43, name = "Floor tom 1" },
    { note = 41, name = "Floor tom 2" },
    { note = 49, name = "Crash" },
    { note = 57, name = "Crash 2" },
    { note = 55, name = "Splash" },
    { note = 52, name = "China" },
    { note = 51, name = "Ride" },
    { note = 53, name = "Ride bell" },
  },
}

-- MT-PowerDrumKit 2 (Manda Audio), from the vendor's note names for REAPER:
-- https://www.powerdrumkit.com/help-drum-map-Reaper.php
-- (MT-PowerDrumKit_2_Drum_Map_for_Reaper.zip). Not General MIDI for the
-- hats: 44 is the half-open hat and the pedal is 65. The kit also plays
-- the same pieces on other notes (35 kick, 39 and 40 snare, 43 47 50 the
-- toms, 60 to 63 the hats); a clip with those shows them on rows of their
-- own, named after General MIDI.
M["mt-powerdrumkit"] = {
  label = "MT-PowerDrumKit 2: its own note map",
  rows = {
    { note = 36, name = "Kick" },
    { note = 38, name = "Snare" },
    { note = 37, name = "Side stick" },
    { note = 42, name = "Hat closed" },
    { note = 44, name = "Hat half open" },
    { note = 46, name = "Hat open" },
    { note = 65, name = "Hat pedal" },
    { note = 48, name = "Tom high" },
    { note = 45, name = "Tom mid" },
    { note = 41, name = "Tom low" },
    { note = 49, name = "Crash left" },
    { note = 57, name = "Crash right" },
    { note = 58, name = "Crash right choked" },
    { note = 55, name = "Splash" },
    { note = 52, name = "China" },
    { note = 51, name = "Ride" },
    { note = 53, name = "Ride bell" },
    { note = 83, name = "Choke all cymbals" },
  },
}

return M
