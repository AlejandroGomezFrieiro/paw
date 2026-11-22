-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "notation",
  version = "0.1.0",
  description = "A MIDI clip as staff notation, read and edited in the terminal and in a window",
  requires = { paw = "^1.0" },
  needs = { "processes" },
}
