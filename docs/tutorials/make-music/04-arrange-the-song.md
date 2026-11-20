# Lesson 4: Arrange the song

*This lesson takes about 15 minutes.*

In this lesson, we make a song from the four bars of lessons 1 to 3. The
song has a verse, a chorus, a second verse and a last chorus. We put a marker at the
start of each part and change the tempo. Then we jump from part to part.

## Open the practice project

1. Start paw in your folder for songs. Type
   `:example make-music/4-arrange` and press Enter.

   - paw opens the song of lesson 3. Each track has four bars, and the
     guitar riff has two bars.

In this practice project, a synth plays the guitar riff through the amp
chain of lesson 3. So the project plays without your recording.

## Copy the verse to make the chorus

1. Type `:1,4co 5` and press Enter.
   - `:1,4co 5` copies bars 1 to 4 of every track to bar 5. paw says
     `copied bars 1–4 to 5.1.00`. The song has eight bars now.
2. Type `/Lead` and press Enter.
   - `/` finds a track or a clip by its name. The cursor goes to the Lead
     track.
3. Press `0` (the start of the song) and `x`.
   - `x` deletes the clip under the cursor. The lead plays only from bar
     5, in the chorus.
4. Press `j` to go to the Guitar track, and press `x`.
   - The verse has drums, bass and chords. The chorus adds the lead and
     the guitar.

## Move the guitar

1. Press `5|` to go to bar 5, on the guitar riff.
2. Press `8L`.
   - `L` moves the clip one step of the grid later, and the grid is one
     beat. The riff moves eight beats, to bar 7. It answers the lead in
     the second half of the chorus.

In the graphical window, you can also drag a clip to move it.

## Repeat verse and chorus

1. Type `:1,8co 9` and press Enter.
   - The verse and the chorus play again from bar 9. The song has 16 bars.

## Put markers on the parts

1. Press `0`. Type `:marker Verse` and press Enter.
   - A marker shows under the ruler at bar 1.
2. Press `5|`. Type `:marker Chorus` and press Enter.
3. Press `9|`. Type `:marker Second verse` and press Enter.
4. Press `13|`. Type `:marker Last chorus` and press Enter.
   - Four markers name the parts of the song.

## Change the tempo

1. Type `:tempo 104` and press Enter.
   - The status line shows `104 bpm`. The clips stay on their bars, and the
     song plays a little faster.
2. Press `gL` to stop the loop.
   - `loop 1–4` goes away from the status line. The whole song plays now.
3. Press `gs` and `<Space><Space>`. Listen to the song, and press `<Space><Space>` to stop.

## Find a part

1. Press `g"`.
   - A list of the markers opens.
2. Type `last` and press Enter.
   - The cursor goes to the last chorus, at bar 13.
3. Press `['`.
   - `['` goes to the marker before, the second verse. `]'` goes to the
     next marker.
4. Press `<Space>ft` (comma, f, t).
   - A list of the tracks opens. `<Space>f` and a letter open a list of other
     things, for example `<Space>fl` the clips.
5. Type `Bass` and press Enter.
   - The cursor goes to the Bass track, at the same bar.
6. Press `gp` to move the playhead to the cursor. Press `<Space><Space>`.
   - The song plays from the second verse. Press `<Space><Space>` to stop.
7. Type `:w arranged` and press Enter.

## What we made

We made a song of 16 bars from a loop of four. We copied, deleted and
moved clips, named the parts with markers, and changed the tempo. Then we
found a part by its marker and a track by its name.

Previous: [Record a guitar](03-record-a-guitar.md) · Next:
[Mix and render the song](05-mix-and-render.md) · [All lessons](README.md)

For more, see [Ex commands](../../reference/ex.md) for `:co` and the other
commands on bars. See also [Markers and regions](../../reference/markers.md),
[Tempo and time signatures](../../reference/tempo.md) and
[Pickers](../../reference/pickers.md).
