-- The doctor in a graphical frontend: the same page painted in pixels, with
-- buttons for what the keys do (see runtime/lua/paw/canvas.tl).
local util = paw.util
local doctor = require("doctor")
local view = require("doctor.panel")

local c = require("paw.canvas").palette
local PAD, ROW, TOP = 16, 30, 52

-- The buttons and rows of the last paint, for the pointer.
view.hits = paw.canvas.hit_list()

--- A button, drawn and remembered for the pointer. Returns where the next goes.
local function button(g, x, y, label, action, opts)
  opts = opts or {}
  return (paw.canvas.button(g, view.hits, x, y, label, action, { fill = opts.fill, color = opts.color, height = 26 }))
end

local colours = { ok = c.play_on, warn = c.warn, fail = c.error, skip = c.text_3 }

function view:paint(g, ctx)
  local w, h = ctx.width, ctx.height
  local model = view.model()
  view.hits:clear()
  g:rect(0, 0, w, h, { fill = c.surface })
  g:rect(0, 0, w, TOP, { fill = c.panel })
  local x = PAD
  if model.running then
    x = button(g, x, 13, "Skip this check", doctor.skip)
    button(g, x, 13, "Stop", doctor.cancel, { fill = c.error, color = c.surface })
  else
    x = button(g, x, 13, "Run all", function() doctor.start() end, { fill = c.select, color = c.surface })
    button(g, x, 13, "Those that need nobody", function() doctor.start({ unattended = true }) end)
  end
  button(g, w - PAD - 70, 13, "Close", function() paw.cmd("doctor.close") end)

  local y = TOP + 10
  for _, row in ipairs(model.rows) do
    local chosen = row.index == view.row
    if chosen then g:rect(PAD - 8, y, w - 2 * PAD + 16, ROW - 2, { fill = c.panel, radius = 5 }) end
    g:rect(PAD, y + 9, 10, 10, { fill = row.running and c.select or colours[row.mark] or c.text_off, radius = 5 })
    g:text(PAD + 22, y + 7, string.format("%d. %s", row.index, row.check.name), { color = c.text, bold = chosen, width = 220 })
    g:text(PAD + 250, y + 7, row.summary, { color = row.mark == "fail" and c.error or c.text_2, width = w - PAD * 2 - 250 })
    local index = row.index
    view.hits:add(g, PAD - 8, y, w - 2 * PAD + 16, ROW - 2, function()
      view.row = index
      if not model.running then doctor.start({ only = { index } }) end
    end)
    y = y + ROW
  end

  -- What the check under the cursor needs from you.
  local row = model.rows[view.row]
  if row and row.check.help then
    local lines = view.wrap(row.check.help, math.floor((w - 2 * PAD) / 7))
    for i, line in ipairs(lines) do g:text(PAD, y + 8 + (i - 1) * 16, line, { color = c.text_2, size = 11 }) end
  end

  -- The bottom: the question, what is being done, or where the report is.
  local by = h - 118
  g:rect(0, by, w, 118, { fill = c.panel })
  if model.meters and #model.meters > 0 then
    for ch, level in ipairs(model.meters) do
      local mx = PAD + (ch - 1) * 120
      local db = math.max(-120, require("paw.dsp").db(level))
      local at = util.clamp((db + 60) / 60, 0, 1)
      g:rect(mx, by + 12, 100, 6, { fill = c.well, radius = 3 })
      g:rect(mx, by + 12, math.max(2, 100 * at), 6, { fill = at > 0.9 and c.error or c.meter_low, radius = 3 })
      g:text(mx, by + 22, "input " .. ch, { color = c.text_2, size = 10 })
    end
  end
  if model.prompt then
    for i, line in ipairs(view.wrap(model.prompt.question, math.floor((w - 2 * PAD) / 8))) do
      if i <= 2 then g:text(PAD, by + 40 + (i - 1) * 18, line, { color = c.text, size = 13, bold = true }) end
    end
    local bx = PAD
    for _, choice in ipairs(model.prompt.choices) do
      local key = choice[1]
      bx = button(g, bx, by + 82, choice[2] .. "  (" .. key .. ")", function() doctor.answer(key) end, { fill = c.control_hover })
    end
  elseif model.running then
    g:text(PAD, by + 40, model.say or "working", { color = c.text, size = 13, width = w - 2 * PAD })
  else
    if model.report then g:text(PAD, by + 40, "report: " .. model.report, { color = c.text, width = w - 2 * PAD }) end
    if model.problem then g:text(PAD, by + 62, model.problem, { color = c.error, width = w - 2 * PAD }) end
  end
end

return view
