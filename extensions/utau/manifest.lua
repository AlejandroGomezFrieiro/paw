-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "utau",
  version = "0.1.0",
  description = "Singing synthesis: vocal parts, a vocal editor, the device that plays the singing and the engine that sings",
  requires = { paw = "^1.0" },
  needs = { "ffi", "processes", "native" },
}
