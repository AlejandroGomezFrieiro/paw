-- DAWproject (.dawproject): the open exchange format of Bitwig Studio,
-- PreSonus Studio One and Steinberg Cubase, read and written: a format of
-- `paw.formats` (`import` and `export`).
--
--   local dp = require("interop.dawproject")
--   local result = dp.import("song.dawproject")   -- result.report lists what stayed behind
--   dp.export("out.dawproject")                   -- the project, its plugins' states and its audio
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local type interop = require("interop")

local M = {
  xml = require("interop.dawproject.xmlio"),
}

--- Import a .dawproject file. Options: `merge` (add to the current
--- project), `media_dir` (where the audio of the file goes).
function M.import(path: string, opts?: interop.Options): interop.Result
  return require("interop.dawproject.import").file(path, opts)
end

--- Write the current project to a .dawproject file. `embed = false` refers
--- to the audio files where they are instead of copying them in.
function M.export(path: string, opts?: interop.Options): interop.Result
  return require("interop.dawproject.export").file(path, opts)
end

return M
