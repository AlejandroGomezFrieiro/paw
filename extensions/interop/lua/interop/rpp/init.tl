-- REAPER projects (.rpp), read and written: a format of `paw.formats`
-- (`import` and `export`), and the file as a tree for scripts.
--
--   local rpp = require("interop.rpp")
--   local doc = rpp.read("song.rpp")            -- the file as a tree
--   doc.project:set("TEMPO", 96, 4, 4, 0)
--   rpp.save(doc, "song.rpp")                   -- unchanged lines are written as read
--   local result = rpp.import("song.rpp")       -- into paw; result.report lists what stayed behind
--   rpp.export("out.rpp")                       -- paw's project as a REAPER project
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local format = require("interop.rpp.format")
local type interop = require("interop")

local M = {
  format = format,
  parse = format.parse,
  write = format.write,
  read = format.read,
  save = format.save,
  line = format.line,
  block = format.block,
  document = format.document,
}

--- Import a .rpp file. Options: `merge` (add to the current project),
--- `instrument` (a device kind for MIDI tracks left without one).
function M.import(path: string, opts?: interop.Options): interop.Result
  return require("interop.rpp.import").file(path, opts)
end

--- Write the current project to a .rpp file.
function M.export(path: string, opts?: interop.Options): interop.Result
  return require("interop.rpp.export").file(path, opts)
end

return M
