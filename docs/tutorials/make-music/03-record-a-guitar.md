# Lesson 3: Record a guitar

*This lesson takes about 25 minutes. You need an audio interface with a
guitar on input 1.*

In this lesson, we record a guitar riff of two bars. We hear the guitar
through an amp chain of built-in devices. Then we record two takes over a
loop, keep the best part of each take, and add a fade.

## Open the practice project

1. Connect the audio interface and the guitar before you start paw.
2. Start paw in your folder for songs. Type
   `:example make-music/3-guitar` and press Enter.

   - paw opens the song of lesson 2: Drums, Bass, Keys and Lead.

## Add the guitar track

1. Press `G`, then `o`. Press `grn` and `<C-u>`, type `Guitar` and press
   Enter.
2. Press `I`, and type `· 1`.
   - The list shows the inputs that match, for example
     `UR22mkII · 1` and `UR22mkII · 1/2`. The first line is input 1 alone.
3. Press Enter.
   - paw says `Guitar ← UR22mkII · 1`, with the name of your interface.
     The header of the track shows the input and its level.
4. Press `<A-i>` (Alt and i) to monitor the input.
   - Play some notes. You hear the clean guitar, and the level in the
     header moves.

If the level does not move, examine the gain knob of input 1 on the
interface. If no input shows in the list, type `:audio` to select the
interface.

## Make the amp chain

1. Press `a`, type `saturation` and press Enter.
   - The saturation device is the amp. It adds drive and harmonics.
2. Press `<Space>dd` (the space bar, then d two times) to open the device panel.
   - The panel shows Saturation and its parameters. The cursor is on the
     name of the device.
3. Press `j` to go to Drive. Press `12+`.
   - The drive increases to about 10 dB. Play: the guitar has some grit.
4. Press `j` to go to Curve, and press `+`.
   - The curve is `Tube` now, which adds even harmonics.
5. Press `a`, type `eq` and press Enter.
   - The equalizer comes after the saturation, as a speaker cabinet comes
     after an amp.
6. Press `w` to go to the EQ, and press `c`.
   - `c` on a device opens its presets.
7. Type `fizz` and press Enter.
   - The preset `Electric guitar: tame the fizz` cuts the highest
     frequencies and the lowest ones. The panel shows the new curve.
8. Press `<C-w>p` to return to the arrange view.

## Record two takes

1. Press `0` (the start of the song), then `gl2W`.
   - The loop is over bars 1 and 2. The status line shows `loop 1–2`.
2. Press `r` to arm the track.
3. Press `R` and play the riff. Play it again on the second time round
   the loop.
4. When the playhead returns to bar 1 the third time, press `<Space><Space>`.
   - A clip with the name `take 1 ‹2/2›` shows. It holds two takes, and
     the second take plays.

paw keeps each time round the loop that reached at least half of the loop.

## Keep the best parts

Here, we keep bar 1 of the second take and bar 2 of the first take.

1. Press `zt`.
   - Two lanes show below the guitar track, one for each take. The take
     that plays is bright.
2. Press `0` and `W` to put the cursor on bar 2.
3. Press `v` to start a selection, and `W` to select bar 2.
4. Type `:take 1` and press Enter.
   - The command line starts with `:'<,'>`, which is the selection. paw
     cuts the clip at bar 2, and take 1 plays there.
5. Press `<Space><Space>` to listen, and `<Space><Space>` to stop.
   - Each piece keeps both takes. To change a piece, select it and type
     `:take 2`.

## Add a fade

1. Press `0`, then `w`.
   - The cursor is on the second piece, at bar 2.
2. Type `:clip.fade out=2` and press Enter.
   - The piece fades out over its last two beats.
3. Press `r` to disarm the track, and `<A-i>` to stop the monitor.
4. Press `gs` and `<Space><Space>`, and `<Space><Space>` to stop.
   - The guitar riff plays with the song and fades out at the end of bar 2.
5. Type `:w with-guitar` and press Enter.

## What we made

We recorded a guitar through an amp chain of built-in devices. We recorded
two takes over a loop and kept the best bar of each. A fade ends the riff
softly.

Previous: [Play a synth from a MIDI keyboard](02-play-a-midi-keyboard.md) ·
Next: [Arrange the song](04-arrange-the-song.md) · [All lessons](README.md)

For more about takes, see
[How to record takes over a loop and comp them](../../how-to/record-takes-and-comp.md).
[Devices](../../reference/devices.md) has the built-in devices and their
presets. [Media files and audio clips](../../reference/media.md) has the
fades.
