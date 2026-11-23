-- plugstate's commands, keys and pickers.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local plugstate = require("plugstate")
local type contracts = require("paw.contracts")
local type types = require("paw.types")

local api = paw.api
local command = paw.command

local type Slot = plugstate.Slot
local type File = plugstate.File
local type Snapshot = plugstate.Snapshot
local type Context = contracts.CommandContext

local function device_name(id: integer): string
  return api.device_get(id).name
end

local function target(): integer
  local id, why = plugstate.target()
  if not id then
    paw.notify(why, "warn")
  end
  return id
end

-- What the device's adapter says of a file, or nil.
local function words_of(id: integer, path: string): string
  local a = plugstate.adapter_of(id)
  local words = a and a.describe and a.describe(path)
  return words and words ~= "" and words or nil
end

local function said(id: integer, slot: Slot, path: string)
  local words = words_of(id, path)
  local a = plugstate.adapter_of(id)
  local name = a and a.name_of and a.name_of(path) or plugstate.stem(path)
  paw.notify(
    string.format("%s: %s %s%s", device_name(id), slot.what or "file", name, words and ("  (" .. words .. ")") or "")
  )
end

--- Set the slot to a file, and say so.
local function load_file(id: integer, slot: Slot, path: string): boolean
  local ok, err = plugstate.set(id, slot.key, path)
  if not ok then
    paw.notify(device_name(id) .. ": " .. tostring(err), "error")
    return
  end
  -- What the slot holds now can be of another kind (a model where an
  -- impulse response was).
  said(id, plugstate.slot(id, slot.key) or slot, path)
  return true
end

