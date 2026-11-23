-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "projdiff",
  version = "0.1.0",
  description = "What changed between two versions of a project, and three-way merges of projects for git",
  requires = { paw = "^1.0" },
  needs = { "processes" },
}
