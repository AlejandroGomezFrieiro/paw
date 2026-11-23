-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
-- It waits for its first use, and a project with a drum track loads it.
return {
  name = "drums",
  version = "0.1.0",
  description = "Drum tracks in one step, and a grid of the kit's pieces by name",
  requires = { paw = "^1.0" },
  needs = {},
  cmd = {
    { "drums.track", desc = "Add a drum track with the built-in kit and a clip to program" },
    { "drums.map", desc = "Make the track a drum track, whatever plays it, with a drum map" },
    "drums.*",
  },
  keys = {
    { "<localleader>kn", view = "arrange", desc = "Add a drum track" },
    { "<localleader>km", view = "arrange", desc = "Choose the track's drum map" },
  },
  kind = "drums",
  view = "drums",
}
