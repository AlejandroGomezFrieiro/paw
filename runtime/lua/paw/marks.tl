-- Marks of the ruler in namespaces, as Neovim's extmarks are: each owner
-- (paw, an extension, the user) puts its marks in a namespace of its own,
-- and the ruler (paw/ruler.tl) places them all with one compositor.
--
--   local ns = paw.marks.namespace("cues")
--   paw.marks.set(ns, 32, { sign = "◆", label = "drop", priority = 30 })
--   paw.ruler.route("cues", "row:regions")
--
-- A mark has a sign, a label, a priority and a style, and a mark with
-- `to` colors a stretch of time (contracts.RulerMark). `paw.ext.unload`
-- removes the namespaces of an extension with their marks.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local registry = require("paw.registry")
local type contracts = require("paw.contracts")

local type Mark = contracts.RulerMark
local type Namespace = contracts.RulerNamespace

local record M
  --- The namespaces by name, with the extension that made or last
  --- changed each one.
  namespaces: registry.Registry<Namespace>
end

M.namespaces = registry.new("marks", "namespaces of ruler marks", {changed = function() api.ui_redraw() end})

-- The ids of the namespaces, from 1, and the name of each id. A name keeps
-- its id after its namespace goes, so that an id never names two
-- namespaces.
local ids: {string: integer} = {}
local names: {string} = {}
local next_mark = 0

--- A copy of a mark, which the ruler places at the window's time.
function M.copy(m: Mark): Mark
  return {
    id = m.id,
    ns = m.ns,
    beat = m.beat,
    to = m.to,
    sign = m.sign,
    label = m.label,
    whole = m.whole,
    priority = m.priority,
    style = m.style,
    label_style = m.label_style,
    edge = m.edge,
    soft = m.soft,
    restyle = m.restyle,
    row = m.row,
    over = m.over,
    line = m.line,
    text = m.text,
    kind = m.kind,
    ref = m.ref,
    cmd = m.cmd,
  }
end

--- The namespace that `ns` names: its id or its name. An error names a
--- namespace that does not exist.
function M.of(ns: integer | string): Namespace
  local name = ns is integer and names[ns] or ns as string
  local found = name and M.namespaces:get(name)
  if not found then
    error("no namespace of marks `" .. tostring(ns) .. "`", 3)
  end
  return found
end

--- Make a namespace, or give the id of the namespace of that name. `spec`
--- can give its `route` (`"row:name"` or `"over:name"`, else
--- `"over:bars"`), the `priority` of its marks that give none, its
--- `glyphs` and `styles`, and a `source(ctx)` that computes its marks for
--- the time in sight. A spec makes the namespace again, with no marks.
---   local ns = paw.marks.namespace("cues", { route = "row:regions" })
function M.namespace(name: string, spec?: Namespace): integer
  assert(type(name) == "string" and name ~= "", "usage: paw.marks.namespace(name, { route = \"row:regions\" })")
  local found = M.namespaces:get(name)
  if found and not spec then
    return found.id
  end
  if not ids[name] then
    names[#names + 1] = name
    ids[name] = #names
  end
  local ns: Namespace = spec or {}
  ns.name, ns.id = name, ids[name]
  ns.route = ns.route or "over:bars"
  ns.priority = ns.priority or 10
  ns.glyphs, ns.styles, ns.marks = ns.glyphs or {}, ns.styles or {}, ns.marks or {}
  M.namespaces:put(name, ns)
  return ns.id
end

--- Put a mark at `beat` of the song in namespace `ns` (its id or name), or
--- change the mark with the id `spec.id`. The fields of `spec` are those
--- of a mark (`sign`, `label`, `priority`, `style`, `to`, `row` or
--- `over`, ...). The table becomes the mark. Gives the id of the mark.
---   paw.marks.set(ns, 32, { sign = "◆", label = "drop" })
function M.set(ns: integer | string, beat: number, spec?: Mark): integer
  local space = M.of(ns)
  assert(type(beat) == "number", "usage: paw.marks.set(ns, beat, { sign = \"◆\", label = \"drop\" })")
  local mark: Mark = spec or {}
  if not mark.id then
    next_mark = next_mark + 1
    mark.id = next_mark
  end
  mark.ns, mark.beat = space.name, beat
  space.marks[mark.id] = mark
  api.ui_redraw()
  return mark.id
end

--- Remove the mark `id` of namespace `ns`. Gives whether it was there.
function M.del(ns: integer | string, id: integer): boolean
  local space = M.of(ns)
  local had = space.marks[id] ~= nil
  space.marks[id] = nil
  api.ui_redraw()
  return had
end

--- Remove the marks of namespace `ns`: all of them, or those that start
--- from `from` up to `to` (beats of the song).
function M.clear(ns: integer | string, from?: number, to?: number)
  local space = M.of(ns)
  for id, mark in pairs(space.marks) do
    if (not from or mark.beat >= from) and (not to or mark.beat < to) then
      space.marks[id] = nil
    end
  end
  api.ui_redraw()
end

--- The marks of namespace `ns` that `paw.marks.set` put, in the order of
--- their beats.
function M.get(ns: integer | string): {Mark}
  local out: {Mark} = {}
  for _, mark in pairs(M.of(ns).marks) do
    out[#out + 1] = mark
  end
  table.sort(
    out,
    function(a: Mark, b: Mark): boolean
      if a.beat ~= b.beat then
        return a.beat < b.beat
      end
      return a.id < b.id
    end
  )
  return out
end

return M
