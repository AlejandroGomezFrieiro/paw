-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "musicops",
  version = "0.1.0",
  description = "Musical operators: humanize, strum, arpeggiate, scales",
  requires = { paw = "^1.0" },
  -- The operators work in the utau view too, when utau is there.
  optional = { utau = "*" },
  needs = {},
}
