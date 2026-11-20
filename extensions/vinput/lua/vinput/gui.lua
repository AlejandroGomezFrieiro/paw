-- The virtual inputs in a graphical frontend: the panel's view painted in
-- pixels and worked with the pointer (see runtime/lua/paw/canvas.lua).
--
--   top      a tab for each input, and a button for a new one
--   chain    the input's stages from left to right, each with what it is
--            set to and, for the tracker, what it is doing
--   settings one row each: drag a slider, click a switch, click a box to
--            choose or type; double click a slider for its usual value
--   bottom   what the tracker says, and a track that takes the input
--
-- Every key of the terminal panel works in the window too.
local api = paw.api
local util = paw.util
local vinput = require("vinput")
local run = require("vinput.run")
local view = require("vinput.panel")
local commands = require("vinput.commands")

local c = require("paw.canvas").palette
local TOP, CHAIN, ROW, BOTTOM, PAD = 46, 112, 34, 40, 16
local LABEL, SLIDER = 120, 250

-- What only the window keeps: which input is shown, where the pointer can
-- do something, what is being dragged, and the list that is open.
local gui = { shown = nil, hits = paw.canvas.hit_list(), list = nil }
-- The pointer goes to the places of the last paint (`paw.canvas.hit_list`).
view.hits = gui.hits
view.gui = gui

local function mix(a, b, t) return paw.draw.mix(a, b, t) end

--- Remember a place the pointer can act on. `on` has `down`, `drag`,
--- `double` and `wheel`, each given the event.
--- A second press soon after the first presses again, where the place
--- says nothing else of it.
local function hit(x, y, w, h, on)
  on.double = on.double or on.down
  return gui.hits:add(nil, x, y, w, h, on)
end

local text_width = paw.canvas.text_width

--- A button: drawn, and remembered for the pointer. Returns where the next goes.
local function button(g, x, y, label, action, opts)
  return (paw.canvas.button(g, gui.hits, x, y, label, { down = action, double = action }, opts))
end

local state_colour = { running = c.play_on, failed = c.error, blocked = c.warn, off = c.text_3 }

--- The input the window shows: the one the keyboard's cursor is on.
local function shown()
  local row = view:current()
  local input = row and row.input or vinput.inputs[1]
  gui.shown = input and input.name
  return input
end

--- The level of a running tracker as a bar: -60 dBFS empty, 0 full.
local function meter(g, x, y, w, db)
  g:rect(x, y, w, 5, { fill = c.well, radius = 2 })
  if not db then return end
  local at = util.clamp((db + 60) / 60, 0, 1)
  g:rect(x, y, math.max(2, w * at), 5, { fill = db > -6 and c.error or db > -14 and c.warn or c.play_on, radius = 2 })
end

--- One stage of the chain as a box. `lines` are its title and what it says.
local function stage_box(g, x, y, w, title, main, sub, colour, on)
  g:rect(x, y, w, CHAIN - 28, { fill = c.panel, stroke = colour or c.line_bar, radius = 7 })
  g:text(x + 12, y + 9, title, { color = c.text_2, size = 11 })
  g:text(x + 12, y + 28, main, { color = c.text, size = 14, bold = true, width = w - 20 })
  if sub then g:text(x + 12, y + 52, sub, { color = c.text_2, size = 11, width = w - 20 }) end
  if on then hit(x, y, w, CHAIN - 28, on) end
end

