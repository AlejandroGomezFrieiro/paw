-- Song sections: named stretches of the timeline. A section has a name and a
-- start, and runs to the start of the next one; the last runs to the end of
-- the project (at least one bar).
--
-- They are kept in the project, as `project.meta.sections`, a list of
-- `{ name, start }` sorted by start, so they are saved, loaded and undone
-- with everything else. `sections.changed` is emitted whenever the list
-- changes, by these calls, by undo and redo, or by loading a project.
--
--   local sections = require("sections")
--   sections.add("Chorus", 64)
--   sections.list()          -- { { index, name, start, finish }, ... }
--   sections.at(70).name     -- "Chorus"
--   sections.rename("Chorus", "Hook")   sections.remove(1)
--
-- Arranging by section lives in `sections.arrange` and is re-exported here:
-- `move`, `duplicate`, `delete`, `yank`, `insert`, `copy`.
local api = paw.api
local M = {}
local EPS = 1e-9
local KEY = "sections"

-- Stored --------------------------------------------------------------------------

--- The stored list, cleaned up and sorted: { { name, start } }.
local function read()
  local meta = api.project_get().meta
  local raw = type(meta) == "table" and meta[KEY] or nil
  local out = {}
  if type(raw) == "table" then
    for _, s in ipairs(raw) do
      if type(s) == "table" and type(s.start) == "number" then
        out[#out + 1] = { name = tostring(s.name or ""), start = s.start }
      end
    end
  end
  table.sort(out, function(a, b) return a.start < b.start end)
  return out
end

--- Replace the stored list. Sections at the same beat collapse into the first.
local function write(list)
  table.sort(list, function(a, b) return a.start < b.start end)
  local stored = {}
  for _, s in ipairs(list) do
    local last = stored[#stored]
    if not (last and math.abs(last.start - s.start) < EPS) then
      stored[#stored + 1] = { name = s.name, start = math.max(0, s.start) }
    end
  end
  local meta = api.project_get().meta
  if type(meta) ~= "table" then meta = {} end
  meta[KEY] = stored
  api.project_set("meta", meta)
end
M.write = write

--- Where the last section ends: the end of the project, but at least a bar
--- after it starts.
local function last_finish(start) return math.max(paw.project.length or 0, start + paw.time.bar(start)) end

--- Every section, in order: { index, name, start, finish }.
function M.list()
  local list = read()
  for i, s in ipairs(list) do
    s.index = i
    s.finish = list[i + 1] and list[i + 1].start or last_finish(s.start)
  end
  return list
end

--- The section a beat lies in, or nil before the first one. The last
--- section takes in everything after it.
function M.at(beat)
  local found
  for _, s in ipairs(M.list()) do
    if s.start <= beat + EPS then
      found = s
    else
      break
    end
  end
  return found
end

--- The section under the edit cursor.
function M.current() return M.at(paw.cursor.beat) end

--- A section by name: exactly, then ignoring case, then by the start of the
--- name. Nil when none matches.
function M.find(name)
  local list, wanted = M.list(), tostring(name):lower()
  for _, s in ipairs(list) do
    if s.name == name then return s end
  end
  for _, s in ipairs(list) do
    if s.name:lower() == wanted then return s end
  end
  for _, s in ipairs(list) do
    if s.name:lower():sub(1, #wanted) == wanted then return s end
  end
end

--- A section from what a caller may give: an index, a name, a section
--- table, or nil for the one under the cursor.
function M.get(which)
  if which == nil then return M.current() end
  if type(which) == "table" then return which.start and M.at(which.start) or nil end
  if type(which) == "number" then return M.list()[which] end
  return M.find(which)
end

local function need(which)
  local s = M.get(which)
  if not s then error(which == nil and "no section at the cursor" or "no section `" .. tostring(which) .. "`", 0) end
  return s
end
M.need = need

--- The start of the next section after a beat, or of the previous one before it.
function M.next_start(beat)
  for _, s in ipairs(M.list()) do
    if s.start > beat + EPS then return s.start end
  end
end

function M.prev_start(beat)
  local found
  for _, s in ipairs(M.list()) do
    if s.start < beat - EPS then found = s.start end
  end
  return found
end

-- Changing them --------------------------------------------------------------------

--- Add a section starting at a beat (the cursor's by default). Returns the
--- new section; fails if one starts there already.
function M.add(name, start)
  start = math.max(0, start or paw.cursor.beat)
  name = tostring(name or "")
  if name == "" then error("a section needs a name", 0) end
  local list = read()
  for _, s in ipairs(list) do
    if math.abs(s.start - start) < EPS then error("section `" .. s.name .. "` starts there already", 0) end
  end
  list[#list + 1] = { name = name, start = start }
  write(list)
  return M.at(start)
end

function M.rename(which, name)
  local s = need(which)
  name = tostring(name or "")
  if name == "" then error("a section needs a name", 0) end
  local list = read()
  list[s.index].name = name
  write(list)
end

--- Remove a section's marker; what is on the timeline stays where it is and
--- becomes part of the section before.
function M.remove(which)
  local s = need(which)
  local list = read()
  table.remove(list, s.index)
  write(list)
end

--- Move where a section starts, leaving the timeline alone.
function M.set_start(which, start)
  local s = need(which)
  local list = read()
  for i, other in ipairs(list) do
    if i ~= s.index and math.abs(other.start - start) < EPS then
      error("section `" .. other.name .. "` starts there already", 0)
    end
  end
  list[s.index].start = math.max(0, start)
  write(list)
end

--- Replace every section at once with a list of { name, start }.
function M.set(list)
  local copy = {}
  for i, s in ipairs(list) do
    copy[i] = { name = tostring(s.name), start = s.start }
  end
  write(copy)
end

-- Events ---------------------------------------------------------------------------

local function fingerprint(list)
  local parts = {}
  for i, s in ipairs(list) do
    parts[i] = string.format("%.9g\0%s", s.start, s.name)
  end
  return table.concat(parts, "\1")
end

local seen = fingerprint(read())
local function check()
  local now = fingerprint(read())
  if now == seen then return end
  seen = now
  paw.emit("sections.changed", { sections = M.list() })
  api.ui_redraw()
end
paw.on("project.changed", check)
paw.on("project.loaded", check)

-- `sections.move`, `sections.duplicate` and the rest come from `sections.arrange`.
return setmetatable(M, { __index = function(_, key) return require("sections.arrange")[key] end })
