-- `paw.part_kinds`: kinds of part that extensions define.
--
-- A part is a part: clips, devices, a fader. A kind says what a part is
-- for, and so how it is made and how its clips are edited: a vocal part is
-- made with a singing device and its clips open in the vocal editor, a drum
-- part's in the drum grid. An extension defines one:
--
--   paw.part_kinds.define("vocal", {
--     title = "Vocal part",            -- how it is offered and described
--     letter = "V",                     -- what the part header shows before the name
--     create = function(part, args) end, -- make an ordinary part this kind
--     editor = function(clip) return true end, -- open a clip (Enter, double click, clip.edit)
--     describe = function(part) return "Kitane" end, -- a few words for K and the header
--     is = function(part) end,         -- a part that is of the kind without saying so
--   })
--
-- and from then on `:part.add vocal` (or `kind=vocal`), `:part.new` (a
-- list of every kind), the window's buttons and menus that make a part,
-- the part header, `K` and `clip.edit` all know it. The kind is kept in the
-- part's `meta.kind`, saved with the project: opened without the
-- extension, the part is an ordinary one, and `K` says which kind it was.
local api = paw.api

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

--- The kinds by name, with the extension that defined each one. `define`
--- puts one, `remove` takes it away.
M.kinds = require("paw.registry").new("part_kinds", "kinds of part", { changed = offer })

local function part_of(which)
  if type(which) == "table" then return which end
  return paw.part(which)
end

--- Define a kind of part (see above). `name` is a word: what is typed
--- after `:part.add` and kept in the part's `meta.kind`.
--- @type function(name: string, spec: contracts.PartKind): contracts.PartKind
function M.define(name, spec)
  if type(name) ~= "string" or not name:match("^[%w_]+$") then error("a kind of part is named by a word", 2) end
  if type(spec) ~= "table" then error("part_kinds.define takes a name and a table", 2) end
  spec.name = name
  spec.title = spec.title or (name:sub(1, 1):upper() .. name:sub(2) .. " part")
  spec.letter = spec.letter or name:sub(1, 1):upper()
  M.kinds:put(name, spec)
  return spec
end

--- Forget a kind: no longer offered, nor in the menus. Parts that keep
--- it are ordinary parts again until something defines it.
function M.remove(name) M.kinds:remove(name) end

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
function M.of(which)
  local id, meta
  if type(which) == "number" then
    -- One entry of the part, not all of it: each part header asks on
    -- each frame. The master (id 0) has no kind.
    if which == 0 then return nil end
    local ok, m = pcall(api.part_get, which, "meta")
    if not ok then return nil end
    id, meta = which, m
  else
    local ok, t = pcall(function() return part_of(which):get() end)
    if not ok or not t or t.master then return nil end
    id, meta = t.id, t.meta
  end
  meta = type(meta) == "table" and meta or {}
  if type(meta.kind) == "string" then return meta.kind end
  for _, name in ipairs(M.order) do
    local spec = M.kinds:get(name)
    if spec.is and spec.is(id) then return name end
  end
end

--- A part's kind as defined, or nil (an ordinary part, or a kind that no
--- loaded extension defines).
function M.spec(which)
  local name = M.of(which)
  return name and M.kinds:get(name)
end

--- Make a part of `name`'s kind: keep the kind on it, then let the kind
--- make it what it is. `args` go to `create`.
function M.set(which, name, args)
  local spec = M.kinds:get(name)
  if not spec then error("no kind of part `" .. tostring(name) .. "`" .. M.known_words(), 2) end
  local part = part_of(which)
  local meta = part.meta or {}
  meta.kind = name
  part.meta = meta
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
  local meta = part.meta or {}
  if meta.kind == nil then return end
  meta.kind = nil
  -- An empty table would cross over as a list; one key keeps it a table.
  if next(meta) == nil then meta = { kind_was = true } end
  part.meta = meta
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

-- The kind's letter in the part header, in the free column before the name.
paw.ui.layer("arrange", "header", "part_kinds", 20, function(c)
  local spec = M.spec(c.part)
  if spec then c.buf:text(c.x, c.y, spec.letter:sub(1, 1), "PartIndex") end
end)

return M
