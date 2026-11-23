-- The check of the time axis: no code of the runtime or of an extension
-- turns beats into columns, or columns into beats, by its own `* zoom` or
-- `/ zoom`. The time axis (runtime/lua/paw/axis.tl) does that, with one
-- rule for each row, the ruler, the playhead and the mouse, so that all
-- of them agree on the column of a beat. It reads text only, so plain
-- LuaJIT runs it (the flake's `zoomlint` check), and so does paw (the
-- suite's tests/zoomlint.lua).
--
--   luajit tools/zoomlint.lua          check the code against the allow-list
--   luajit tools/zoomlint.lua counts   print the uses of today, in the format of the allow-list
--
-- tools/zoomlint-allowed.txt holds one line `<file> <count> <reason>` for
-- each file that keeps such a use with a reason (pixels, not cells; the
-- spacing of a score). A count that goes up fails. A count that goes down
-- also fails, until its line is made smaller, so the list only gets
-- shorter. Tests are not checked: a test finds a cell as it likes.
local M = {}

M.ALLOWED = "tools/zoomlint-allowed.txt"
M.AXIS = "runtime/lua/paw/axis.tl"
-- Code that is not paw's own: the vendored compiler and library.
M.SKIP = { "runtime/lua/tl.lua", "runtime/lua/compat53/" }

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function lines_of(cmd)
  local out = {}
  local pipe = assert(io.popen(cmd))
  for line in pipe:lines() do
    out[#out + 1] = line
  end
  pipe:close()
  return out
end

--- The files to check, relative to `root`, in order.
function M.files(root)
  local out = {}
  local found = lines_of(
    "cd '"
      .. root
      .. "' && find runtime/lua extensions -type f \\( -name '*.lua' -o -name '*.tl' \\) 2>/dev/null | sort"
  )
  for _, path in ipairs(found) do
    local skip = path == M.AXIS
      or path:match("^extensions/[^/]+/tests[^/]*%.lua$")
      or path:match("^extensions/[^/]+/tests/")
    for _, prefix in ipairs(M.SKIP) do
      skip = skip or path:sub(1, #prefix) == prefix
    end
    if not skip then out[#out + 1] = path end
  end
  return out
end

--- The uses of `* zoom` and `/ zoom` in a text: the line of each. A name
--- counts when its last part is `zoom` or ends in `_zoom` (`paw.opt.zoom`,
--- `g.zoom`, `note_zoom`); `vzoom` (the rows of a track) does not. What
--- follows `--` on a line is a comment, and is left out.
function M.uses(text)
  local out = {}
  local n = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local code = line:gsub("%-%-.*$", "")
    for name in code:gmatch("[*/]%s*%(?%s*([%w_%.]+)") do
      if name == "zoom" or name:match("[%._]zoom$") then out[#out + 1] = n end
    end
  end
  return out
end

--- The allow-list: `{ [file] = { count, line } }`.
function M.read_allowed(path)
  local out = {}
  local n = 0
  for line in ((read(path) or "") .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local file, count = line:match("^([^#%s]%S*)%s+(%d+)")
    if file then out[file] = { tonumber(count), n } end
  end
  return out
end

--- The problems under `root`: each a line of text. Empty when all is well.
function M.check(root)
  local allowed = M.read_allowed(root .. "/" .. M.ALLOWED)
  local problems = {}
  local seen = {}
  for _, path in ipairs(M.files(root)) do
    local uses = M.uses(read(root .. "/" .. path) or "")
    local allow = allowed[path]
    seen[path] = true
    local limit = allow and allow[1] or 0
    if #uses > limit then
      problems[#problems + 1] = string.format(
        "%s:%d: %d use%s of `* zoom` or `/ zoom`, %d allowed. Put the beat on the time axis"
          .. " (paw.axis: x_of, beat_of, range, cells, beats) so that it takes the column that the"
          .. " ruler gives it",
        path,
        uses[1],
        #uses,
        #uses == 1 and "" or "s",
        limit
      )
    elseif allow and #uses < limit then
      problems[#problems + 1] =
        string.format("%s:%d: %d now: make the line `%s %d ...`", M.ALLOWED, allow[2], #uses, path, #uses)
    end
  end
  for path, allow in pairs(allowed) do
    if not seen[path] then
      problems[#problems + 1] = string.format("%s:%d: %s is gone: remove the line", M.ALLOWED, allow[2], path)
    end
  end
  table.sort(problems)
  return problems
end

--- The uses of today, as lines of the allow-list (with no reason).
function M.counts(root)
  local out = {}
  for _, path in ipairs(M.files(root)) do
    local uses = M.uses(read(root .. "/" .. path) or "")
    if #uses > 0 then out[#out + 1] = path .. " " .. #uses end
  end
  return out
end

-- Run as a script (`luajit tools/zoomlint.lua`), not loaded by a test.
if arg and arg[0] and arg[0]:match("zoomlint%.lua$") and not paw then
  if arg[1] == "counts" then
    print(table.concat(M.counts("."), "\n"))
    os.exit(0)
  end
  local problems = M.check(".")
  if #problems > 0 then
    io.stderr:write(table.concat(problems, "\n") .. "\n")
    os.exit(1)
  end
  print("zoomlint: every beat goes to a column through the time axis")
end

return M
