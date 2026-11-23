-- Golden files of the terminal screen: `T.expect_screen(name, w, h, opts)`
-- draws the screen at a small size and compares it with a file that a person
-- read and accepted. tests/suite.lua loads this file with `dofile` and calls
-- it with `T`. See docs/how-to/run-the-tests.md and the skill lua-testing.
--
-- The file of a test file `tests/<file>.lua` is
-- `tests/screens/<file>/<name>.txt`, and the file of
-- `extensions/<ext>/<file>.lua` is `extensions/<ext>/screens/<file>/<name>.txt`.
-- With PAW_BLESS=1 in the environment, a missing or different file is written,
-- and a file that no test of a test file uses is removed.
--
-- The text of a golden file: one line for each row of the screen. A run of
-- cells in a style other than the most frequent one is `{id:text}`. Spaces
-- at the end of a row in the most frequent style are left out. After the
-- rows, a line `--`, then one line for each style: `<id>: <colours and
-- attributes>`. Style 0 is the most frequent style, and it has no marks.
-- The ids go in the order of the first cell of each style.
local api = paw.api

local bless = os.getenv("PAW_BLESS") == "1"
-- The name of the test that runs now, for the command that blesses its files.
local running

local function bless_hint() return string.format("PAW_BLESS=1 tests/tools/suite.sh only %q", running or "<words>") end

-- The test file of a chunk source: nil for a source that is not a test file.
local function test_file_of(source)
  local file = source:match("^@(tests/[^/]+%.lua)$")
  if file == "tests/suite.lua" then return nil end
  return file or source:match("^@(extensions/[^/]+/tests[%w_]*%.lua)$")
end

-- The folder of the golden files of a test file.
local function folder_of(file)
  local dir, base = file:match("^(.*)/([^/]+)%.lua$")
  return dir .. "/screens/" .. base
end

-- The test file that called the helper: the first test file on the stack,
-- so a local helper of a test file can call it too.
local function calling_test_file()
  local level = 3
  while true do
    local info = debug.getinfo(level, "S")
    if not info then error("T.expect_screen: called from no test file", 3) end
    local file = test_file_of(info.source)
    if file then return file end
    level = level + 1
  end
end

-- Cells --------------------------------------------------------------------

-- A colour as the Rust `Debug` text of `paw_scene::cells::Color` gives it,
-- in the words of a highlight group: `#rrggbb`, the number of an indexed
-- colour, or `default`.
local function colour_words(debug_text)
  local r, g, b = debug_text:match("^Rgb%((%d+), (%d+), (%d+)%)$")
  if r then return string.format("#%02x%02x%02x", tonumber(r), tonumber(g), tonumber(b)) end
  return debug_text:match("^Indexed%((%d+)%)$") or debug_text:lower()
end

-- The bits of `paw_scene::cells` (BOLD, DIM, ...), in the order of the bits.
local attribute_names = { "bold", "dim", "italic", "underline", "reverse", "strike" }

