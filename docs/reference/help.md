# Help

<!-- tags: help-pages -->

The manual is in paw, as the manual of Vim is in Vim. `:help` opens the
contents in a window split from the current window. `:help` with a topic
goes to the place that describes the topic.

## Topics

| Topic | Goes to |
| --- | --- |
| `:help gU`, `:help Ctrl-w o`, `:help <C-w>o` | a key, written in either form: its row in the key table (`reference/keys.md`) if it has one |
| `:help :s`, `:help :helpgrep` | a command |
| `:help 'timebind'` | an option |
| `:help paw.qf`, `:help paw.qf.feed` | a Lua module or function |
| `:help paw://tracks` | an address |
| `:help key-rule`, `:help quickfix-list`, `:help motions` | a section of the manual |
| `:help grammar`, `:help course-5`, `:help notation`, `:help notation-keys` | a page: of the manual, a lesson of the course, an extension (by its name), a section of an extension |

paw finds a topic as Vim does. First it looks for the tag itself, then
for the tags that start with it, then the tags that hold it. Last, it looks
for the tags that hold its letters in order (`:help qflst`). `Tab` after `:help ` completes the tags in that
order.

## Tags

paw makes a tag for these:

- each heading: its words joined with `-`. "The quickfix list" is `quickfix-list`. In the page of an extension, the tag starts with its name. In a lesson, it starts with `course-5`.
- each paragraph that starts in bold: "**Motions** move the cursor" is `motions`.
- each key, command, option, Lua name and address written as code, at the place that describes it (the first column of a table, the start of an item of a list), before the places that only name it.
- each name in a comment `<!-- tags: a b -->`.

A tag in the manual comes before a tag in the tutorials and the extensions.

## Pages

The pages are all Markdown files in `docs/`, and the `README.md` and
`doc/*.md` files of each extension. The contents show the pages of the
manual in four groups, in the order of `docs/README.md`: tutorials, how-to
guides, reference and explanation. A page has the name of its file
(`grammar`). If two groups have a page with the same name, the name of the
group comes first (`how-to-recording`). The course is in
`docs/tutorials/course`.

Help shows the extensions of your configuration and the extensions that
come with paw, also when they are not loaded. The page of an extension that
is not loaded says how to load it. Help reads the pages from the source
tree that paw runs from, or from the source tree that `$PAW_HOME` names.

## The help window

A page of help is a text buffer that you cannot change. It moves,
searches, selects and copies as any text (`j` `k`, `w`, `/`, `n`, `v`,
`y`, `gg`). `:vs`, `:sp`, `Ctrl-w` and `:q` work on its window as on any
other window. A heading shows its tag at the right (`*quickfix-list*`), as
in the help of Vim. Code has its own color, and tables show in columns.

| Keys or command | In help |
| --- | --- |
| `Ctrl-]`, `Enter`, a double click | Follows the link under the cursor, or finds the key, command or word there. |
| `Ctrl-t`, `Ctrl-o` | Return to where you followed the link. `Ctrl-o` returns through every jump, across pages. |
| `K` | Finds the word under the cursor (in any text buffer). |
| `-` | Shows the contents. |
| `:helpgrep stretch` | Puts every line of help that holds the words in the quickfix list, and goes to the first. `]q` `[q` go through them. Case counts only when a word has a capital. |

## Help from other places

- The bottom line of each view ends with its topic: `:help arrange-view` in the arrange view, `:help mixer` in the mixer.
- In the keys picker (`?`) and the commands picker (`,,`), `Ctrl-]` opens the help of the chosen key or command.
- The panel of the tutor gives the page of its lesson (`:help course-5`).
- In the graphical window, help opens as a docked pane, with the same keys. `Ctrl-w f` shows it in a window of its own.
