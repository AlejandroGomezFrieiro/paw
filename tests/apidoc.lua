-- The Lua API's reference: every public function says what it does, and
-- what tools/apidoc.lua makes of it (runtime/types/paw.lua, docs/reference/api.md) is
-- up to date. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

-- Functions in files another piece of work owns tonight (the scene: ui.lua,
-- buf.lua, canvas.lua, frontend.tl), to be given comments there.
local KNOWN_GAPS = {}

-- What `paw -l tools/apidoc.lua check` says, run in a program of its own:
-- a fresh runtime, with nothing a test has added.
local function check()
  local pipe = io.popen("readlink /proc/" .. api.env().pid .. "/exe")
  local binary = pipe:read("*l")
  pipe:close()
  local out = T.scratch .. "/apidoc.txt"
  local code = os.execute(string.format("'%s' --clean --no-plugins -l tools/apidoc.lua check > '%s' 2>&1", binary, out))
  return T.read_file(out), code == 0 or code == true
end

test("apidoc: every public function of the paw modules has a doc comment", function()
  local text = check()
  local gaps = {}
  for name in text:gmatch("undocumented: (%S+)") do
    if not KNOWN_GAPS[name] then gaps[#gaps + 1] = name end
  end
  eq(table.concat(gaps, " "), "", "functions with no `---` comment over them")
end)

test("apidoc: the LuaLS meta file and the :help reference are up to date", function()
  local text = check()
  eq(text:match("out of date: [^\n]*") or "", "", "run `paw --clean --no-plugins -l tools/apidoc.lua`")
end)

test("apidoc: the reference is a page of help, and its names are tags", function()
  local apidoc = assert(loadfile("tools/apidoc.lua"))("module")
  local page = T.read_file("docs/reference/api.md")
  eq(
    page:find("- `paw.commands.define(name, run, opts)`: Define or replace a command.", 1, true) ~= nil,
    true,
    "a function with its comment"
  )
  eq(page:find("- `paw.api.undo_discard()`", 1, true) ~= nil, true, "the kernel's functions too")
  local meta = T.read_file("runtime/types/paw.lua")
  eq(meta:find("---@meta", 1, true), 1, "a LuaLS meta file")
  eq(
    meta:find("function paw.commands.define(name, run, opts) end", 1, true) ~= nil,
    true,
    "a function with its parameters"
  )
  eq(meta:find("function paw.Track:clips() end", 1, true) ~= nil, true, "a method")
  eq(
    meta:find("---@param id integer\nfunction paw.api.clip_get(id) end", 1, true) ~= nil,
    true,
    "a kernel function with its parameter's type"
  )
  eq(#apidoc.functions() > 500, true, "it finds the functions")
  local tag = paw.help.lookup("paw.ext.unload")
  eq(tag ~= nil, true, ":help paw.ext.unload finds it")
end)
