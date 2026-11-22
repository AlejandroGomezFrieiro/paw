# About time and tempo

Music has two clocks, which are beats and bars for the music and seconds
for a recording. When the tempo is constant, the two clocks agree, but when
the tempo changes, each clip must keep one of them. The page explains which
clock each part of paw keeps, and why. For the commands, see
[Tempo and time signatures](../reference/tempo.md).

## The tempo map

The tempo map is a list of tempo changes and time signature changes. A
tempo change holds until the next change, or it ramps to the next change
like the linear tempo points of REAPER do. The engine follows the map
sample by sample, so the playhead, the loop, the metronome, MIDI and
automation all agree with the map. Plugins get the same tempo and bar at
each block.

A project with one tempo and one signature keeps the fields that it had
before the tempo map existed. Older projects open with no change, and a
song with one tempo has a short file.

## Which clock each thing keeps

MIDI clips and automation keep their beats, because a note is a musical
event and it must stay on its beat when the tempo changes.

An audio clip keeps its length in seconds, because a recording is sound in
time, and a change of tempo must not make a recording faster or cut it. The
only question is where the clip starts, and the clip's timebase decides it:

- With `time`, which is the default and works like the audio items of
  REAPER, the start stays at the same second.
- With `beats`, the start stays on its beat.
- With `stretch`, both the start and the length stay on their beats, and
  paw stretches the sound to fit.

## Bent clips

A clip can follow the tempo while the tempo changes inside the clip. A
uniform stretch would be wrong there, because the beats would drift from
the grid, so paw bends the clip along the tempo map. Each beat of the
sound, at the tempo of the clip, plays on a beat of the song. A looped clip
is an exception, because its repeats must be equal, so paw stretches it
evenly.

## Recordings

A take remembers the tempo at which you recorded it, in
`clip.source_tempo`. If you later switch the clip to follow the tempo, paw
already knows the tempo of its sound.
