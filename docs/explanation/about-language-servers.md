# About language servers

paw shows problems in the music and in the mix where they are, and it
offers fixes. A language server finds the problems, and each view of paw
shows them. For example, a
server finds a parallel fifth, a fader that clips, or a master that is too
loud. Each view then shows the problem on the thing that has it.

## Four layers

The design has four layers, and no layer knows a server by its name. The
layers are:

1. Addresses. Each thing that a server can talk about has a URI.
2. Subjects. A subject is what a server gets, which is a part of the
   project as plain data.
3. Clients. A client starts a server and speaks to it.
4. Features. Diagnostics, labels, hover, actions and suggestions are
   features. paw keeps them by location, and each view draws them where
   they belong.

A new server needs no change in the views, and a new view shows the
diagnostics of every server. MIDI LSP, which comes with paw as an
extension, is one server of many. `extensions/mixdiag` is another server,
and it runs in the kernel process.

## Why addresses use ids

A fix must change the correct thing, also after other edits. paw used to
find a note again by its pitch and start, but a move of the note broke the
link. Now each note gets an id when paw makes it, and the id stays with the
note through every move. A diagnostic on `paw://clip/7/note/41` stays on
the same note, and its fix changes the same note.

## Why subjects are projections

A server must not know the internal model of paw, so it gets a subject,
which is a stable view of a part of the project. For example, a subject can
be a clip in the format of MIDI LSP, a track, the mix or a render. When the
model changes, only the projection changes, and the servers continue to
work.

A server says what it wants to see. With `focus`, it gets only what a
person looks at, so a large project does not send all its clips.

## Why the protocol is LSP

LSP has clients and libraries in many languages, and it has free `data`
fields where paw puts its locations and workspace edits. A server for paw
is a usual LSP server with a small extension, and a server that speaks
another protocol needs only an adapter.

## Why a workspace edit is one undo step

A fix can change many things, e.g., a fader and a device, or many notes.
paw checks all the changes first and then applies them together, so one
`u` removes the full fix, and a fix that is not valid changes nothing.

See [Language servers and diagnostics](../reference/language-servers.md)
for the reference, and
[How to write a language server](../how-to/write-a-language-server.md).
