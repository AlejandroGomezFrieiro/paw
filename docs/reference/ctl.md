# Scripts and `paw ctl`

<!-- tags: scripting-scripts-and-other-programs -->

Other programs use paw through scripts with `paw -l`, calls with `paw ctl`, and terminals with `paw attach`, and every option of the command line is in [The programs and their options](programs.md).

## `paw -l`

`paw -l script.lua [args]` runs a script with no UI and then stops. The arguments are the `...` of the script, and `arg` holds them the way `-l` of Neovim gives them, so `arg[0]` is the script and `arg[1]` and after are the arguments. A script gets the null audio backend, unless its options give another backend.

## `paw ctl`

An instance of paw listens on a Unix socket, and `paw ctl` calls it.

```sh
paw ctl eval 'paw.transport.position'
paw ctl cmd part.add Bass device=synth
paw ctl part_set 3 volume -6                 # any paw.api function
paw ctl keys 'ggm'
paw ctl eval 'paw.api.ui_snapshot(100, 30)'   # the screen as text
```

| Method | Effect |
| --- | --- |
| `eval <lua>` | runs Lua and gives its result |
| `cmd <command> [args]` | runs a command |
| `keys <keys>` | types keys |
| `<function> [args]` | calls a function of `paw.api`. The arguments can be JSON |

- An `eval` is one undo step, and `paw.api.undo_label(text)` gives the step a name.
- `--json` makes each answer one line: `{"ok": true, "result": ...}`, or
  `{"ok": false, "error": "..."}` with exit status 1.

```sh
paw ctl --json eval 'return paw.api.project_get()'
paw ctl --json eval 'return paw.query("clip[name~=riff] > note[pitch>=c5]")'
paw ctl --json part_add '{"name": "Bass"}'
```

The socket carries one JSON object on each line, for example `{"id":1,"method":"eval","params":["..."]}`. A connection can also get the events that it subscribed to, the screen of the terminal UI, and the state that a frontend draws, which paw sends in parts when it changes. [The control protocol](protocol.md) describes all the messages.

## `paw attach`

`paw attach` makes its terminal a terminal of an instance that runs already. It is a seat of its own, with its own cursor, mode, selection and keys, in the same project. The terminal of the instance continues if there is one, and `paw --headless` has none. `:detach` leaves, and the instance continues.

`paw ctl`, `paw attach` and `paw-gui` reach an instance in three ways:

```sh
paw attach                                   # the socket of this machine
paw attach --socket /tmp/studio.sock         # another socket, for example one that SSH carries
paw attach --connect studio:7700 --token-file studio.token   # over the network
```

Over the network, the instance must start with `--listen-tcp 0.0.0.0:7700`, or `127.0.0.1:7700` for this machine only. The connection is encrypted (TLS) and must show that it knows the token. The section "On another machine" in [How to work on paw from another computer](../how-to/work-from-another-computer.md) gives the steps.

## `paw doctor`

`paw doctor` runs the checks of [the doctor extension](../../extensions/doctor/README.md) that need no person, and it prints the report. It opens the sound device, but other scripts get the null backend. It takes the audio options of the program, `--seconds`, `--plugin` and `--only`, and it finds the extension in the source tree beside the binary, or in `$PAW_HOME`.

## `paw-mcp`

`paw-mcp` is a Model Context Protocol server in front of the socket, and [crates/paw-mcp](../../crates/paw-mcp/README.md) describes it.
