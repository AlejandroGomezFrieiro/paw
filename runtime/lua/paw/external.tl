-- Changes made outside paw to the files of the open project: a `git
-- checkout`, another editor, a second program. The kernel watches the
-- folders and reports a burst of changes as one `files.changed`. paw acts
-- on them when you come back to it (the focus of the terminal or the
-- window, or the next key where the terminal does not report it), as
-- `opt.on_external_change` says:
--
--   "ask"     (the default) ask on the command line: reload them, or keep
--             paw's version, which the next save writes over them
--   "reload"  read them again, as one undo step, when the project has no
--             change that is not saved; else ask
--   "keep"    keep paw's version, and say so once
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")
local type KeymapModule = require("paw.keymap")

--- paw/views/cmdline.lua, as far as this module calls it.
local record Cmdline
  ask_key: function(prompt: string, on_key: function(key: string))
end

local record Paw is partial.Paw
  ui: UiModule
  keymap: KeymapModule
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local record M
end

options.define(
  "on_external_change", "ask", {type = "string", values = {"ask", "reload", "keep"}}
) -- when a file of the project changes outside paw: "ask", "reload" or "keep"

--- The changed files as a short list for a message.
local function names(paths: {string}): string
  local out: {string} = {}
  for i, p in ipairs(paths) do
    if i > 3 then
      out[#out + 1] = string.format("%d more", #paths - 3)
      break
    end
    out[#out + 1] = p
  end
  return table.concat(out, ", ")
end

local function count(paths: {string}): string
  return string.format("%d file%s", #paths, #paths == 1 and "" or "s")
end

--- Read the changed files again, as one undo step.
function M.reload()
  local paths = api.project_changed_files()
  local ok, err = pcall(api.project_reload) as (boolean, string)
  if not ok then
    local reason = tostring(err):gsub("^[^:]*:%d+: ", "")
    paw.notify("could not read the project again: " .. reason, "error")
    return
  end
  api.undo_label("read again from the disk")
  paw.notify(string.format("read again: %s changed outside paw (%s); `u` goes back", count(paths), names(paths)))
end

--- Keep paw's version of the project.
function M.keep()
  local paths = api.project_changed_files()
  api.project_keep_changes()
  paw.notify(
    string.format(
      "kept paw's version: %s changed outside paw (%s); the next save writes over them, `:e!` reads them",
      count(paths),
      names(paths)
    )
  )
end

local asking = false

--- True if paw asks now what to do with the changes.
function M.asking(): boolean
  return asking
end

--- Act on the changes as the option says: called when paw gets the focus,
--- or at the next key after them.
function M.act()
  local paths = api.project_changed_files()
  if #paths == 0 or asking then
    return
  end
  local how = opt.on_external_change
  if how == "keep" then
    M.keep()
    return
  end
  if how == "reload" and not api.project_get().modified then
    M.reload()
    return
  end
  asking = true
  local cmdline = (require as function(string): Cmdline)("paw.views.cmdline")
  cmdline.ask_key(
    string.format("%s changed outside paw (%s): read again? y/n ", count(paths), names(paths)),
    function(key: string)
      asking = false
      if key == "y" or key == "Y" then
        M.reload()
      else
        M.keep()
      end
    end
  )
end

-- Coming back to paw is the focus that the terminal (mode 1004) or the
-- window reports. A terminal that does not report it has the next key.
events.on(kernel.files_changed, function() paw.keymap.on_next_key(M.act) end)
events.on(
  paw.ui.desktop_focus,
  function(event: UiModule.DesktopFocus)
    if event.focused then
      M.act()
    end
  end
)

return M
