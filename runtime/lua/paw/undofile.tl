-- The undo file: as Neovim's undofile, a project opened again can still
-- undo past its last save. After each save of a project folder, the kernel
-- writes the undo tree into the project's state directory
-- (`paw.loading.project_dir(path)/undo/`), on a thread of its own; when the
-- project opens, the kernel reads it back, if the project's files are still
-- those it was written for. See crates/paw-core/src/session/undo_file.rs.
--
--   options.opt.undofile = true      -- keep the undo file (false under --clean)
--   options.opt.undofile_mb = 256    -- about how many megabytes for one project
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local type partial = require("paw.partial")
local type types = require("paw.types")

local record Loading
  project_dir: function(path: string): string
end
local record Paw is partial.Paw
  loading: Loading
end
local paw = (_G as {string: Paw}).paw

local record M
  dir: function(path: string): string
end

--- The undo folder of the project at `path`, or nil when paw keeps none.
function M.dir(path: string): string
  if not path or not options.opt.undofile then
    return nil
  end
  return paw.loading.project_dir(path) .. "/undo"
end

events.on(
  kernel.project_loaded,
  function(e: kernel.Loaded)
    local dir = M.dir(e.path)
    if not dir then
      return
    end
    local ok, read = pcall(api.undo_file_open, dir) as (boolean, types.UndoFileOpen)
    if not ok then
      paw.notify("the undo file was not read: " .. tostring(read), "warn")
    elseif read.stale then
      paw.notify("the undo file is for another version of the project: not read", "warn")
    end
  end
)

events.on(
  kernel.project_saved,
  function(e: kernel.Saved)
    local dir = M.dir(e.path)
    if dir then
      api.undo_file_write(dir, math.floor(options.opt.undofile_mb * 1024 * 1024))
    end
  end
)

-- The program ends after the undo file being written is whole.
local exit: events.Event<kernel.Nothing> = events.event("exit")
events.on(exit, function() api.undo_file_wait() end)

return M
