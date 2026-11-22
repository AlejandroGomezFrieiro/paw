-- A song to try the drums extension with, from the root of the source:
--
--   paw -e 'dofile("extensions/drums/demo.lua")'
--   paw-gui -e 'dofile("extensions/drums/demo.lua")'
--
-- A drum track on the built-in kit with a groove and a fill, bass under it,
-- and a second drum track whose instrument is the synth, standing in for a
-- plugin kit such as MT-PowerDrumKit. Enter on a clip of either (or a double
-- click in the window) opens the drum grid.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "extensions/drums"
if not package.loaded.drums then paw.ext.load(here) end
local drums = require("drums")

paw.project.new()
paw.project.name = "Drums demo"
paw.project.tempo = 96

--- Hits from a bar of steps per piece: `x` a hit, `X` an accent, `o` a ghost.
local function pattern(rows, step, offset)
  local notes, velocity = {}, { x = 100, X = 124, o = 48 }
  for note, steps in pairs(rows) do
    for i = 1, #steps do
      local v = velocity[steps:sub(i, i)]
      if v then
        notes[#notes + 1] = { pitch = note, start = (offset or 0) + (i - 1) * step, length = step, velocity = v }
      end
    end
  end
  return notes
end

local kit = drums.make_track({ name = "Drums" })
local groove = {
  [49] = "X...............",
  [42] = "..x.x.x.x.x.x.xo",
  [46] = "...............x",
  [38] = "....X..o.o..X...",
  [37] = "..........o.....",
  [36] = "x.....x...x..x..",
}
local fill = {
  [42] = "x.x.x.x.........",
  [38] = "....X.......X.XX",
  [50] = "........XX......",
  [47] = "..........XX....",
  [45] = "............X...",
  [36] = "x.....x.x.......",
}
local notes = pattern(groove, 0.25)
for _, n in ipairs(pattern(groove, 0.25, 4)) do
  if n.pitch ~= 49 then notes[#notes + 1] = n end
end
for _, n in ipairs(pattern(groove, 0.25, 8)) do
  if n.pitch ~= 49 then notes[#notes + 1] = n end
end
for _, n in ipairs(pattern(fill, 0.25, 12)) do
  notes[#notes + 1] = n
end
local beat = kit:add_clip({ start = 0, length = 16, name = "groove", notes = notes })
kit:add_clip({ start = 16, length = 16, name = "groove", notes = notes })

local bass = paw.add_track({ name = "Bass", volume = -5 })
bass:add_device("synth", { wave = 1, cutoff = 500, release = 0.05 })
local roots = { 38, 38, 41, 36 }
for bar = 0, 7 do
  local root, n = roots[bar % 4 + 1], {}
  for s = 0, 7 do
    n[#n + 1] = { pitch = root + (s == 6 and 12 or 0), start = s * 0.5, length = 0.4 }
  end
  bass:add_clip({ start = bar * 4, length = 4, name = "bass", notes = n })
end

-- What a plugin kit looks like: any instrument, with a drum map on the track.
local plugin = paw.add_track({ name = "Plugin kit", volume = -12 })
plugin:add_device("synth", { wave = 3, attack = 0.001, decay = 0.08, sustain = 0, release = 0.05 })
drums.set_map(plugin, "gm-kit")
plugin:add_clip({
  start = 0,
  length = 8,
  name = "toms",
  notes = pattern(
    { [48] = "X.x.x.x.........", [45] = "........x.x.x.x.", [43] = "........X.......", [49] = "X..............." },
    0.25
  ),
})

paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 16, true
paw.cursor.set_track(kit)
paw.cursor.set_beat(beat.start)
