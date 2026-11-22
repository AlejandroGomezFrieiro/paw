-- The doctor's page: the checks with how each one went, what the one under
-- the cursor needs from you, and the question being asked. In the terminal it
-- floats over the screen; in the window it is painted in pixels (see gui.lua).
local api = paw.api
local util = paw.util
local doctor = require("doctor")

local view = { title = "Doctor", row = 1, scroll = 0 }

local MARK = { ok = "ok", warn = "WARN", fail = "FAIL", skip = "skip" }
local STYLE = { ok = "MeterLow", warn = "Warn", fail = "Error", skip = "Faint" }

--- Text broken into lines of at most `width` columns.
function view.wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line ~= "" and api.str_width(line) + 1 + api.str_width(word) > width then
      lines[#lines + 1], line = line, ""
    end
    line = line == "" and word or (line .. " " .. word)
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

--- What the page shows, as plain data for both ways of drawing it: a row
--- for each check (`check`, `mark`, `summary`, `running`), the question
--- being asked, what is being said, and how far the run has got.
function view.model()
  local run = doctor.run()
  local rows = {}
  for index, check in ipairs(doctor.checks) do
    local id = doctor.id_of(check)
    local result = doctor.results[id]
    rows[#rows + 1] = {
      check = check,
      index = index,
      id = id,
      result = result,
      mark = result and result.status or nil,
      summary = result and result.summary or "",
      running = run and run.running and run.current == check,
    }
  end
  -- While a check runs, the page is on it.
  for _, row in ipairs(rows) do
    if row.running then view.row = row.index end
  end
  view.row = util.clamp(view.row, 1, math.max(1, #rows))
  return {
    rows = rows,
    run = run,
    running = run and run.running,
    prompt = run and run.running and run.prompt or nil,
    say = run and run.running and run.say or nil,
    meters = run and run.running and run.meters or nil,
    report = run and not run.running and run.report or nil,
    problem = run and run.problem,
  }
end

--- The key of each answer a question takes, for the keys to listen on.
view.answer_keys = { "y", "n", "s", "w", "r", "l", "b", "a", "d" }

local eighths = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

--- A level (0 to 1) as one character: nothing at -60 dBFS, full at 0.
function view.glyph(level)
  local db = math.max(-120, require("paw.dsp").db(level))
  local at = util.clamp((db + 60) / 60, 0, 1)
  return at <= 0 and " " or eighths[util.clamp(math.ceil(at * 8), 1, 8)]
end

function view:current()
  local model = view.model()
  return model.rows[self.row], model
end

function view:render(buf, ctx)
  local model = view.model()
  local w, h = buf.width, buf.height
  local y = 0
  for _, row in ipairs(model.rows) do
    if y >= h - 9 then break end
    local chosen = row.index == self.row and ctx.focused
    if chosen then buf:fill(0, y, w, 1, " ", "Selected") end
    local x = 1
    local mark = row.running and ">>" or MARK[row.mark] or "  "
    x = x + buf:text(x, y, string.format("%-4s", mark), row.running and "Accent" or STYLE[row.mark] or "Faint") + 1
    x = x + buf:text(x, y, string.format("%d. %s", row.index, row.check.name), chosen and "Bright" or "DeviceName") + 2
    if w - x > 8 then buf:text(x, y, util.fit(row.summary, w - x - 1), "Dim") end
    y = y + 1
  end

  -- What the check under the cursor needs from you.
  local row = model.rows[self.row]
  y = y + 1
  if row and row.check.help and y < h - 6 then
    for _, line in ipairs(view.wrap(row.check.help, w - 2)) do
      if y >= h - 6 then break end
      buf:text(1, y, line, "Faint")
      y = y + 1
    end
  end
  -- And what that check found, once it has run.
  if row and row.result then
    y = y + 1
    for _, text in ipairs(row.result.lines) do
      for _, line in ipairs(view.wrap(text, w - 4)) do
        if y >= h - 6 then break end
        buf:text(1, y, "- " .. line, "Dim")
        y = y + 1
      end
    end
  end

  -- The bottom: a question, what is being done, or how to begin.
  local bottom = h - 5
  buf:fill(0, bottom - 1, w, 1, view.rule or "-", "Rule")
  if model.meters and #model.meters > 0 then
    local x = 1
    x = x + buf:text(x, bottom, "input ", "Dim")
    for ch, level in ipairs(model.meters) do
      x = x + buf:text(x, bottom, string.format("%d", ch), "Dim")
      x = x + buf:text(x, bottom, view.glyph(level) .. " ", "MeterLow")
    end
  end
  if model.prompt then
    for i, line in ipairs(view.wrap(model.prompt.question, w - 2)) do
      if i <= 2 then buf:text(1, bottom + i, line, "Bright") end
    end
    local x = 1
    for _, choice in ipairs(model.prompt.choices) do
      x = x + buf:text(x, bottom + 3, choice[1], "EmptyKey") + 1
      x = x + buf:text(x, bottom + 3, choice[2], "Dim") + 3
    end
  elseif model.running then
    buf:text(1, bottom + 1, util.fit(model.say or "working", w - 2), "Bright")
    buf:text(1, bottom + 3, "s skip this check   Esc stop and write the report", "Faint")
  else
    if model.report then buf:text(1, bottom + 1, util.fit("report: " .. model.report, w - 2), "Bright") end
    if model.problem then buf:text(1, bottom + 2, util.fit(model.problem, w - 2), "Error") end
    buf:text(1, bottom + 3, "A all   <CR> this one   u those that need nobody   o the report   q close", "Faint")
  end
end

function view:on_mouse(event)
  if event.kind == "scroll_down" then self.row = self.row + 1 end
  if event.kind == "scroll_up" then self.row = self.row - 1 end
  if event.kind == "down" then self.row = event.y + 1 end
  api.ui_redraw()
end

paw.ui.view("doctor", view)
package.loaded["doctor.panel"] = view
return view
