-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
-- It waits for its first use.
return {
  name = "templates",
  version = "0.1.0",
  description = "A track, a group of tracks or a chain of devices saved under a name, to make again in any project",
  requires = { paw = "^1.0" },
  needs = {},
  cmd = {
    { "templates", desc = "List the templates" },
    { "template.load", desc = "Make a template again: a track or group below the cursor track, a chain on it" },
    { "template.save", desc = "Save the track as a template, or the group with every track in it" },
    "template.*",
  },
  keys = {
    { "<localleader>Tl", view = "arrange", desc = "Make a track, group or chain from a template" },
    { "<localleader>Tf", view = "arrange", desc = "Save the track's devices as a chain" },
    { "<localleader>Ts", view = "arrange", desc = "Save the track or group as a template" },
  },
}
