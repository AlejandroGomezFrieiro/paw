-- The vocal editor's window, note inspector: the properties of the notes
-- the edits work on (the selection, else the note under the cursor). A
-- value dragged sideways or typed (click it, type, Enter) is given to every
-- one of them; a right click puts it back to its default.
--
--   lyric, tuning in cents, the phonemizer for these notes, the vibrato and
--   its numbers, the transition, the per-note expressions the part's
--   renderer has (velocity, volume, attack, ...), and the note's phonemes.
local util = paw.util
local music = paw.music
local utau = require("utau")
local notes = require("utau.notes")
local shapes = require("utau.shapes")
local lyrics = require("utau.lyrics")
local c = require("paw.canvas").palette

local ROW = 21

-- What a classic voicebank's renderer offers, for when the engine has not
-- said: OpenUtau's per-note expressions.
local DEFAULT_EXPRESSIONS = {
  { abbr = "vel", name = "velocity", min = 0, max = 200, default = 100, kind = 0 },
  { abbr = "vol", name = "volume", min = 0, max = 200, default = 100, kind = 0 },
  { abbr = "atk", name = "attack", min = 0, max = 200, default = 100, kind = 0 },
  { abbr = "dec", name = "decay", min = 0, max = 100, default = 0, kind = 0 },
  { abbr = "mod", name = "modulation", min = 0, max = 100, default = 0, kind = 0 },
  { abbr = "alt", name = "alternate", min = 0, max = 16, default = 0, kind = 0 },
  { abbr = "gen", name = "gender", min = -100, max = 100, default = 0, kind = 0 },
  { abbr = "bre", name = "breath", min = 0, max = 100, default = 0, kind = 0 },
  { abbr = "lpf", name = "lowpass", min = 0, max = 100, default = 0, kind = 0 },
  { abbr = "shft", name = "tone shift", min = -36, max = 36, default = 0, kind = 0 },
}

local M = {}

