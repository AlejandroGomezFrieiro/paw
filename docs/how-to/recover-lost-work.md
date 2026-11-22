# How to recover lost work

You can get back work after a crash, a power loss, or a damaged project
file. The rules are in [Project files](../reference/project-files.md).

1. Start paw. If a session ended badly, a message says that there is work
   to recover.
2. Type `:recover`. paw lists the safety copies, the `.bak` files, and the
   takes that no clip uses.
3. Select an entry. paw opens it with the name of its project, but it does
   not save it.
4. Look at the project, and if it is correct, type `:w`.

If a plugin caused the crash, select the entry with "(plugins offline)".
Then set the plugins online one at a time (see
[How to open a project without its plugins](open-a-project-without-its-plugins.md)).

If the project file is damaged, paw shows a message when you open it.
Type `:recover`, and the newest safety copy and the `.bak` file of the
project are first in the list.

If a take is not on its track after a crash, type `:recover` and select
the take. paw then puts it on the track that recorded it.

In the graphical window, select File → Recover unsaved work….

paw makes safety copies only when `paw.opt.autosave` is more than 0.
