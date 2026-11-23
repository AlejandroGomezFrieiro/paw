# How to drive paw from an agent

<!-- tags: scripting-driving-paw-from-an-agent -->

You can let a program edit a project in paw, such as an agent that writes
code, an assistant or a script of your own. The steps assume that paw runs
on the same machine.

## With a shell

1. Start paw, or start `paw --headless` for an instance with no terminal.
2. To read the state, call `project_get`, `part_list` and `clip_notes` with
   `paw ctl --json`:

   ```sh
   paw ctl --json eval 'return paw.api.project_get()'
   paw ctl --json eval 'return paw.query("clip[name~=riff] > note[pitch>=c5]")'
   ```

   Notes have ids, and an id stays with its note through every edit.
3. To change the project, send one `eval` for each step of the work, and
   each `eval` is one undo step:
   - To give a step a name, call `paw.api.undo_label("agent: verse drums")`
     in the `eval`.
   - To find sections, use `paw.markers`. To move notes along the key, use
     `paw.harmony.key()` and `paw.harmony.step(key, pitch, n)`.
4. To check the result without a person who listens, call `paw.render` and
   `paw.api.measure`. They give the loudness, the true peak, the clipped
   samples and the level of each part.

`--json` gives one line for each answer, and if the call fails, the exit
status is 1. The details are in [Scripts and `paw ctl`](../reference/ctl.md).

## Without a shell

If the assistant is a chat application with no shell, use `paw-mcp`. It
is a Model Context Protocol server that offers the same work as typed
tools. It has edits of single notes by id, markers, render options,
`diagnose`, and `batch` for several changes as one named undo step. The
details are in [crates/paw-mcp](../../crates/paw-mcp/README.md).

## Where the agent finds the reference

- `:help`, and `paw.help` in Lua.
- [The Lua API](../reference/api.md): the comment above each function.
- The resources of `paw-mcp`: `paw://reference/api` and
  `paw://reference/lua/<module>`.
