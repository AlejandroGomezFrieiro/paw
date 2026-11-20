-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "interop",
  version = "0.1.0",
  description = "Opening and writing the projects of other programs: REAPER (.rpp) and DAWproject (Bitwig Studio, Studio One, Cubase)",
  requires = { paw = "^1.0" },
}
