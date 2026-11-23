-- The Lua API's reference and the Teal declarations, made from the source:
-- the `---` comment over each public function of the `paw` modules, the
-- `//` comment over each `paw.api` function in crates/paw-core/src/api/,
-- the serde structs of the kernel's events and of the window's props, and
-- the modules of the runtime in Teal. Run from the source tree:
--
--   paw --clean --no-plugins -l tools/apidoc.lua          write the files
--   paw --clean --no-plugins -l tools/apidoc.lua check    say what is out of date or undocumented
--
-- It writes docs/reference/api.md (the reference that `:help` shows),
-- runtime/types/paw.lua (a LuaLS meta file), the Teal declarations in
-- runtime/types, the kernel's event descriptors, the rows of the runtime's
-- events in docs/reference/events.md, and lowers the counts of
-- runtime/types/any-allowed.txt. `nix flake check` and tests/apidoc.lua
-- check that all are up to date and that every public function says what
-- it does.
--
-- The generator is Teal, in tools/apidoc/: readers (read/) fill one model
-- (model.tl), and one writer (write/) makes each file. This file stays Lua
-- because `paw -l` runs a Lua file: it finds the Teal modules, which paw
-- compiles as it loads them (paw/lang.tl).
--
-- `loadfile("tools/apidoc.lua")("module")` gives the generator to a test:
-- `model()` and the readers' functions.
package.path = "tools/?.lua;" .. package.path
local run = require("apidoc.run")

local mode = ...
if mode == "module" then
  local rust = require("apidoc.read.rust")
  return {
    model = run.model,
    undocumented = run.undocumented,
    -- The functions of `paw.api` as the source shows them, by name.
    kernel_functions = rust.kernel_functions,
  }
end
run.main(mode)
