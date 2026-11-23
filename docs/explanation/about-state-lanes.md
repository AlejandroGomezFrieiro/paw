# About state lanes

<!-- tags: state-lanes state-lane-design -->

A state lane is a lane for changes of sound that are not a number. An
automation lane moves a number, e.g., a fader, a pan or a parameter, but
some changes are not numbers, e.g., the model of an amp simulator, the
preset of an amp plugin or the instrument file of a sampler. Each point of
a state lane gives a device one state, and the device keeps the state up to
the next point. For the keys and the fields, see
[Automation](../reference/automation.md#state-lanes).

The page explains how a state lane works. It also explains why a change
lands exactly on its point in one case, and near its point in another case.

## A lane of states, in the core

A state lane is part of the core and not of an extension, and it knows
nothing about any one plugin. Each state of the lane has one or more of the
following parts:

- A saved state (`state`), which is all the bytes that the plugin saves.
- A request to the device (`call`), e.g., an LV2 property that names a
  file.
- Parameter values (`params`), and a program change (`program` and
  `bank`).

A point holds the number of a state, and the state holds until the next
point, with no curve between the points. Before the first point, the first
state holds, as the first value of a curve holds. The lane keeps the states
inside the project and not in an extension's `meta`, so a project with a
state lane opens and plays without the extension that made the states. The
`plugstate` extension only fills the lane, because it turns a model, a
preset or a snapshot into a state.

## How paw gives each part of a state

A plugin takes the parts of a state in different ways, and paw uses the
most exact way for each part.

| Part | Where paw gives it | Where the change lands |
| --- | --- | --- |
| Parameters | the audio thread | on the frame of the point |
| Program change | the audio thread, as an event to that device only | on the frame of the point |
| Request that the plugin prepares as a message (an LV2 `patch:Set`) | the audio thread | on the frame of the point; a plugin that loads a file on its worker plays it from the point in a render, and some milliseconds later as the song plays |
| Saved state (`setState` in CLAP and VST3), or a request with no message | the main thread | in a render, on the frame of the point; as the song plays, some milliseconds after the point, and later if the plugin loads a model in the background |

### On the audio thread

The engine ends a block on each point of a state lane, so a new state
starts on the first frame of a block, and the engine sets parameters and
sends a program change there. The change lands on the exact frame, also
with a large buffer.

An LV2 plugin takes a file through a `patch:Set` message on its atom input.
The main thread makes the message before the song plays, and the engine
gives it to the plugin. Neural Amp Modeler loads the model on its worker
thread, and the model plays when the worker answers, which is after the
block that brought the message. The engine therefore gives the message on
the last frame of the block before the point, and the new model plays from
the frame of the point.

In a render, paw waits after each block until the worker has done the work
that the block asked for, so the render has the new model from the frame
of the point, and each render is the same. The LV2 standard also lets a
host do the work inside the block, but paw does not do that, because Neural
Amp Modeler then gave different sound in some renders. As the song plays,
the worker loads the model in the background, and the new model plays some
milliseconds after the point.

A plugin in its helper process (see
[About the plugin sandbox](about-the-plugin-sandbox.md)) gets the message
through the shared memory, with its block.

### On the main thread

CLAP and VST3 load a saved state only on the main thread, and many plugins
then load the parts of the state in the background, e.g., TONE3000 loads
its models in that way. Such plugins also do not change their preset for a
program change, so a saved state cannot land on a frame while the song
plays. paw gives the state when the main loop sees the playhead after the
point. The change comes some milliseconds after the point, and the plugin
can need more time to load what the state names.

A render does not have to keep time. It stops on the frame of the point,
and the main thread gives the saved state. Then the render waits until the
plugin is ready, and it continues.

A plugin in a helper process tells paw that it is ready when its process
uses no processor time for a moment. While a plugin loads a model, its
process works, and when the process is quiet, the plugin is ready. paw
waits for that sign, but not longer than the render's `settle` time (5
seconds). A plugin in paw's own process gives no such sign, so paw waits a
fixed half second.

paw also waits at the start of each render, and it plays half a second of
silence with the song stopped. A plugin can fade over to a new model as it
plays, and TONE3000 takes about a third of a second for the fade. The wait
fixes the first second of a render, which had no model in it when a plugin
loaded its model in the background.

