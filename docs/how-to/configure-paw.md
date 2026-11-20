# How to configure paw

<!-- tags: configuration init.lua -->

This guide shows you how to change paw with your own `init.lua`. You can
set options and colors, add commands and keys, and run code on events.

1. Make the file `~/.config/paw/init.lua`.
2. Add the lines that you need from the sections below.
3. Start paw. If paw runs already, type `:reload`.

`:reload` runs the Lua runtime, your configuration and your extensions
again. It does not change the project and does not stop the audio.

## Set options

```lua
paw.opt.zoom = 4
paw.opt.track_height = 2      -- rows for each track in the arrange view
paw.opt.header_width = 28     -- columns of the track headers
```

For every option, see [Options](../reference/options.md). To try an option
before you write it, type `:set zoom=4` in paw.

## Change a color

```lua
paw.ui.hl("Playhead", { bg = "#ff5555" })
```

You can change each highlight group. The groups and their colors are in
`runtime/lua/paw/theme.tl`. To change the color of one track, type
`:track.color teal` on the track.

## Add a command and a key

```lua
paw.command("track.synth", function(ctx)
  local track = paw.add_track({ name = ctx.args[1] or "Synth" })
  track:add_device("synth", { cutoff = tonumber(ctx.args.cutoff) or 1800 })
  paw.cursor.set_track(track)
end, { desc = "Add a synth track: `track.synth Lead cutoff=900`" })

paw.keymap.set("<leader>s", "track.synth", { desc = "Add a synth track" })
```

Now `:track.synth Lead cutoff=900` adds a track, and `<Space>s` does the same
with the default values.

If you map a key in one view, do not use a key of the global leader for
it. To find the keys that break this rule, type
`:lua =paw.keyrule.broken()`. See [The key rule](../reference/key-rule.md).

## Use a different leader key

The leader key is the space bar. It starts the keys that work in every
view: `<Space>m` opens the mixer, and `<Space><Space>` plays and stops. To
use the comma as the leader, add this line to `init.lua`:

```lua
paw.opt.leader = ","
```

Each key on the leader moves to the comma: `,m` opens the mixer, and
`,<Space>` plays. `:set leader=,` does the same for this session.

## Run code on an event

```lua
paw.on("project.saved", function(event) paw.notify("saved to " .. event.path) end)
```

## Choose the audio devices

```lua
paw.audio.use({ output = "UR22mkII Stereo", input = "UR22mkII", buffer = 128 })
```

See [How to choose the audio devices](choose-audio-devices.md).

## Start with a layout of windows

```lua
paw.layouts.edit = {
  { name = "Edit", layout = { dir = "h", "arrange", "roll" } },
  { name = "Mix", layout = "mixer" },
}
paw.opt.layout = "edit"
```

See [Windows, buffers and tabs](../reference/windows.md#layouts).

## Examples

- [config](../../config) has a fuller configuration and two small extensions. It loads the bundled extensions.
  To try it, start `paw --config config` in the source tree.
- [extensions/utau](../../extensions/utau) is a larger extension: song
  synthesis with the engines of OpenUtau, a vocal editor and a lyric sheet.

## See also

- [How to change the status line](change-the-status-line.md).
- [Files that paw keeps](../reference/state-files.md): the directory of the configuration, Lua devices and extensions.
- [How to write a device in Lua](write-a-device-in-lua.md): devices in `~/.config/paw/devices/`.
