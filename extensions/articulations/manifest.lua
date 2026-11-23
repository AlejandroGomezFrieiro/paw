-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "articulations",
  version = "0.1.0",
  description = "Each note's articulation as its MIDI 2.0 attribute, named per instrument by maps, sent as keyswitches to MIDI 1.0 instruments",
  requires = { paw = "^1.0" },
  -- The score shows the articulations and writes them, when notation is there.
  optional = { notation = "*" },
  needs = {},
}
