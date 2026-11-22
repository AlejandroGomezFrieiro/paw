# About project files

paw keeps a project as a folder of files and writes each file in a safe
way, because a project holds hours of work. A project must survive a crash
during a save and a move to another disk. It must also survive a merge in
version control, and a second program that changes one of its files. The
page explains why paw keeps a project as a folder and how it writes the
files. For the details, see [Project files](../reference/project-files.md)
and [Media files and audio clips](../reference/media.md).

## A project is a folder of files

A project kept in one file is hard to merge, because version control sees
one large file that changes at each save, so two people who change two
different tracks change the same file, and a merge must take that file
apart.

paw keeps a project as a folder. The settings that you can edit by hand,
e.g., the tempo, the meter and the order of the tracks, are in
`project.toml`. Each track has a folder of its own with the name of the
track. In the folder, `track.json` holds the track and its clips,
`devices.json` holds the chain, and each clip has a file of its own.

Each file has a name that a person can read, with the usual extension,
e.g., `.toml`, `.json`, `.midi2` or `.wav`. paw adds no extension of its
own, so other programs and the tools of the shell can read each file.

The rule is that each part that can be a file is a file, as long as a save
and an open stay fast. One change then changes one or two small files, so a
`git diff` shows what changed in which track, and a merge of two changes to
two tracks needs no help.

A track folder has the name of the track, and it gets the new name when you
rename the track. A clip file has the name of the clip. Version control
then shows a rename as a rename, because the bytes of the files do not
change.

## MIDI clips are MIDI files

A MIDI clip is a MIDI 2.0 Clip File (`.midi2`), as the MIDI Association
specifies it. paw holds notes and controllers at the resolution of MIDI
2.0, and the clip file holds the same resolution, so a clip goes to its
file and back with no loss. Other programs that read MIDI 2.0 can read the
clips of a paw project without paw.

A clip file is binary, so for `git diff`, `paw clip cat` prints a clip as
text, with one note on each line. paw writes a `.gitattributes` file that
tells git to use it, and `:checkhealth` tells you how to configure git for
it.

A Standard MIDI File (`.mid`) is MIDI 1.0, and paw reads and writes it for
exchange with other programs. MIDI 1.0 goes into MIDI 2.0 with no loss, but
the other direction loses resolution, because a value of 32 bits becomes a
value of 7 bits, and a controller of one note has no place. `:export` tells
you what it rounded and what it left out.

## The same project gives the same bytes

paw writes the JSON files with the keys in order, and it writes each number
with the fewest digits that read back exactly. A save of a project that did
not change therefore writes the same bytes, and one change gives a small
diff.

paw compares each file with the file on the disk and writes only the files
that changed, so a save after one edit is fast, even for a large project.
The time of each file that did not change stays the same.

## A save is all or nothing for each file

If a program writes over a file and the power fails during the write, the
file is half old and half new, which means it is damaged. paw instead
writes each new file next to its place, flushes it to the disk, and then
renames it over the old file. A rename is atomic on the file system, so
after a crash each file is either the complete old file or the complete new
file. paw writes `project.toml` last, so it never names a file that is not
complete.

Before a save changes `project.toml`, paw keeps the old one as
`project.toml.bak`. If another program damages `project.toml`, the `.bak`
and the track folders still hold the project, and `:recover` opens them.

## paw never deletes your files

A save does not delete a file that the project no longer uses. Instead, it
moves the file to the `unused` folder of the project, at the same path. For
example, a clip that you removed is in `unused/tracks/<track>/clips`. paw
never empties `unused`, so you decide when to delete it.

When a file has the same bytes as a file that the save needs at another
path, paw moves the file there, which is what happens when you rename a
track.

## Repeats share one file

When you copy a part, the two clips have the same notes, so the project
writes their notes to one file and both clips name it. When you change one
of the two clips, it gets a file of its own at the next save.

## Files from outside the folder

A clip or a sound file can come from a file outside the project folder,
e.g., a library of loops. The project names the file and keeps no copy, so
many projects can use one library. A whole track can also come from
outside, from the track folder of another project, and a chain of devices
can come from a `devices.json`. You can make a sound one time and use it in
many songs.

The first edit of such a clip, track or chain makes a copy that belongs to
the project. paw tells you about the copy one time on the message line, and
the copy remembers the file that it came from. An undo of the edit returns
to the file outside. `:collect` copies every file from outside into the
folder, for a project that you send to another person.

A file that paw cannot find does not stop the project. Its clip stays,
empty and marked offline, and a save keeps its path.

## Relative paths

A project names the files in its folder by a path relative to the folder,
so you can move or copy the folder. If paw cannot find a sound file, it
looks for the file before it asks you. It looks in the folder of the
project, by the last parts of the old path, and next to other files that it
found.

## A project is always a folder

A project of yours is always a folder, because two forms of one project
would need two sets of rules, e.g., which form a command writes, where the
media goes and what version control sees. One form gives one set of rules.

paw still writes a project in one JSON file for its own work, i.e., for the
safety copies, the states of the undo history, and the versions that
`extensions/projdiff` compares and merges. Such files are fast to write in
one piece, and no person edits them. `:w song.json` therefore saves the
folder `song` and tells you so. A project that an earlier version of paw
saved in one file opens, and `:w` saves it as a folder beside the file.

## Safety copies

A save protects the work that you saved, and safety copies protect the
work that you did not save. paw copies a changed project to a recovery
folder at intervals, and also when paw panics. A take writes its WAV header
every two seconds, so a power loss leaves a valid file. `:recover` brings
all of it back from one list.

## Why recordings of an unsaved project go elsewhere

A project with no folder has no `media` folder, so paw records into a
shared recordings folder. At the first save, it links or copies the files
into `media` in the project folder. The original files stay, because
earlier undo steps can still use them.
