-- DAWproject (.dawproject): the open exchange format of Bitwig Studio,
-- PreSonus Studio One and Steinberg Cubase, read and written.
--
--   local dp = require("dawproject")
--   local result = dp.import("song.dawproject")   -- result.report lists what stayed behind
--   dp.export("out.dawproject")                   -- the project, its plugins' states and its audio
local M = {
  xml = require("dawproject.xml"),
}

--- Import a .dawproject file. Options: `merge` (add to the current
--- project), `media_dir` (where the audio of the file goes).
function M.import(path, opts) return require("dawproject.import").file(path, opts) end

--- Write the current project to a .dawproject file. `embed = false` refers
--- to the audio files where they are instead of copying them in.
function M.export(path, opts) return require("dawproject.export").file(path, opts) end

--- Show a report in a page, and a one-line summary.
function M.show(report, summary)
  paw.notify(summary .. (report:empty() and "" or "; see the list of what was not carried over"),
    report:empty() and "info" or "warn")
  if not report:empty() then pcall(paw.ui.page, "DAWproject", report:lines(30)) end
end

return M
