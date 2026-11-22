# About MIDI 2.0 in paw

paw keeps all MIDI at the resolution of MIDI 2.0, and it changes MIDI to
MIDI 1.0 only at the edge, for the devices and ports that need MIDI 1.0.
MIDI 1.0 has seven-bit values, which gives 128 steps for a controller and one
pitch wheel for each channel. A slow filter sweep in 128 steps can sound as
steps, and a bend of one note bends all the notes of the channel. MIDI 2.0
has 32-bit values and controllers for each note. For the reference, see
[MIDI](../reference/midi.md).

## Values are fractions and not steps

A value in a clip is a fraction, not a count of seven-bit steps, so a sweep
that you draw or record keeps its full resolution in the project file.
When a device takes only MIDI 1.0, paw rounds the value at that point. A
better device, or a later version of a plugin, then gets the full data from
the same project.

## Controllers for each note

A controller move with a `key` belongs to one note, in the same way as in
MIDI 2.0 and in the note expressions of CLAP and VST3. One note of a chord
can bend while the other notes stay at their pitch.

Moves for one note stay on the clip like any other move, and paw gives them
to each device in the best form that the device takes. CLAP and VST3
plugins get note expressions, and a CLAP plugin that prefers MIDI 2.0 gets
MIDI 2.0. A device with only MIDI 1.0 cannot get the moves, because MIDI
1.0 has no bend for one note.

## How paw reads MIDI 2.0 ports and widens MIDI 1.0

paw opens the ALSA sequencer as a MIDI 2.0 client, so a MIDI 2.0 keyboard
arrives with all its data. A MIDI 1.0 keyboard arrives as the same events
with less resolution. When the Linux kernel has no MIDI 2.0 sequencer, paw
widens MIDI 1.0 by the rules of the specification. The rest of paw reads
one form of MIDI, from any port and on any kernel.

## MPE for MIDI 1.0 synths

A hardware synth with MIDI 1.0 can still play the controllers of each note
with MIDI Polyphonic Expression (MPE). MPE gives each note a channel of its
own, so the pitch bend of the channel is the bend of the note. paw gives a
new note the channel that was released first, so the release of a note
that still sounds does not bend with the next note. The bend range is 48
semitones, the same as the bend range of a note in paw, so a bend sounds
the same through MPE and through MIDI 2.0.

## Why the audio thread stamps MIDI output

A hardware synth must sound at the same time as the tracks. The audio
thread knows when you hear each message, because it knows the output
latency and the delay of the plugins. It puts the time on the message, and
another thread schedules the message on a sequencer queue. The audio thread
never waits for the sequencer, and the synth sounds in time.