local function style_words(fg, bg, attrs)
  local words = { "fg=" .. colour_words(fg), "bg=" .. colour_words(bg) }
  for bit, name in ipairs(attribute_names) do
    if math.floor(attrs / 2 ^ (bit - 1)) % 2 == 1 then words[#words + 1] = name end
  end
  return table.concat(words, " ")
end

-- The cells of one row: { char, style } for each character of the text.
-- `ui_frame_snapshot` gives each row as text and as the `Debug` text of its
-- cells. The second half of a double-width character is a cell with `'\0'`
-- and no character in the text, so it is skipped.
local function row_cells(text, cells_debug)
  local chars = {}
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    chars[#chars + 1] = char
  end
  local out = {}
  for ch, fg, bg, attrs in cells_debug:gmatch("Cell { ch: '(.-)', fg: (.-), bg: (.-), attrs: (%d+) }") do
    if ch ~= "\\0" then out[#out + 1] = { chars[#out + 1] or "?", style_words(fg, bg, tonumber(attrs)) } end
  end
  return out
end

-- The styles of the cells of `rows`: the most frequent one (style 0), the
-- id of each style, and the legend of the golden text. The ids after 0 go
-- in the order of the first cell of each style.
local function number_styles(rows)
  local count, order = {}, {}
  for _, row in ipairs(rows) do
    for _, cell in ipairs(row) do
      if not count[cell[2]] then order[#order + 1] = cell[2] end
      count[cell[2]] = (count[cell[2]] or 0) + 1
    end
  end
  local base = order[1]
  for _, style in ipairs(order) do
    if count[style] > count[base] then base = style end
  end
  local id = { [base] = 0 }
  local legend = { "--", "0: " .. base }
  for _, style in ipairs(order) do
    if not id[style] then
      id[style] = #legend - 1
      legend[#legend + 1] = id[style] .. ": " .. style
    end
  end
  return base, id, legend
end

-- The golden text of a region of a frame (see the top of this file):
-- `region.rows` and `region.cols` are each `{ first, last }`. A column is a
-- character: a double-width character counts as one. Without styles,
-- the text only, with spaces at the end of a row left out.
local function golden_text(frame, region, styles)
  local rows = {}
  for y = region.rows[1], region.rows[2] do
    rows[#rows + 1] = { unpack(row_cells(frame.text[y], frame.cells[y]), region.cols[1], region.cols[2]) }
  end
  local base, id, legend = number_styles(rows)
  -- Each row as runs of one style.
  local lines = {}
  for _, row in ipairs(rows) do
    local parts, run, run_style = {}, {}, nil
    local function close_run()
      if #run == 0 then return end
      local text = table.concat(run)
      local marked = styles and run_style ~= base
      parts[#parts + 1] = marked and ("{" .. id[run_style] .. ":" .. text .. "}") or text
      run = {}
    end
    for _, cell in ipairs(row) do
      if cell[2] ~= run_style then close_run() end
      run_style = cell[2]
      run[#run + 1] = cell[1]
    end
    close_run()
    -- Spaces that end a row go when they are not marked: those of style 0,
    -- or all of them without styles.
    lines[#lines + 1] = table.concat(parts):gsub(" +$", "")
  end
  if styles then
    for _, line in ipairs(legend) do
      lines[#lines + 1] = line
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

-- Files --------------------------------------------------------------------

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

local function write(path, data)
  os.execute("mkdir -p '" .. path:match("^(.*)/") .. "'")
  local file = assert(io.open(path, "wb"))
  file:write(data)
  file:close()
end

-- The rows that differ, as lines of a report: at most `limit` of them.
local function difference(want, got, limit)
  local function lines(text)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
      out[#out + 1] = line
    end
    return out
  end
  local a, b = lines(want), lines(got)
  local out, shown = {}, 0
  for i = 1, math.max(#a, #b) do
    if a[i] ~= b[i] then
      shown = shown + 1
      if shown > limit then
        out[#out + 1] = "  ..."
        break
      end
      out[#out + 1] = string.format("  line %d want: %s", i, a[i] or "(none)")
      out[#out + 1] = string.format("  line %d got:  %s", i, b[i] or "(none)")
    end
  end
  return table.concat(out, "\n")
end

-- The record of a run --------------------------------------------------------

-- For each test file: how many tests it has, how many ran to the end without
-- a skip, and the golden files that its tests used. A golden file that no
-- test used is unused only when every test of its file ran to the end: a
-- filter, a shard, a skip or a failure can leave out the test that uses it.
local registered, completed, used = {}, {}, {}

-- `fn`, the test `name` of `file`, as a test that counts when it ends
-- without an error or a skip.
local function counted(file, name, fn)
  registered[file] = (registered[file] or 0) + 1
  return function(...)
    running = name
    local result = fn(...)
    if result == nil then completed[file] = (completed[file] or 0) + 1 end
    return result
  end
end

local function list(dir)
  local ok, entries = pcall(api.read_dir, dir)
  return ok and entries or {}
end

-- The golden files of the folder of `file`, by name.
local function golden_files(folder)
  local out = {}
  for _, entry in ipairs(list(folder)) do
    if not entry.is_dir and entry.name:match("%.txt$") then out[#out + 1] = folder .. "/" .. entry.name end
  end
  return out
end

-- Each folder `<dir>/screens/<base>` of the checkout, with its test file
-- `<dir>/<base>.lua`.
local function golden_folders()
  local dirs = { "tests" }
  for _, entry in ipairs(list("extensions")) do
    if entry.is_dir then dirs[#dirs + 1] = "extensions/" .. entry.name end
  end
  local out = {}
  for _, dir in ipairs(dirs) do
    for _, entry in ipairs(list(dir .. "/screens")) do
      if entry.is_dir then
        out[#out + 1] = { folder = dir .. "/screens/" .. entry.name, file = dir .. "/" .. entry.name .. ".lua" }
      end
    end
  end
  return out
end

return function(T)
  --- Draw the screen `width` by `height` and compare it with the golden file
  --- `name` of the calling test file. `opts.rows = { first, last }` and
  --- `opts.cols = { first, last }` keep only those rows and columns;
  --- `opts.styles = false` leaves the styles out.
  local function expect_screen(name, width, height, opts)
    opts = opts or {}
    assert(name:match("^[%w_%-]+$"), "T.expect_screen: a name is letters, digits, - and _")
    local file = calling_test_file()
    local path = folder_of(file) .. "/" .. name .. ".txt"
    used[path] = true
    local region = { rows = opts.rows or { 1, height }, cols = opts.cols or { 1, width } }
    local function inside(span, size) return 1 <= span[1] and span[1] <= span[2] and span[2] <= size end
    assert(
      inside(region.rows, height) and inside(region.cols, width),
      "T.expect_screen: rows and cols are inside the screen"
    )
    local got = golden_text(api.ui_frame_snapshot(width, height), region, opts.styles ~= false)
    local want = read(path)
    if want == got then return end
    if bless then
      write(path, got)
      print("bless " .. path)
      return
    end
    if not want then
      error(string.format("no golden screen %s\n  to write it, run: %s\n  then read the file", path, bless_hint()), 2)
    end
    error(
      string.format(
        "the screen is not the golden screen %s\n%s\n  if the new screen is right, run: %s\n  and read the diff",
        path,
        difference(want, got, 4),
        bless_hint()
      ),
      2
    )
  end

  -- Each test counts for the check of unused golden files.
  local function counting(add)
    return function(name, fn, opts)
      local file = test_file_of(debug.getinfo(2, "S").source) or "?"
      return add(name, counted(file, name, fn), opts)
    end
  end
  T.test, T.last = counting(T.test), counting(T.last)
  T.expect_screen = expect_screen

  --- After the run: the golden files that no test used, of the test files
  --- whose every test ran to the end, and the folders of no test file. Each
  --- is a failure; with PAW_BLESS=1 it is removed. Gives the number of
  --- failures.
  return function()
    local unused = {}
    for _, golden in ipairs(golden_folders()) do
      local whole = registered[golden.file] and completed[golden.file] == registered[golden.file]
      local orphan = not read(golden.file)
      if whole or orphan then
        for _, path in ipairs(golden_files(golden.folder)) do
          if not used[path] then unused[#unused + 1] = path end
        end
      end
    end
    table.sort(unused)
    if #unused == 0 then return 0 end
    if bless then
      for _, path in ipairs(unused) do
        os.remove(path)
        print("remove " .. path)
        -- A folder that is empty now goes too; one with files stays.
        os.remove(path:match("^(.*)/"))
      end
      return 0
    end
    print(
      "FAIL  every golden screen has a test\n      no test uses: "
        .. table.concat(unused, ", ")
        .. "\n      remove them, or run the suite with PAW_BLESS=1"
    )
    return 1
  end
end
