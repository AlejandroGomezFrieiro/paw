-- Annotations, as LSP's inlay hints: a short label a server (or any plugin)
-- puts on something with an address: a loudness readout on a mixer strip,
-- a word on a device, a mark on a stretch of time. Kept by namespace and
-- document as diagnostics are, and drawn by the views that can place them.
--
--   paw.annotation.set("mixcheck", "paw://project#mix", {
--     { location = { uri = "paw://part/3" }, label = "-9.1 LUFS", kind = "loudness" },
--   })
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local A = require("paw.address")
local util = require("paw.util")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")

--- A label as `paw.annotation.set` takes it: the address it is on, as a
--- text or a location, and the text to show.
local record Entry
  location: string | contracts.Location
  label: string
  kind: string
  tooltip: string
end

--- A label that is kept: `Entry` with its namespace, and a location.
local record Annotation
  namespace: string
  location: contracts.Location
  label: string
  kind: string
  tooltip: string
end

--- The payload of `annotation.changed`: the namespace and the document.
local record Changed
  namespace: string
  document: string
end

--- What a layer of a mixer strip or of a device gets (`paw.ui.layer`).
local record Cell
  buf: contracts.Buf
  x: integer
  y: integer
  width: integer
  part: integer
  device: integer
end

local record Paw is partial.Paw
  ui: UiModule
end
local paw = (_G as {string: Paw}).paw

local record M
  type Entry = Entry
  type Annotation = Annotation
  type Changed = Changed

  --- The event `annotation.changed`: annotations changed.
  changed: events.Event<Changed>
end

M.changed = events.event("annotation.changed")

-- store[namespace][document] = list
local store: {string: {string: {Annotation}}} = {}

--- Publish the labels of `namespace` in a document. They replace its old labels there.
function M.set(namespace: string, doc: string, list?: {Entry})
  local out: {Annotation} = {}
  for _, a in ipairs(list or {}) do
    local where = a.location
    local loc: contracts.Location
    if where is string then
      loc = {uri = where}
    else
      loc = where
    end
    if loc and a.label then
      out[#out + 1] = {
        namespace = namespace, location = loc, label = tostring(a.label), kind = a.kind, tooltip = a.tooltip
      }
    end
  end
  store[namespace] = store[namespace] or {}
  store[namespace][doc] = #out > 0 and out or nil
  events.emit(M.changed, {namespace = namespace, document = doc})
  api.ui_redraw()
end

--- Forget the labels of a namespace, of one document or all. With no
--- namespace, forget the labels of all namespaces.
function M.reset(namespace?: string, doc?: string)
  for ns, docs in pairs(store) do
    if not namespace or ns == namespace then
      if doc == nil then
        store[ns] = nil
      else
        docs[doc] = nil
      end
    end
  end
  api.ui_redraw()
end

--- The labels on an address exactly (`exact`), or on it and what it holds.
function M.get(uri?: string, exact?: boolean): {Annotation}
  local out: {Annotation} = {}
  for _, docs in pairs(store) do
    for _, list in pairs(docs) do
      for _, a in ipairs(list) do
        if not uri or a.location.uri == uri or (not exact and A.within(a.location.uri, uri)) then
          out[#out + 1] = a
        end
      end
    end
  end
  return out
end

-- Where they are drawn: a part's label on its mixer strip, over the peak
-- readout (the meter still holds the peak); a
-- device's after its name in the device panel; stretches of time on the
-- arrange view's ruler.
paw.ui.layer(
  "mixer",
  "strip_foot",
  "annotations",
  40,
  function(c: Cell)
    if not next(store) then
      return
    end
    local list = M.get(A.part(c.part), true)
    if #list > 0 and c.width > 1 then
      local text = list[1].label
      if api.str_width(text) > c.width then
        text = util.fit(text, c.width)
      end
      c.buf:fill(c.x, c.y, c.width, 1, " ", nil)
      c.buf:text(c.x + c.width - api.str_width(text), c.y, text, "Annotation")
    end
  end
)
paw.ui.layer(
  "inspector",
  "device",
  "annotations",
  40,
  function(c: Cell)
    if not next(store) then
      return
    end
    local list = M.get(A.device(c.device), true)
    if #list > 0 and c.width > #list[1].label + 2 then
      c.buf:text(c.x + c.width - api.str_width(list[1].label), c.y, list[1].label, "Annotation")
    end
  end
)
local arrange = paw.ui.views:get("arrange") as contracts.ArrangeView
arrange.layers.annotations = function(_: contracts.ArrangeView, c: contracts.ArrangeLayer)
  if not next(store) then
    return
  end
  for _, a in ipairs(M.get()) do
    local t = a.location.selector and a.location.selector.time
    if t then
      local x = c.x(t[1])
      if x >= 0 and x < c.ruler.width then
        local text = util.fit(a.label, math.max(1, c.ruler.width - x)):gsub("%s+$", "")
        c.ruler:text(x, 0, text, "Annotation")
      end
    end
  end
end

events.on(
  kernel.project_loaded,
  function()
    if next(store) then
      M.reset()
    end
  end
)

return M
