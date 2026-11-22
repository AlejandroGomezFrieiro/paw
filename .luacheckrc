-- luacheck's configuration for the Lua of the source tree (`luacheck .` in
-- the dev shell). Teal files are checked by tools/tlcheck.sh instead.
std = "luajit"
globals = { "paw" }
max_line_length = false
exclude_files = {
  "target/", ".claude/",
  -- Copies of programs from outside paw, and generated files.
  "runtime/lua/tl.lua", "runtime/lua/compat53/", "runtime/types/paw.lua",
}
ignore = {
  "212", -- an unused argument: a callback takes what its contract gives
  "213", -- an unused loop variable: `for i, x in ipairs(t)` reads well
  "4..", -- shadowing: a style, which the suite's Teal check counts for .tl
  "542", -- an empty if branch: it holds a comment that says why
  "581", -- `not (x > y)`: it reads as the rule it checks
  "613", -- trailing spaces in a string: the text means them
}
-- paw sends `print` to the message line when a screen is attached.
files["runtime/lua/paw/init.lua"] = { globals = { "print" } }
-- A test sets a value again to check the next step; the last one it sets
-- need not be read.
files["tests/**/*.lua"] = { ignore = { "311" } }
files["extensions/*/tests*.lua"] = { ignore = { "311" } }
files["crates/*/tests/*.lua"] = { ignore = { "311" } }
files["extensions/interop/tools/reaper-*.lua"] = { std = "lua53", read_globals = { "reaper" } }
files["bench/daws/ardour_init.lua"] = {
  read_globals = { "ardour", "ARDOUR", "Session", "Temporal", "Editor", "Editing", "C" },
  globals = { "factory" },
}
-- The singer's name comes from the script that runs it.
files["extensions/utau/images/make/scene.lua"] = { read_globals = { "UTAU_SINGER" } }
