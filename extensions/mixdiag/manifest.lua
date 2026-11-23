-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "mixdiag",
  version = "0.1.0",
  description = "The mix measured (LUFS, true peak, phase) and reported as findings to jump to",
  requires = { paw = "^1.0" },
  needs = {},
}
