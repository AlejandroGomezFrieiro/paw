# templates

A track, a group of tracks or a chain of devices, saved under a name, to
make again in any project. For example: a vocal track with its chain and
levels, a string section with all its instruments, a mastering chain.

```lua
paw.ext.load("/path/to/paw/extensions/templates")   -- or link it into ~/.config/paw/extensions
```

![The keys track saved with \Ts as a template, then made again below another track with \Tl and a part of its name, and its devices shown with ,d](images/tui-templates.gif)

## Try it

1. Type `:ext.load templates`.
2. Put the cursor on a track with devices, and press `\Ts`. Type `Keys`
   and press Enter. The message says that the template is saved.
3. Move the cursor to another track, and press `\Tl`.
4. Type `ke` and press Enter. A copy of the track appears below the
   cursor track.
5. Press `<Space>dd`. The devices of the new track are the devices of the saved
   track.

## How to

### How to save a track or a group

1. Put the cursor on the track, or on the track of a group.
2. Press `\Ts`, type a name and press Enter.

If a template has the same name, paw asks first. To keep the clips of the
track too, call `templates.save_track(track, name, { clips = true })`.

### How to save the devices of a track as a chain

1. Put the cursor on the track.
2. Press `\Tf`, type a name and press Enter.

### How to make a template again

1. Put the cursor on a track.
2. Press `\Tl`. Type a part of the name, or choose from the list.

A track or a group appears below the cursor track. A chain goes at the end
of the devices of the cursor track.

### In the graphical window

- Choose `Track` → "From a template…".
- In the menu of a track, choose "Save as a template…", "Save its devices
  as a chain…" or "Add devices from a template…".

## Reference

| Keys | Command | Effect |
| --- | --- | --- |
| `\Ts` | `template.save [name]` | saves the cursor track. On a group, saves the group with all its tracks |
| `\Tf` | `template.fx [name]` | saves the devices of the track as a chain |
| `\Tl` | `template.load [name]` | makes a template again: a track or a group below the cursor track, a chain at the end of the devices of the cursor track. A part of the name is enough. Without a name, you choose from a list |
| | `template.delete [name]` | deletes a template |
| | `templates` | lists the templates |

<!-- tags: :templates -->

A name that a file cannot hold (`Bass/Sub`) becomes a name that it can
hold (`Bass_Sub`), and the message tells you.

### What a template holds

| Kind | What it holds |
| --- | --- |
| a track | its name, level, pan, color, input, devices with their parameters and plugin state, automation lanes, and what extensions keep with it (a drum map). Its clips only when asked |
| a group | the track of the group and every track in it, groups in it too, each as above. When paw makes the group again, the members play into the new group |
| a chain | the devices of a track, in order, with their parameters and plugin state |

A template does not hold the track that its track played into, or the
tracks that it sent to. Those belong to the project that it came from.

Templates are JSON files in
`~/.local/share/paw/templates/<kind>/<name>.json`, in the shape that
`Track:snapshot()` gives. `paw.opt.templates_dir` puts them in another
directory.

### Lua

```lua
local templates = require("templates")
templates.save_track(track, "Lead vocal")        -- devices with their settings, levels, automation
templates.save_fx(track, "Vocal chain")          -- the devices only
templates.save_group(group, "String section")    -- a group and every track in it
templates.load("Lead vocal")                     -- makes it again below the cursor track
```
