# The order of a turn

<!-- tags: scripting-turn -->

paw does its work in turns, and each turn runs the same steps in the same order. A key you press, a timer of an extension and a request of a connection each run in a turn. The list below gives the steps, so that an extension knows what it sees when its code runs.

## The steps of a turn

1. **Messages.** paw takes the messages that came since the last turn, in the order they came. These are the keys, the mouse and the size of each terminal, and the requests of connections. Then paw hears the MIDI that came in from ports and the output of helper programs, with `midi.*` and `proc.output` events.
2. **Upkeep.** paw looks after the plugins (their idle calls and their loads), the files that changed on the disk, the bakes and the renders. With the stepped audio backend of the tests (`paw --audio step`), the engine first plays the blocks up to the time of the turn.
3. **Timers.** paw runs the timers that are due at the time of the turn, in the order of their due times.
4. **The end of the turn.**
    1. paw sends the edits of the turn to the engine. Automation that a control holds is written, and the media files are read ahead of the playhead.
    2. paw sends the change events of the edits to their handlers. A handler can edit the project too, and paw then sends the events of those edits, for up to 64 rounds.
    3. paw sends `edit.before`, `edit.after`, `selection.changed`, `view.opened` and `view.closed`. Then it sends the scenes and the state to the connections.
    4. paw closes the undo step. The edits of the turn are one step.
5. **Wait.** paw waits until a message comes or the next timer is due. While a plugin asks for idle calls, or work runs in the background, paw also takes a turn every 16 milliseconds.

After a turn that changed the screen, paw draws it again on each terminal.

## What follows from the order

- When a key and a timer are due in the same turn, the key runs first. MIDI that came in is heard before the timers too.
- A timer that a handler starts with no delay runs in the next turn, not in the turn that started it.
- Code that reads the project in a change handler sees the edits that the engine has. `paw.flush()` does steps 4.1 and 4.2 at once, in the middle of a turn.
- A request of a connection is a turn of its own. Its events are sent and its undo step closes before paw answers it.
- `paw.api.step()` takes one turn. `paw.wait(ms)` takes a turn at each due time on the way. Code that waits in a handler gets the MIDI and the helper output, but the keys and the requests wait for the turn that is running to end.

## Times

| Function | Clock |
| --- | --- |
| `paw.api.now()` | The time of the turn: the clock that timers and delays use. With `paw --clock manual` it moves only when a script waits. |
| `paw.api.real_ms()` | The time on the wall, to measure how long work takes. |

See also [Events](events.md), [Timers, programs and other modules in Lua](lua-other.md) and [Programs](programs.md).
