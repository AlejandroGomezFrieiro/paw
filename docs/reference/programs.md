# The programs and their options

<!-- tags: programs command-line-options -->

paw has three programs, which are `paw` (the kernel and the terminal interface),
`paw-gui` (the graphical window) and `paw-mcp` (a Model Context Protocol
server for AI assistants), and `--help` on each program prints its options.
The package also has `chain-lsp`, the language server of the chain
language, which needs nothing else of paw.

## paw

| Use | Effect |
| --- | --- |
| `paw [options] [project]` | Opens the terminal interface. A sound file as the project starts a new project with it. |
| `paw -l <script.lua> [args...]` | Runs a Lua script without a UI, then stops. |
| `paw --headless [project]` | Runs without a UI until it gets a quit command. |
| `paw ctl [--json] <method> [params...]` | Calls a method of an instance that runs, through its socket. |
| `paw attach` | Shows the terminal interface of an instance that runs, in this terminal. |
| `paw doctor [options]` | Checks the audio, MIDI, plugins and environment, and prints a report. |
| `paw clip cat <file.midi2>` | Prints a MIDI 2.0 clip file as text, one note to a line. Git uses it to show the changes of project folders. |
| `paw chain schema [options]` | Prints paw's schema of the [chain language](chain-language.md) as JSON: each kind of device that paw has after it starts, with your plugins and the Lua devices of your extensions, and each kind of split and modulator. `--clean` leaves out your extensions, and `--no-plugins` leaves out your plugins. The [schema format](chain-schema.md) gives each field. |

| Option | Effect |
| --- | --- |
| `-e <lua>` | Runs Lua code after the start. You can give it more than once. |
| `--keys <keys>` | Types keys after the start, for example `'jj<Space>'`. |
| `--clean` | Does not load your configuration and extensions. |
| `--config <dir>` | The configuration directory. The default is `~/.config/paw`. |
| `--runtime <dir>` | Loads the Lua runtime from this directory, not the copy in the program. |
| `--audio <name>` | The audio backend: `auto`, `null`, `step`, `pipewire`, `alsa` or `jack`. paw in a BrowserPod pod has `page` instead of the last three (see [paw in a BrowserPod pod](../../web/browserpod/README.md)). `step` is the null backend for the tests: paw plays the sound only as the clock moves, so a test knows how much sound played. Use it with `--clock manual`. `paw.api.engine_get().backend` then says `step`. |
| `--rate <hz>` | The sample rate. |
| `--buffer <n>` | The frames for each audio callback. |
| `--output <name>` | The output device, by its name or a part of it (see `:audio`). |
| `--input <name>` | The input device, by its name or a part of it. |
| `--no-input` | Does not open the input of the audio device. |
| `--clock <clock>` | The clock that timers and delays wait for. `wall` (the default) is the time on the wall. With `manual`, the time moves only when a script waits with `paw.wait`, so a test steps the timers in order. The tests use it. |
| `--listen <path>` | The path of the control socket. The default is `$XDG_RUNTIME_DIR/paw.sock`. |
| `--no-listen` | Does not open a control socket. paw stops with an error if you also give `--listen`. The graphical window always gives `--listen`, so `paw-gui --no-listen` stops at once with this error. |
| `--listen-tcp <address>` | Also accepts connections from the network, on `host:port`, in TLS. `127.0.0.1:7700` accepts only this computer, `0.0.0.0:7700` any computer that knows the token. |
| `--no-tls` | Accepts network connections without encryption. |
| `--token-file <path>` | The file of the token for network connections. The default is `~/.local/state/paw/token`. paw makes it if it does not exist. |
| `--no-plugins` | Does not look for CLAP, LV2 and VST3 plugins. |
| `--plugins-in-process` | Loads plugins into this process, not each into a process of its own. |
| `--plugins-offline` | Opens the project with every plugin offline (see `:plugins.online`). |
| `--startuptime <file>` | Writes the time of each step of the start to the file, in the format of Neovim's `--startuptime`. Each module that paw loads, each extension and your `init.lua` gets a line with the clock, its whole time and its own time without the modules that it loads. The last lines are the project and the first frame. paw adds the lines to the end of the file. `paw-gui` passes the option to its kernel, and there the file ends when the kernel is ready. |
| `-h`, `--help` | Shows the help. |
| `-V`, `--version` | Shows the version. |

After `-l <script.lua>`, paw gives all the other arguments to the script,
including those that start with `-`. A wrong option makes paw print the usage
and stop with the exit code 2.

### Options of `paw ctl` and `paw attach`

`paw ctl` and `paw attach` connect to the socket of the instance on this
computer, unless an option names a different one.

