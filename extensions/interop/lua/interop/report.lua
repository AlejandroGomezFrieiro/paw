-- What an import or export could not carry over, grouped by kind.
--
--   report:add("Plugins not installed here", "Guitar: VST3: Archetype (Neural DSP)")
--   report:lines()   -- for showing to the user
local Report = {}
Report.__index = Report

local M = {}

function M.new(title)
  return setmetatable({ title = title, groups = {}, order = {} }, Report)
end

local function group(self, name)
  local g = self.groups[name]
  if not g then
    g = { name = name, items = {}, count = 0 }
    self.groups[name] = g
    self.order[#self.order + 1] = name
  end
  return g
end

--- Add one thing that was not carried over, under a group name.
function Report:add(name, text)
  local g = group(self, name)
  g.count = g.count + 1
  g.items[#g.items + 1] = text
end

--- Count things of a group without listing each (`n` defaults to 1); the
--- same `text` is listed once with its total.
function Report:count(name, text, n)
  local g = group(self, name)
  g.count = g.count + (n or 1)
  g.totals = g.totals or {}
  if not g.totals[text] then
    g.totals[text] = 0
    g.items[#g.items + 1] = text
  end
  g.totals[text] = g.totals[text] + (n or 1)
end

--- True when nothing was left out.
function Report:empty() return #self.order == 0 end

--- The groups as plain data: { { name, count, items = { "text", ... } } }.
function Report:data()
  local out = {}
  for _, name in ipairs(self.order) do
    local g = self.groups[name]
    local items = {}
    for i, text in ipairs(g.items) do
      local total = g.totals and g.totals[text]
      items[i] = total and total > 1 and string.format("%s (%d)", text, total) or text
    end
    out[#out + 1] = { name = name, count = g.count, items = items }
  end
  return out
end

--- Lines of text, at most `limit` items per group (default 12).
function Report:lines(limit)
  limit = limit or 12
  local lines = {}
  if self.title then lines[#lines + 1] = self.title end
  if self:empty() then
    lines[#lines + 1] = "Everything was carried over."
    return lines
  end
  for _, g in ipairs(self:data()) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("%s (%d)", g.name, g.count)
    for i, text in ipairs(g.items) do
      if i > limit then
        lines[#lines + 1] = string.format("  ... and %d more", #g.items - limit)
        break
      end
      lines[#lines + 1] = "  " .. text
    end
  end
  return lines
end

function Report:text(limit) return table.concat(self:lines(limit), "\n") end

return M
