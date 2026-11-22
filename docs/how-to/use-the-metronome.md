# How to use the metronome

You can play with a click, and you can get a count-in before a take. The
rules are in [Recording](../reference/recording.md#count-in) and
[Tempo and time signatures](../reference/tempo.md).

## Hear the click

1. Press `gm`, and the status line shows `click`. The metronome plays when
   the song plays.
2. Press `gm` again to stop the metronome.

The metronome plays a higher click on the first beat of each bar. It plays
one click on each beat of the time signature, so a bar of 6/8 has six
clicks. When the tempo changes, the click follows the tempo map.

To change the tempo, press `grt`, type the tempo and press `Enter`.

The metronome plays through the main output with the song, but paw does
not put the click in a rendered file.

## Change the sound of the click

Type `:click` to see the settings, and change them in the following ways:

- To make the click quieter or louder, type `:click level=-6`. The level
  is in dB, from -60 to +12.
- To play the same click on each beat, type `:click accent=off`.
  `:click accent=on` plays the higher click on the first beat again.
- To hear the click only in headphones on outputs 3 and 4 of the audio
  interface, type `:click output=3`, and the click is no longer in the
  main output. `:click output=song` puts it back with the song.

## Count in before a take

1. Press `gM`, and the status line shows `count 1`. A take that starts
   from a stop now begins after one bar of clicks.
2. To count two bars, type `:countin 2`.
3. To stop the count-in, press `gM` again, or type `:countin off`.

The count-in clicks even when the metronome is off. To cancel a count,
press `Esc` or `<Space><Space>`.

In the graphical window, the transport bar has a button for the metronome.
