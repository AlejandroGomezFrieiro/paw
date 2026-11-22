-- A files buffer's key line names what its keys do there, not a text
-- buffer's in general.
local T = ...
local test, eq = T.test, T.eq
local paw = require("paw")

test("files: the key line of a files buffer names its own keys, each one mapped", function()
  T.fresh()
  local dir = T.scratch .. "/keybar-files"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/a.txt", "a")
  paw.cmd("e", { dir })
  local words = {}
  for _, e in ipairs(paw.ui.keybar.entries()) do
    words[#words + 1] = e[1] .. " " .. e[2]
  end
  local line = table.concat(words, " · ")
  eq(
    line:find("dd trash", 1, true) ~= nil and line:find("gh hear", 1, true) ~= nil and line:find("+1", 1, true) == nil,
    true,
    "the files keys: " .. line
  )
  eq(#paw.ui.keybar.check(), 0, "every key it shows is mapped: " .. table.concat(paw.ui.keybar.check(), ", "))
  paw.cmd("q")
end)
