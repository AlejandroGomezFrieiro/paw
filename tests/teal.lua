-- Languages that compile to Lua (paw/lang.tl), Teal first: the types of
-- every Teal file of the source tree, and files in such languages that load
-- as extensions and modules, compiled once and then taken from the cache.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq

local function write(path, text)
  os.execute("mkdir -p '" .. path:match("^(.*)/") .. "'")
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

test("teal: every Teal file of the source tree passes a strict tl check", function()
  local files = {}
  local pipe = assert(io.popen("find runtime config extensions -name '*.tl' | sort"))
  for line in pipe:lines() do files[#files + 1] = line end
  pipe:close()
  eq(#files > 5, true, "the runtime's modules in Teal are found")
  local lines = {}
  for _, e in ipairs(paw.lang.check(files)) do
    lines[#lines + 1] = string.format("%s:%d:%d: %s", e.file, e.line, e.col, e.msg)
  end
  eq(table.concat(lines, "\n"), "", "type errors")
end)

test("teal: the checker finds a type error", function()
  local file = T.scratch .. "/teal/wrong.tl"
  write(file, 'local n: integer = paw.music.name(60)\nreturn n\n')
  local found = paw.lang.check({ file })
  eq(#found, 1, "one error")
  eq(found[1].line, 1, "on its line")
end)

test("teal: a format that an extension in Teal registers is checked", function()
  local file = T.scratch .. "/teal/format.tl"
  write(file, 'paw.formats.register({ name = "notes", extensions = { "txt" },\n'
    .. '  imprt = function(path: string): string return path end })\n')
  local found = paw.lang.check({ file })
  eq(#found, 1, "one error")
  eq(found[1].msg, "unknown field imprt", "the misspelled side")
end)

test("teal: an event of the kernel is a descriptor: its handler gets the payload's record, and a wrong one is caught", function()
  local file = T.scratch .. "/teal/events.tl"
  write(file, 'local kernel = require("paw.events.kernel")\n'
    .. 'paw.on(kernel.project_saved, function(p: kernel.Saved) print(p.path) end)\n'
    .. 'paw.on(kernel.project_saved, function(p: kernel.TrackId) print(p.id) end)\n')
  local found = paw.lang.check({ file })
  eq(#found, 1, "one error")
  eq(found[1].line, 3, "the handler that takes another payload")
  -- Lua gives the descriptor or the name; the payload is the kernel's.
  local path
  local id = paw.on(require("paw.events.kernel").project_saved, function(p) path = p.path end)
  paw.project.save(T.scratch .. "/teal/saved.json")
  paw.flush()
  paw.off(id)
  eq(path and path:match("saved") ~= nil, true, "the payload of project.saved")
end)

test("teal: an extension in Teal compiles once, then comes from the cache", function()
  local entry = paw.ext.load("config/extensions/scale.tl")
  T.after(function() paw.ext.unload("scale") end)
  eq(entry.ok, true, "it loads: " .. tostring(entry.error))
  eq(paw.ext.provides("scale")[1].items[1], ":scale.notes", "the extension owns its command")
  local compiled, cached = paw.lang.stats.compiled, paw.lang.stats.cached
  paw.ext.unload("scale")
  paw.ext.load("config/extensions/scale.tl")
  eq(paw.lang.stats.compiled, compiled, "not compiled again")
  eq(paw.lang.stats.cached, cached + 1, "taken from the cache")
end)

test("teal: the loader compiles with the types: `is` a name of a function type tests for a function", function()
  local file = T.scratch .. "/teal/alias.tl"
  write(file, 'local type Fn = function(): string\n'
    .. 'local function call(x: Fn | string): string\n  if x is Fn then return x() end\n  return x\nend\n'
    .. 'return call(function(): string return "called" end)\n')
  eq(assert(paw.lang.loadfile(file))(), "called", "the function is called")
end)

-- The guide's test (tests/guides_howto.lua) runs `table.unpack`, `&`, `|`,
-- `>>`, `//` and utf8.len; this one the edges of the library.
test("teal: the Lua 5.3 library that Teal's code calls works on LuaJIT (compat-5.3)", function()
  local file = T.scratch .. "/teal/compat.tl"
  write(file, 'local function kind(x: number | string): string\n'
    .. '  if x is integer then return "integer" elseif x is number then return "float" end\n'
    .. '  return "string"\nend\n'
    .. 'return { kind(3), kind(0.5), kind(2^53), kind(2^60), kind("x"), math.tointeger(4.0), math.tointeger(4.5) == nil,\n'
    .. '  1 << 31, ~0, -7 // 2, utf8.char(72, 0x20AC) }\n')
  eq(paw.inspect(assert(paw.lang.loadfile(file))()), paw.inspect({ "integer", "float", "integer", "float", "string", 4, true,
    2147483648, 4294967295, -4, "H\226\130\172" }))
end)

test("teal: a file with a type error loads, and its errors stay known from the cache", function()
  local file = T.scratch .. "/teal/typo.tl"
  write(file, 'local n: integer = "one"\nreturn 1\n')
  local chunk = paw.lang.loadfile(file)
  eq(chunk and chunk(), 1, "it loads and runs")
  local function said()
    local items = paw.health.run("teal").items
    for _, item in ipairs(items) do
      if item.text:find(file, 1, true) then return item.level .. " " .. table.concat(item.advice or {}, "\n") end
    end
  end
  eq((said() or ""):match("^warn 1:"), "warn 1:", ":checkhealth teal shows the error and its line")
  paw.lang.problems[file] = nil
  local cached = paw.lang.stats.cached
  paw.lang.loadfile(file)
  eq(paw.lang.stats.cached, cached + 1, "taken from the cache")
  eq((said() or ""):match("^warn 1:"), "warn 1:", "the error comes back with it")
end)

test("teal: an error in a Teal file names the file and its line", function()
  local file = T.scratch .. "/teal/broken.tl"
  write(file, 'local x = 1\nlocal function (\n')
  local chunk, err = paw.lang.loadfile(file)
  eq(chunk, nil, "no chunk")
  eq(err:find(file .. ": 2:", 1, true) ~= nil, true, "the file and the line: " .. tostring(err))
end)

test("teal: any language with a compiler joins the registry; require finds its modules", function()
  local dir = T.scratch .. "/teal/lib"
  -- A language whose compiler is a command: here `cat`, as its files are Lua.
  paw.lang.add("lul", { name = "lul", command = "cat %s" })
  T.after(function() paw.lang.compilers.lul = nil end)
  write(dir .. "/tealtest/twice.lul", "return { twice = function(n) return 2 * n end }\n")
  write(dir .. "/tealtest/half.tl", "local record M\n  half: function(n: number): number\nend\nfunction M.half(n: number): number return n / 2 end\nreturn M\n")
  local saved = package.path
  package.path = dir .. "/?.lua;" .. package.path
  T.after(function()
    package.path = saved
    package.loaded["tealtest.twice"], package.loaded["tealtest.half"] = nil, nil
  end)
  eq(require("tealtest.twice").twice(21), 42, "a module in the added language")
  eq(require("tealtest.half").half(42), 21, "a module in Teal")
end)
