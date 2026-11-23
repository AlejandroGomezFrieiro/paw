-- The virtual inputs in the terminal: every input with its chain and what
-- it is doing, and under it its settings, one to a row.
local api = paw.api
local util = paw.util
local vinput = require("vinput")
require("vinput.run")

local view = { row = 1, scroll = 0 }

--- The panel as a flat list of rows: an input's heading, its name, then
--- its settings.
function view:rows()
  local rows = {}
  for _, input in ipairs(vinput.inputs) do
    rows[#rows + 1] = { input = input, heading = true }
    rows[#rows + 1] = { input = input, name = true }
    for _, setting in ipairs(vinput.settings(input.kind)) do
      rows[#rows + 1] = { input = input, setting = setting }
    end
  end
  return rows
end

--- The row under the cursor.
function view:current()
  local rows = self:rows()
  self.row = util.clamp(self.row, 1, math.max(1, #rows))
  return rows[self.row], rows
end

--- Put the cursor on an input's heading.
function view:go(name)
  for index, row in ipairs(self:rows()) do
    if row.heading and row.input.name == name then self.row = index end
  end
end

local eighths = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

--- A level in dBFS as one cell: nothing at -60, full at 0.
function view.level_glyph(db)
  if not db then return " " end
  local at = util.clamp((db + 60) / 60, 0, 1)
  return at <= 0 and " " or eighths[util.clamp(math.ceil(at * 8), 1, 8)]
end

--- A port's name in a few words: `Steinberg UR22mkII  Input 2:capture_MONO`
--- as `UR22mkII Input 2`.
function view.short(source)
  local text = source:gsub(":capture_%w+$", ""):gsub("%s+", " ")
  local words = {}
  for word in text:gmatch("%S+") do
    words[#words + 1] = word
  end
  -- A maker's name ahead of the model's says little.
  if #words > 2 and not words[1]:match("%d") and words[2]:match("%d") then table.remove(words, 1) end
  text = table.concat(words, " ")
  if api.str_width(text) > 24 then text = text:sub(1, 23) .. "…" end
  return text
end

--- An input's chain in words, stage by stage, for a heading.
function view.chain(input)
  local kind = vinput.kinds[input.kind]
  local parts = {}
  for _, stage in ipairs(kind.stages) do
    if stage.key == "source" then
      parts[#parts + 1] = input.source ~= "" and view.short(input.source) or "no source"
    elseif stage.key == "level" then
      parts[#parts + 1] = string.format("×%.2f", input.gain)
    elseif stage.key == "tracker" then
      parts[#parts + 1] = stage.title
    elseif stage.key == "notes" then
      parts[#parts + 1] = "ch " .. input.channel .. (input.split ~= "" and " split" or "")
    elseif stage.key == "port" then
      parts[#parts + 1] = "MIDI “" .. input.name .. "”"
    end
  end
  return table.concat(parts, " ▸ ")
end

--- What an input is doing, in a few words.
function view.status_text(status)
  local parts = { status.text }
  if status.state == "running" then
    if status.level then parts[#parts + 1] = string.format("%.0f dBFS", status.level) end
    if status.notes then parts[#parts + 1] = status.notes .. (status.notes == 1 and " note" or " notes") end
    if status.load then parts[#parts + 1] = string.format("%.1f ms", status.load) end
  end
  return table.concat(parts, " · ")
end

local state_style = { running = "MeterLow", failed = "Error", blocked = "Warn", off = "Faint" }

function view:render(buf, ctx)
  local _, rows = self:current()
  local inputs = 0
  for _, r in ipairs(rows) do
    if r.heading then inputs = inputs + 1 end
  end
  local inner = paw.ui.titlebar(buf, {
    name = "Virtual inputs",
    context = "guitar to MIDI",
    focused = ctx.focused,
    right = inputs > 0 and tostring(inputs) or nil,
  })
  inner = inner:sub(1, 0, inner.width - 1, inner.height)
  local w, h = inner.width, inner.height
  if #rows == 0 then
    inner:text(1, 1, "No virtual inputs.", "Empty")
    inner:text(1, 3, "a", "EmptyKey")
    inner:text(4, 3, "add one that turns a guitar into MIDI", "Empty")
    return
  end
  if self.row <= self.scroll then self.scroll = self.row - 1 end
  if self.row > self.scroll + h then self.scroll = self.row - h end
  for y = 0, h - 1 do
    local index = y + 1 + self.scroll
    local r = rows[index]
    if not r then break end
    local chosen = index == self.row and ctx.focused
    if chosen then
      inner:fill(-1, y, w + 1, 1, " ", "Selected")
      buf:text(0, y + 1, paw.draw.g.mark, "SelectedMark")
    end
    local input = r.input
    if r.heading then
      local status = vinput.status(input.name)
      local x =
        inner:text(0, y, input.on and "● " or "○ ", input.on and (state_style[status.state] or "Accent") or "Faint")

      x = x + inner:text(x, y, input.name, input.on and "DeviceName" or "DeviceOff") + 2
      local right = view.status_text(status)
      local room = w - x - api.str_width(right) - 4
      if room > 12 then inner:text(x, y, util.fit(view.chain(input), room), "Dim") end
      local rx = w - api.str_width(right) - 3
      inner:text(rx, y, view.level_glyph(status.peak or status.level), "MeterLow")
      inner:text(rx + 2, y, right, state_style[status.state] or "Dim")
    else
      local setting = r.setting
      local label = r.name and "Name" or setting.name
      local value = r.name and input.name or vinput.format(setting, input[setting.key])
      inner:text(2, y, util.fit(label, 10), chosen and "Bright" or "Param")
      local x = 13
      if setting and setting.type == "number" then
        local bar = util.clamp(math.floor(w / 4), 8, 28)
        paw.draw.slider(
          inner,
          x,
          y,
          bar,
          (input[setting.key] - setting.min) / (setting.max - setting.min),
          chosen and "ParamBar" or "Dim",
          "ParamBarOff"
        )
        x = x + bar + 1
      end
      local empty = setting and setting.type ~= "number" and setting.type ~= "switch" and input[setting.key] == ""
      x = x + inner:text(x, y, value, empty and "Warn" or "ParamValue") + 3
      if setting and setting.key == "gain" then
        local advice = vinput.status(input.name).advice
        if advice then
          x = x + inner:text(x, y, string.format("the tracker would take %.2f (g)", advice.gain), "Accent") + 3
        end
      end
      local help = r.name and "the MIDI port parts take; renaming it takes the parts along" or setting.help
      if chosen and w - x > 16 then inner:text(x, y, util.fit(help, w - x - 1), "Faint") end
    end
  end
end

function view:on_mouse(event)
  if event.kind == "scroll_down" then self.row = self.row + 1 end
  if event.kind == "scroll_up" then self.row = self.row - 1 end
  if event.kind == "down" then self.row = event.y + self.scroll end
  api.ui_redraw()
end

paw.ui.view("vinput", view)
paw.ui.dock("vinput", { side = "bottom", hidden = true })
package.loaded["vinput.panel"] = view
return view
