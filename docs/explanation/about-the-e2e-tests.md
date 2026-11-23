# About the end-to-end scenarios

<!-- tags: e2e scenarios oracle golden -->

The end-to-end scenarios test the work of a person over many days, on a
song that grows and changes in all the views, while the Lua suite tests one
behavior in each test on a new project. The page explains why the scenarios
have their shape, and how they know what the project must hold after each
step. For the commands, see
[How to run the tests](../how-to/run-the-tests.md#run-the-end-to-end-scenarios).

## Who runs the scenarios

The scenarios are for a CI pipeline and for the release check before a
tag. The short mode is for each pull request, and the full mode is for each
night. The repository has no CI pipeline that runs them yet. An agent that
tests a change runs the Lua suite and not the scenarios, and
`tests/tools/suite.sh` and the default `nix flake check` do not run them.

## A scenario is a sequence of days

A day is one session of work. `tests/tools/e2e.sh` starts a new paw process
for each day, on the project folder that the day before saved. During the
day, the scenario types keys and Ex commands as a person does, and it
switches between the views. When the day ends, it saves the project and
quits. Each day therefore also tests that the project opens from the disk
in a new process, so nothing can live only in the memory of the process.

A seed sets the details, e.g., the tempo, the notes, the names, the levels
and the part that the person changes. The same seed gives the same days on
each machine, because the scenarios use their own number generator and not
the one of LuaJIT. The scenarios follow the process of a person, and the
music does not need to be good.

## How a scenario knows the right result

General checks such as "the project opens" or "it is not silent" find a
crash, but they do not find a wrong result. For example, a volume that goes
2 dB down for `3-` is a wrong result that opens and plays. Each scenario
therefore has an oracle, which is a second description of what the project
must hold. The oracle has three parts, and each part covers what the other
parts cannot cover.

### A reference model for the data of the project

`tests/e2e/model.lua` is a small model of a project. It holds the tempo,
the markers and the regions. For each part, it holds the name, color,
volume, pan, mute, solo, devices, sends, clips, notes and the points of its
automation lanes. Each action of a scenario gives two things:

- The keys that the person types.
- The same change, written as a change to the model.

After each action, the test runner reads the state of paw through the
public Lua objects, in the shape of the model, and it compares each field.
The first fields that differ give the failure, e.g.,
`project.parts[Bass].volume: want 7, got 6`.

The model must stay small enough to trust, so it follows these rules:

- It uses no code of paw, not even to read a file, and it has its own
  reader of MIDI files and of WAV headers. A bug in paw therefore cannot
  also be in the model.
- It holds only what the person sees and relies on, and not ids, caches or
  the layout of the screen. A field that a scenario does not know is `ANY`,
  and the test runner does not compare it. For example, the layout of the
  clips of an imported MIDI file is `ANY`, but the notes of each part are
  always known, at their time in the song.
- Each rule in it comes from the documentation. For example, the fader
  stops at +6 dB, because the reference of the mixer says so. When the
  model and paw do not agree, the documentation decides which one is wrong.

An action that the person takes back, e.g., an undo, or a clip deleted and
brought back, gives no change to the model, so the model also checks the
undo of each such action.

### Properties for what is the same in two ways

Some checks need no model, because two ways to do one thing must give the
same result:

- Undo of each change of the day gives the state of the start of the day,
  and redo of each change gives the state of the end of the day. The test
  runner presses `u` until the undo state is the state of the start of the
  day, and then `<C-r>` the same number of times, so a day that ends with an
  undo does not redo that change too.
- A save, an open in a new process and a save again write the same bytes.
  A known bug can make one file an exception, with its reason, and the run
  prints the reason each time, until the fix removes it.
- An export, opened again, holds what the model holds, less what the
  format cannot carry. The scenario names those losses, field by field,
  e.g., paw's own devices do not go into a REAPER project.

### Approved renders for the sound

The model cannot say how the song sounds. For the sound, the test runner
renders the song offline at the end of each day. It checks that the render
is not silent, and it compares the loudness of each second with an approved
fingerprint. The fingerprints are in `tests/e2e/golden/<scenario>.json`,
with one line for each seed and day, and a second that differs by more than
1.5 dB fails.

A fingerprint changes only by an explicit command,
`tests/tools/e2e.sh <scenario> --approve`. Run it in a commit that tells
why the sound changed, e.g., a new synth or a fix of the gain, so that a
review of the commit looks at the numbers that changed. A fingerprint that
changes with no reason is a bug.

The fingerprint is coarse on purpose. It finds a part that is silent, a
send that doubles a level, or a part at the wrong time, but it does not
find a small change of the tone.

## The other checks of a day

At the end of each day, the test runner also checks that no message of
the day was an error, and that `:checkhealth` shows no `ERROR`.

The report line of each day names the slowest key of the day, with its
processor time and the load of the machine. The time is the time that the
kernel needs for the key, and a command that does long work, for example
`:import` or `:export`, doesn't count. The time is for a person to read
and doesn't fail the day, because it depends on the machine and its load.
The rule of fast keys is measured with the scripts in `bench/`.

## A failure

A failure names the scenario, the seed, the day, the step and the action
in words, and the first fields that differ. It prints the command that
does the same run again. The folder of the run stays in
`target/e2e/<scenario>-seed<N>`. It holds the project of the day before and
a copy of the project after each day, and also the project of the failed
day as it was at the failure.

## What the scenarios cover now, and next

The scenario `song` has 14 days:

| Day | The work |
| --- | --- |
| 1 | A sketch: a tempo, a lead and a bass drawn, a bar drawn and undone, a marker, the mixer and the help. |
| 2 | Material from outside: a public-domain MIDI file and a CC0 sample, synths, names, colors, a repeated bar, levels. |
| 3 | A first mix: a reverb part with sends, pan and level in the mixer, a faster tempo, exports as WAV and MIDI. |
| 4 | The piano roll: a transpose tried, undone and tried again, the velocity, a quantize, the bass an octave down. |
| 5 | A take played on the test MIDI port of the null backend, recorded from bar 5 and quantized to the beat. |
| 6 | Automation: volume points typed with `:lane.add` and `A`, a pan lane, a solo tried in the mixer. |
| 7 | A time stretch of the sample, a region over a loop, a marker named when asked. |
| 8 | A voice deleted and brought back with `u`, another deleted for good. |
| 9 | The files buffer puts the sample on a new part. The pickers find a part and a marker. |
| 10 | The undo tree: two ideas on two branches, `g-` to the first. |
| 11 | `:media.collect`, and a stem for each part. |
| 12 | Rework: a new bass, a bar of lead deleted, a slower tempo. |
| 13 | The lead's bar repeated, its last copy muted. |
| 14 | The last levels, the help of `:export`, the final mix and a MIDI file. |

The recorded take of day 5 shows how the model deals with time on a loaded
machine, where the notes come late by up to half a beat. The model holds
the played notes as they must be after a quantize to the beat, and the
scenario quantizes the take before the comparison.

The scenario `interop` has the first two days of `song`. On its third day,
it writes the song as a REAPER project and as a DAWproject file, and it
opens each file again.

The scenario `notation` imports a public-domain chorale, writes a melody
over a sketch in the score, and corrects notes there. After each edit, the
model checks the MIDI notes, because the notes are the truth. Then the
scenario writes MusicXML and LilyPond, reads the MusicXML with its own small
reader, and imports the file again to compare the notes. On the last day,
it moves a note of the chorale in the score.

`--seeds` runs each scenario with several seeds, for the run of each night,
and each seed has its own approved renders.

Later work adds scenarios for the other extensions.
`tests/e2e/assets/LICENSES.md` lists the sounds and MIDI files with their
sources and licenses.
