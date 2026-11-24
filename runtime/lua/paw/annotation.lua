-- Annotations, as LSP's inlay hints: a short label a server (or any plugin)
-- puts on something with an address: a loudness readout on a mixer strip,
-- a word on a device, a mark on a stretch of time. Kept by namespace and
-- document as diagnostics are, and drawn by the views that can place them.
--
--   paw.annotation.set("mixcheck", "paw://project#mix", {
--     { location = { uri = "paw://part/3" }, label = "-9.1 LUFS", kind = "loudness" },
--   })
local api = paw.api
local A = paw.address

local M = {}

local store = {} -- store[namespace][document] = list

--- Publish the labels of `namespace` in a document. They replace its old labels there.
function M.set(namespace, doc, list)
  local out = {}
  for _, a in ipairs(list or {}) do
    local loc = type(a.location) == "string" and { uri = a.location } or a.location
    if loc and a.label then
      out[#out + 1] =
        { namespace = namespace, location = loc, label = tostring(a.label), kind = a.kind, tooltip = a.tooltip }
    end
  end
  store[namespace] = store[namespace] or {}
  store[namespace][doc] = #out > 0 and out or nil
  paw.emit("annotation.changed", { namespace = namespace, document = doc })
  api.ui_redraw()
end

--- Forget the labels of a namespace, of one document or all. With no
--- namespace, forget the labels of all namespaces.
function M.reset(namespace, doc)
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
function M.get(uri, exact)
  local out = {}
  for _, docs in pairs(store) do
    for _, list in pairs(docs) do
      for _, a in ipairs(list) do
        if not uri or a.location.uri == uri or (not exact and A.within(a.location.uri, uri)) then out[#out + 1] = a end
      end
    end
  end
  return out
end

-- Where they are drawn: a part's label on its mixer strip, over the peak
-- readout (the meter still holds the peak); a
-- device's after its name in the device panel; stretches of time on the
-- arrange view's ruler.
paw.ui.layer("mixer", "strip_foot", "annotations", 40, function(c)
  if not next(store) then return end
  local list = M.get(A.part(c.part), true)
  if #list > 0 and c.width > 1 then
    local text = list[1].label
    if api.str_width(text) > c.width then text = paw.util.fit(text, c.width) end
    c.buf:fill(c.x, c.y, c.width, 1, " ", nil)
    c.buf:text(c.x + c.width - api.str_width(text), c.y, text, "Annotation")
  end
end)
paw.ui.layer("inspector", "device", "annotations", 40, function(c)
  if not next(store) then return end
  local list = M.get(A.device(c.device), true)
  if #list > 0 and c.width > #list[1].label + 2 then
    c.buf:text(c.x + c.width - api.str_width(list[1].label), c.y, list[1].label, "Annotation")
  end
end)
paw.ui.views:get("arrange").layers.annotations = function(_, c)
  if not next(store) then return end
  for _, a in ipairs(M.get()) do
    local t = a.location.selector and a.location.selector.time
    if t then
      local x = c.x(t[1])
      if x >= 0 and x < c.ruler.width then
        c.ruler:text(x, 0, paw.util.fit(a.label, math.max(1, c.ruler.width - x)):gsub("%s+$", ""), "Annotation")
      end
    end
  end
end

paw.on("project.loaded", function()
  if next(store) then M.reset() end
end)

return M
