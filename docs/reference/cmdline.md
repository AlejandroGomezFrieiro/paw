# The command line

<!-- tags: cmdline command-line -->

`:` opens the command line at the bottom of the screen, and it runs a command by its name, for example `:q` to quit and `:w` to save. Ranges, `:s` and `:g` are described in [Ex commands](ex.md).

## Completion

While you type a command, a list above the command line shows what the line can become, with a description of each item. The list shows command names first, and after the name it shows the arguments of the command.

| Command | The list shows |
| --- | --- |
| `:send` | tracks, by name |
| `:device.add` | devices |
| `:open`, `:import`, `:render`, `:write` | files |
| `:set` | options |

| Key | Effect |
| --- | --- |
| `Tab`, `Ctrl-n` | Puts the next item of the list in the line. |
| `Shift-Tab`, `Ctrl-p` | Puts the previous item in the line. |
| `Enter` | Runs the line. On a directory, it opens the directory in the list. |
| `Up`, `Down` | The lines typed before. |
| `Esc` | Closes the command line. |

A command name that is not complete runs the command of that name with `.open`, if an extension has one, so `:notation` runs `:notation.open`. Otherwise paw shows the commands that the name can mean.

## Options

| Command | Effect |
| --- | --- |
| `:set {name} {value}`, `:set {name}={value}` | Sets an option: `:set zoom 4`, `:set zoom=4`. |
| `:set {name}` | Sets a true or false option to true: `:set follow`. For other options, shows the value. |
| `:set no{name}` | Sets a true or false option to false: `:set nofollow`. |
| `:set {name}!`, `:set inv{name}` | Switches a true or false option: `:set follow!`. |
| `:set {name}?` | Shows the value of an option: `:set zoom?`. |
| `:set {name}=a,b` | Sets an option that is a list: `:set doctor_plugins=Surge,Vital`. Nothing after `=` makes the list empty. |
| `:set {name}+=a`, `:set {name}-=a` | Adds an item to a list option, or removes it. |
| `:setlocal {name}` | Sets an option of the window: `:setlocal timebind`. |

A name that is not an option gives the error `E518`. See [Options](options.md).

## Prompts

Some keys open a prompt with the current value in it, for example `grn` (rename the track). The value is selected, so what you type replaces it, and you press `Left` or `Home` first to edit the value instead.

Some prompts ask for a number, for example `grv`, `grp`, `grt`, and `c` on a parameter or on a point of automation. A number is the value with its sign, so `-6` is -6 dB and `+3` is +3 dB. To change the value by a step, put `=` after the sign, so `-=3` is 3 dB lower and `+=2` is 2 dB higher. The prompt shows this rule, and the Ex commands `:volume` and `:pan` use the same rule (`:t* volume -=3`).

## Unsaved work

Work is unsaved when the project has changes, and also when a project with no file is not empty, for example a project opened from a MIDI file or a REAPER project. The commands `:open`, `:edit`, `:new`, `:recent`, `:recover`, `:tutor` and `:q` do not replace a project with unsaved work. They show a message and stop.

- `:w` saves the work first.
- The same command with `!` discards the work: `:open! song`, `:new!`, `:q!`.
- `:e!` alone opens the project again as you saved it last, the same as in Vim.

The graphical window asks in a dialog box.

`:open` opens a project, a MIDI file (as a new project) or a sound file.
`:example` opens an example or a practice project that comes with paw.

## Relative names

A file name without a folder (`:render mix.wav`, `:import loop.wav`) goes into the folder of the project, and a project name (`:w take2`) goes beside that folder. Before the first save, a name goes into the folder where paw started. `..` goes up, `~` is your home folder, and a name that starts with `/` is a full path.

The lists of files (`:open`, `:import` and the others) and the Save as prompt start in this folder too. `:w` with no name on a project that has no file asks for the name at a prompt (`Save as (folder):`) that starts with the project's name, and Tab completes names, `..` and `~` too.

| Command | Effect |
| --- | --- |
| `:pwd` | Shows the folder for relative names. |
| `:cd {folder}` | Sets that folder, the same as in Vim. A relative folder starts from the folder now. |
| `:cd -` | Returns to the folder before. |
| `:cd` | Goes to your home folder. |

## Errors

A command that fails shows one line that says why, and the full error with the place in the code goes to the log.

## Messages

After an error, the bottom line says how to read the full message, until
you read it.

| Key or command | Effect |
| --- | --- |
| `:messages` | Shows all messages, newest at the bottom. A long message wraps over many rows. |
| `<Space>fl` | Chooses a message from a list, newest first. |

## Find what is slow

| Command | Effect |
| --- | --- |
| `:profile start` | Starts `jit.profile`, the tool of LuaJIT that finds slow Lua code. Each millisecond, it notes the Lua function that runs. |
| `:profile start {file}` | The same, and `:profile stop` also writes the folded stacks to the file, for a flame graph. |
| `:profile stop` | Stops `jit.profile` and puts the 30 Lua functions that took the most time in the quickfix list, with their share of the samples, their file and their line. |
| `:profile` | Says whether `jit.profile` runs. |

To see where the time of the start goes, start paw with `--startuptime <file>` (see [The programs and their options](programs.md)).

## Keys that are not complete

If you stop in the middle of a key sequence, paw lists the keys that can come next, and a group of keys shows its name, for example `+automation`. `paw.opt.hint_delay` sets the time before the list shows, and `paw.opt.hints` turns it off.

A key sequence that has no mapping stops with a message, for example `<Space>kn is not mapped`. paw discards the other keys that you typed and does not run them as new commands.

## Find a key or a command

| Key | Effect |
| --- | --- |
| `?` | Lists every key of the focused view and the global keys. Type a part of a key or of its description to filter the list. `Enter` runs the key. See [Pickers](pickers.md). |
| `<Space>f:` | Chooses a command by its name. |
| `:help all` | Shows the keys of the focused view as one page. |