--- The per-note expressions of a vocal part's renderer: numbers, choices
--- and switches (its curves are in the curve panel).
function M.expressions(part_id)
  local config = utau.config(part_id)
  local renderers = utau.renderers and utau.renderers.renderers or {}
  local chosen
  for _, r in ipairs(renderers) do
    if r.id == config.renderer then chosen = r end
  end
  if not chosen then
    local kind
    for _, s in ipairs(utau.singers) do
      if s.id == config.singer then kind = s.type end
    end
    for _, r in ipairs(renderers) do
      for _, t in ipairs(r.singer_types or {}) do
        if t == kind and not chosen then chosen = r end
      end
    end
  end
  local out = {}
  for _, e in ipairs(chosen and chosen.expressions or DEFAULT_EXPRESSIONS) do
    if e.kind ~= 1 then out[#out + 1] = e end
  end
  return out
end

local function props(note) return note.meta and type(note.meta.utau) == "table" and note.meta.utau or {} end

local function expression(note, abbr)
  for _, e in ipairs(type(props(note).ex) == "table" and props(note).ex or {}) do
    if e[1] == abbr and (e[3] or -1) == -1 then return e[2] end
  end
end

M.set_expression = shapes.set_expression

--- Change the properties of the notes the edits work on with `fn(props, note)`.
function M.apply(view, fn)
  local indices = view:targets()
  local which = {}
  for _, i in ipairs(indices) do
    which[i] = true
  end
  if not next(which) then return 0 end
  return notes.change_props(view.clip_id, function(p, note)
    fn(p, note)
    return true
  end, which)
end

-- The fields of the inspector, each `{ key, label, get(note), set(props, value) }`
-- and how it is worked: "number" (`min`, `max`, `step`, `unit`), "text",
-- "toggle", "choice" (`options`) or "button" (`run`).
local function fields(view, S)
  local out = {}
  local function add(f) out[#out + 1] = f end
  add({ key = "lyric", label = "Lyric", kind = "text", get = function(n) return notes.lyric(n) or "" end })
  add({
    key = "tu",
    label = "Tuning",
    kind = "number",
    min = -1200,
    max = 1200,
    step = 1,
    unit = "c",
    get = function(n) return props(n).tu or 0 end,
    set = function(p, v) p.tu = (v and v ~= 0) and math.floor(v + 0.5) or nil end,
  })
  add({
    key = "po",
    label = "Phonemizer",
    kind = "choice",
    get = function(n) return props(n).po or "" end,
    set = function(p, v) p.po = (v and v ~= "") and v or nil end,
    show = function(v)
      if v == "" then return "the part's" end
      for _, ph in ipairs(utau.phonemizers) do
        if ph.id == v then return ph.name end
      end
      return v:match("([^%.]+)$") or v
    end,
    options = function()
      local list = { { label = "the part's own", value = "" } }
      for _, ph in ipairs(utau.phonemizers) do
        list[#list + 1] = { label = ph.name, value = ph.id, detail = ph.tag }
      end
      return list
    end,
  })
  add({ section = "Vibrato" })
  add({
    key = "vb",
    label = "Vibrato",
    kind = "toggle",
    get = function(n) return shapes.vb(n) ~= nil end,
    set = function(p, on) p.vb = on and shapes.copy(shapes.DEFAULT_VB) or nil end,
  })
  local first = S.list[S.targets[1]]
  if first and shapes.vb(first) then
    for _, vf in ipairs(shapes.VB_FIELDS) do
      add({
        key = "vb" .. vf.i,
        label = vf.name,
        kind = "number",
        min = vf.min,
        max = vf.max,
        step = vf.step,
        unit = vf.unit,
        indent = true,
        get = function(n)
          local vb = shapes.vb(n)
          return vb and vb[vf.i] or shapes.DEFAULT_VB[vf.i]
        end,
        set = function(p, v, n)
          local vb = shapes.vb(n) or shapes.copy(shapes.DEFAULT_VB)
          vb[vf.i] = v == nil and shapes.DEFAULT_VB[vf.i] or v
          p.vb = vb
        end,
      })
    end
  end
  add({ section = "Transition" })
  add({
    key = "pp",
    label = "Points",
    kind = "button",
    button = "Reset",
    get = function(n)
      local pp = shapes.pp(n)
      return string.format(
        "%d, %d ms%s",
        #pp.pts,
        math.floor(pp.pts[#pp.pts][1] - pp.pts[1][1] + 0.5),
        shapes.has_pp(n) and "" or " (default)"
      )
    end,
    set = function(p) p.pp = nil end,
  })
  add({
    key = "snap",
    label = "From the note before",
    kind = "toggle",
    get = function(n) return shapes.pp(n).snap end,
    set = function(p, on, n)
      local pp = shapes.pp(n)
      pp.snap = on
      p.pp = pp
    end,
  })
  add({ section = "Expressions" })
  for _, e in ipairs(M.expressions(S.clip.part)) do
    local f = {
      key = "ex:" .. e.abbr,
      label = e.name:sub(1, 1):upper() .. e.name:sub(2),
      abbr = e.abbr,
      get = function(n) return expression(n, e.abbr) or e.default end,
      set = function(p, v) M.set_expression(p, e.abbr, (v ~= nil and math.abs(v - e.default) > 1e-9) and v or nil) end,
    }
    if e.kind == 2 and e.options and #e.options > 0 then
      f.kind = "choice"
      f.show = function(v) return tostring(e.options[math.floor(v) + 1] or v) end
      f.options = function()
        local list = {}
        for i, o in ipairs(e.options) do
          list[i] = { label = o, value = i - 1 }
        end
        return list
      end
    elseif e.kind == 3 then
      f.kind = "toggle"
      local get = f.get
      f.get = function(n) return get(n) ~= 0 end
      local set = f.set
      f.set = function(p, on) set(p, on and 1 or 0) end
    else
      f.kind, f.min, f.max, f.unit = "number", e.min, e.max, ""
      f.step = (e.max - e.min) > 50 and 1 or 0.1
    end
    add(f)
  end
  return out
end

local function show_value(f, v)
  if f.kind == "number" then
    local text = string.format("%g", math.floor(v * 10 + 0.5) / 10)
    if f.key == "tu" and v > 0 then text = "+" .. text end
    return text .. (f.unit ~= "" and (" " .. f.unit) or "")
  elseif f.kind == "toggle" then
    return v and "on" or "off"
  elseif f.show then
    return f.show(v)
  end
  return tostring(v)
end

return function(gui)
  local I = {}

  function I.paint(view, g, S)
    local w, h = g.width, g.height
    local ox, oy = g:origin_x(), g:origin_y()
    g:rect(0, 0, w, h, { fill = c.panel })
    g:line(0, 0, 0, h, { color = c.line_bar })
    local list = S.list
    local targets = S.targets
    if #targets == 0 then
      g:text(14, 14, "Note", { color = c.text, bold = true, size = 14 })
      g:text(14, 38, "Click a note to see its", { color = c.text_2 })
      g:text(14, 54, "properties; Shift+click or", { color = c.text_2 })
      g:text(14, 70, "Ctrl+drag for several.", { color = c.text_2 })
      return
    end
    local first = list[targets[1]]
    local title = #targets == 1
        and string.format("%s  ·  %s", music.name(first.pitch), paw.time.format(S.clip.start + first.start))
      or string.format("%d notes", #targets)
    g:text(14, 10, title, { color = c.text, bold = true, size = 14, width = w - 20 })
    g:text(
      14,
      30,
      #targets == 1 and string.format("length %g", first.length) or "a value set here goes to all of them",
      { color = c.text_3, size = 10, width = w - 20 }
    )
    local y = 50
    local drag = gui.drag
    for _, f in ipairs(fields(view, S)) do
      if y + ROW > h - 4 then break end
      if f.section then
        y = y + 4
        g:text(14, y + 2, f.section, { color = c.select, bold = true, size = 11 })
        g:line(14 + #f.section * 7 + 6, y + 9, w - 12, y + 9, { color = c.line_bar })
        y = y + 18
      else
        local value = f.get(first)
        local mixed = false
        for i = 2, #targets do
          if f.get(list[targets[i]]) ~= value then mixed = true end
        end
        if drag and drag.mode == "field" and drag.field.key == f.key then
          value, mixed = drag.value, false
        end
        local lx = f.indent and 26 or 14
        g:text(lx, y + 4, f.label, { color = c.text_2, size = 11, width = 120 })
        local vx, vw = 128, w - 128 - 10
        local text = mixed and "—" or show_value(f, value)
        local entry = view.entry
        if entry and entry.kind == "field" and entry.key == f.key then
          g:rect(vx, y + 1, vw, ROW - 3, { fill = c.warn, radius = 4 })
          g:text(
            vx + 6,
            y + 4,
            view:entry_text() .. "▏",
            { color = c.surface, bold = true, size = 11, width = vw - 8 }
          )
        elseif f.kind == "toggle" then
          g:rect(vx, y + 2, 34, ROW - 5, { fill = (value and not mixed) and c.select or c.control, radius = 8 })
          g:rect((value and not mixed) and vx + 19 or vx + 3, y + 5, 12, ROW - 11, { fill = c.text, radius = 6 })
          if mixed then g:text(vx + 42, y + 4, "mixed", { color = c.text_3, size = 10 }) end
        elseif f.kind == "button" then
          g:text(vx, y + 4, text, { color = c.text, size = 11, width = vw - 56 })
          g:rect(w - 62, y + 1, 52, ROW - 3, { fill = c.control, radius = 4 })
          g:text(w - 36, y + 4, f.button, { color = c.text, size = 11, align = "center", width = 52 })
        else
          local fill = f.kind == "number" and c.surface or c.control
          g:rect(vx, y + 1, vw, ROW - 3, { fill = fill, radius = 4, stroke = f.kind == "number" and c.line_bar or nil })
          if f.kind == "number" and not mixed then
            -- How far along its range the value is.
            local frac = util.clamp((value - f.min) / (f.max - f.min), 0, 1)
            g:rect(vx + 1, y + ROW - 5, (vw - 2) * frac, 2, { fill = c.select })
          end
          g:text(
            vx + 6,
            y + 4,
            text .. (f.kind == "choice" and "  ▾" or ""),
            { color = c.text, size = 11, width = vw - 8 }
          )
        end
        gui.fields[#gui.fields + 1] = { x = ox + vx, y = oy + y, w = vw, h = ROW, field = f, value = value }
        y = y + ROW
      end
    end
    -- The phonemes of the first note: what is sung, and what was changed.
    if #targets == 1 and y + 40 < h then
      y = y + 4
      g:text(14, y + 2, "Phonemes", { color = c.select, bold = true, size = 11 })
      g:line(14 + 70, y + 9, w - 12, y + 9, { color = c.line_bar })
      y = y + 18
      local got = view:phonemes_of(targets[1])
      if #got == 0 then g:text(14, y + 2, "not sung yet", { color = c.text_3, size = 11 }) end
      for k, p in ipairs(got) do
        if y + 16 > h then break end
        local o = view:phoneme_override(targets[1], k)
        local missing = p.flags % 2 == 1
        local name = p.phoneme ~= "" and p.phoneme or p.alias
        g:text(
          14,
          y + 2,
          name,
          { color = missing and c.error or o.phoneme and c.mute or c.select, bold = true, size = 11, width = 110 }
        )
        local notes_ = {}
        if missing then notes_[#notes_ + 1] = "not in the voicebank" end
        if o.offset then notes_[#notes_ + 1] = string.format("%+d ticks", o.offset) end
        if o.phoneme then notes_[#notes_ + 1] = "typed" end
        g:text(128, y + 2, table.concat(notes_, ", "), { color = c.text_3, size = 10, width = w - 136 })
        y = y + 16
      end
    end
  end

  local function commit_text(view, f, text)
    if f.key == "lyric" then
      local words = lyrics.tokens(text)
      local indices = view:targets()
      if #words > 1 and #indices > 1 then
        -- Several words go to the notes in order, as the lyric sheet does.
        local which = {}
        for _, i in ipairs(indices) do
          which[i] = true
        end
        local k = 0
        notes.change(view.clip_id, function(n)
          k = k + 1
          n.meta.lyric = words[math.min(k, #words)]
          return true
        end, which)
      else
        for _, i in ipairs(indices) do
          notes.set_lyric(view.clip_id, i, text)
        end
      end
      return
    end
    local v = tonumber((text:gsub("[^%d%.%-+]", "")))
    if not v then return paw.notify("not a number: " .. text, "warn") end
    v = util.clamp(v, f.min, f.max)
    M.apply(view, function(p, n) f.set(p, v, n) end)
  end

  local function field_drag(view, e)
    local d = gui.drag
    if e.kind == "move" then
      local f = d.field
      local v = d.v0 + (e.x - d.x0) * f.step * ((e.shift and 0.1) or 1)
      v = util.clamp(math.floor(v / f.step + 0.5) * f.step, f.min, f.max)
      if math.abs(e.x - d.x0) >= 3 then d.moved = true end
      d.value = v
      d.label = f.label .. " " .. show_value(f, v) .. "  (Shift for small steps)"
    elseif e.kind == "up" then
      gui.drag = nil
      local f = d.field
      if d.moved then
        M.apply(view, function(p, n) f.set(p, d.value, n) end)
      else
        view:type_text(
          string.format("%g", d.v0),
          function(text) commit_text(view, f, text) end,
          { kind = "field", key = f.key, label = f.label:lower() }
        )
      end
    end
  end

  function I.pointer(view, e)
    for _, slot in ipairs(gui.fields) do
      if
        e.x >= slot.x
        and e.x < slot.x + slot.w + (slot.field.kind == "button" and 60 or 0)
        and e.y >= slot.y
        and e.y < slot.y + slot.h
      then
        local f = slot.field
        if e.button == "right" then
          if f.set and f.kind ~= "toggle" then M.apply(view, function(p, n) f.set(p, nil, n) end) end
          return
        end
        if f.kind == "number" then
          gui.drag = { mode = "field", panel = field_drag, field = f, v0 = slot.value, value = slot.value, x0 = e.x }
        elseif f.kind == "text" then
          view:type_text(
            slot.value,
            function(text) commit_text(view, f, text) end,
            { kind = "field", key = f.key, label = f.label:lower() }
          )
        elseif f.kind == "toggle" then
          M.apply(view, function(p, n) f.set(p, not slot.value, n) end)
        elseif f.kind == "button" then
          M.apply(view, function(p, n) f.set(p, nil, n) end)
        elseif f.kind == "choice" then
          gui.popup = {
            x = slot.x - 60,
            y = slot.y + slot.h,
            w = slot.w + 60,
            items = f.options(),
            scroll = 0,
            current = slot.value,
            pick = function(value)
              M.apply(view, function(p, n) f.set(p, value, n) end)
            end,
          }
        end
        return
      end
    end
  end

  function I.paint_popup(view, g, popup)
    local rows = math.min(#popup.items, math.floor((gui.geo.h - popup.y - 40) / 20))
    popup.rows = rows
    popup.scroll = util.clamp(popup.scroll, 0, math.max(0, #popup.items - rows))
    local x = math.min(popup.x, gui.geo.w - popup.w - 4)
    popup.left = x
    g:rect(x, popup.y, popup.w, rows * 20 + 8, { fill = c.panel, stroke = c.select, radius = 6 })
    for r = 1, rows do
      local item = popup.items[r + popup.scroll]
      local on = item.value == popup.current
      g:text(
        x + 10,
        popup.y + 6 + (r - 1) * 20,
        (on and "● " or "   ") .. item.label,
        { color = on and c.select or c.text, size = 11, width = popup.w - 20 }
      )
    end
    if #popup.items > rows then
      g:text(x + popup.w - 12, popup.y + rows * 20 - 8, "⋮", { color = c.text_3, align = "right", width = 20 })
    end
  end

  function I.popup_pointer(view, e)
    local p = gui.popup
    gui.popup = nil
    if not p.rows or e.x < p.left or e.x >= p.left + p.w then return end
    local r = math.floor((e.y - p.y - 4) / 20) + 1
    local item = r >= 1 and r <= p.rows and p.items[r + p.scroll]
    if item then p.pick(item.value) end
  end

  function I.popup_wheel(e)
    local p = gui.popup
    p.scroll = p.scroll + (e.dy > 0 and -3 or 3)
  end

  I.expressions = M.expressions
  I.apply = M.apply
  return I
end
