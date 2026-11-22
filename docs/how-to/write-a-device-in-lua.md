# How to write a device in Lua

<!-- tags: writing-a-device-in-lua -->

You can make an effect in Lua. The example is a tilt equalizer with an
output level, and each field and helper is in
[Lua devices](../reference/lua-devices.md).

1. Make the file `~/.config/paw/devices/tilt.lua` with the following text:

   ```lua
   local dsp = require("paw.dsp")

   local dev = dsp.device {
     name = "Tilt",
     params = {
       { key = "tilt", name = "Tilt", min = -6, max = 6, default = 0, unit = "dB" },
       { key = "output", name = "Output", min = -12, max = 12, default = 0, unit = "dB" },
     },
   }

   local low, high

   function dev.init(sample_rate)
     low = { dsp.biquad(), dsp.biquad() }
     high = { dsp.biquad(), dsp.biquad() }
   end

   function dev.process(b)
     local p = b.params
     for ch = 1, 2 do
       low[ch]:set("lowshelf", 800, 0.7, -p.tilt, b.sample_rate)
       high[ch]:set("highshelf", 800, 0.7, p.tilt, b.sample_rate)
     end
     local g = dsp.gain(p.output)
     for i = 0, b.frames - 1 do
       b.left[i] = g * high[1]:process(low[1]:process(b.left[i]))
       b.right[i] = g * high[2]:process(low[2]:process(b.right[i]))
     end
   end

   return dev
   ```

2. Select a track and type `:device.add lua:tilt`. The device panel shows
   Tilt with its two parameters.
3. Play the song and change `tilt` with `+` and `-` in the device panel.
4. To change the code, edit the file and save it. paw loads it again
   within one second, and the parameters keep their values.

If the device does not show, type `:device.scripts`, which shows each
script and why a script did not load.

If the device stops while it plays, the device panel shows the error with
the file and the line. Correct the file and save it, and the device starts
again.

For an instrument, set `category = "instrument"` and add to `b.left`
and `b.right` for the notes in `b.events`.

To ship the device with an extension, put the file in the `devices/`
directory of the extension.
