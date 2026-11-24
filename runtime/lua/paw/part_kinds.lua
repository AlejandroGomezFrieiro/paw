-- `paw.part_kinds`: kinds of part that extensions define, the `part`
-- family of `paw.kinds`.
--
-- A part is a part: clips, devices, a fader. A kind says what a part is
-- for, and so how it is made and how its clips are edited: a vocal part is
-- made with a singing device and its clips open in the vocal editor, a drum
-- part's in the drum grid. An extension defines one:
--
--   paw.kinds.define("part", "vocal", {
--     title = "Vocal part",            -- how it is offered and described
--     letter = "V",                     -- what the part header shows before the name
--     head = "vocal",                   -- the head of its rows (paw.heads), if not the default
--     create = function(part, args) end, -- make an ordinary part this kind
--     editor = function(clip) return true end, -- open a clip (Enter, double click, clip.edit)
--     describe = function(part) return "Kitane" end, -- a few words for K and the header
--     is = function(part) end,         -- a part that is of the kind without saying so
--   })
--
-- and from then on `:part.add vocal` (or `kind=vocal`), `:part.new` (a
-- list of every kind), the window's buttons and menus that make a part,
-- the part header, `K` and `clip.edit` all know it. The kind is the part's
-- field `kind`, saved with the project: opened without the extension, the
-- part plays as an ordinary one, its head shows the kind's name, and `K`
-- says that no extension here defines it. `:part.kind <name>` changes the
-- kind of a part, and `:part.kind` with no name clears it.
--
-- This module stays Lua for now: its port to Teal changes the stand-in
-- records of four modules that read it (paw/heads.tl, paw/insert.tl,
-- paw/nest.tl, paw/frontend/host.tl), and is open work.
local api = paw.api
local kinds = require("paw.kinds")

local M = { order = {} }

--- Offer the kind `name` in `M.order` and in the menu that makes a part,
--- or take it away when `spec` is nil.
local function offer(name, spec)
  local at
  for i, other in ipairs(M.order) do
    if other == name then at = i end
  end
  if spec and not at then
    M.order[#M.order + 1] = name
  elseif not spec and at then
    table.remove(M.order, at)
  end
  local menu = paw.frontend.menus.timeline
  for i = #menu, 1, -1 do
    if menu[i].part_kind == name then table.remove(menu, i) end
  end
  if spec then
    local label = "New " .. spec.title:sub(1, 1):lower() .. spec.title:sub(2)
    table.insert(menu, { label = label, command = "part.add kind=" .. name, part_kind = name })
  end
end

--- Offer the kind and give it to the kernel, as the kind on top changes.
local function changed(name, spec)
  offer(name, spec)
  kinds.mirror("part", name, spec and { title = spec.title, schema = spec.schema }, M.kinds:owner(name))
end

--- The kinds by name, with the extension that defined each one.
--- `paw.kinds.define("part", ...)` puts one, `paw.kinds.remove` takes it
--- away.
M.kinds = require("paw.registry").new("part_kinds", "kinds of part", { changed = changed })

local function part_of(which)
  if type(which) == "table" then return which end
  return paw.part(which)
end

-- A kind of part (see above), through `paw.kinds.define("part", name,
-- spec)`: `name` is what is typed after `:part.add` and kept in the
-- part's field `kind`. `paw.kinds.remove("part", name)` forgets it: no
-- longer offered, nor in the menus. Parts that keep it keep its name.
local function define_kind(name, spec)
  spec.name = name
  spec.title = spec.title or (name:sub(1, 1):upper() .. name:sub(2) .. " part")
  spec.letter = spec.letter or name:sub(1, 1):upper()
  M.kinds:put(name, spec)
  return spec
end
local function remove_kind(name) M.kinds:remove(name) end
local function get_kind(name) return M.kinds:get(name) end
local function owner_of(name) return M.kinds:owner(name) end
kinds.family("part", { define = define_kind, remove = remove_kind, get = get_kind, owner = owner_of })

--- The defined kinds, in the order they were defined.
function M.list()
  local out = {}
  for i, name in ipairs(M.order) do
    out[i] = M.kinds:get(name)
  end
  return out
end

--- The name of the kind of a part: the kind that it keeps. If not, a kind
--- whose `is` claims it. Nil for a usual part.
--- @type function(which: integer): string
function M.of(which)
  local id, kind
  if type(which) == "number" then
    -- One field of the part, not all of it: each part header asks on
    -- each frame. The master (id 0) has no kind.
    if which == 0 then return nil end
    local ok, k = pcall(api.part_get, which, "kind")
    if not ok then return nil end
    id, kind = which, k
  else
    local ok, t = pcall(function() return part_of(which):get() end)
    if not ok or not t or t.master then return nil end
    id, kind = t.id, t.kind
  end
  if type(kind) == "string" then return kind end
  for _, name in ipairs(M.order) do
    local spec = M.kinds:get(name)
    if spec.is and spec.is(id) then return name end
  end
end

--- A part's kind as defined, or nil (an ordinary part, or a kind that no
--- loaded extension defines).
--- @type function(which: integer): contracts.PartKind
function M.spec(which)
  local name = M.of(which)
  return name and M.kinds:get(name)
