# The quickfix list

<!-- tags: quickfix-list qf -->

As in Neovim, the quickfix list is one shared list of what is wrong, or
found, in the project. Each entry gives a place, which is a clip, a note, a part, a
point of a lane, a device or its parameter, or a bar, and it says what it
is about and can have a fix. While the list has entries, the status line counts
them as `qf E2 W5`, and as `qf 3/7 E2 W5` after you go to one.

## Problems

paw keeps one list, called Problems, and adds entries when something goes wrong, as follows.

- the diagnostics worse than a hint, with those of language servers and of the mix diagnostics. `:set qf_diagnostics=error` keeps only errors, and `off` none.
- renders that go over full scale, that are louder than `render_loudest` (-9 LUFS), or that fail.
- sound files that are not there.
- plugins that stopped, that gave numbers that are not valid, or that are not installed.
- plugin files that a scan could not use.

The other places keep their entries too: the marks, `]d`, `:diagnostics`,
the mix report and the messages. Extensions add entries (see
[The Lua interface](scripting.md)).

## Keys and commands

| Keys or command | Effect |
| --- | --- |
| `]q` `[q` | Go to the next and the previous entry. A count goes further. The first `]q` goes to the first entry. The view that shows the entry gets the keyboard, and the cursor goes there. For an entry inside a subproject, the window goes inside that subproject first, and for an entry of a song part, back to the song. |
| `]Q` `[Q` | Go to the last and the first entry. |
| `:cnext` `:cprev` `:cfirst` `:clast` | The same as the keys. |
| `:cc 3` | Goes to entry 3. `:cc` alone goes to the current entry. |
| `:copen`, `:copen 15` | Opens a window that shows the list, along the bottom, the full width (`qf_height` rows). |
| `:cclose` | Closes the window. |
| `:cwindow` | Opens the window if the list has entries, and closes it if not. |
| `j` `k` `gg` `G`, `Enter`, `<Space>la`, `q` | In the window of the list: move, go to the entry, do its fix, close the window. |
| `:colder` `:cnewer` | Show the list before and after in the history. paw keeps ten lists. |
| `:chistory` | Lists all lists in the history. |
| `:cdiag`, `:cdiag error` | Makes a list of the diagnostics (as `vim.diagnostic.setqflist`), or of the errors. |
| `:cdo part.mute` | Runs a command on every entry. The cursor goes to each entry, and its address is the target of the command. All is one undo step. |
| `:cfdo part.solo` | Runs a command one time for each part that has entries. All is one undo step. |
| `:cfix`, `:cfix .` | Does the fix of every entry that has one, as one undo step. Does the fix of the current entry. |
| `:lopen` `:lnext` `]l` `[l` `:ldiag` and more | The same for the location list of the window. `:ldiag` lists what the window shows (the piano roll its clip, the mixer and the device panel the part). `:lopen` shows it below the window. |

The list is a buffer like any other buffer. `:vs quickfix` shows it next to
the window, and `:e quickfix` in the window. A layout keeps its window. The
graphical window docks it in a pane (`:copen`, More). `:qf.window` shows it
in a window of its own.

Several commands fill the list: `:g/pattern/` (see [Ex commands](ex.md)),
`:vimgrep` (see [Search the text of the project](grep.md)), `:query` and
`:select` (see [Structural queries](queries.md)), `:profile stop` (see
[The command line](cmdline.md)), and `Ctrl-q` in a picker.
