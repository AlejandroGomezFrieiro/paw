# How to use articulations with a plugin instrument

This guide shows you how to play the articulations of a plugin instrument.
Examples are the play styles of a bass or the shorts of a string library. paw
keeps the articulation on each note. A map tells the plugin about it with
its keyswitches, controllers, program changes or MIDI channels. For each
field of a map, see the README of the
[articulations extension](../../extensions/articulations/README.md).

## Put a plugin with a map on a track

1. Type `:ext.load articulations`.
2. Add the plugin to a track. When paw has a map for the plugin, it binds
   the map to the track. A message tells you so.
3. If no map names the plugin, type `:art.maps`. Then bind a map by its
   name: `:art.map sine-cc`.

paw has maps for MODO BASS 2 and SINE Player.
The maps of paw come from the documentation of each vendor. They are not
checked with each plugin. Read the top of the map file before you use
it. For MODO BASS 2, first set the keys of the map in the Control tab of
the plugin.

## Give notes an articulation

1. Open a clip of the track in the piano roll.
2. Put the cursor on a note, or select notes in visual mode.
3. Press `\a`. Choose an articulation and press Enter.

For a modifier that goes over any articulation, for example a palm mute on
the bass, press `\A`.

## Move the keyswitches

Some plugins let you move the keyswitches to other keys. When the
keyswitches of the plugin are an octave lower than those of the map:

1. Put the cursor on the track.
2. Type `:art.shift -1oct`. `:art.shift -2` moves them two keys down.
   `:art.shift 0` puts them back.

The track keeps the shift. The keys that the notes play do not move.

## Make a map of your own for a plugin

1. Type `:art.new My bass`. paw writes an empty map in
   `~/.config/paw/articulations/`.
2. Add a line that names the plugin, for example
   `match = ["vst3:My Bass"]` or `match = ["plugin:My Bass"]`.
3. Write each articulation, and in its `out` what the plugin needs for it.

| `out` | What the plugin gets |
| --- | --- |
| `"ks=C0"` | a keyswitch |
| `"hold=C0"` | a key held while the notes play |
| `"cc58=0-15"` | a controller value from a range |
| `"pc=3"` | a program change |
| `"ch=2"` | the notes on channel 2 |

4. If the chart of the vendor calls key 60 `C3`, add `middle_c = "C3"`.
   Then write the keys as the chart writes them.

Your own maps come before the maps of paw.

## Name the drums of a drum plugin

Drum plugins have no articulations. The `drums` extension names their
notes instead. For MT-PowerDrumKit 2, type `:drums.map mt-powerdrumkit`.
