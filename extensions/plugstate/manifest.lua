-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
-- It waits for its first use: its modules are the slowest to load after notation's.
return {
  name = "plugstate",
  version = "0.1.0",
  description = "Load a plugin's models, impulse responses and instruments without its window, and keep snapshots of its state",
  requires = { paw = "^1.0" },
  needs = { "ffi", "processes", "network" },
  cmd = {
    { "plugstate.load", desc = "Load a file into the plugin (an amp model, an impulse response)" },
    { "plugstate.snapshot", desc = "Keep the plugin's whole state as a snapshot" },
    "plugstate.*",
  },
  keys = {
    { "]m", view = "inspector", desc = "Load the next file of the folder (model, impulse response)" },
    { "[m", view = "inspector", desc = "Load the previous file of the folder" },
    {
      "<localleader>m",
      view = "inspector",
      desc = "Choose a file for the plugin (model, impulse response), each heard",
    },
    { "<localleader>s", view = "inspector", desc = "Keep the plugin's whole state as a snapshot" },
    { "<localleader>v", view = "inspector", desc = "Bring back a snapshot, each heard" },
    { "]v", view = "inspector", desc = "Bring back the next snapshot" },
    { "[v", view = "inspector", desc = "Bring back the previous snapshot" },
    { "<localleader>t", view = "inspector", desc = "Search TONE3000's library for a model or an impulse response" },
  },
}
