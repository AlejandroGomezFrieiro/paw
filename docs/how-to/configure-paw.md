# How to configure paw

<!-- tags: configuration init.lua -->

You can change paw with your own `init.lua`. In the file, you can set
options and colors, add commands and keys, and run code on events.

1. Make the file `~/.config/paw/init.lua`.
2. Add the lines that you need from the sections below.
3. Start paw. If paw is already open, type `:reload`.

`:reload` runs the Lua runtime, your configuration and your extensions
again, and it does not change the project or stop the audio.

## Set options

```lua
paw.opt.zoom = 4
paw.opt.part_height = 2      -- rows for each part in the arrange view
paw.opt.header_width = 28     -- columns of the part headers
```

Every option is listed in [Options](../reference/options.md). If you want
to try an option before you write it, type `:set zoom=4` in paw.

## Change a color

```lua
paw.ui.hl("Playhead", { bg = "#ff5555" })
```

You can change each highlight group, and the groups and their colors are
in `runtime/lua/paw/theme.tl`. To change the color of one part, type
`:part.color teal` on the part.

## Add a command and a key

```lua
paw.command("part.synth", function(ctx)
  local part = paw.add_part({ name = ctx.args[1] or "Synth" })
  part:add_device("synth", { cutoff = tonumber(ctx.args.cutoff) or 1800 })
  paw.cursor.set_part(part)
end, { desc = "Add a synth part: `part.synth Lead cutoff=900`" })

paw.keymap.set("<leader>tn", "part.synth", { desc = "Add a synth part" })
```

With these lines, `:part.synth Lead cutoff=900` adds a part, and
`<Space>tn` does the same with the default values.

If you map a key in one view, do not use a key of the global leader for
it. To find the keys that break the rule, type
`:lua =paw.keyrule.broken()`, and read [The key rule](../reference/key-rule.md).

## Use a different leader key

The leader key is the space bar, and it starts the keys that work in every
view. For example, `<Space>mm` opens the mixer, and `<Space><Space>` plays
and stops. If you want the comma as the leader, add the following line to
`init.lua`:

```lua
paw.opt.leader = ","
```

Each key on the leader then moves to the comma, so `,m` opens the mixer,
and `,<Space>` plays. `:set leader=,` does the same for the current
session only.

## Run code on an event

```lua
paw.on("project.saved", function(event) paw.notify("saved to " .. event.path) end)
```

## Choose the audio devices

```lua
paw.audio.use({ output = "UR22mkII Stereo", input = "UR22mkII", buffer = 128 })
```

The details are in [How to choose the audio devices](choose-audio-devices.md).

## Start with a layout of windows

```lua
paw.layouts.edit = {
  { name = "Edit", layout = { dir = "h", "arrange", "roll" } },
  { name = "Mix", layout = "mixer" },
}
paw.opt.layout = "edit"
```

The details are in [Windows, buffers and tabs](../reference/windows.md#layouts).

## Examples

- [config](../../config) has a fuller configuration and three small
  extensions, and it loads the bundled extensions. To try it, start
  `paw --config config` in the source tree.
- [extensions/utau](../../extensions/utau) is a larger extension, with song
  synthesis by the engines of OpenUtau, a vocal editor and a lyric sheet.

## See also

- [How to change the status line](change-the-status-line.md).
- [Files that paw keeps](../reference/state-files.md): the directory of the configuration, Lua devices and extensions.
- [How to write a device in Lua](write-a-device-in-lua.md): devices in `~/.config/paw/devices/`.