## Other ways that paw did not choose

Other ways can give a saved state on an exact frame as the song plays, and
paw uses none of them:

1. A second instance of the plugin. See the next section.
2. The saved state, given early. paw could give the saved state before the
   point, by the time that the plugin needs to load it. But the time is not
   known and is not the same each time, so the change would come before the
   point by an unknown time, which is not better than after it.
3. A parameter of the plugin that chooses its preset. A plugin that has
   such a parameter gets it on the frame of the point, like each parameter,
   so put the parameter in the state (`params`). TONE3000 and Soundshed
   Guitar have no such parameter.

### A second instance of the plugin

paw could load the next state into a second instance before the point, and
change to that instance on the frame of the point. The cost is a second
instance, with its memory and its processor time while it plays beside the
first. To keep the sound continuous, the second instance must also hear
the input before the point, and a crossfade hides the difference between
the two.

On one test machine, the helper process of one TONE3000 instance with a
preset used 35 MB of memory. A render of 32 seconds with a second instance
on a second part took 5 % longer (a median of 2.60 s for 2.47 s, under a
load of other work). paw does not do this yet, because a render is already
exact, and as the song plays, a change of some milliseconds is difficult to
hear in most music.

## The state that the project keeps

A device that a state lane drives holds the lane's states as the song
plays. The project keeps the device's own state, and it does not read the
lane's state back from the plugin, in the same way as for a parameter that
a lane moves. When you stop or remove the lane, paw gives the device its
own state again.

## After a saved state, the state is the truth

A saved state, a snapshot, a preset and an undo all give a plugin a whole
state. After the plugin gets a whole state, the state is the truth, and the
values of the parameters that paw shows are only a copy of the state.

Some plugins take the state only at the start of their next block, e.g.,
JUCE plugins such as Surge XT. paw lets a plugin sleep when its sound
stops, and a plugin that sleeps processes no block, so it would never take
the state.

For that reason, a plugin that gets a state always processes its next
block, and its tail time starts again. A VST3 controller reads its values
from the processor when it gets the state, before the processor has the
new values, so paw gives the controller the state of the component again
after the next block.

### The echo of a state

After a state, a plugin tells paw the values of its parameters. The
messages are the echo of the state and not an edit, so paw only updates the
values that it shows:

- The echo makes no undo step and does not change the project. It does not
  remove a parameter that the project sets.
- The echo does not write automation, and it does not change the parameter
  that `:param.last` uses.
- paw does not send the echo of a VST3 plugin back to its processor,
  because the processor already has the state. After an undo soon after a
  state, an old echo therefore cannot play the values of the earlier state.

### How paw tells the echo from an edit

A move in the window of a plugin is an edit, also right after a state. paw
tells the echo from a move by what the plugin says and not by the time, so
a slow computer that gets the echo late does not turn it into an edit. paw
uses these signs:

- Gestures. A plugin marks a move of the user in its window as a gesture.
  CLAP sends `GESTURE_BEGIN` and `GESTURE_END` around the move, and VST3
  calls `beginEdit` and `endEdit`. A change in a gesture is always an edit.
- Values that paw asked for. A value that paw reads back from the plugin
  after a state is the echo, because paw asked for it. A change that a
  CLAP plugin sends without a gesture in its first block after the state
  is also the echo, because that is the block in which a plugin such as
  Surge XT takes the state.
- The value itself, for the other changes:
  - Some plugins send a change without a gesture at other times. A value
    that a recent state gave the parameter is the echo of that state, and
    another value is an edit. paw keeps the values of the states since the
    last edit of each parameter, so the late echo of a state before an undo
    is also an echo. A change without a gesture to the value of one of
    those states makes no edit, which is correct, because the plugin
    already has that value.
  - An LV2 editor writes a control without a gesture, because paw does not
    give it `ui:touch`, so the value decides, as above. The messages that
    an LV2 plugin sends from its audio thread (`patch:Set`) change
    properties and not parameters, so they are never an edit.

paw keeps the edit mark with each change, also when the plugin runs in a
process of its own, because each change in the shared memory between the
two processes has a flag for an edit.

Surge XT stops the notes that sound when it takes a whole state, and that
includes a note that starts in the same block as the state. Put a point of
a saved state before the next note, not on it.
