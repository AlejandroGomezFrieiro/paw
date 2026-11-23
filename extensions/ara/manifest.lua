-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "ara",
  version = "0.1.0",
  description = "ARA plugins (Melodyne-style editors of whole clips) on audio parts",
  requires = { paw = "^1.0" },
  needs = { "native" },
}
