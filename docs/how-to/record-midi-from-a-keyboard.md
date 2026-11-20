# How to record MIDI from a keyboard

This guide shows you how to record notes that you play on a MIDI keyboard.
It assumes that the keyboard is connected to the computer. For each rule,
see [Recording](../reference/recording.md) and [MIDI](../reference/midi.md).

## Prepare the track

1. Press `o` to add a track.
2. Press `a` to add an instrument. Type a part of its name, for example
   `Synth`, and press `Enter`.
3. Press `I`. Type a part of the name of the keyboard, and press `Enter`.
   If you do not choose a port, the track takes MIDI from all the ports.
4. Press `r` to arm the track. Play some keys. You hear the instrument.

If the list does not show the keyboard, type `:midi.inputs`. The page
shows each MIDI port that paw finds, and if it is open.

## Record a take

1. Move the cursor to where the take starts.
2. Press `R`, and play. The take starts at the cursor.
3. Press `<Space><Space>` to stop. The take is a new MIDI clip on the track.
4. To edit the notes, press `Enter` on the clip. The piano roll opens.

Each take is a new clip. If you record again over a clip, the new clip is
on top of the old clip.

## Merge a take into the clip

1. Record the new take over the clip, as above.
2. Put the cursor on the clips and press `J`. paw merges the clips into
   one clip, with the notes of both.

To merge the clips of some bars, type the bars: `:5,8j` merges the clips
in bars 5 to 8.

To merge each take into the clip under it while you record (overdub),
type `:set midi_record merge`. `u` undoes the take and the merge in one
step. A take round a loop stays a clip of takes. To make each take a new
clip again, type `:set midi_record new`.

## Record over a loop

1. Move the cursor to the first bar of the part. Type `gl4W` to loop four
   bars from the cursor.
2. Press `R`.
3. Play the part again each time round the loop.
4. Press `<Space><Space>` to stop. The clip over the loop has a take for each time
   round. The last take plays.

To choose among the takes, see
[How to record takes over a loop and comp them](record-takes-and-comp.md).
