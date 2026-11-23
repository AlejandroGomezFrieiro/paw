-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "midilsp",
  version = "0.1.0",
  description = "MIDI LSP, the language server for music: voice-leading diagnostics with fixes, the chords it hears, suggestions",
  requires = { paw = "^1.0" },
  needs = { "processes" },
}
