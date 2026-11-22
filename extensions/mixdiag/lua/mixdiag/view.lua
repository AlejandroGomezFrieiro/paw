-- The list of findings (when there is no picker), and the strip of marks
-- drawn above the arrange view, lined up with its timeline.
local api = paw.api
local M = {}

local styles = { error = "MixError", warn = "MixWarn", info = "MixInfo", hint = "MixHint" }
local glyphs = { error = "E", warn = "W", info = "I", hint = "H" }
local rank = { error = 1, warn = 2, info = 3, hint = 4 }

paw.ui.hl("MixError", "Error")
paw.ui.hl("MixWarn", "Warn")
paw.ui.hl("MixInfo", "Title")
paw.ui.hl("MixHint", "Dim")

-- The report ----------------------------------------------------------------------

-- What was measured and what it came to, then the findings to go to. It
-- reads the findings afresh each time it is drawn, so a measurement that
-- ends while it is open shows at once.
local list = { title = "Mix report", items = {}, at = 1, scroll = 0, modal = true }

--- The report's head: what is being measured or was, the numbers, and the tally.
local function head(mixdiag)
  local target = mixdiag.target()
  local lines = {}
  local aim = target.integrated
      and string.format("target %s: %g LUFS, %g dBTP", target.name, target.integrated, target.true_peak or 0)
    or "target: " .. target.name
  if mixdiag.job then
    lines[1] = {
      string.format(
        "measuring the %s… %d%%",
        mixdiag.job.range.label,
        math.floor((mixdiag.job.progress or 0) * 100 + 0.5)
      ),
      "Warn",
    }
  elseif mixdiag.result then
    local range = mixdiag.range_measured and mixdiag.range_measured.label or "mix"
    lines[1] = {
      "the " .. range .. (mixdiag.stale() and ", measured before the last change" or ""),
      mixdiag.stale() and "Warn" or "Title",
    }
  else
    lines[1] = { "nothing measured yet", "Dim" }
  end
  lines[2] = {
    mixdiag.result and mixdiag.summary(mixdiag.result) or "a measures the song, l the loop, t the cursor's track",
    mixdiag.result and "Normal" or "Dim",
  }
  local counts = {}
  for _, f in ipairs(mixdiag.findings or {}) do
    counts[f.severity] = (counts[f.severity] or 0) + 1
  end
  local tally = {}
  for _, s in ipairs(mixdiag.severities) do
    if counts[s] then tally[#tally + 1] = counts[s] .. " " .. s end
  end
  lines[3] =
    { (mixdiag.result and (#tally > 0 and table.concat(tally, ", ") or "no findings") .. "   " or "") .. aim, "Dim" }
  return lines
end

function list:render(buf)
  local mixdiag = require("mixdiag")
  self.items = mixdiag.result and mixdiag.items() or {}
  self.at = paw.util.clamp(self.at, 1, math.max(1, #self.items))
  local top = head(mixdiag)
  for i, line in ipairs(top) do
    buf:text(1, i - 1, paw.util.fit(line[1], math.max(1, buf.width - 2)), line[2])
  end
  buf:fill(0, #top, buf.width, 1, paw.draw.g.h, "Rule")
  local first = #top + 1
  local rows = buf.height - first - 1
  self.first, self.rows = first, rows
  if self.at < self.scroll + 1 then self.scroll = self.at - 1 end
  if self.at > self.scroll + rows then self.scroll = self.at - rows end
  if mixdiag.result and #self.items == 0 then buf:text(1, first, "no findings", "Dim") end
  for row = 0, rows - 1 do
    local i = row + 1 + self.scroll
    local item = self.items[i]
    if not item then break end
    if i == self.at then buf:fill(0, first + row, buf.width, 1, " ", "Visual") end
    buf:text(1, first + row, paw.util.fit(item.text, math.max(1, buf.width - 2)), styles[item.severity] or "Normal")
  end
  buf:text(
    1,
    buf.height - 1,
    paw.util.fit(
      "j/k move  Enter go there  a measure the song  l the loop  t the track  T target  q close",
      buf.width - 2
    ),
    "Dim"
  )
end

--- Go to the finding chosen. Floating, the report closes first; in a window
--- of its own it stays open beside the arrange view.
local function go()
  local item = list.items[list.at]
  if not (item and item.finding) then return end
  if paw.ui.float and paw.ui.float.name == "mixdiag" then paw.ui.close() end
  paw.ui.focus("arrange")
  require("mixdiag").jump(item.finding)
end

local function measure(scope)
  return function()
    local ok, err = pcall(require("mixdiag").analyze, scope)
    if not ok then paw.notify("mix: " .. tostring(err), "warn") end
  end
end

local actions = {
  j = function() list.at = list.at + 1 end,
  k = function() list.at = list.at - 1 end,
  g = function() list.at = 1 end,
  G = function() list.at = #list.items end,
  ["<CR>"] = go,
  a = measure("song"),
  l = measure("loop"),
  t = measure("track"),
  T = function() paw.cmd("mix.target") end,
  q = function() paw.ui.close() end,
  -- Escape closes the report only while it floats, as a prompt does; in a
  -- window of its own it stays, and `q` closes it.
  ["<Esc>"] = function()
    if paw.ui.float then paw.ui.close() end
  end,
}
actions["<Down>"], actions["<Up>"], actions["<Enter>"] = actions.j, actions.k, actions["<CR>"]

function list:on_key(key)
  local action = actions[key]
  if action then action() end
  api.ui_redraw()
end

function list:on_mouse(event)
  if event.kind == "scroll_down" then self.at = self.at + 3 end
  if event.kind == "scroll_up" then self.at = self.at - 3 end
  if event.kind == "down" and self.first then
    local i = event.y - self.first + 1 + self.scroll
    if event.y >= self.first and event.y < self.first + self.rows and self.items[i] then
      -- A click chooses a finding; a click on the one chosen goes there.
      if i == self.at then
        go()
      else
        self.at = i
      end
    end
  end
  api.ui_redraw()
end

paw.ui.view("mixdiag", list)

--- Show the report, on the first finding.
function M.open()
  list.at, list.scroll = 1, 0
  local items = require("mixdiag").items()
  local width = 60
  for _, item in ipairs(items) do
    width = math.max(width, api.str_width(item.text) + 6)
  end
  paw.ui.open("mixdiag", { title = "Mix report", width = math.min(width, 140), height = math.min(#items + 8, 30) })
end

M.list_view = list

-- The strip -----------------------------------------------------------------------

local strip = { focusable = false }

function strip:render(buf)
  local mixdiag = require("mixdiag")
  buf:fill(0, 0, buf.width, 1, " ", "Ruler")
  local arrange = paw.ui.views.arrange
  local g = arrange and arrange.geometry
  local job = mixdiag.job
  local label
  if job then
    label = string.format(" measuring %d%%", math.floor((job.progress or 0) * 100 + 0.5))
  elseif mixdiag.result then
    label = " " .. #mixdiag.findings .. (mixdiag.stale() and " (old)" or "")
  end
  if g then
    buf:text(0, 0, paw.util.fit(" mix" .. (label or ""), math.max(1, g.hw - 1)), job and "Warn" or "Dim")
    -- The most severe finding wins a column.
    local columns = {}
    for _, mark in ipairs(mixdiag.marks()) do
      local x = g.hw + math.floor((mark.beat - arrange.scroll) * g.zoom + 0.5)
      if x >= g.hw and x < buf.width and (not columns[x] or rank[mark.severity] < rank[columns[x]]) then
        columns[x] = mark.severity
      end
    end
    for x, severity in pairs(columns) do
      buf:text(x, 0, glyphs[severity], styles[severity])
    end
  else
    buf:text(0, 0, " mix" .. (label or ""), "Dim")
  end
end

paw.ui.view("mixdiag_strip", strip)

-- In the graphical frontend, the findings that have a place are flags in a
-- band under the ruler, in the colour of the worst at each place; a click
-- goes to that one.
if paw.frontend and paw.frontend.bands then
  local c = paw.canvas.palette
  local colours = { error = c.error, warn = c.warn, info = c.select, hint = c.text_3 }
  table.insert(paw.frontend.bands, function()
    local mixdiag = require("mixdiag")
    local out, at = {}, {}
    for _, f in ipairs(mixdiag.findings or {}) do
      if f.beat then
        local key = string.format("%.6f", f.beat)
        local flag = at[key]
        if not flag then
          flag = { beat = f.beat, length = 0, count = 0 }
          at[key], out[#out + 1] = flag, flag
        end
        flag.count = flag.count + 1
        if not flag.worst or rank[f.severity] < rank[flag.worst.severity] then flag.worst = f end
      end
    end
    for _, flag in ipairs(out) do
      local f = flag.worst
      flag.name = flag.count > 1 and (f.rule .. " +" .. (flag.count - 1)) or f.rule
      flag.color = colours[f.severity]
      flag.hint = f.severity
        .. ": "
        .. mixdiag.format(f)
        .. (flag.count > 1 and string.format(" (and %d more here)", flag.count - 1) or "")
      flag.run = function() mixdiag.jump(f) end
    end
    return out
  end)
  paw.on("mixdiag.done", paw.frontend.refresh)
end

local docked = false

function M.strip(show)
  if show and not docked then
    paw.ui.dock("mixdiag_strip", { side = "top", size = 1 })
    docked = true
  elseif show then
    paw.ui.show("mixdiag_strip")
  elseif docked then
    paw.ui.hide("mixdiag_strip")
  end
end

function M.strip_visible() return docked and paw.ui.visible("mixdiag_strip") end

return M
