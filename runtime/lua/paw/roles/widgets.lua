-- The widget roles: what panels of controls are made of (the mixer's
-- strips, an editor's toolbar). Each draws in cells as the terminal always
-- drew it; a window paints them as widgets (crates/paw-gui/src/roles.rs).
-- Props say what a widget shows, never where: the rectangle marked is its
-- place in both frontends.
local draw = paw.draw
local util = paw.util
local role = paw.roles.define

--- Text, as `buf:text` writes it: `align` "left" (the default), "right" or
--- "center" in the rectangle, cut to it.
role("label", {
  props = {
    text = "string",
    style = "highlight group",
    align = "left | right | center",
    tone = "theme token (window)",
    font = "mono (the default) | sans | title: how a window writes it",
    strike = "boolean (window)",
    capital = "boolean: a window writes the first letter in capitals",
  },
  cells = function(buf, p)
    local text = util.fit(tostring(p.text or ""), buf.width)
    local w = paw.api.str_width(text)
    local x = p.align == "right" and buf.width - w or p.align == "center" and math.floor((buf.width - w) / 2) or 0
    buf:text(x, 0, text, p.style)
  end,
})

--- Something to click: its text, lit when `on`. A window draws `icon`
--- in place of the text, when it has one of that name, and writes `words`
--- in place of the text where it has them.
role("button", {
  props = {
    text = "string",
    style = "highlight group",
    on = "boolean",
    menu = "boolean: it opens a menu",
    quiet = "boolean: no face until the pointer is on it",
    off = "boolean: dimmed",
    tone = "theme token of its text (window)",
    words = "string (window)",
    icon = "up | down | remove | window | plus | automate | learn | plugs | warning | circle | mic | speaker (window)",
  },
  cells = function(buf, p)
    buf:text(0, 0, util.fit(tostring(p.text or ""), buf.width), p.on and (p.on_style or "Visual") or p.style)
  end,
})

--- A letter that is on or off (mute, solo, armed): `style` when on. A
--- window draws `icon` in place of the letter (a button's icons).
role("switch", {
  props = {
    letter = "string",
    on = "boolean",
    style = "highlight group when on",
    tone = "mute | solo | rec | play_on | select",
    icon = "a button's icon (window)",
  },
  cells = function(buf, p) buf:text(0, 0, p.letter or "?", p.on and p.style or "FlagOff") end,
})

--- A value turned between two ends (a pan): `value` from -1 to 1. A rail
--- with a mark where it sits in cells, or its `text` (`L30`) in `style`
--- where it has one. A window paints a rail, or with `round` a round knob.
role("knob", {
  props = { value = "number -1..1", style = "highlight group of the mark", text = "string", round = "boolean (window)" },
  cells = function(buf, p)
    if p.text then
      buf:text(0, 0, util.fit(p.text, buf.width), p.style)
    else
      draw.pan(buf, 0, 0, buf.width, p.value or 0, p.style)
    end
  end,
})

--- A fader: its cap `at` (0 at the bottom to 1 at the top of its travel),
--- 0 dB marked at `zero`; `value` the level it stands for.
role("fader", {
  props = { at = "number 0..1", zero = "number 0..1", value = "number (dB)", selected = "boolean" },
  cells = function(buf, p)
    local g, rows = draw.g, buf.height
    local row = function(f) return math.floor(util.clamp(f or 0, 0, 1) * (rows - 1) + 0.5) end
    local mid = math.floor(buf.width / 2)
    buf:fill(mid, 0, 1, rows, g.fader_rail, "FaderTrack")
    if p.zero then buf:text(mid, rows - 1 - row(p.zero), g.zero, "FaderZero") end
    buf:text(0, rows - 1 - row(p.at), string.rep(g.fader, buf.width), p.selected and "FaderSel" or "Fader")
  end,
})

--- Level meters, a column each, lit from the bottom: `levels` (linear,
--- one a column), `hold`, the loudest of late, and `clipped`, the clip
--- light on top, lit once a level reached full scale. Bound to a track's
--- meter (`bind = "meter:<id>"`), a window moves all three with
--- `scene.live`, and they are not sent in the scene.
role("meter", {
  props = { levels = "list of numbers 0..", hold = "number", clipped = "boolean" },
  bound = { "levels", "hold", "clipped" },
  cells = function(buf, p)
    for i, level in ipairs(p.levels or {}) do
      if i > buf.width then break end
      draw.vmeter(buf, i - 1, 0, buf.height, level, p.hold)
    end
    if p.clipped then buf:text(0, 0, string.rep(draw.g.upper, math.min(buf.width, #(p.levels or {}))), "MeterClip") end
  end,
})

--- The loudest of late in dB, at the right of its rectangle: `hold`
--- (linear), red with `clipped`. Bound to a track's meter (`bind =
--- "meter:<id>"`), a window takes both from `scene.live`.
role("peak", {
  props = { hold = "number", clipped = "boolean" },
  bound = { "hold", "clipped" },
  cells = function(buf, p)
    local db = 20 * math.log10(math.max(p.hold or 0, 1e-6))
    local text = db < -60 and "-inf" or string.format("%.1f", db)
    local style = p.clipped and "MeterClip" or db > -0.1 and "MeterHigh" or "TrackIndex"
    buf:text(buf.width - #text, 0, text, style)
  end,
})

--- A name on a plate of a colour (a strip's track): `style` is the plate's
--- highlight group, `color` its colour for a window.
role("chip", {
  props = { text = "string", style = "highlight group", color = "#rrggbb", selected = "boolean" },
  cells = function(buf, p)
    buf:fill(0, 0, buf.width, buf.height, " ", p.style)
    buf:text(1, 0, util.fit(tostring(p.text or ""), buf.width - 1))
  end,
})

--- A parameter: a slider along its first `bar` columns, then its value
--- in its unit at the right of the rest (`text`). `fraction` is where it
--- sits, from 0 to 1; `centred` fills from the middle; `steps` is the
--- number of choices of a parameter that has them. Bound to a parameter
--- (`bind = "param:<device>:<key>"`), a window takes `fraction` and `text`
--- from `scene.live`, so that automation moves it with no new scene.
role("param", {
  props = {
    fraction = "number 0..1",
    text = "string",
    bar = "number (columns)",
    centred = "boolean",
    steps = "number",
    style = "highlight group of the bar",
    off_style = "highlight group of the rest of the rail",
    value_style = "highlight group of the value",
    dim = "boolean (window)",
  },
  bound = { "fraction", "text" },
  cells = function(buf, p)
    local bar = math.min(p.bar or buf.width, buf.width)
    if bar > 0 then draw.slider(buf, 0, 0, bar, p.fraction or 0, p.style, p.off_style) end
    local text, room = tostring(p.text or ""), buf.width - bar
    if room <= 0 or text == "" then return end
    if paw.api.str_width(text) > room then text = util.fit(text, room) end
    buf:text(buf.width - paw.api.str_width(text), 0, text, p.value_style)
  end,
})

--- A device's power: ` on `, or ` off ` lit when it is bypassed. A window
--- paints a power button, lit when on.
role("power", {
  props = { on = "boolean" },
  cells = function(buf, p) buf:text(0, 0, p.on and " on " or " off ", p.on and "FlagOff" or "Mute") end,
})

--- The heading of a group of rows, such as a device and its parameters:
--- nothing of its own in cells, where the rows' text says it all; a window
--- paints a band across, dimmed when `off`.
role("band", {
  props = { off = "boolean", selected = "boolean: the keyboard's cursor is on it" },
  cells = function() end,
})