| Option | Effect |
| --- | --- |
| `--socket <path>` | A different socket. |
| `--connect <host:port>` | An instance that listens on the network. |
| `--token <token>`, `--token-file <path>` | The token of that instance. `$PAW_TOKEN` also gives it. |
| `--accept-certificate` | Accepts the certificate that the instance shows, though a different one is remembered for it. |
| `--no-tls` | Connects without encryption, to an instance started with `--no-tls`. |
| `--listen-audio` | (`attach` only) Plays the sound of the instance on this computer, at about 1 Mbit/s. |
| `--listen-audio-to <file.wav>` | (`attach` only) Writes the sound of the instance to a file. |

In an attached terminal, `:detach` leaves and the instance continues to run,
`:upload <file>` sends a sound file from this computer into the project, and
`:listen` starts and stops the sound on this computer.

### Options of `paw doctor`

| Option | Effect |
| --- | --- |
| `--seconds <n>` | The length of the dropout runs. |
| `--plugin <name>` | A plugin to load and play. You can give it more than one time. |
| `--only <ids>` | Only these checks, separated by commas. |

`paw doctor` also takes the audio options of `paw` (`--audio`, `--output` and the others).

### Examples of `paw ctl`

```sh
paw ctl eval 'return paw.transport.position'
paw ctl cmd transport.toggle
paw ctl --json eval 'return paw.project.tempo'
paw ctl track_add '{"name": "Bass"}'
paw ctl --connect studio:7700 --token-file studio.token cmd transport.toggle
```

## paw-gui

| Use | Effect |
| --- | --- |
| `paw-gui [kernel options] [project]` | Starts a kernel (`paw --headless`) and shows it. The kernel options go to `paw`. |
| `paw-gui --socket <path>` | Shows a kernel that runs already. |
| `paw-gui --connect <host:port> --token-file <path>` | Shows a kernel on a different computer, started with `--listen-tcp`. `--token` and `$PAW_TOKEN` also give the token. |

| Option | Effect |
| --- | --- |
| `--accept-certificate` | Accepts the certificate that the kernel shows, though a different one is remembered for it. |
| `--no-tls` | Connects without encryption, to a kernel started with `--no-tls`. |
| `--listen-audio` | Plays the sound of the kernel on this computer. The engine menu also has this. |
| `--renderer gpu\|software` | Draws with OpenGL on the graphics card (the default), or with Mesa on the processor (llvmpipe). `PAW_GUI_RENDERER` also sets it. |

## paw-mcp

`paw-mcp` is a Model Context Protocol server that talks over stdin and stdout.

| Use | Effect |
| --- | --- |
| `paw-mcp [options]` | Attaches to a kernel that runs. |
| `paw-mcp --spawn [project] [-- kernel options...]` | Starts a headless kernel of its own, and stops it at the end. The options after `--` go to the kernel, for example `--audio null`. |

| Option | Effect |
| --- | --- |
| `--socket <path>` | The control socket of the kernel. The default is `$PAW_SOCKET`, else `$XDG_RUNTIME_DIR/paw.sock`. |
| `--paw <path>` | The `paw` program for `--spawn`. The default is `$PAW_BIN`, the `paw` next to this program, or `paw` on the `PATH`. |
| `--root <dir>` | Where relative paths start, and where files can be written. The default is the current directory. |
| `--allow-eval` | Gives the tools `lua`, `run_command` and `send_keys`, which run any code in paw. |
| `--allow-any-path` | Lets save and render write outside `--root`. |
| `--timeout <secs>` | The time to wait for the kernel for each call. The default is 600. |

## chain-lsp

`chain-lsp` is the language server of the [chain language](chain-language.md). It talks LSP over stdin and stdout, and the [README of the crate](../../crates/chain-lsp/README.md) lists what it does.

| Use | Effect |
| --- | --- |
| `chain-lsp [options]` | Serves one editor, from its `initialize` to its `exit`. |

| Option | Effect |
| --- | --- |
| `--schema <file>` | The [schema](chain-schema.md) of the host, as a JSON file. |
| `--schema-command <program> [args...]` | A program that prints the schema of the host, for example `paw chain schema`. It takes the rest of the command line. |
| `--stdio` | Does nothing, because the server always talks over stdin and stdout. Some editors give it. |

The `initializationOptions` of the editor come before these options. Without a schema, the server checks only the grammar.

## Environment variables

| Variable | Effect |
| --- | --- |
| `PAW_HOME` | The source tree, or the `share/paw` directory of the package. paw finds the extensions, the examples and the manual there. The package sets it. |
| `PAW_TOKEN` | The token for a network connection. |
| `PAW_SOCKET` | The control socket for `paw-mcp`. |
| `PAW_BIN` | The `paw` program for `paw-mcp --spawn`. |
| `PAW_GUI_RENDERER` | `gpu` or `software`, as `--renderer`. |
| `PAW_TTIMEOUTLEN` | How long the terminal waits after an Escape key for the rest of a key, in milliseconds. The default is 15. A slow link can send the Escape first and the arrow after it. `0` turns the wait off. |
| `XDG_RUNTIME_DIR` | The directory of the default control socket, `paw.sock`. |
| `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME` | The base directories of [the files that paw keeps](state-files.md). |
