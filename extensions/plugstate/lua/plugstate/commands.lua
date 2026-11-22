-- plugstate's commands, keys and pickers.
local api = paw.api
local plugstate = require("plugstate")
local command = paw.command

local function device_name(id) return api.device_get(id).name end

local function target()
  local id, why = plugstate.target()
  if not id then paw.notify(why, "warn") end
  return id
end

local function words_of(id, slot, path)
  local a = plugstate.adapter_of(id)
  local words = a and a.describe and a.describe(path)
  return words and words ~= "" and words or nil
end

local function said(id, slot, path)
  local words = words_of(id, slot, path)
  local a = plugstate.adapter_of(id)
  local name = a and a.name_of and a.name_of(path) or plugstate.stem(path)
  paw.notify(
    string.format("%s: %s %s%s", device_name(id), slot.what or "file", name, words and ("  (" .. words .. ")") or "")
  )
end

--- Set the slot to a file, and say so.
local function load(id, slot, path)
  local ok, err = plugstate.set(id, slot.key, path)
  if not ok then return paw.notify(device_name(id) .. ": " .. tostring(err), "error") end
  -- What the slot holds now can be of another kind (a model where an
  -- impulse response was).
  said(id, plugstate.slot(id, slot.key) or slot, path)
  return true
end

--- Choose a file for a slot of a device from the library folders. Each
--- one is loaded as a trial as the selection rests on it, and heard with
--- what the track plays; Escape puts back what was there.
function plugstate.pick(id, slot, query)
  local d = api.device_get(id)
  local roots = plugstate.roots()
  paw.pick({
    title = (slot.what or "File"):gsub("^%l", string.upper) .. "s · " .. d.name,
    items = function() return plugstate.files(slot) end,
    query = query,
    format = function(f)
      local now = f.path == slot.value and "●" or " "
      return string.format("%s %-32s %s", now, f.name, f.folder)
    end,
    primary = function(f) return f.name end,
    empty = "no "
      .. (slot.what or "file")
      .. " files in "
      .. table.concat(roots, ", ")
      .. " (the folders are paw.opt.plugstate_folders)",
    on_choose = function(f) load(id, slot, f.path) end,
    audition_key = "plugstate",
    audition = function(f)
      local ok, err = paw.audition.try(function()
        local fine, why = plugstate.set(id, slot.key, f.path)
        if not fine then error(why, 0) end
        return true
      end)
      if not ok then return f.name .. " · " .. tostring(err) end
      return { label = f.name .. " · " .. paw.audition.through(d.track), keep = function() said(id, slot, f.path) end }
    end,
    preview = function(f)
      local lines = { { text = f.name, style = "Title" }, f.path }
      local words = words_of(id, slot, f.path)
      if words then lines[#lines + 1] = words end
      return lines
    end,
  })
end

--- Split `slot=<key>` from the words of a command.
local function slot_and_words(ctx)
  local slot = ctx.args.slot and tostring(ctx.args.slot) or nil
  local words = {}
  for _, w in ipairs(ctx.args) do
    words[#words + 1] = tostring(w)
  end
  return slot, table.concat(words, " ")
end

local exists = paw.api.fs_exists

command("plugstate.load", function(ctx)
  local id = target()
  if not id then return end
  local key, text = slot_and_words(ctx)
  local slot = plugstate.slot(id, key)
  if not slot then
    return paw.notify(device_name(id) .. ": no " .. (key or "file") .. " to set (`:plugstate.info` lists them)", "warn")
  end
  local path = text:gsub("^~", os.getenv("HOME") or "~")
  if slot.kind ~= "file" and text ~= "" then return load(id, slot, text) end
  if path ~= "" and exists(path) then return load(id, slot, path) end
  if path:find("/", 1, true) then return paw.notify(device_name(id) .. ": there is no file " .. path, "error") end
  -- Words: the one file they find, or the list to choose from.
  if text ~= "" then
    local found = plugstate.search(slot, text)
    if #found == 1 then return load(id, slot, found[1].path) end
  end
  plugstate.pick(id, slot, text ~= "" and text or nil)
end, {
  desc = "Load a file into the plugin (an amp model, an impulse response): `plugstate.load ~/nam/deluxe.nam`, words to find one by, or none to choose from a list where each is heard; `slot=<key>` picks which file",
  complete = "files",
})

command("plugstate.at", function(ctx)
  local id = target()
  if not id then return end
  local key, text = slot_and_words(ctx)
  local state, why
  if ctx.args.snapshot then
    state, why = plugstate.lane_snapshot(id, tostring(ctx.args.snapshot))
  else
    local slot = plugstate.slot(id, key)
    if not slot then
      return paw.notify(
        device_name(id) .. ": no " .. (key or "file") .. " to set (`:plugstate.info` lists them)",
        "warn"
      )
    end
    local value = text
    if slot.kind == "file" and not exists((text:gsub("^~", os.getenv("HOME") or "~"))) then
      local found = text ~= "" and plugstate.search(slot, text) or {}
      if #found ~= 1 then
        return paw.notify(
          device_name(id)
            .. ": "
            .. (#found == 0 and "no file found by `" .. text .. "`" or #found .. " files found: give more words"),
          "warn"
        )
      end
      value = found[1].path
    end
    state, why = plugstate.lane_state(id, slot.key, value)
  end
  if not state then return paw.notify(device_name(id) .. ": " .. tostring(why), "error") end
  local beat = paw.cursor.beat
  local ok, err = pcall(plugstate.lane_point, id, beat, state)
  if not ok then return paw.notify(device_name(id) .. ": " .. (tostring(err):gsub("^.-:%d+: ", "")), "error") end
  paw.notify(string.format("%s: %s from %s, on its state lane", device_name(id), state.name, paw.time.format(beat)))
end, {
  desc = "Change the plugin to a file or a snapshot at the cursor, on its state lane, as the song plays: `plugstate.at deluxe`, `plugstate.at slot=block2 ~/nam/x.nam`, `plugstate.at snapshot=B`",
  complete = "files",
})

local function step(n)
  return function(ctx)
    local id = target()
    if not id then return end
    local key = ctx.args.slot and tostring(ctx.args.slot) or nil
    local slot = plugstate.slot(id, key)
    if not slot or slot.kind ~= "file" then
      return paw.notify(device_name(id) .. ": no file to step through", "warn")
    end
    local f = plugstate.neighbour(slot, n * (ctx.count or 1))
    if not f then
      return paw.notify(
        device_name(id)
          .. ": no "
          .. (slot.what or "file")
          .. " files beside it or in "
          .. table.concat(plugstate.roots(), ", "),
        "warn"
      )
    end
    load(id, slot, f.path)
  end
end
command("plugstate.next", step(1), { desc = "Load the next file of the folder (a count skips more)" })
command("plugstate.prev", step(-1), { desc = "Load the previous file of the folder (a count skips more)" })

command("plugstate.info", function()
  local id = target()
  if not id then return end
  local a = plugstate.adapter_of(id)
  local lines = { device_name(id) .. " · " .. a.name .. " (" .. (a.desc or "") .. ")" }
  -- The framework of its saved state, as `:plugstate.tree` reads it.
  if api.device_get(id).plugin then
    local doc = require("plugstate.juceplugins").open(id)
    if doc then
      lines[#lines + 1] = "state: "
        .. (doc.title or doc.framework)
        .. " · "
        .. table.concat(doc:layer_names(), " › ")
        .. " · "
        .. #doc:params()
        .. " parameters in it"
    end
  end
  for _, s in ipairs(plugstate.slots(id)) do
    local value = s.value
    if value == nil or value == "" then value = "none" end
    -- The key first: it is what `slot=` takes.
    local label = s.label and s.label ~= s.key and (" (" .. s.label .. ")") or ""
    lines[#lines + 1] = string.format("%s%s: %s", s.key, label, tostring(value))
    if s.kind == "file" and s.value and s.value ~= "" then
      local words = words_of(id, s, s.value)
      if words then lines[#lines + 1] = "  " .. words end
    end
  end
  local snaps = plugstate.snapshots(id)
  if #snaps > 0 then
    local names = {}
    for _, s in ipairs(snaps) do
      names[#names + 1] = (s.name == plugstate.current(id) and "●" or "") .. s.name
    end
    lines[#lines + 1] = "snapshots: " .. table.concat(names, ", ")
  end
  paw.notify(table.concat(lines, "\n"))
end, { desc = "What the plugin holds besides its parameters (its files), and its snapshots" })

command("plugstate.files", function(ctx)
  local id = target()
  if not id then return end
  local key, text = slot_and_words(ctx)
  local slot = plugstate.slot(id, key)
  if not slot or slot.kind ~= "file" then return paw.notify(device_name(id) .. ": no file to list", "warn") end
  local found = plugstate.search(slot, text)
  local lines =
    { string.format("%d %s files%s", #found, slot.what or "", text ~= "" and (" with “" .. text .. "”") or "") }
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
end, {
  desc = "List the files the plugin can load, in the library folders: `plugstate.files clean` lists those with the word",
})

command("plugstate.snapshot", function(ctx)
  local id = target()
  if not id then return end
  local name = table.concat(ctx.args, " ")
  local kept, replaced = plugstate.snapshot(id, name)
  paw.notify(string.format("%s: snapshot %s %s", device_name(id), kept, replaced and "replaced" or "kept"))
end, {
  desc = "Keep the plugin's whole state as a named snapshot in the project: `plugstate.snapshot crunch` (none: A, B, C...)",
})

local function recalled(id, snap, err)
  if not snap then return paw.notify(device_name(id) .. ": " .. tostring(err), "warn") end
  paw.notify(device_name(id) .. ": snapshot " .. snap.name)
end

--- Choose a snapshot of the device in a picker, each heard as a trial.
function plugstate.pick_snapshot(id)
  local d = api.device_get(id)
  paw.pick({
    title = "Snapshots · " .. d.name,
    items = plugstate.snapshots(id),
    format = function(s) return (s.name == plugstate.current(id) and "● " or "  ") .. s.name end,
    primary = function(s) return s.name end,
    empty = "no snapshots of " .. d.name .. " yet: `:plugstate.snapshot <name>` keeps how it is now",
    on_choose = function(s) recalled(id, plugstate.recall(id, s.name)) end,
    audition_key = "plugstate.snapshots",
    audition = function(s)
      paw.audition.try(function() plugstate.recall(id, s.name) end)
      return { label = s.name .. " · " .. paw.audition.through(d.track), keep = function() recalled(id, s) end }
    end,
  })
end

command("plugstate.recall", function(ctx)
  local id = target()
  if not id then return end
  local name = table.concat(ctx.args, " ")
  if name == "" then return plugstate.pick_snapshot(id) end
  recalled(id, plugstate.recall(id, name))
end, {
  desc = "Bring back a snapshot of the plugin's state: `plugstate.recall crunch`, or none to choose",
  complete = function()
    local id = plugstate.target()
    local names = {}
    for _, s in ipairs(id and plugstate.snapshots(id) or {}) do
      names[#names + 1] = s.name
    end
    return names
  end,
})

command("plugstate.recall_next", function(ctx)
  local id = target()
  if id then recalled(id, plugstate.step(id, ctx.count or 1)) end
end, { desc = "Bring back the next snapshot (a count skips more)" })
command("plugstate.recall_prev", function(ctx)
  local id = target()
  if id then recalled(id, plugstate.step(id, -(ctx.count or 1))) end
end, { desc = "Bring back the previous snapshot (a count skips more)" })

command("plugstate.forget", function(ctx)
  local id = target()
  if not id then return end
  local name = table.concat(ctx.args, " ")
  if name == "" then return paw.notify("plugstate.forget needs the name of a snapshot", "warn") end
  local snap, err = plugstate.forget(id, name)
  if not snap then return paw.notify(device_name(id) .. ": " .. err, "warn") end
  paw.notify(device_name(id) .. ": snapshot " .. snap.name .. " forgotten")
end, { desc = "Forget a snapshot: `plugstate.forget crunch`" })

command("plugstate.adapters", function()
  local lines = {}
  for _, a in ipairs(plugstate.adapters) do
    lines[#lines + 1] = string.format("%-8s %s", a.name, a.desc or "")
  end
  paw.notify(table.concat(lines, "\n"))
end, { desc = "The kinds of plugin plugstate knows, and what of their state it sets" })

local function dmap(lhs, rhs, desc) paw.keymap.set(lhs, rhs, { view = "devices", desc = desc }) end
dmap("]m", "plugstate.next", "Load the next file of the folder (model, impulse response)")
dmap("[m", "plugstate.prev", "Load the previous file of the folder")
dmap("<localleader>m", "plugstate.load", "Choose a file for the plugin (model, impulse response), each heard")
dmap("<localleader>s", "plugstate.snapshot", "Keep the plugin's whole state as a snapshot")
dmap("<localleader>v", "plugstate.recall", "Bring back a snapshot, each heard")
dmap("]v", "plugstate.recall_next", "Bring back the next snapshot")
dmap("[v", "plugstate.recall_prev", "Bring back the previous snapshot")
