-- The hooks the runtime gives around edits, undo, saving, keys, the
-- selection and the views on screen: events an extension listens for with
-- `paw.on` like any other (see docs/reference/events.md for every one).
--
-- Some events ask: a handler of `edit.before`, `project.saving` or
-- `key.pre` that returns `false, "why"` refuses what is about to happen.
--
--   paw.on("edit.before", function(e)          -- e.changes: what this turn changed
--     for _, c in ipairs(e.changes) do
--       if c.name == "track.removed" then return false, "tracks stay" end
--     end
--   end)
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")

--- The payload of a change event, as far as this module reads it.
local interface Change
  restored: boolean
end

--- One change of an edit: the event's name and its payload.
local record Edit
  name: string
  payload: Change
end

--- A region of a view that visual mode selects (paw/keymap.lua).
local type Region = contracts.Region

--- What is selected now: the payload of `selection.changed`.
local record Selection
  view: string
  kind: string
  region: Region
  clips: {integer}
  notes: {{integer}}
end

--- The payload of `undo` and `redo`.
local record Move
  from: integer
  to: integer
  how: string
  label: string
end

--- A value this module passes on and never reads.
local record Value
end

local type KernelFn = function(...: Value): Value

-- What this module reads of `paw`, which paw/init.lua makes: the parts of
-- the modules in Lua that their doc comments type (runtime/types/paw.d.tl
-- cannot be named here, as it requires this module).
local record Paw is partial.Paw
  ui: UiModule
end
local paw = (_G as {string:Paw}).paw

local record M
  type Change = Change
  type Edit = Edit
  type Region = Region
  type Selection = Selection
  type Move = Move
end

-- The events that say the project was edited, and so make up an edit.
local EDITS: {string:boolean} = {}
for _, name in ipairs({ "project.changed", "track.added", "track.changed", "track.removed", "track.moved",
  "device.added", "device.changed", "device.removed", "clip.added", "clip.changed", "clip.removed",
  "lane.added", "lane.changed", "lane.removed", "cue.changed" }) do
  EDITS[name] = true
end

local changes: {Edit} = {}  -- what this turn has edited so far: { name, payload }