--- Choose a file for a slot of a device from the library folders. Each
--- one is loaded as a trial as the selection rests on it, and heard with
--- what the part plays; Escape puts back what was there.
function plugstate.pick(id: integer, slot: Slot, query?: string)
  local d = api.device_get(id)
  local roots = plugstate.roots()
  local source: contracts.PickSource<File> = {
    title = (slot.what or "File"):gsub("^%l", string.upper) .. "s · " .. d.name,
    items = function(): {File} return plugstate.files(slot) end,
    query = query,
    format = function(f: File): string
      local now = f.path == slot.value and "●" or " "
      return string.format("%s %-32s %s", now, f.name, f.folder)
    end,
    primary = function(f: File): string return f.name end,
    empty = "no "
      .. (slot.what or "file")
      .. " files in "
      .. table.concat(roots, ", ")
      .. " (the folders are paw.opt.plugstate_folders)",
    on_choose = function(f: File) load_file(id, slot, f.path) end,
    audition_key = "plugstate",
    audition = function(f: File): string | contracts.Hearing<File>
      local ok, err = paw.audition.try(
        function(): boolean, string
          local fine, why = plugstate.set(id, slot.key, f.path)
          if not fine then
            error(why, 0)
          end
          return true
        end
      )
      if not ok then
        return f.name .. " · " .. tostring(err)
      end
      return {
        label = f.name .. " · " .. paw.audition.through(d.part),
        keep = function() said(id, slot, f.path) end,
      }
    end,
    preview = function(f: File): {string | contracts.PageLine}
      local lines: {string | contracts.PageLine} = {{text = f.name, style = "Title"} as contracts.PageLine, f.path}
      local words = words_of(id, f.path)
      if words then
        lines[#lines + 1] = words
      end
      return lines
    end,
  }
  paw.pick(source)
end

--- Split `slot=<key>` from the words of a command.
local function slot_and_words(ctx: Context): string, string
  local slot = ctx.args.slot and tostring(ctx.args.slot) or nil
  local words: {string} = {}
  for _, w in ipairs(ctx.args) do
    words[#words + 1] = tostring(w)
  end
  return slot, table.concat(words, " ")
end

-- The words of a command as one text.
local function text_of(ctx: Context): string
  local _, text = slot_and_words(ctx)
  return text
end

local function home(path: string): string
  return (path:gsub("^~", os.getenv("HOME") or "~"))
end

local exists = api.fs_exists

-- The slot that `slot=<key>` names (the first without it), or a warning.
local function slot_or_say(id: integer, key: string): Slot
  local slot = plugstate.slot(id, key)
  if not slot then
    paw.notify(device_name(id) .. ": no " .. (key or "file") .. " to set (`:plugstate.info` lists them)", "warn")
  end
  return slot
end

command(
  "plugstate.load",
  function(ctx: Context)
    local id = target()
    if not id then
      return
    end
    local key, text = slot_and_words(ctx)
    local slot = slot_or_say(id, key)
    if not slot then
      return
    end
    local path = home(text)
    if slot.kind ~= "file" and text ~= "" then
      load_file(id, slot, text)
      return
    end
    if path ~= "" and exists(path) then
      load_file(id, slot, path)
      return
    end
    if path:find("/", 1, true) then
      paw.notify(device_name(id) .. ": there is no file " .. path, "error")
      return
    end
    -- Words: the one file they find, or the list to choose from.
    if text ~= "" then
      local found = plugstate.search(slot, text)
      if #found == 1 then
        load_file(id, slot, found[1].path)
        return
      end
    end
    plugstate.pick(id, slot, text ~= "" and text or nil)
  end,
  {
    desc = "Load a file into the plugin (an amp model, an impulse response): `plugstate.load ~/nam/deluxe.nam`, words to find one by, or none to choose from a list where each is heard; `slot=<key>` picks which file",
    complete = "files",
  }
)

-- The state that `:plugstate.at` puts on the lane: a snapshot, or a slot
-- set to a value (a file: its path, or words that find one file). Nil
-- and why, with the level of the message.
local function at_state(id: integer, ctx: Context): types.LaneState, string, string
  if ctx.args.snapshot then
    local state, why = plugstate.lane_snapshot(id, tostring(ctx.args.snapshot))
    return state, why, "error"
  end
  local key, text = slot_and_words(ctx)
  local slot = plugstate.slot(id, key)
  if not slot then
    return nil, "no " .. (key or "file") .. " to set (`:plugstate.info` lists them)", "warn"
  end
  local value = text
  if slot.kind == "file" and not exists(home(text)) then
    local found: {File} = text ~= "" and plugstate.search(slot, text) or {}
    if #found ~= 1 then
      return nil,
        (#found == 0 and "no file found by `" .. text .. "`" or #found .. " files found: give more words"),
        "warn"
    end
    value = found[1].path
  end
  local state, why = plugstate.lane_state(id, slot.key, value)
  return state, why, "error"
end

command(
  "plugstate.at",
  function(ctx: Context)
    local id = target()
    if not id then
      return
    end
    local state, why, level = at_state(id, ctx)
    if not state then
      paw.notify(device_name(id) .. ": " .. tostring(why), level)
      return
    end
    local beat = paw.cursor.beat
    local ok, err = pcall(plugstate.lane_point, id, beat, state) as (boolean, string)
    if not ok then
      paw.notify(device_name(id) .. ": " .. (tostring(err):gsub("^.-:%d+: ", "")), "error")
      return
    end
    paw.notify(string.format("%s: %s from %s, on its state lane", device_name(id), state.name, paw.time.format(beat)))
  end,
  {
    desc = "Change the plugin to a file or a snapshot at the cursor, on its state lane, as the song plays: `plugstate.at deluxe`, `plugstate.at slot=block2 ~/nam/x.nam`, `plugstate.at snapshot=B`",
    complete = "files",
  }
)

local function step(n: integer): function(ctx: Context)
  return function(ctx: Context)
    local id = target()
    if not id then
      return
    end
    local key = ctx.args.slot and tostring(ctx.args.slot) or nil
    local slot = plugstate.slot(id, key)
    if not slot or slot.kind ~= "file" then
      paw.notify(device_name(id) .. ": no file to step through", "warn")
      return
    end
    local f = plugstate.neighbour(slot, n * (ctx.count or 1))
    if not f then
      paw.notify(
        device_name(id)
          .. ": no "
          .. (slot.what or "file")
          .. " files beside it or in "
          .. table.concat(plugstate.roots(), ", "),
        "warn"
      )
      return
    end
    load_file(id, slot, f.path)
  end
end
command("plugstate.next", step(1), {desc = "Load the next file of the folder (a count skips more)"})
command("plugstate.prev", step(-1), {desc = "Load the previous file of the folder (a count skips more)"})

-- The line of `:plugstate.info` on the framework of the saved state, as
-- `:plugstate.tree` reads it, or nil.
local function state_line(id: integer): string
  if not api.device_get(id).plugin then
    return nil
  end
  local doc = require("plugstate.juceplugins").open(id)
  if not doc then
    return nil
  end
  return "state: "
    .. (doc.title or doc.framework)
    .. " · "
    .. table.concat(doc:layer_names(), " › ")
    .. " · "
    .. #doc:params()
    .. " parameters in it"
end

command(
  "plugstate.info",
  function()
    local id = target()
    if not id then
      return
    end
    local a = plugstate.adapter_of(id)
    local lines = {device_name(id) .. " · " .. a.name .. " (" .. (a.desc or "") .. ")"}
    lines[#lines + 1] = state_line(id)
    for _, s in ipairs(plugstate.slots(id)) do
      local value = s.value
      if value == nil or value == "" then
        value = "none"
      end
      -- The key first: it is what `slot=` takes.
      local label = s.label and s.label ~= s.key and (" (" .. s.label .. ")") or ""
      lines[#lines + 1] = string.format("%s%s: %s", s.key, label, tostring(value))
      local file = s.value
      if s.kind == "file" and file is string and file ~= "" then
        local words = words_of(id, file)
        if words then
          lines[#lines + 1] = "  " .. words
        end
      end
    end
    local snaps = plugstate.snapshots(id)
    if #snaps > 0 then
      local names: {string} = {}
      for _, s in ipairs(snaps) do
        names[#names + 1] = (s.name == plugstate.current(id) and "●" or "") .. s.name
      end
      lines[#lines + 1] = "snapshots: " .. table.concat(names, ", ")
    end
    paw.notify(table.concat(lines, "\n"))
  end,
  {desc = "What the plugin holds besides its parameters (its files), and its snapshots"}
)

command(
  "plugstate.files",
  function(ctx: Context)
    local id = target()
    if not id then
      return
    end
    local key, text = slot_and_words(ctx)
    local slot = plugstate.slot(id, key)
    if not slot or slot.kind ~= "file" then
      paw.notify(device_name(id) .. ": no file to list", "warn")
      return
    end
    local found = plugstate.search(slot, text)
    local lines = {
      string.format("%d %s files%s", #found, slot.what or "", text ~= "" and (" with “" .. text .. "”") or "")
    }
    for i, f in ipairs(found) do
      if i > 40 then
        lines[#lines + 1] = "…"
        break
      end
      lines[#lines + 1] = (f.path == slot.value and "● " or "  ")
        .. f.name
        .. (f.folder ~= "" and ("  " .. f.folder) or "")
    end
    paw.notify(table.concat(lines, "\n"))
  end,
  {
    desc = "List the files the plugin can load, in the library folders: `plugstate.files clean` lists those with the word",
  }
)

command(
  "plugstate.snapshot",
  function(ctx: Context)
    local id = target()
    if not id then
      return
    end
    local kept, replaced = plugstate.snapshot(id, text_of(ctx))
    paw.notify(string.format("%s: snapshot %s %s", device_name(id), kept, replaced and "replaced" or "kept"))
  end,
  {
    desc = "Keep the plugin's whole state as a named snapshot in the project: `plugstate.snapshot crunch` (none: A, B, C...)",
  }
)

local function recalled(id: integer, snap: Snapshot, err?: string)
  if not snap then
    paw.notify(device_name(id) .. ": " .. tostring(err), "warn")
    return
  end
  paw.notify(device_name(id) .. ": snapshot " .. snap.name)
end

--- Choose a snapshot of the device in a picker, each heard as a trial.
function plugstate.pick_snapshot(id: integer)
  local d = api.device_get(id)
  local source: contracts.PickSource<Snapshot> = {
    title = "Snapshots · " .. d.name,
    items = plugstate.snapshots(id),
    format = function(s: Snapshot): string return (s.name == plugstate.current(id) and "● " or "  ") .. s.name end,
    primary = function(s: Snapshot): string return s.name end,
    empty = "no snapshots of " .. d.name .. " yet: `:plugstate.snapshot <name>` keeps how it is now",
    on_choose = function(s: Snapshot) recalled(id, plugstate.recall(id, s.name)) end,
    audition_key = "plugstate.snapshots",
    audition = function(s: Snapshot): string | contracts.Hearing<Snapshot>
      paw.audition.try(function() plugstate.recall(id, s.name) end)
      return {
        label = s.name .. " · " .. paw.audition.through(d.part),
        keep = function() recalled(id, s) end,
      }
    end,
  }
  paw.pick(source)
end

command(
  "plugstate.recall",
  function(ctx: Context)
    local id = target()
    if not id then
      return
    end
    local name = text_of(ctx)
    if name == "" then
      plugstate.pick_snapshot(id)
      return
    end
    recalled(id, plugstate.recall(id, name))
  end,
  {
    desc = "Bring back a snapshot of the plugin's state: `plugstate.recall crunch`, or none to choose",
    complete = function(): {string}
      local id = plugstate.target()
      local names: {string} = {}
      for _, s in ipairs(id and plugstate.snapshots(id) or {}) do
        names[#names + 1] = s.name
      end
      return names
    end,
  }
)

command(
  "plugstate.recall_next",
  function(ctx: Context)
    local id = target()
    if id then
      recalled(id, plugstate.step(id, ctx.count or 1))
    end
  end,
  {desc = "Bring back the next snapshot (a count skips more)"}
)
command(
  "plugstate.recall_prev",
  function(ctx: Context)
    local id = target()
    if id then
      recalled(id, plugstate.step(id, -(ctx.count or 1)))
    end
  end,
  {desc = "Bring back the previous snapshot (a count skips more)"}
)

command(
  "plugstate.forget",
  function(ctx: Context)
    local id = target()
    if not id then
      return
    end
    local name = text_of(ctx)
    if name == "" then
      paw.notify("plugstate.forget needs the name of a snapshot", "warn")
      return
    end
    local snap, err = plugstate.forget(id, name)
    if not snap then
      paw.notify(device_name(id) .. ": " .. err, "warn")
      return
    end
    paw.notify(device_name(id) .. ": snapshot " .. snap.name .. " forgotten")
  end,
  {desc = "Forget a snapshot: `plugstate.forget crunch`"}
)

command(
  "plugstate.adapters",
  function()
    local lines: {string} = {}
    for _, a in ipairs(plugstate.adapters) do
      lines[#lines + 1] = string.format("%-8s %s", a.name, a.desc or "")
    end
    paw.notify(table.concat(lines, "\n"))
  end,
  {desc = "The kinds of plugin plugstate knows, and what of their state it sets"}
)

local function dmap(lhs: string, rhs: string, desc: string)
  paw.keymap.set(lhs, rhs, {view = "devices", desc = desc})
end
dmap("]m", "plugstate.next", "Load the next file of the folder (model, impulse response)")
dmap("[m", "plugstate.prev", "Load the previous file of the folder")
dmap("<localleader>m", "plugstate.load", "Choose a file for the plugin (model, impulse response), each heard")
dmap("<localleader>s", "plugstate.snapshot", "Keep the plugin's whole state as a snapshot")
dmap("<localleader>v", "plugstate.recall", "Bring back a snapshot, each heard")
dmap("]v", "plugstate.recall_next", "Bring back the next snapshot")
dmap("[v", "plugstate.recall_prev", "Bring back the previous snapshot")
