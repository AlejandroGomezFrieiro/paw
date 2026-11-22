# How to change the tempo and the time signature

<!-- tags: change-tempo -->

You can set the tempo and the time signature of the song, and you can
change them in the middle of the song. The status line shows the tempo
and the time signature at the playhead, for example `120 bpm 4/4`.

## Set the tempo of the song

1. Press `grt`, and a prompt shows the current tempo.
2. Type the new tempo, for example `96`, and press `Enter`.

You can also type `:tempo 96`.

If you want to find the tempo of a song that you hear, tap it:

1. Play the song, and press `<Space>Tt` on a beat of the song.
2. Press `<Space>Tt` again on each next beat. Each tap sets the tempo from
   the taps so far.
3. Stop after four or more taps. The message gives the tempo, for
   example `tapped 92 bpm at 1.1.00`.

The command is `:tempo.tap`, and a pause of more than two seconds starts a
new count.

## Set the time signature

Type `:timesig 6/8`, and the time signature starts at the bar of the
cursor. At the start of the song, it is the time signature of the whole
song.

## Change the tempo or the time signature in the song

- To change the tempo from bar 17, type `:tempo 140 at 17`. To change it
  from the cursor, type `:tempo 140 here`.
- To change the time signature from bar 9, type `:timesig 7/8 at 9`.
- To make the tempo change slowly up to the next change, put the cursor
  after the first change and type `:tempo.ramp`.

The ruler marks a tempo change as `▾140` and a signature change as
`‖7/8`. To see all the changes, type `:tempo.list`. To remove a change,
put the cursor after it and type `:tempo.remove` or `:timesig.remove`.

To see the tempo as a curve under the ruler, press `zT`.

MIDI clips stay on their beats when the tempo changes, but audio clips
keep their length in seconds. If you want an audio clip to follow the
tempo, see [How to fit audio to the tempo](fit-audio-to-the-tempo.md).

In the graphical window, drag the tempo in the transport bar, or
double-click it to type a value.

## See also

- [Tempo and time signatures](../reference/tempo.md): every command, the timebase of audio clips.
- [About time and tempo](../explanation/about-time-and-tempo.md)
