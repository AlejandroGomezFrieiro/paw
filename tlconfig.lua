-- Teal's configuration for the source tree (`cyan check`, `tl check`, editors and
-- `paw.lang.check`): the `paw` global comes from runtime/types/paw.d.tl, which
-- tools/apidoc.lua makes, and the runtime's own modules are found by name.
return {
  include_dir = { "runtime/types", "runtime/lua" },
  global_env_def = "paw",
  gen_target = "5.1",
  gen_compat = "off",
}
