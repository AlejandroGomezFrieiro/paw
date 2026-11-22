# luafx

Devices written in Lua. You can use them as they are, or copy them as a
start for your own devices. When the extension loads, the device picker
shows them beside the built-in devices.

```lua
paw.ext.load("extensions/luafx")   -- or put the directory in ~/.config/paw/extensions
```

## Try it

1. Type `:ext.load luafx`.
2. Put the cursor on a track with an instrument, and type `:device.add`.
   The device picker opens.
3. Type `lua` in the picker. The four devices of the list below appear.
4. Choose "Chords (Lua)".
5. Play a note on the track. You hear a chord.

## How to change one of the devices

1. Copy the file from `devices/` into `~/.config/paw/devices/`.
2. Edit the copy. When you save it, paw loads it again, and the devices made
   from it keep their parameters.

A script in `~/.config/paw/devices/` has priority over a script with the
same name in an extension. To learn how to write a device, read
[How to write a device in Lua](../../docs/how-to/write-a-device-in-lua.md).

## Reference

| Device | Kind | What it does |
| --- | --- | --- |
| Gain and pan (Lua) | `lua:gain_pan` | a level in dB, a balance, and stereo, mono or swapped sides |
| Drive (Lua) | `lua:drive` | a soft clipper with a low-pass tone control and a dry/wet mix |
| Chords (Lua) | `lua:chords` | a MIDI effect: each note becomes a chord on that note |
| Sine (Lua) | `lua:sine` | an instrument: eight sine voices with attack and release |

The devices are the files in `devices/`. An extension gives devices with
that directory and needs nothing more.
