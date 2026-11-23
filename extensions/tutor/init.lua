-- A course for first-time users, inside paw, in the way `vimtutor`
-- teaches Vim. `:tutor` starts it. See README.md beside this file.
local tutor = require("tutor")
local panel = require("tutor.panel")
require("tutor.lessons")

-- Where this extension is, so that `:tutor.try` can find the extensions
-- bundled beside it.
local here = debug.getinfo(1, "S").source:match("^@(.*)/init%.lua$") or "extensions/tutor"
tutor.home = here

local command, map = paw.command, paw.keymap.set

local function run(ctx, force)
  local what = ctx.args[1]
  if what == "list" then return tutor.list() end
  if what == "quit" or what == "leave" then return tutor.quit() end
  if what == "hint" then return tutor.hint() end
  if what == "next" or what == "skip" then return tutor.skip() end
  if what == "restart" then return tutor.restart() end
  if what == "reset" then return tutor.reset() end
  tutor.start(what, { force = force })
end

command("tutor", function(ctx) run(ctx, false) end, {
  desc = "The course: `tutor` (where you left off), `tutor 3`, `tutor list`, `tutor quit`, `tutor hint`, `tutor next`, `tutor restart`",
})
command(
  "tutor!",
  function(ctx) run(ctx, true) end,
  { desc = "Start a lesson even if the open project has unsaved changes, which are lost" }
)
command("tutor.hint", tutor.hint, { desc = "A hint for the tutor's step" })
command("tutor.next", tutor.skip, { desc = "Skip the tutor's step (or go on to the next lesson)" })
command("tutor.restart", tutor.restart, { desc = "Start the lesson again from a fresh practice project" })
command("tutor.list", tutor.list, { desc = "The lessons and how far you got" })
command("tutor.quit", tutor.quit, { desc = "Leave the tutor and reopen your own project" })
command("tutor.try", function(ctx)
  local name = ctx.args[1] and tostring(ctx.args[1])
  if not name then
    return paw.notify("usage: tutor.try <extension>, for one of the extensions bundled with paw", "warn")
  end
  if paw.ext.loaded[name] and paw.ext.loaded[name].ok then return paw.notify(name .. " is loaded already") end
  local path = here:gsub("/tutor$", "") .. "/" .. name
  -- An extension starts at init.lua, or at init.tl when it is written in Teal.
  local exists = require("tutor.store").exists
  if not (exists(path .. "/init.lua") or exists(path .. "/init.tl")) then
    return paw.notify("no bundled extension `" .. name .. "` in " .. path, "warn")
  end
  local entry = paw.ext.load(path)
  if entry.ok then
    paw.notify(name .. " loaded for this session. To have it always, link " .. path .. " into ~/.config/paw/extensions")
  end
end, { desc = "Load one of the extensions bundled with paw, for this session: `tutor.try sections`" })

paw.keymap.group("<leader>h", "tutor")
map("<leader>hh", "tutor.hint", { desc = "Tutor: a hint" })
map("<leader>hn", "tutor.next", { desc = "Tutor: skip this step, or go on to the next lesson" })
map("<leader>hr", "tutor.restart", { desc = "Tutor: start the lesson again" })
map("<leader>hl", "tutor.list", { desc = "Tutor: the lessons" })
map("<leader>hq", "tutor.quit", { desc = "Tutor: leave, and reopen your project" })

-- What makes no event (a window closing, the key hints appearing) is noticed
-- by looking a few times a second.
paw.every(200, tutor.poll)

-- After `:reload` the tutor carries on where it was.
if tutor.state().active then panel.show() end

return tutor
