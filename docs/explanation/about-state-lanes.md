# About state lanes

<!-- tags: state-lanes state-lane-design -->

An automation lane moves a number: a fader, a pan, a parameter. Some
changes of sound are not a number. Examples are the model of an amp
simulator, the preset of an amp plugin, and the instrument file of a
sampler. A state lane is a lane for these changes. Each point of the lane
gives a device one state, and the device keeps the state up to the next
point. For the keys and the fields, see
[Automation](../reference/automation.md#state-lanes).

This page tells how a state lane works. It also tells why a change lands
exactly on its point in one case, and near it in another case.

## A lane of states, in the core

A state lane is part of the core, not of an extension. It knows nothing
about one plugin. Each state of the lane has one or more of these parts:

- a saved state: all the bytes that the plugin saves (`state`),
- a request to the device (`call`), for example an LV2 property that
  names a file,
- parameter values (`params`),
- a program change (`program` and `bank`).

A point holds the number of a state, and the state holds to the next
point, with no curve between the points. Before the first point, the first
state holds, as the first value of a curve holds. The lane keeps the
states inside the project, not in an extension's `meta`. So a project with
a state lane opens and plays without the extension that made the states.
The `plugstate` extension only fills the lane: it changes a model, a
preset or a snapshot into a state.

## Three ways to give a state

A plugin takes the parts of a state in different ways. paw uses the way
that is most exact for each part.

| Part | Where paw gives it | Where the change lands |
| --- | --- | --- |
| Parameters | the audio thread | on the frame of the point |
| Program change | the audio thread, as an event to that device only | on the frame of the point |
| Request that the plugin prepares as a message (an LV2 `patch:Set`) | the audio thread | on the frame of the point; a plugin that loads a file on its worker plays it from the point in a render, and some milliseconds later as the song plays |
| Saved state (`setState` in CLAP and VST3), or a request with no message | the main thread | in a render, on the frame of the point; as the song plays, some milliseconds after the point, and later if the plugin loads a model in the background |

### On the audio thread

The engine ends a block on each point of a state lane. So a new state
starts on the first frame of a block, and the engine sets parameters and
sends a program change there. This gives a change on the exact frame,
also with a large buffer.

An LV2 plugin takes a file through a `patch:Set` message on its atom
input. The main thread makes the message before the song plays, and the
engine gives it to the plugin. Neural Amp Modeler loads the model on its
worker thread, and the model plays when the worker answers. The worker
answers after the block that brought the message. So the engine gives the
message on the last frame of the block before the point. The new model
then plays from the frame of the point.

In a render, paw waits after each block until the worker has done the
work that the block asked for. So the render has the new model from the
frame of the point, and each render is the same. The LV2 standard also
lets a host do the work inside the block. paw does not do this, because
Neural Amp Modeler then gave different sound in some renders. As the song plays, the worker loads
the model in the background, and the new model plays some milliseconds
after the point.

A plugin in its helper process (see
[About the plugin sandbox](about-the-plugin-sandbox.md)) gets the
message through the shared memory, with its block.

### On the main thread

CLAP and VST3 load a saved state only on the main thread. Many plugins
then load the parts of the state in the background: TONE3000 loads its
models, for example. These plugins also do not change their preset for a
program change. So a saved state cannot land on a frame while the song
plays. paw gives it when the main loop sees the playhead after the
point. That is some milliseconds after the point, and the plugin can need
more time to load what the state names.

A render does not have to keep time. It stops on the frame of the point,
and the main thread gives the saved state. Then the render waits until
the plugin is ready, and continues.

A plugin in a helper process tells paw when it is ready: its process uses
no processor time for a moment. While a plugin loads a model, its process
works. When the process is quiet, the plugin is ready. paw waits for this
sign, but not longer
than the render's `settle` time (5 seconds). A plugin in paw's own process
gives no such sign, so paw waits a fixed half second. The same wait
occurs at the start of each render. Then paw plays half a second of
silence with the song stopped. A plugin can fade over to a new model as
it plays, and TONE3000 takes about a third of a second for this. This fixes
the first second of a render that had no model in it, when a plugin loads
its model in the background.

## The other ways that paw did not choose

Three other ways can give a saved state on an exact frame as the song
plays.

- **A second instance of the plugin.** paw can load the next state into a
  second instance before the point, and change to it on the frame of the
  point. This costs a second instance: its memory, and its processor time
  while it plays beside the first. To keep the sound continuous, the second
  instance must also hear the input before the point, and a crossfade
  hides the difference between the two. On one test machine, the helper
  process of one TONE3000 instance with a preset used 35 MB of memory. A
  render of 32 seconds with a second instance on a second track took 5 %
  longer (a median of 2.60 s for 2.47 s, under a load of other work). paw
  does not do this yet: a render is already
  exact, and as the song plays a change of some milliseconds is
  difficult to hear in most music.
- **The saved state, early.** paw can give the saved state before the
  point, by the time that the plugin needs to load it. The time is not
  known, and is not the same each time. The change then comes before the
  point by an unknown time, which is not better than after it.
- **A parameter of the plugin that chooses its preset.** A plugin that
  has such a parameter gets it on the frame of the point, as each
  parameter. Put the parameter in the state (`params`). TONE3000 and
  Soundshed Guitar have no such parameter.

## The state that the project keeps

A device that a state lane drives holds the lane's states as the song
plays. The project keeps the device's own state, and does not read the
lane's state back from the plugin. This is the same as for a parameter
that a lane moves. When you stop or remove the lane, paw gives the
device its own state again.

## After a saved state: the state is the truth

A saved state, a snapshot, a preset and an undo all give a plugin a whole
state. After this, the state is the truth. The values of the parameters
that paw shows are only a mirror of the state.

Some plugins take the state only at the start of their next block. JUCE
plugins, for example Surge XT, do this. paw lets a plugin sleep when its
sound stops. A plugin that sleeps processes no block, and so it never
takes the state.

For this reason, a plugin that gets a state always processes its next
block. Its tail time then starts again. A
VST3 controller reads its values from the processor when it gets the
state, before the processor has the new values. For this reason, paw
gives the controller the state of the component again after the next
block.

After a state, a plugin tells paw the values of its parameters. These
messages are the echo of the state, not an edit. For the echo, paw only
updates the values that it shows:

- The echo makes no undo step, and does not change the project.
- The echo does not remove a parameter that the project sets.
- The echo does not write automation, and does not change the parameter
  that `:param.last` uses.
- paw does not send the echo of a VST3 plugin back to its processor,
  because the processor already has the state. So, after an undo soon
  after a state, an old echo cannot play the values of the earlier state.

A move in the window of a plugin is an edit, also immediately after a
state. paw tells the echo from a move by what the plugin says, not by
the time. So, a slow computer that gets the echo late does not make
it an edit:

- A plugin marks a move of the user in its window as a gesture: CLAP
  sends `GESTURE_BEGIN` and `GESTURE_END` around the move, and VST3 calls
  `beginEdit` and `endEdit`. A change in a gesture is always an edit.
- A value that paw reads back from the plugin after a state is the echo,
  because paw asked for it. So is a change that a CLAP plugin sends
  without a gesture in its first block after the state. This is the
  block in which a plugin such as Surge XT takes the state.
- Some plugins send a change without a gesture at other times. For such
  a change, the value tells: a value that a recent state gave the
  parameter is the echo of that state, and a different value is an edit.
  paw keeps the values of the states since the last edit of each
  parameter, so the late echo of a state before an undo is also an echo.
  A change without a gesture to the value of one of these states makes no
  edit. This is correct, because the plugin already has that value.
- An LV2 editor writes a control without a gesture, because paw does not
  give it `ui:touch`. The value tells, as in the previous item. The
  messages that an LV2 plugin sends from its audio thread (`patch:Set`)
  change properties, not parameters. These are never an edit.

paw keeps this mark with each change, also when the plugin runs in a
process of its own. Each change in the shared memory between the two
processes has a flag for an edit.

Surge XT stops the notes that sound when it takes a whole state. This
also stops a note that starts in the same block as the state. Put a
point of a saved state before the next note, not on it.
