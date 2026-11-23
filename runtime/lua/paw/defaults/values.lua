-- The default commands and keys: exact values. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local util = paw.util
local command, map = paw.command, paw.keymap.set
local cursor = paw.cursor
local common = require("paw.defaults.common")
local need_track, read_pan, param_reader = common.need_track, common.read_pan, common.param_reader

--
-- A prompt that takes a number (`-6` is -6), or `+=2` and `-=3` to step from the value now.

command("track.volume.set", function()
  local track = need_track()
  if not track then return end
  paw.ui.ask_value(
    { label = track.name .. " volume", now = track.volume, unit = "dB", min = -120, max = 24 },
    function(v)
      track.volume = v
      paw.notify(string.format("%s at %+.1f dB", track.name, track.volume))
    end
  )
end, { desc = "Type the track's volume in dB: a number (-6 is -6 dB), or +=2 and -=3 to step" })
command("track.pan.set", function()
  local track = need_track()
  if not track then return end
  paw.ui.ask_value({
    label = track.name .. " pan",
    now = util.round(track.pan * 100, 1),
    parse = read_pan,
    min = -100,
    max = 100,
    show = function(v) return paw.draw.pan_text(v / 100) end,
  }, function(v)
    track.pan = v / 100
    paw.notify(track.name .. " panned " .. paw.draw.pan_text(track.pan))
  end)
end, { desc = "Type the track's pan: L30, R25, C, or -100 to 100; +=10 and -=10 step" })
command("tempo.set", function()
  -- The tempo in force at the cursor: the change at or before it, in the
  -- window's map as the tempo lane edits it (inside a subproject with its
  -- own tempo, its own map).
  local point = paw.tempolane.point_at(cursor.beat)
  paw.ui.ask_value({ label = "Tempo", now = point.bpm, unit = "bpm", min = 1, max = 999 }, function(v)
    paw.tempolane.add(point.beat, v)
    paw.notify(
      string.format("tempo %g bpm from %s", v, point.beat == 0 and "the start" or "bar " .. paw.time.bar_of(point.beat))
    )
  end)
end, {
  desc = "Type the tempo in force at the cursor (the change at or before it) in bpm: a number, or +=2 and -=3 to step",
  label = "Set the tempo",
})

command("device.value", function()
  local device, row = paw.ui.views:get("devices"):selected()
  if not (device and row and row.param) then
    return paw.notify("choose a parameter in the device panel first", "warn")
  end
  local p = row.param
  paw.ui.ask_value({
    label = p.name,
    now = api.device_get(row.device.id).params[p.key],
    min = p.min,
    max = p.max,
    parse = param_reader(p),
    show = function(v) return paw.frontend.format_value(p, v) end,
  }, function(v)
    api.device_set_param(row.device.id, p.key, v)
    paw.notify(p.name .. " " .. paw.frontend.format_value(p, api.device_get(row.device.id).params[p.key]))
  end)
end, { desc = "Type the value of the parameter chosen in the device panel, in its own unit" })

for _, name in ipairs({ "arrange", "mixer" }) do
  map("grv", "track.volume.set", { view = name, desc = "Type the volume" })
  map("grp", "track.pan.set", { view = name, desc = "Type the pan" })
end
map("grt", "tempo.set", { desc = "Type the tempo" })
-- Tapped again and again in time; each tap sets the tempo from the taps so far.
map("<leader>Tt", "tempo.tap", { desc = "Tap the tempo (the beat): again and again, in time", repeatable = false })
-- The device panel's `c` and `=` are in paw/device_rows.lua.
