-- What an import or export could not carry over, grouped by kind.
--
--   report:add("Plugins not installed here", "Guitar: VST3: Archetype (Neural DSP)")
--   report:lines()   -- for showing to the user
local record M
  --- One group of a report as plain data: its name, how many things it
  --- holds, and the text of each (with its total when it was counted).
  record GroupData
    name: string
    count: integer
    items: {string}
  end

  --- The list of what did not carry over.
  record Report
    title: string
    --- The groups by name.
    groups: {string: Group}
    --- The names of the groups in the order they were first used.
    order: {string}

    add: function(self: Report, name: string, text: string)
    count: function(self: Report, name: string, text: string, n?: integer)
    empty: function(self: Report): boolean
    data: function(self: Report): {GroupData}
    lines: function(self: Report, limit?: integer): {string}
    text: function(self: Report, limit?: integer): string
  end

  --- One group: the texts in the order they came, and for counted texts
  --- the total of each (a text is listed once).
  record Group
    name: string
    items: {string}
    count: integer
    totals: {string: integer}
  end
end

local type Report = M.Report
local type Group = M.Group

local Report_meta: metatable<Report> = {__index = M.Report}

function M.new(title: string): Report
  return setmetatable({title = title, groups = {}, order = {}} as Report, Report_meta)
end

local function group(self: Report, name: string): Group
  local g = self.groups[name]
  if not g then
    g = {name = name, items = {}, count = 0}
    self.groups[name] = g
    self.order[#self.order + 1] = name
  end
  return g
end

--- Add one thing that was not carried over, under a group name.
function M.Report:add(name: string, text: string)
  local g = group(self, name)
  g.count = g.count + 1
  g.items[#g.items + 1] = text
end

--- Count things of a group without listing each (`n` defaults to 1); the
--- same `text` is listed once with its total.
function M.Report:count(name: string, text: string, n?: integer)
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
function M.Report:empty(): boolean
  return #self.order == 0
end

--- The groups as plain data: { { name, count, items = { "text", ... } } }.
function M.Report:data(): {M.GroupData}
  local out: {M.GroupData} = {}
  for _, name in ipairs(self.order) do
    local g = self.groups[name]
    local items: {string} = {}
    for i, text in ipairs(g.items) do
      local total = g.totals and g.totals[text]
      items[i] = total and total > 1 and string.format("%s (%d)", text, total) or text
    end
    out[#out + 1] = {name = name, count = g.count, items = items}
  end
  return out
end

--- Lines of text, at most `limit` items per group (default 12).
function M.Report:lines(limit?: integer): {string}
  limit = limit or 12
  local lines: {string} = {}
  if self.title then
    lines[#lines + 1] = self.title
  end
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

function M.Report:text(limit?: integer): string
  return table.concat(self:lines(limit), "\n")
end

return M
