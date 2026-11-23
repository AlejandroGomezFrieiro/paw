-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "chainlsp",
  version = "0.1.0",
  description = "chain-lsp, the language server of the chain language: diagnostics of the chain files of the project",
  requires = { paw = "^1.0" },
  needs = { "processes" },
}
