-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "plugstate",
  version = "0.1.0",
  description = "Load a plugin's models, impulse responses and instruments without its window, and keep snapshots of its state",
  requires = { paw = "^1.0" },
  needs = { "ffi", "processes", "network" },
}
