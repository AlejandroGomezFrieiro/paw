# Structural queries

<!-- tags: query select :select :query paw.query -->

A query finds things by their place in the project, in the same way that a
Tree-sitter query or a CSS selector finds nodes in a tree.

```
:select clip[name~=pizz] > note[pitch>=C5]     the high notes of the pizzicato clips
:select group[name=Strings] clip               every clip of the parts in the Strings group
:query note[lyric^=la], note[art=staccato]     two kinds of note
:query clip:has(note[vel>120])                 clips with a very loud note
```

## Commands

| Command | Effect |
| --- | --- |
| `:select` | Chooses what the query finds, where things can be chosen: the notes in the piano roll (each in its clip, the first clip shown), or the clips in the arrange view, as a visual selection. It also lists all of it in the quickfix list. |
| `:query` | Only lists what the query finds in the quickfix list. |
| `:lquery` | Lists it in the location list of the window. |

After a query, `:cdo` acts on each thing it found (see [The quickfix list](quickfix.md)).

## The tree

- The project holds its parts, markers and regions. A group holds its members. In a window narrowed to a group (`:narrow`), the project holds only the parts of that group.
- A part holds its clips, devices and automation lanes.
- A MIDI clip holds its notes and controller moves.
- A lane holds its points.

## Syntax

| Syntax | Meaning |
| --- | --- |
| `part` `group` `clip` `note` `cc` `device` `lane` `point` `marker` `region` | A step: a kind of thing. |
| `*` | A step: any kind. |
| `kind[test]` | The things of a kind that pass the test. |
| `a > b` | A `b` directly in an `a`. |
| `a b` | A `b` anywhere in an `a`. |
| `a, b` | Both queries. |
| `a:has(query)` | An `a` that holds something that the query finds. |

## Tests

A test is a field, an operator and a value.

| Operator | Holds when the field |
| --- | --- |
| `=` `!=` `<` `<=` `>` `>=` | compares as written |
| `~=` | matches a regular expression |
| `^=` | starts with the value |
| `$=` | ends with the value |
| `*=` | holds the words |

- `pitch=c4|e4` is either value.
- A field alone holds when it is set (`part[mute]`). `!field` holds when it is not set (`clip[!muted]`).
- A pitch is `c4`, `c#4`, `60`, or `c` in any octave.
- A length is in beats or a note value (`note[len<1/8]`).
- Text compares without regard to case.

## Fields

The fields are those that `paw.api` gives for each kind (a note has
`pitch` `velocity` `start` `length`, a clip `name` `start` `length` `kind`
`file`, a part `name` `volume` `pan` `mute` `solo`). The fields below are
also available.

| Kind | Fields |
| --- | --- |
| note | `vel` `len` `end` `at` (the beat in the song) `bar` `lyric` `art` (its articulations: any can match) `channel`, and the fields of `:s` and `:g` (`paw.ex.field`) |
| clip | `end` `bar` `notes` (the count) `muted` `part` (the name of its part) |
| part, group | `index` `group` `devices` (the count) |
| marker, region | `name` `start` `end` `bar` |
| device | `index` `part` |
| lane | `name` `points` |
| all | `comment` |

## Motions and text objects of the tree

The keys below obey the key rule.

| Keys | View | Effect |
| --- | --- | --- |
| `]c` `[c` | arrange | The next or the previous clip of the same kind on the part: the same name without a number or "copy" at its end (`pizz 2` is a `pizz`), and MIDI or audio as this clip. |
| `]s` `[s` | arrange | The next or the previous part next to this part in its group (or at the top). |
| `[{` `]}` | arrange | Up to the group of the part (as `[{` of Vim goes to the brace around). The last part of the group (if the cursor is there, the last part of the group around it). |
| `]u` | arrange | Down into a group, to its first part. `[u` is the same as `[{`. |
| `ig` `ag` | arrange | The parts of the group of the cursor. With the group part. |
| `]n` `[n` | piano roll | The next or the previous note of the same pitch. |
| `]]` `[[` `]s` `[s` `[{` `]}` | notation, in a score | The next or the previous instrument. In its group. The first and the last of the group. See [Scores](../../extensions/notation/doc/reference.md#scores) in the reference of notation. |

They take a count, and they are motions for the operators, so `d]c` deletes
up to the next clip of the kind. `]c`, `[c`, `]n`, `[n`, `]]`, `[[`, `[{`
and `]}` go in the jump list. In the arrange view and the piano roll, `]`
and `[` change the pan and the velocity, so `]]` there is two steps of that
value. `:g` and `:v` (see [Ex commands](ex.md)) are another way to act
on what a pattern finds.

## Lua

| Function | Effect |
| --- | --- |
| `paw.query(q)` | Gives the nodes: `{ kind, id, data, parent, part, clip, location }`. `data` is the thing as `paw.api` gives it. paw keeps the nodes of clips and notes from one query to the next, so read a node and don't change it. |
| `paw.query.select(q)` | Does what `:select` does. |
| `paw.query.field(kind, name, fn)` | Adds a field of your own. |

A query can also be a table of steps. A step is a string or a table of the
kind and its tests. `">"` between two steps makes the second step directly
in the first.

```lua
for _, n in ipairs(paw.query("clip[name~=pizz] > note[pitch>=C5]")) do print(n.data.pitch) end
paw.query({ { "clip", name = "~= pizz" }, ">", { "note", pitch = ">= C5", function(n) return n.data.velocity > 90 end } })
paw.query.select("note[lyric=la]")
paw.query.field("note", "channel", function(n) return n.data.meta.channel end)
```
