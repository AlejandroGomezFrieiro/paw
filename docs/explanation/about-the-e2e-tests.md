# About the end-to-end scenarios

<!-- tags: e2e scenarios oracle golden -->

The Lua suite tests one behavior in each test, on a new project. The
end-to-end scenarios test the work of a person over many days: a song
that grows and changes, in all the views. This page
tells why the scenarios have their shape, and how they know what the
project must hold after each step. For the commands, see
[How to run the tests](../how-to/run-the-tests.md#run-the-end-to-end-scenarios).

## Who runs them

The scenarios are for the CI pipeline and for the release check before a
tag. The short mode runs on each pull request, and the full mode runs
each night. An agent that tests a change runs the Lua suite, not the
scenarios. `tests/tools/suite.sh` and the default `nix flake check` do
not run them.

## A scenario is a sequence of days

A day is one session of work. `tests/tools/e2e.sh` starts a new paw
process for each day, on the project folder that the day before saved.
In the day, the scenario types keys and Ex commands as a person does, and
switches between the views. At the end of the day, it saves the project
and quits. So each day also tests that the project opens from the disk
in a new process. Nothing can live only in the memory of the process.

A seed sets the details: the tempo, the notes, the names, the levels,
the track that the person changes. The same seed gives the same days on
each machine, because the scenarios use their own generator of numbers,
not the generator of LuaJIT. The process is that of a person. The music
does not need to be good.

## The oracle: how a scenario knows the right result

General checks ("the project opens", "it is not silent") find a crash.
They do not find a wrong result. A volume that goes 2 dB down for `3-` is
a wrong result that opens and plays. So each scenario has an oracle, a
second description of what the project must hold. The oracle has three
parts. Each part covers what the other parts cannot cover.

### A reference model, for the data of the project

`tests/e2e/model.lua` is a small model of a project. It holds the tempo
and the markers. For each track, it holds the name, color, volume, pan,
mute, solo, devices, sends, clips and notes. Each action of a scenario gives two
things:

- the keys that the person types, and
- the same change, written as a change to the model.

After each action, the harness reads the state of paw through the public
Lua objects, in the shape of the model, and compares each field. The
first fields that differ give the failure, for example
`project.tracks[Bass].volume: want 7, got 6`.

The model must stay small and trustworthy:

- It uses no code of paw, not even to read a file. It has its own reader
  of MIDI files and of WAV headers. A bug in paw cannot also be in the
  model.
- It holds only what the person sees and relies on. It does not hold
  ids, caches or the layout of the screen.
- Each rule in it comes from the documentation. For example, the fader
  stops at +6 dB, because the reference of the mixer says so. When the
  model and paw do not agree, the documentation decides which one is
  wrong.
- A field that a scenario does not know is `ANY`, and the harness does
  not compare it. An example is the layout of the clips of an imported
  MIDI file. The notes of each track are always known, at their time in
  the song.

An action that the person takes back (an undo, a clip deleted and
brought back) gives no change to the model. So the model also checks
the undo of each such action.

### Properties, for what is the same in two ways

Some checks need no model, because two ways to do one thing must give
the same result:

- Undo of each change of the day gives the state of the start of the
  day. Redo of each change gives the state of the end of the day.
- A save, an open in a new process and a save again write the same
  bytes. A known bug can make one file an exception, with its reason. The
  run prints the reason each time, until the fix removes it.
- An export, opened again, holds what the model holds, less what the
  format cannot carry. The scenario names these losses, field by field.
  For example, paw's own devices do not go into a REAPER project.

### Approved renders, for the sound

The model cannot say how the song sounds. For the sound, the harness
renders the song offline at the end of each day. It checks that the
render is not silent, and it compares the loudness of each second with
an approved fingerprint. The fingerprints are in
`tests/e2e/golden/<scenario>.json`, one line for each seed and day. A
second that differs by more than 1.5 dB fails.

A fingerprint changes only by an explicit command,
`tests/tools/e2e.sh <scenario> --approve`. Do it in a commit that tells
why the sound changed, for example a new synth or a fix of the gain. A review
of that commit looks at the numbers that changed. A fingerprint that
changes with no reason is a bug.

The fingerprint is coarse on purpose. It finds a track that is silent, a
send that doubles a level, or a part at the wrong time. It does not find
a small change of the tone.

## The other checks of a day

At the end of each day, the harness also checks these:

- No message of the day was an error.
- The slowest key of the day stays under 100 ms of processor time (the
  rule of fast keys). On a loaded machine, the limit grows as `T.quick`
  says in [How to run the tests](../how-to/run-the-tests.md). The time is
  the time that the kernel needs for the key. A command that does real
  work, for example `:import` or `:render`, does not count.
- `:checkhealth` shows no `ERROR`.

## A failure

A failure names the scenario, the seed, the day, the step and the action
in words, and the first fields that differ. It prints the command that
does the same run again. The folder of the run stays in
`target/e2e/<scenario>-seed<N>`. It holds the project of the day before
and a copy of the project after each day. It also holds the project of
the failed day, as it was at the failure.

## What the scenarios cover now, and next

The scenario `song` has three days. Day 1 is a sketch. Day 2 brings
material from outside: a public-domain MIDI file and a CC0 sample. Day 3
is a first mix with a send, a tempo change and exports as WAV and MIDI.

The scenario `interop` has the first two days of `song`. On its third
day, it writes the song as a REAPER project and as a DAWproject file, and
opens each again.

Later slices add days up to two weeks: the piano roll, automation, a
recorded take, a time stretch and stems. They also add scenarios for the
other extensions. `tests/e2e/assets/LICENSES.md` lists the sounds and
MIDI files with their sources and licenses.
