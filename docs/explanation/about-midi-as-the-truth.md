# About MIDI as the truth

In paw, the MIDI notes of a clip are the truth, which means that they are
what plays and that every view edits them. For example, the piano roll,
Ex, the language servers, MIDI export and the score of the notation
extension all edit the same notes. The page explains why paw keeps one
truth, and how extensions keep data that MIDI cannot hold.

## Why there is one truth and many views

A score shows more than MIDI can say. For example, it shows the letter
name of a pitch (G sharp or A flat), the voice of a note, a staccato or a
dynamic. The first design that comes to mind gives the score a model of
its own and renders MIDI from it, but then there are two truths. An edit
in the piano roll changes the MIDI and the score does not know about it,
so the two drift apart and one of them must win.

paw does not use that design. The notes belong to nobody, so any view or
extension edits them, and nothing asks for permission or refuses. A score
is a view of the notes, like the notation editor of REAPER. An edit in the
score is an edit of the MIDI, so a note that you enter is a MIDI note at
the written place with the written length. A dynamic sets the velocities of
the notes when you write it.

After you write it, the MIDI is free to change. The piano roll can give a
note marked `f` a different velocity, and the mark stays as a label.

## Data that MIDI cannot hold

An extension keeps its data about a note in `note.meta`, under a key of its
own, and its data about a clip in `clip.meta`. For example, `meta.lyric`
holds a sung syllable, and `meta.notation` holds a letter name and a voice.
The core keeps the data with the note through moves, copies, undo and
project files, but the core never reads it.

The data goes where the note goes, because it is on the note. A note that
you move, copy or paste in the piano roll keeps its letter name and its
voice, and a deleted note takes its data with it.

## A project without the extension

Nothing in the core knows about notation or about sung notes. Without the
extension, a clip written in notation is a MIDI clip like all other clips,
so its notes play and every view edits them. The data of the extension
stays on the notes and paw saves it with the project. When the extension
loads again, it shows the notes as they are now, with the data on the
notes that are left.

The rule is strict for that reason. If an extension owned the clip data, a
project would need the extension to play, but with MIDI as the truth, a
project always plays.

## Attributes are MIDI

A MIDI 2.0 note-on can carry an attribute, e.g., an articulation of the
orchestral articulation profile. An attribute is MIDI and not `meta`, so
the core keeps it, plays it, records it and writes it in MIDI files. The
articulations extension only gives the numbers names for each instrument.
See [Project objects in
Lua](../reference/lua-objects.md#note-attributes-noteattr).

## Compared with REAPER

paw uses the model of REAPER, where MIDI belongs to the item and notation
shows it. REAPER keeps what MIDI cannot say as notation events, both on the
notes (letter name, voice, articulation, text) and with the item (dynamics,
clefs, key signatures). paw keeps the same things in `meta`.

The notation extension differs from REAPER in one way, because it reads
played music itself, e.g., strums, swing, drift, voices, hands, grace notes
and tuplets. REAPER quantizes for the display only. The settings of the
transcription belong to the clip (`:notation.set`).
