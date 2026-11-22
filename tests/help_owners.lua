-- `:help` on an extension's commands and keys lands in that extension's
-- pages, wherever else the manual names them, on the place it is described.
-- The walk loads every bundled extension, so it runs in a kernel of its own
-- (tests/tools/help_walk.lua) and leaves this one as it was.
local T = ...
local test, eq = T.test, T.eq

test("help: every extension command and key finds where its own extension's pages describe it", function()
  local bin = (os.getenv("PAW_TEST_BIN") or "target/release") .. "/paw"
  local p =
    io.popen("'" .. bin .. "' --clean --no-plugins --no-listen --audio null -l tests/tools/help_walk.lua 2>/dev/null")
  local out = p:read("*a")
  p:close()
  local walked = tonumber(out:match("WALKED (%d+)"))
  eq(walked and walked > 200, true, "commands and keys walked: " .. tostring(walked))
  local wrong, unnamed = {}, {}
  for line in out:gmatch("[^\n]+") do
    if line:match("^WRONG ") then wrong[#wrong + 1] = line:sub(7) end
    if line:match("^UNNAMED ") then unnamed[#unnamed + 1] = line:sub(9) end
  end
  eq(table.concat(wrong, "\n"), "", "each lands in its extension's pages, a key the core maps in the core's")
  eq(table.concat(unnamed, " "), "", "each is named in its extension's pages")
end)
