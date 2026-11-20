-- Languages that compile to Lua (paw/lang.lua), Teal first: the types of
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
