-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "sampler",
  version = "0.1.0",
  description = "paw's own sample player, a CLAP plugin for SFZ and Decent Sampler instruments",
  requires = { paw = "^1.0" },
  needs = { "native" },
}