local function paint_chain(g, w, input, status)
  local y = TOP + 14
  local kind = vinput.kinds[input.kind]
  local stages = kind.stages
  local gap = 26
  local bw = (w - 2 * PAD - gap * (#stages - 1)) / #stages
  for index, stage in ipairs(stages) do
    local x = PAD + (index - 1) * (bw + gap)
    if stage.key == "source" then
      local name = input.source ~= "" and view.short(input.source) or "choose…"
      stage_box(g, x, y, bw, stage.title, name, input.source ~= "" and input.source:match(":(capture_%w+)$") or "the guitar, dry",
        input.source == "" and c.warn or nil, { down = function() gui.list = { input = input.name } run.sources(input.kind, true) end })
    elseif stage.key == "level" then
      stage_box(g, x, y, bw, stage.title, string.format("× %.2f", input.gain),
        status.level and string.format("%.0f dBFS, wants −18", status.level) or "wants −18 dBFS")
      meter(g, x + 12, y + 70, bw - 24, status.peak or status.level)
    elseif stage.key == "tracker" then
      local sub = status.state == "running" and string.format("%d notes · %.1f ms a frame", status.notes or 0, status.load or 0)
        or status.text
      stage_box(g, x, y, bw, stage.title, status.state == "running" and "running" or (status.text:match("^[^:]*")), sub,
        state_colour[status.state] or c.select, { down = function() run.restart(input.name) end })
    elseif stage.key == "notes" then
      stage_box(g, x, y, bw, stage.title, "channel " .. input.channel,
        (input.attack_velocity and "velocity from the picking" or "velocity 100") .. (input.split ~= "" and " · split" or ""))
    else
      stage_box(g, x, y, bw, stage.title, input.name, "tracks take it as MIDI", c.select,
        { down = function() commands.activate({ input = input, name = true }) end })
    end
    if index < #stages then
      local ax, ay = x + bw + 5, y + (CHAIN - 28) / 2
      g:line(ax, ay, ax + gap - 12, ay, { color = c.text_3, width = 2 })
      g:poly({ ax + gap - 12, ay - 5, ax + gap - 5, ay, ax + gap - 12, ay + 5 }, { fill = c.text_3 })
    end
  end
end

--- A setting's row: its name, what changes it, its value, what it is for.
local function paint_setting(g, w, y, input, setting, chosen, index)
  local name = input.name
  if chosen then g:rect(PAD - 8, y, w - 2 * PAD + 16, ROW - 4, { fill = c.panel, radius = 5 }) end
  g:text(PAD, y + 8, setting and setting.name or "Name", { color = chosen and c.text or c.text, bold = chosen })
  local x = PAD + LABEL
  local function choose() view.row = index end
  if setting and setting.type == "number" then
    local at = (input[setting.key] - setting.min) / (setting.max - setting.min)
    g:rect(x, y + 13, SLIDER, 4, { fill = c.well, radius = 2 })
    g:rect(x, y + 13, SLIDER * at, 4, { fill = chosen and c.select or mix(c.select, c.text_2, 0.6), radius = 2 })
    g:rect(x + (SLIDER - 10) * at, y + 8, 10, 14, { fill = chosen and c.text or c.text_2, radius = 3 })
    local left = x   -- `x` moves on along the row
    local function to(e)
      local value = setting.min + util.clamp((e.x - left - 5) / (SLIDER - 10), 0, 1) * (setting.max - setting.min)
      vinput.set(name, setting.key, util.round(value, setting.step))
    end
    hit(x - 6, y, SLIDER + 12, ROW - 4, {
      down = function(e) choose() to(e) end, drag = to,
      double = function() vinput.set(name, setting.key, setting.default) end,
      wheel = function(e) vinput.nudge(name, setting.key, e.dy > 0 and 1 or -1) end,
    })
    x = x + SLIDER + 14
    g:text(x, y + 8, vinput.format(setting, input[setting.key]), { color = c.select })
    x = x + 74
    if setting.key == "gain" then
      local advice = vinput.status(name).advice
      if advice then
        x = button(g, x, y + 3, string.format("use %.2f", advice.gain), function() vinput.set(name, "gain", advice.gain) end, { color = c.select }) + 4
      end
    end
  elseif setting and setting.type == "switch" then
    local on = input[setting.key]
    g:rect(x, y + 6, 38, 18, { fill = on and c.select or c.control_hover, radius = 9 })
    g:rect(x + (on and 22 or 2), y + 8, 14, 14, { fill = on and c.surface or c.text_2, radius = 7 })
    hit(x - 4, y, 46, ROW - 4, { down = function() choose() vinput.set(name, setting.key, not on) end })
    x = x + 52
    g:text(x, y + 8, vinput.format(setting, on), { color = c.select })
    x = x + text_width(vinput.format(setting, on)) + 18
  else
    -- Something chosen from a list or typed: a box that opens it.
    local value = setting and vinput.format(setting, input[setting.key]) or input.name
    local empty = setting and input[setting.key] == ""
    local bw = math.max(SLIDER, math.min(text_width(value) + 34, w - x - PAD - 40))
    g:rect(x, y + 3, bw, 24, { fill = c.well, stroke = chosen and c.select or c.line_bar, radius = 5 })
    g:text(x + 10, y + 8, value, { color = empty and c.warn or c.text, width = bw - 30 })
    if setting and setting.type == "choice" then g:text(x + bw - 18, y + 8, "▾", { color = c.text_2 }) end
    hit(x, y + 3, bw, 24, { down = function()
      choose()
      if setting and setting.type == "choice" then
        gui.list = { input = name }
        run.sources(input.kind, true)
      else
        commands.activate({ input = input, setting = setting, name = not setting })
      end
    end })
    x = x + bw + 16
  end
  local help = setting and setting.help or "the MIDI port tracks take; renaming it takes the tracks along"
  if w - x - PAD > 60 then g:text(x, y + 9, help, { color = c.text_3, size = 11, width = w - x - PAD }) end
end

--- The list of ports to choose a source from, over everything else.
local function paint_list(g, w, h, input)
  local sources = run.sources(input.kind)
  local items = {}
  for _, name in ipairs(sources or {}) do items[#items + 1] = name end
  local lw, lh = math.min(560, w - 2 * PAD), math.min(h - 80, 60 + math.max(1, #items) * 28)
  local x, y = (w - lw) / 2, math.max(30, (h - lh) / 2)
  -- Anywhere outside the list closes it.
  hit(0, 0, w, h, { down = function() gui.list = nil end })
  g:rect(0, 0, w, h, { fill = "#00000088" })
  g:rect(x, y, lw, lh, { fill = c.control, stroke = c.select, radius = 8 })
  g:text(x + 16, y + 12, "Source of " .. input.name, { color = c.text, size = 13, bold = true })
  g:text(x + lw - 16, y + 14, "the port the guitar is on", { color = c.text_2, size = 11, align = "right", width = 160 })
  if not sources then
    g:text(x + 16, y + 44, "Looking for audio ports…", { color = c.text_2 })
  elseif #items == 0 then
    g:text(x + 16, y + 44, vinput.kinds[input.kind].program() and "No audio ports were found." or vinput.kinds[input.kind].missing,
      { color = c.warn, width = lw - 32 })
  end
  for index, name in ipairs(items) do
    local iy = y + 40 + (index - 1) * 28
    if iy + 28 > y + lh then break end
    local on = name == input.source
    if on then g:rect(x + 8, iy, lw - 16, 26, { fill = mix(c.control, c.select, 0.25), radius = 5 }) end
    g:text(x + 18, iy + 6, (on and "● " or "   ") .. name, { color = on and c.text or c.text, width = lw - 36 })
    hit(x + 8, iy, lw - 16, 26, { down = function()
      gui.list = nil
      vinput.set(input.name, "source", name)
    end })
  end
end

function view:paint(g, ctx)
  local w, h = ctx.width, ctx.height
  gui.hits:clear()
  g:rect(0, 0, w, h, { fill = c.surface })
  g:rect(0, 0, w, TOP, { fill = c.panel })
  local input = shown()

  -- A tab for each input.
  local x = PAD
  for _, other in ipairs(vinput.inputs) do
    local status = vinput.status(other.name)
    local on = input and other.name == input.name
    local tw = text_width(other.name) + 40
    g:rect(x, 11, tw, 24, { fill = on and c.control_hover or c.control, stroke = on and c.select or nil, radius = 5 })
    g:rect(x + 10, 19, 8, 8, { fill = other.on and (state_colour[status.state] or c.select) or c.text_3, radius = 4 })
    g:text(x + 24, 16, other.name, { color = on and c.text or c.text, bold = on })
    hit(x, 11, tw, 24, { down = function() view:go(other.name) end })
    x = x + tw + 8
  end
  x = button(g, x, 11, "+ Add", function() commands.open(vinput.add({}).name) end)

  if not input then
    g:text(PAD + 8, TOP + 40, "No virtual inputs yet.", { color = c.text, size = 16, bold = true })
    g:text(PAD + 8, TOP + 68, "A virtual input turns something else into an input a track can take.", { color = c.text_2 })
    g:text(PAD + 8, TOP + 88, "“+ Add” makes one that listens to a guitar and sends the notes it hears as MIDI.", { color = c.text_2 })
    return
  end

  local status = vinput.status(input.name)
  -- On the right of the tabs: the input on or off, and away with it.
  local rx = w - PAD - 86
  button(g, rx, 11, "Remove", function() vinput.remove(input.name) end, { width = 86, color = c.text_2 })
  button(g, rx - 76, 11, input.on and "On" or "Off", function() vinput.set(input.name, "on", not input.on) end,
    { width = 68, on = input.on, lit = c.play_on })

  paint_chain(g, w, input, status)

  -- The settings, under the chain; the keyboard's row is lit.
  local _, rows = view:current()
  local y = TOP + CHAIN + 8
  for index, row in ipairs(rows) do
    if row.input == input and not row.heading then
      if y + ROW > h - BOTTOM then break end
      paint_setting(g, w, y, input, row.setting, index == view.row, index)
      y = y + ROW
    end
  end

  -- What the tracker says, and a track for the input.
  g:rect(0, h - BOTTOM, w, BOTTOM, { fill = c.panel })
  local colour = state_colour[status.state] or c.select
  g:rect(PAD, h - BOTTOM + 15, 10, 10, { fill = input.on and colour or c.text_3, radius = 5 })
  local said = view.status_text(status)
  if status.advice and status.state ~= "running" then
    said = said .. string.format("   ·   last time the level was %.1f dB %s", status.advice.db, status.advice.way)
  end
  g:text(PAD + 18, h - BOTTOM + 13, said, { color = status.state == "failed" and c.error or c.text, width = w - 2 * PAD - 230 })
  button(g, w - PAD - 190, h - BOTTOM + 8, "New track from this input", function()
    local track = vinput.make_track(input.name)
    paw.notify("track “" .. track.name .. "” plays what “" .. input.name .. "” hears")
  end, { width = 190 })

  if gui.list and vinput.get(gui.list.input) then
    paint_list(g, w, h, vinput.get(gui.list.input))
  else
    gui.list = nil
  end
end

function view:on_close()
  gui.list, gui.hits.drag = nil, nil
end

return gui
