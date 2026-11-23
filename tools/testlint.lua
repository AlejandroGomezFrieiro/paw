-- The check that refuses a new test that depends on time (a sleep, a read
-- of the clock or a speed check) or on the machine (a read of the home
-- folder or the user name, or a path in /home) in a test file. It reads
-- text only, so
-- plain LuaJIT runs it (the flake's `testlint` check), and so does paw (the
-- suite's tests/testlint.lua).
--
--   luajit tools/testlint.lua           check the tree against tests/timing-allowed.txt
--   luajit tools/testlint.lua counts    print the counts of today, in the format of that file
--
-- tests/timing-allowed.txt holds one line `<file> <pattern> <count>` for
-- each use that is there today. A count that goes up fails: rewrite the test
-- (docs/how-to/run-the-tests.md, "Write a test that does not depend on
-- time"). A count that goes down also fails, until its line is made
-- smaller, so the list only gets shorter. A read of the machine has no
-- allow-list: each one fails. It also checks the clocks of the product code:
-- only the files of `M.real_time` read the wall clock (`api.real_ms()`), and
-- a budget reader there does not read the schedule clock (`api.now()`).
-- The window (crates/paw-gui) is
-- paused: the check skips it until that work starts again.
local M = {}

-- What counts ---------------------------------------------------------------------

--- The patterns, by the name that the allow-list uses. `find` is a plain
--- string, `match` a Lua pattern. `lessons` patterns apply to the lessons of
--- the tutor only. `machine` patterns read the machine: no count of them
--- is allowed.
M.lua_patterns = {
  { name = "api.sleep(", find = "api.sleep(" },
  { name = "api.wait(", find = "api.wait(" },
  { name = "paw.wait(", find = "paw.wait(" },
  { name = "api.now()", find = "api.now()" },
  { name = "api.real_ms(", find = "api.real_ms(" },
  { name = "os.clock(", find = "os.clock(" },
  { name = "cpu_ms(", find = "cpu_ms(" },
  { name = "T.quick(", find = "T.quick(" },
  { name = ":meter(", find = ":meter(" },
  { name = "wait=N", match = "wait%s*=%s*%d", lessons = true },
  { name = 'os.getenv("HOME")', find = 'os.getenv("HOME")', machine = true },
  { name = 'os.getenv("USER")', find = 'os.getenv("USER")', machine = true },
  { name = 'os.getenv("LOGNAME")', find = 'os.getenv("LOGNAME")', machine = true },
  { name = "/etc/passwd", find = "/etc/passwd", machine = true },
  { name = "/home/", match = "[\"']/home/", machine = true },
}
M.rust_patterns = {
  { name = "thread::sleep", find = "thread::sleep" },
  { name = "Instant::now", find = "Instant::now" },
  { name = "cpu_percent", find = "cpu_percent" },
  { name = "quiet(Duration", match = "quiet%(.*Duration" },
  { name = 'var("HOME")', match = 'var_?o?s?%("HOME"%)', machine = true },
  { name = 'var("USER")', match = 'var_?o?s?%("USER"%)', machine = true },
  { name = 'var("LOGNAME")', match = 'var_?o?s?%("LOGNAME"%)', machine = true },
  { name = "home_dir(", find = "home_dir(", machine = true },
  { name = "/etc/passwd", find = "/etc/passwd", machine = true },
  { name = "/home/", find = '"/home/', machine = true },
}

--- The names of the `machine` patterns.
M.machine = {}
for _, p in ipairs(M.lua_patterns) do
  if p.machine then M.machine[p.name] = true end
end
for _, p in ipairs(M.rust_patterns) do
  if p.machine then M.machine[p.name] = true end
end

local LESSONS = "^extensions/tutor/lua/tutor/lessons/"

local function lines_of(cmd)
  local out = {}
  local pipe = assert(io.popen(cmd))
  for line in pipe:lines() do
    out[#out + 1] = line
  end
  pipe:close()
  return out
end

--- The files that the check reads, relative to `root`: the Lua tests (not
--- the runner, tests/suite.lua, whose waits are the helpers of all tests),
--- the lessons of the tutor, and the Rust tests: the files in a `tests`
--- folder and the `#[cfg(test)]` modules of the other files.
function M.files(root)
  local cd = "cd '" .. root .. "' 2>/dev/null && "
  local lua = lines_of(
    cd
      .. "{ find tests -maxdepth 1 -name '*.lua' ! -name suite.lua;"
      .. " find extensions -mindepth 2 -maxdepth 2 -name 'tests*.lua';"
      .. " find extensions/tutor/lua/tutor/lessons -name '*.lua'; } 2>/dev/null | sort"
  )
  local rust = lines_of(
    cd .. "find crates extensions -name '*.rs' ! -path '*/target/*' ! -path 'crates/paw-gui/*' 2>/dev/null | sort"
  )
  return lua, rust
end

local function count_line(counts, line, patterns, lessons)
  for _, p in ipairs(patterns) do
    if lessons or not p.lessons then
      local start, n = 1, 0
      while true do
        local at, stop
        if p.find then
          at, stop = line:find(p.find, start, true)
        else
          at, stop = line:find(p.match, start)
        end
        if not at then break end
        n, start = n + 1, stop + 1
      end
      if n > 0 then counts[p.name] = (counts[p.name] or 0) + n end
    end
  end
end

--- The uses of each pattern in the text of a Lua file. Comments do not
--- count.
function M.count_lua(text, lessons)
  local counts = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if not line:match("^%s*%-%-") then count_line(counts, line, M.lua_patterns, lessons) end
  end
  return counts
end

--- The uses of each pattern in the test code of a Rust file: the whole
--- file when it is in a `tests` folder, else the items marked
--- `#[cfg(test)]`, to the brace that closes each. Comments do not count.
function M.count_rust(text, whole)
  local counts = {}
  local inside, depth, opened = whole, 0, false
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if not inside and line:match("^%s*#%[cfg%(test%)%]") then
      inside, depth, opened = true, 0, false
    end
    if inside then
      if not line:match("^%s*//") then count_line(counts, line, M.rust_patterns, false) end
      if not whole then
        -- The item ends at the brace that closes its first brace, or at
        -- its `;` when it has no body (`mod tests;`, a `use`).
        local _, open = line:gsub("{", "")
        local _, close = line:gsub("}", "")
        depth = depth + open - close
        opened = opened or open > 0
        local bodiless = not opened and line:match(";%s*$")
        if (opened and depth <= 0) or bodiless then inside = false end
      end
    end
  end
  return counts
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

--- The counts of today: `{ [file] = { [pattern] = count } }`, files
--- relative to `root`.
function M.counts(root)
  local out = {}
  local lua, rust = M.files(root)
  for _, file in ipairs(lua) do
    local counts = M.count_lua(read(root .. "/" .. file) or "", file:find(LESSONS) ~= nil)
    if next(counts) then out[file] = counts end
  end
  for _, file in ipairs(rust) do
    local counts = M.count_rust(read(root .. "/" .. file) or "", file:find("/tests/") ~= nil)
    if next(counts) then out[file] = counts end
  end
  return out
end

-- The allow-list ------------------------------------------------------------------

--- The lines of the allow-list as `{ [file] = { [pattern] = count } }`, or
--- nil and an error.
function M.read_allowed(path)
  local text = read(path)
  if not text then return nil, path .. " is missing" end
  local allowed = {}
  local n = 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    if not (line:match("^%s*#") or line:match("^%s*$")) then
      local file, pattern, count = line:match("^(%S+) (%S+) (%d+)$")
      if not file then return nil, string.format("%s:%d: not `<file> <pattern> <count>`: %s", path, n, line) end
      allowed[file] = allowed[file] or {}
      allowed[file][pattern] = tonumber(count)
    end
  end
  return allowed
end

--- The lines of the allow-list for `counts`, sorted.
function M.format(counts)
  local out = {}
  local files = {}
  for file in pairs(counts) do
    files[#files + 1] = file
  end
  table.sort(files)
  for _, file in ipairs(files) do
    local patterns = {}
    for pattern in pairs(counts[file]) do
      if not M.machine[pattern] then patterns[#patterns + 1] = pattern end
    end
    table.sort(patterns)
    for _, pattern in ipairs(patterns) do
      out[#out + 1] = string.format("%s %s %d", file, pattern, counts[file][pattern])
    end
  end
  return table.concat(out, "\n") .. "\n"
end

M.ALLOWED = "tests/timing-allowed.txt"

-- The clocks of the product code ------------------------------------------------------

--- The product files that read the wall clock, `api.real_ms()`. Each one
--- measures a budget of work or waits for another thread or process. Every
--- other product file reads only the schedule clock, `api.now()`, which a
--- test steps (`paw --clock manual`). A file with `budget = true` reads only
--- the wall clock: a read of `api.now()` there is a budget on the schedule
--- clock, which does not move in a test, so its loop never ends.
M.real_time = {
  ["extensions/doctor/lua/doctor/init.lua"] = {},
  ["extensions/doctor/lua/doctor/report.lua"] = { budget = true },
  ["extensions/notation/lua/notation/bench.lua"] = { budget = true },
  ["extensions/utau/lua/utau/engine.lua"] = {},
  ["extensions/utau/lua/utau/init.lua"] = {},
  ["extensions/vinput/lua/vinput/run.lua"] = {},
  ["runtime/lua/paw/collector.tl"] = { budget = true },
  ["runtime/lua/paw/defaults/project.lua"] = {},
  ["runtime/lua/paw/derived.tl"] = {},
  ["runtime/lua/paw/grep.tl"] = {},
  ["runtime/lua/paw/help.tl"] = {},
  ["runtime/lua/paw/limit.tl"] = { budget = true },
  ["runtime/lua/paw/lsp/init.tl"] = {},
  ["runtime/lua/paw/pick/sources.tl"] = { budget = true },
  ["runtime/lua/paw/profile.tl"] = { budget = true },
  ["runtime/lua/paw/slices.tl"] = { budget = true },
}

--- The Lua and Teal files of the product under `root`: the runtime and the
--- extensions, without their tests and the lessons of the tutor.
function M.product_files(root)
  local cd = "cd '" .. root .. "' 2>/dev/null && "
  local out = {}
  for _, file in
    ipairs(lines_of(cd .. "find runtime/lua extensions \\( -name '*.lua' -o -name '*.tl' \\) 2>/dev/null | sort"))
  do
    if not (file:match("/tests[^/]*%.lua$") or file:find(LESSONS)) then out[#out + 1] = file end
  end
  return out
end

--- The problems of the clocks of the product code under `root`.
function M.check_clocks(root)
  local problems = {}
  for _, file in ipairs(M.product_files(root)) do
    local now, real = 0, 0
    for line in ((read(root .. "/" .. file) or "") .. "\n"):gmatch("(.-)\n") do
      if not line:match("^%s*%-%-") then
        local _, n = line:gsub("api%.now%(%)", "")
        local _, r = line:gsub("api%.real_ms%(", "")
        now, real = now + n, real + r
      end
    end
    local listed = M.real_time[file]
    if real > 0 and not listed then
      problems[#problems + 1] = string.format(
        "%s: %d of `api.real_ms()`, the wall clock. A delay or a throttle reads `api.now()`;"
          .. " a budget of work goes in the list `real_time` of tools/testlint.lua",
        file,
        real
      )
    elseif now > 0 and listed and listed.budget then
      problems[#problems + 1] = string.format(
        "%s: %d of `api.now()` in a budget reader. A budget of work reads `api.real_ms()`:"
          .. " the schedule clock does not move in a test",
        file,
        now
      )
    end
  end
  return problems
end

--- The problems of the tree at `root` (default "."): a list of lines, empty
--- when the counts and the allow-list agree.
function M.check(root)
  root = root or "."
  local allowed, err = M.read_allowed(root .. "/" .. M.ALLOWED)
  if not allowed then return { err } end
  local counts = M.counts(root)
  local problems = {}
  -- More than the list allows: a new sleep, clock read or speed check. A
  -- read of the machine is never allowed.
  for file, patterns in pairs(counts) do
    for pattern, n in pairs(patterns) do
      local limit = allowed[file] and allowed[file][pattern] or 0
      if M.machine[pattern] then
        problems[#problems + 1] = string.format(
          "%s: %d of `%s`. A test reads nothing of the machine: take a folder from T.scratch or T.home(),"
            .. " or seal the command (the skills lua-testing and rust-testing, part Self-contained)",
          file,
          n,
          pattern
        )
      elseif n > limit then
        problems[#problems + 1] = string.format(
          "%s: %d of `%s`, %d allowed. A test does not sleep, read the clock or check a speed:"
            .. " wait for a state, or measure in bench/ (docs/how-to/run-the-tests.md)",
          file,
          n,
          pattern,
          limit
        )
      end
    end
  end
  -- Fewer than the list allows: the list gets shorter with the code.
  for file, patterns in pairs(allowed) do
    for pattern, limit in pairs(patterns) do
      local n = counts[file] and counts[file][pattern] or 0
      if M.machine[pattern] then
        problems[#problems + 1] =
          string.format("%s: `%s` reads the machine and has no place in %s", file, pattern, M.ALLOWED)
      elseif n < limit then
        problems[#problems + 1] = n == 0
            and string.format(
              "%s: no `%s` now: remove the line `%s %s %d` from %s",
              file,
              pattern,
              file,
              pattern,
              limit,
              M.ALLOWED
            )
          or string.format(
            "%s: %d of `%s` now: make the line `%s %s %d` in %s",
            file,
            n,
            pattern,
            file,
            pattern,
            n,
            M.ALLOWED
          )
      end
    end
  end
  for _, problem in ipairs(M.check_clocks(root)) do
    problems[#problems + 1] = problem
  end
  table.sort(problems)
  return problems
end

-- Run as a program ---------------------------------------------------------------------

if arg and arg[0] and arg[0]:match("testlint%.lua$") then
  if arg[1] == "counts" then
    io.write(M.format(M.counts(".")))
    os.exit(0)
  end
  local problems = M.check(".")
  for _, line in ipairs(problems) do
    print(line)
  end
  if #problems > 0 then
    print(string.format("testlint: %d problems", #problems))
    os.exit(1)
  end
  print(
    "testlint: no test reads the machine, or depends on time beyond "
      .. M.ALLOWED
      .. ", and each clock read of the product is on its clock"
  )
end

return M
