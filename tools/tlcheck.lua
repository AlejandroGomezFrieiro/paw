-- The strict check of every Teal file of the source tree: the runtime's
-- modules, runtime/types, the example configuration, the extensions and
-- tools/. It runs `paw.lang.check`, the compiler in the program, with the
-- source tree's tlconfig.lua. Every error and every warning (an unused
-- local, a shadowed name) is a problem. tools/tlcheck.sh, the test suite
-- (tests/teal.lua) and `nix flake check` run this one check.
--
--   paw --clean --no-plugins -l tools/tlcheck.lua     print each problem; exit 1 when there is one
--
-- It is Lua because `paw -l` runs a Lua file. `loadfile("tools/tlcheck.lua")("module")`
-- gives `files()`, `include()` and `problems()` to a test.
local M = {}

-- The lines that a shell command prints.
local function lines_of(command)
  local out = {}
  local pipe = assert(io.popen(command))
  for line in pipe:lines() do
    out[#out + 1] = line
  end
  pipe:close()
  return out
end

--- The Teal files of the source tree, sorted.
function M.files() return lines_of("find runtime config extensions tools -name '*.tl' | sort") end

--- The directories besides tlconfig.lua's where a module is found: each
--- extension's `lua/`, so that a module of an extension finds the
--- extension's other modules (their names start with the extension's, so
--- they do not collide).
function M.include() return lines_of("find extensions -mindepth 2 -maxdepth 2 -type d -name lua | sort") end

--- Each problem as `file:line:col: message`, in the order of the files.
function M.problems()
  local out = {}
  for _, e in ipairs(paw.lang.check(M.files(), { include = M.include() })) do
    out[#out + 1] = string.format("%s:%d:%d: %s", e.file, e.line, e.col, e.msg)
  end
  return out
end

if ... == "module" then return M end
local problems = M.problems()
for _, line in ipairs(problems) do
  print(line)
end
print(
  #problems == 0 and "tl check: no errors"
    or ("tl check: " .. #problems .. (#problems == 1 and " problem" or " problems"))
)
paw.api.quit(#problems == 0 and 0 or 1)
