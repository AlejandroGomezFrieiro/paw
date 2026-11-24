# How to find out what went wrong

You can read the log of paw after a crash, an error or a strange result,
and you can make the log say more. The log is the
file `paw.log` in `~/.local/state/paw`, and paw keeps the logs of the
last five runs. [Files that paw keeps](../reference/state-files.md)
lists them.

## Read the log

- If paw still runs, type `:log`. The log of this run opens in the
  window, with the cursor on its last line.
- If paw stopped or crashed, start it again and type `:log!`. The log of
  the run before opens. After a crash, the terminal also says where the
  log is.
- To read the logs of older runs, open `~/.local/state/paw/paw.log.2` to
  `paw.log.4` in any text editor.

Each line has the time in UTC, the level, the target and the message:

```text
2026-11-24 18:05:12.345 INFO  undo: step 14: Delete notes (keys dd)
2026-11-24 18:05:13.002 WARN  audio: xruns: 3 (+2)
```

## Find the cause

1. Search for the errors with `/ERROR`, and press `n` for the next one.
2. Read the lines before the error. The `undo` lines and the command
   lines that start with `:` show what you did before it.
3. If the error has a block of lines called the flight recorder before
   it, read that block too. It has the detail that the log leaves out in
   a normal run, such as each key that ran a command.
4. If a plugin is the cause, its lines have the target `plugin` and the
   name of the plugin. See
   [How to deal with a plugin that crashes or hangs](deal-with-a-plugin-that-crashes.md).
5. If the sound had gaps, the lines with the target `audio` count the
   xruns and the late plugin blocks. See
   [How to fix crackles and dropouts](fix-crackles-and-dropouts.md).

## Make the log say more

- To log more for one run, start paw with the variable `PAW_LOG`:

  ```sh
  PAW_LOG=debug paw song
  ```

- To keep more detail for one target in each run, set the option in your
  configuration:

  ```lua
  paw.opt.loglevel = "info,plugin=debug"
  ```

- To write the flight recorder into the log now, without an error, type
  `:log dump`. Do this right after you see the problem, before the
  detail goes out of memory.

The option and the variable are in [Options](../reference/options.md#the-log).

## Send the log with a report

1. Copy `paw.log` of the run that had the problem.
2. Read it before you send it. paw writes no environment variables to
   the log, and it writes your home folder as `~`, but the names of your
   projects, parts and plugins are in it.
