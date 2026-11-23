-- The check of the word part: paw calls its container a part, and no name,
-- message, comment or page calls it a track. The word "track" stays only in
-- its other senses: a track of a MIDI file, the sound track of a video, a
-- track of another program or file format (REAPER, DAWproject, OpenUtau),
-- the number of a track on an album, and to track a value. It reads text
-- only, so plain LuaJIT runs it (the flake's `partlint` check), and so does
-- paw (the suite's tests/partlint.lua).
--
--   luajit tools/partlint.lua          check the files against the allow-list
--   luajit tools/partlint.lua counts   print the uses of today, in the format of the allow-list
--
-- tools/partlint-allowed.txt holds one line `<file> <count> <reason>` for
-- each file that keeps the word in another sense. It works as the list of
-- tools/zoomlint.lua: a count that goes up fails, and a count that goes
-- down fails until its line is made smaller.
local zoomlint = dofile("tools/zoomlint.lua")

local M = {}

M.ALLOWED = "tools/partlint-allowed.txt"

-- The folders and files that the check reads.
M.ROOTS = {
  "README.md",
  "AGENTS.md",
  "CLAUDE.md",
  ".claude",
  "bench",
  "config",
  "crates",
  "docs",
  "examples",
  "extensions",
  "fuzz",
  "runtime",
  "tests",
  "tools",
  "web",
}

-- Text that is not paw's own, or that records the past: the vendored
-- compiler and library, the guides of Rust that come from outside, the
-- engine of OpenUtau (its words are its own), the paused window, dated logs
-- and results of benchmarks, and the recordings of the terminal. This
-- check and its list are left out too.
M.SKIP = {
  "runtime/lua/tl.lua",
  "runtime/lua/compat53/",
  ".claude/skills/rust-skills/rules/",
  "crates/paw-gui/",
  "extensions/utau/engine/",
  "bench/RESULTS.md",
  "bench/results/",
  "tools/partlint.lua",
  "tools/partlint-allowed.txt",
}

-- The kinds of file that hold text.
local TEXT = {
  "rs",
  "lua",
  "tl",
  "md",
  "toml",
  "sh",
  "txt",
  "json",
  "jsonl",
  "nix",
  "py",
  "js",
  "mjs",
  "yml",
  "yaml",
  "chain",
  "ini",
}

-- Words that contain "track" in a sense that is not the container.
local OTHER = {
  "track_caller", -- a Rust attribute
  "tracker", -- a pitch tracker, a music tracker
  "tracking",
  "tracked", -- also untracked
  "heaptrack", -- a profiler
  "keytrack", -- SFZ opcodes
  "veltrack",
  "soundtrack",
  "tracktion", -- another program
  "trackpad",
}

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
  local names = {}
  for _, ext in ipairs(TEXT) do
    names[#names + 1] = "-name '*." .. ext .. "'"
  end
  local found = lines_of(
    "cd '"
      .. root
      .. "' && find "
      .. table.concat(M.ROOTS, " ")
      .. " -type f \\( "
      .. table.concat(names, " -o ")
      .. " \\) -not -path '*/node_modules/*' -not -path '*/target/*' 2>/dev/null | sort"
  )
  local out = {}
  for _, path in ipairs(found) do
    local skip = false
    for _, prefix in ipairs(M.SKIP) do
      skip = skip or path:sub(1, #prefix) == prefix
    end
    if not skip then out[#out + 1] = path end
  end
  return out
end

--- The uses of the word "track" in a text, in any case and inside names
--- (`TrackId`, `file_track`): the line of each. The words of `OTHER` do not
--- count.
function M.uses(text)
  local out = {}
  local n = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local low = line:lower()
    for _, word in ipairs(OTHER) do
      low = low:gsub(word, "")
    end
    for _ in low:gmatch("track") do
      out[#out + 1] = n
    end
  end
  return out
end

local PART = {
  allowed = M.ALLOWED,
  files = M.files,
  uses = M.uses,
  what = 'the word "track"',
  fix = "Call the container a part. If the word means a track of a MIDI file or of another program,"
    .. " give the file a line in tools/partlint-allowed.txt with the reason",
}

--- The problems under `root`: each a line of text. Empty when all is well.
function M.check(root) return zoomlint.scan(root, PART) end

--- The uses of today, as lines of the allow-list (with no reason).
function M.counts(root) return zoomlint.scan_counts(root, PART) end

-- Run as a script (`luajit tools/partlint.lua`), not loaded by a test.
if arg and arg[0] and arg[0]:match("partlint%.lua$") and not paw then
  if arg[1] == "counts" then
    print(table.concat(M.counts("."), "\n"))
    os.exit(0)
  end
  local problems = M.check(".")
  if #problems > 0 then
    io.stderr:write(table.concat(problems, "\n") .. "\n")
    os.exit(1)
  end
  print("partlint: the container is a part")
end

return M
