-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "doctor",
  version = "0.1.0",
  description = "A guided check of the real hardware (audio, MIDI, recording, plugins), with a written report",
  requires = { paw = "^1.0" },
  needs = { "ffi" },
}
