# About seats

One instance of paw can serve more than one person, or more than one
screen, at a time, and each of them is a seat. `paw attach` adds a
terminal, and `paw-gui` adds a graphical window. The page explains why paw
divides the state of a module between the seats and the project.

## One project seen from many places

All seats edit one project, so they share one list of tracks, one set of
notes and one undo tree. But each person looks at another part of the
project. For example, one person edits the drums in the piano roll while
another person moves the faders in the mixer. If the two seats shared one
cursor, each key of one person would move the view of the other person.

paw therefore keeps two kinds of state:

- All seats share the state of the project. It holds the notes,
  clips, tracks, the lanes that the project saves and the diagnostics of the
  project.
- The state of a view belongs to one seat. It holds the focused view, the
  cursor, the mode, the selection, registers, marks and the scroll. It also
  holds a drag, a prompt, a suggestion on the screen and keys that are not
  complete.

Seat 0 belongs to the instance. It is the terminal of the instance, if
there is one, and each connection that has no seat of its own, e.g.,
`paw ctl` and scripts. A graphical window that started its own kernel
shares seat 0.

## Why modules do not change for seats

The first solution that comes to mind is a table of state for each seat in
each module, but then all code must find the current seat. Each module
would be more difficult to write, and each module that a person forgets
would be wrong.

paw does something else. A module keeps its state where it usually keeps
it, in locals or in the table of its view, and it names that state one time
with `paw.seats.keep` or `paw.seats.fields`. When the turn of another seat
starts, paw puts the values of that seat in place, so the code that reads
the values does not know about seats. With one seat nothing moves, so the
usual case costs nothing.

The rule has a consequence, which is that paw swaps a table that a module
keeps as a whole. A new seat must get a new table, or two seats share one
table.

## Turns

The kernel runs one turn at a time, and each turn runs in one seat. A timer
runs in the seat that started it. `paw.seats.within` runs code in another
seat and then returns to the current seat.

[Timers, programs and other
modules](../reference/lua-other.md#pawseats-the-state-of-each-seat) lists
the functions.

## Frontends on one instance

A paw instance is one kernel with one project, and many frontends can show
it at the same time. You can use `paw attach` in a terminal, and
`paw-gui --socket` or `paw-gui --connect` for a graphical window. The
frontends can be on the same computer or on other computers.

### Each frontend has a seat

Each attached frontend has a seat of its own, which holds its cursor, its
mode and its selection. The seat also holds the keys that are not complete,
its registers, its prompt and the panels that it shows. The project is the
same for all seats, so two people can edit one song, each in another view,
and neither person moves the cursor of the other.

The options in `paw.opt`, e.g., the zoom, belong to the instance, and all
seats share them.

A graphical window that starts its own kernel shares the seat of that
kernel, so `paw ctl` acts on what the window shows. A connection that does
not attach, e.g., `paw ctl` or a script, also uses that seat.

### One undo history

An edit from one seat shows at once in all the other seats. Two edits of
the same thing are two steps in the one undo history, and the last edit
stays. `u` undoes the last step from any seat. paw does not try to merge
edits, because one history is easier to understand than one history for
each seat.

### What stays on the computer of the instance

The plugin windows, the files that Save and Render write, and the recording
from the sound device stay on the computer of the instance. A frontend on
another computer shows the project, but the files are on the disk of the
instance. For that reason, `:upload` sends a sound file to the instance
before paw imports it.

### Why the network connection is safe

A connection over the network uses TLS, and the instance makes its own
certificate the first time that it listens. No certificate authority signs
the certificate. Instead, the client trusts the certificate at the first
connection and remembers its fingerprint in
`~/.local/state/paw/known_instances`. After that, the client refuses any
other certificate.

A connection must also show that it knows the token of the instance, but
the token itself never goes over the network. A computer that listens on
the network cannot copy the token, and a false instance cannot get it.

### Why the remote sound is late

paw sends the sound to a client as 16-bit samples at half the rate of the
engine, e.g., 24 kHz for 48 kHz. With the data of the protocol, the stream
is about 1 Mbit/s, which a home network carries but a slow link does not.
The client waits until it has a fifth of a second of sound before it plays,
and it keeps no more than one second. The buffer gives a smooth sound on a
network that is not regular, but the sound is late. Use the remote sound to
monitor a mix, and not to play along with the song.

### See also

- [How to work on paw from another computer](../how-to/work-from-another-computer.md).
- [The control protocol](../reference/protocol.md).