--- Count an event of this turn as a part of the edit of the turn. Undo,
--- redo and the open of a project are not edits (`restored`).
function M.note(name: string, payload: Change)
  if EDITS[name] and not payload.restored then changes[#changes + 1] = { name = name, payload = payload } end
end

-- Edits ------------------------------------------------------------------------------

--- The end of an edit: the turn changed the project, and its changes are
--- about to become an undo step. `edit.before` may refuse them, which puts
--- the project back as the turn found it; handlers that answer with edits
--- of their own join the step. `edit.after` hears of the step made.
local function finish_edit(): boolean
  local list = changes
  changes = {}
  if #list == 0 or not (events.listened("edit.before") or events.listened("edit.after")) then return false end
  if not api.undo_pending() then return false end
  local ok, why = events.emit("edit.before", { changes = list })
  if ok == false then
    api.undo_discard()
    paw.flush()
    changes = {}
    paw.notify("not done: " .. tostring(why or "an extension refused the edit"), "warn")
    return false
  end
  -- What the handlers changed in answer is part of it.
  paw.flush()
  for _, c in ipairs(changes) do list[#list + 1] = c end
  changes = {}
  api.undo_checkpoint()
  events.emit("edit.after", { changes = list, state = api.undo_current() })
  -- Edits made in answer to it are an edit of their own.
  paw.flush()
  return #changes > 0
end

-- The selection and the views on screen -------------------------------------------------
--
-- Both are compared at the end of each turn, and only while something
-- listens for them by name or family: working them out costs a little.

local last_selection: string = ""
local last_views: {string:boolean} = nil

local function region_key(r: Region): string
  if not r then return "" end
  return string.format("%s %s %s %s %s %s", tostring(r.view), r.kind, r.r0, r.r1, r.c0, r.c1)
end

--- The current selection: the visual selection of the focused view and the
--- clips selected with the pointer. Also the selected notes of the clips that
--- the piano roll edits.
function M.selection(): Selection
  local region = paw.keymap.selection()
  local clips = paw.frontend.chosen_clips()
  -- The roll's clip may be gone (undone, or a new project): no notes then.
  local ok, got = pcall(paw.frontend.chosen_refs)
  local notes: {{integer}} = ok and got or {}
  local kind = region and "region" or #clips > 0 and "clips" or #notes > 0 and "notes" or nil
  return { view = paw.ui.focused, kind = kind, region = region, clips = clips, notes = notes }
end

local function selection_changes()
  if not events.listened("selection.changed") then return end
  local s = M.selection()
  local parts = { region_key(s.region), table.concat(s.clips, ",") }
  for _, ref in ipairs(s.notes) do parts[#parts + 1] = ref[1] .. ":" .. ref[2] end
  local key = table.concat(parts, "|")
  if key == last_selection then return end
  last_selection = key
  events.emit("selection.changed", s)
end

--- The names of the views on screen.
function M.views_shown(): {string:boolean}
  local out: {string:boolean} = {}
  for _, rect in ipairs(paw.ui.arrange()) do
    if rect.name then out[rect.name] = true end
  end
  local float = paw.ui.float
  if float then out[float.name] = true end
  return out
end

local function views_change()
  if not (events.listened("view.opened") or events.listened("view.closed")) then
    last_views = nil
    return
  end
  local now = M.views_shown()
  local before = last_views
  last_views = now
  if not before then return end
  for name in pairs(before) do
    if not now[name] then events.emit("view.closed", { name = name }) end
  end
  for name in pairs(now) do
    if not before[name] then events.emit("view.opened", { name = name }) end
  end
end

--- The end of a turn, after its events are delivered: the kernel's
--- `settle`.
function M.turn()
  for _ = 1, 8 do
    if not finish_edit() then break end
  end
  selection_changes()
  views_change()
end

-- Keys -----------------------------------------------------------------------------------

--- Before a key is dispatched: `key.pre` sees it first. False when a
--- handler took it, and the keymap is not to have it.
function M.key(key: string): boolean
  if not events.listened("key.pre") then return true end
  local ok = events.emit("key.pre", { key = key, mode = paw.keymap.mode, view = paw.ui.focused })
  return ok ~= false
end

-- Undo, redo and saving ------------------------------------------------------------------
--
-- The kernel's functions are wrapped where every caller reaches them (the
-- keys, commands, frontends over the socket), so that each move in the
-- undo tree and each save is heard of.

local function label_of(id: integer): string
  for _, state in ipairs(api.undo_tree().states) do
    if state.id == id then return state.label end
  end
end

local function moving(fn: KernelFn, how: string): KernelFn
  return function(...: Value): Value
    -- A step still open is closed first, so that `from` is the state it made.
    api.undo_checkpoint()
    local from = api.undo_current()
    local result = fn(...)
    local to = api.undo_current()
    if to ~= from then
      local name = how == "undo" and "undo" or how == "redo" and "redo" or (to < from and "undo" or "redo")
      if events.listened(name) then
        local move: Move = { from = from, to = to, how = how, label = label_of(name == "undo" and from or to) }
        events.emit(name, move)
      end
    end
    return result
  end
end

local kernel = api as {string:KernelFn}
for name, how in pairs({ undo = "undo", redo = "redo", undo_goto = "goto", undo_step = "step", undo_travel = "travel" }) do
  kernel[name] = moving(kernel[name], how)
end

local save = api.project_save
--- `project.saving` before a project is written, which may refuse it;
--- `project.saved` comes after, as a change event.
api.project_save = function(path?: string): string
  local ok, why = events.emit("project.saving", { path = path or api.project_get().path })
  if ok == false then error("not saved: " .. tostring(why or "an extension refused"), 2) end
  return save(path)
end

return M
