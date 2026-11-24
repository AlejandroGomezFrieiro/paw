# About kinds

<!-- tags: kinds-of-things -->

A kind is the name of a sort of thing in a project, e.g., a MIDI clip, a
vocal part or the phonemes of a sung note. paw has four families of kinds,
and one function defines a kind in each of them,
`paw.kinds.define(family, name, spec)`. The page explains what each family
holds, why the core keeps a list of every kind, and what happens to a
project when the extension that defined a kind is not loaded.
[Extensions](../reference/extensions.md) describes the fields of each
kind.

## The four families

The stream family names what a lane or a clip carries, and the core
defines four stream kinds. A `midi` stream has notes, an `audio` stream
has samples, and `curve` and `state` streams have the values of a lane.
Each stream kind says whether it counts time in beats, samples or seconds,
and it can declare properties, e.g., the `midi` stream has a property
`lyrics` for a stream whose notes carry words. The kernel checks a stream
type against its kind, so a property that a kind does not declare is an
error with its name.

The clip family names the sorts of clips. The core has four of them,
`midi`, `audio`, `nest` (a subproject that plays as a clip) and `curve`,
and an extension adds more, e.g., a film or light cues. A clip of an
extension's kind keeps the data of the kind and the sound that the kind
made from it. The field `gives` of the kind names the stream kind of that
sound.

The part family names the sorts of parts, e.g., a vocal part of the utau
extension or a drum part of the drums extension. The core defines no kind
of part. A part keeps the name of its kind in its own field `kind`, and
`:part.kind` changes it.

The meta family names the keys that modules keep in `meta`. The project, a
part, a clip and a note each have a `meta` table, where an extension keeps
its own data under a key, and the extension declares each key with
`paw.meta.define(key, spec)`. `K` then names the extension that keeps a
key, and the version of a key lets the extension move data of an older
version.

## Why the core keeps every kind

The Lua side of a kind holds functions, e.g., how a clip of the kind
draws or what Enter opens. The kernel keeps a plain copy of each kind:
its name, its title, its owner, the stream that it gives and the schema
of its data. The copy lets the parts of paw that run no Lua of the
extension know the kind. For example, a tool that reads the project
through `paw.api.kinds_list` sees the owner of each kind and the fields of
its data. Such a tool can change the data of a kind with a schema, and a kind
without one is read only for the tool.

The owner of a kind is the extension that defined it, the core, or your
configuration. When an extension unloads, its kinds go with it, and a kind
that it replaced comes back. An extension cannot replace a kind of the
core, because the rest of paw relies on what those kinds do.

## A project without the extension

A project opens and plays when the extension that defined one of its
kinds is not loaded. A clip of the kind keeps its data and its sound, and
it plays the sound. A part of the kind shows the name of the kind, plays,
and keeps its clips, its lanes and its devices. A key of `meta` that no
loaded extension declares stays as it is, and `:checkhealth meta` lists
it with the files that hold it. paw saves all of them again as it read
them, so a project that went through a computer without the extension
loses nothing.

## Why some data is a field and not a key of meta

A key of `meta` belongs to one extension, and the core never reads it.
When the core or a file format needs the data, the data becomes a field.
The lyric of a note is the example. A lyric is MIDI data: a MIDI file
keeps lyrics, MIDI import and export read and write them, and a MIDI clip
file keeps each lyric as a standard MIDI 2.0 Lyrics message. So the
lyric is the field `note.lyric`, which is plain text.

The data of utau
belongs to its kind: the phonemes, the pitch curves and the flags of a
sung note are in utau's own key of `meta`, because only utau reads them. The kind of a part and the group that holds a part are fields
for the same reason: the views, the mixer and saving all read them.
