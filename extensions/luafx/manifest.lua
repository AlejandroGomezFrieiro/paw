-- What the extension is, for `:extensions` and `paw.ext` (see docs/reference/extensions.md).
return {
  name = "luafx",
  version = "0.1.0",
  description = "Devices written in Lua, to use and to start your own from",
  requires = { paw = "^1.0" },
  needs = { "ffi" },
}