end

--- Make a part of `name`'s kind: keep the kind on it, then let the kind
--- make it what it is. `args` go to `create`. The lanes, clips and
--- devices that the part has stay.
function M.set(which, name, args)
  local spec = M.kinds:get(name)
  if not spec then error("no kind of part `" .. tostring(name) .. "`" .. M.known_words(), 2) end
  local part = part_of(which)
  api.part_set(part.id, { kind = name })
  if spec.create then spec.create(part, args or {}) end
  return part
end

--- A new part of the kind `name`. `opts.name` is its name (if not given,
--- the title of the kind without "part"), and `opts.index` its place. The
--- other options go to `create`.
function M.add(name, opts)
  opts = opts or {}
  local spec = M.kinds:get(name)
  if not spec then error("no kind of part `" .. tostring(name) .. "`" .. M.known_words(), 2) end
  local part = paw.add_part({
    name = opts.name or spec.title:gsub("%s*[Tt]rack$", ""),
    index = opts.index,
  })
  local ok, err = pcall(M.set, part, name, opts)
  if not ok then
    -- Nothing half made is left behind.
    part:remove()
    error(err, 0)
  end
  return part
end

--- ": there are vocal, drums", for messages.
function M.known_words()
  if #M.order == 0 then return ": no extension has defined one" end
  return ": there are " .. table.concat(M.order, ", ")
end

--- A few words on a part's kind, for `K` and the part header:
--- `Vocal part · Kitane`, "vocal (no extension here defines it)", or nil.
function M.describe(which)
  local name = M.of(which)
  if not name then return nil end
  local spec = M.kinds:get(name)
  if not spec then return name .. " (no extension here defines it)" end
  local words = spec.describe and spec.describe(part_of(which).id)
  if words and words ~= "" then return spec.title .. " · " .. words end
  return spec.title
end

--- Make a part an ordinary one again, as far as its kind goes: what the
--- kind made (its devices) stays, for the extension to take away.
function M.clear(which)
  local part = part_of(which)
  if api.part_get(part.id, "kind") == nil then return end
  api.part_set(part.id, "kind", nil)
end

--- Open a clip in its part's kind's editor. True when it did.
function M.open(clip)
  local data = type(clip) == "table" and clip:get() or api.clip_get(clip)
  local spec = M.spec(data.part)
  if spec and spec.editor then return spec.editor(paw.clip(data.id)) == true end
  return false
end

-- Enter, a double click and `clip.edit` ask the part's kind first.
table.insert(paw.frontend.openers, 1, M.open)

return M
