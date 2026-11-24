-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "vinput",
  version = "0.1.0",
  description = "Virtual inputs: a guitar heard as MIDI through gdi2m, as a port any part takes",
  requires = { paw = "^1.0" },
  needs = { "processes" },
}
