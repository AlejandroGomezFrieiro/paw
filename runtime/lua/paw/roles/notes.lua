-- The roles of views that show notes on a plane of beats and pitches (the
-- piano roll, paw/views/pianoroll.lua): notes, the keyboard beside them,
-- the playhead and scroll bars, each drawn in cells as the terminal always
-- drew it and painted by a window as what it is, where it is between cells
-- (crates/paw-gui/src/roles.rs).
local role = paw.roles.define

--- A note: a bar of `style` (the terminal's) with a mark at its start and,
--- when it is four cells or longer, its `label` (its name, or the
--- articulation it carries). A window paints it in `color` (its track's),
--- fainter the softer its `velocity`, lit when `selected`, outlined when
--- the keyboard's cursor is on it (`cursor`); `pending` for a note being
--- drawn in insert mode, not yet written; `ghost` for where a drag will
--- put one, which a terminal draws without the mark. `bend` is the note's
--- own pitch bend at its end, in semitones, from `bend_at` (0 to 1) of its
--- length: a terminal ends the note with an arrow up or down, a window
--- draws the line the pitch takes.
role("note", {
  props = {
    label = "string",
    style = "highlight group",
    color = "#rrggbb",
    velocity = "number 0..127",
    selected = "boolean",
    cursor = "boolean",
    pending = "boolean",
    ghost = "boolean",
    bend = "semitones",
    bend_at = "number 0..1",
  },
  cells = function(buf, p)
    local w = buf.width
    buf:fill(0, 0, w, 1, " ", p.style)
    if p.ghost then
      if w >= 4 and p.label then buf:text(1, 0, tostring(p.label):sub(1, w - 1), p.style) end
      return
    end
    buf:text(0, 0, paw.draw.g.clip_start)
    local bent = p.bend and p.bend ~= 0 and w >= 2
    if w >= 4 and p.label then buf:text(1, 0, tostring(p.label):sub(1, w - (bent and 2 or 1))) end
    if bent then
      local up = p.bend > 0
      buf:text(w - 1, 0, paw.opt.ascii and (up and "/" or "\\") or (up and "↗" or "↘"))
    end
  end,
})

--- The keyboard down the left of a roll, a row a pitch from `top` down:
--- white and black keys, the C of each octave named, the row of the
--- keyboard's cursor (`cursor`) lit and named, `names` (`{ pitch, name }`
--- each: what the instrument calls a key) and `labels` (`{ pitch, label,
--- style }`: what a module says of a row) written on them, a dot on the
--- keys `sounding` at the cursor.
role("keyboard", {
  props = {
    top = "pitch of the first row",
    cursor = "pitch",
    names = "list of { pitch, name }",
    labels = "list of { pitch, label, style }",
    sounding = "list of pitches",
  },
  cells = function(buf, p)
    local names, labels, sounds = {}, {}, {}
    for _, n in ipairs(p.names or {}) do
      names[n[1]] = n[2]
    end
    for _, l in ipairs(p.labels or {}) do
      labels[l[1]] = l
    end
    for _, pitch in ipairs(p.sounding or {}) do
      sounds[pitch] = true
    end
    local w = buf.width
    for row = 0, buf.height - 1 do
      local pitch = p.top - row
      if pitch < 0 then break end
      paw.draw.piano_key(buf, row, pitch, pitch == p.cursor, w, names[pitch])
      local look = labels[pitch]
      if look and pitch ~= p.cursor then
        buf:text(0, row, paw.util.fit(look[2], w - 1) .. " ", look[3] or "PianoWhite")
      end
      if sounds[pitch] then buf:text(w - 1, row, "•", "PianoCursor") end
    end
  end,
})

--- The playhead over a stretch of time (a roll's ruler and grid): a line
--- on the left edge of the cell of the song's beat `at`, with a cap on the
--- first row, where the stretch (`from`, the song's beat at its left edge,
--- `per` columns a beat) shows it, between `lo` and `hi`. Bound to
--- `position`, a window moves it with `scene.live`, with no new scene.
--- With `spans` (`{ y, h, style, glyph }` each, rows of the rectangle),
--- a terminal draws the line only there, in each one's style (`glyph`
--- false keeps the character under it), and a window draws it whole.
--- `spans_at(x)`, a function, gives the spans at another column `x`: a
--- terminal moves the playhead by itself as the song plays.
role("playhead", {
  props = {
    at = "beat",
    from = "beat at the left edge",
    per = "columns a beat",
    lo = "beat",
    hi = "beat",
    spans = "list",
  },
  bound = { "at" },
  cells = function(buf, p)
    local g = paw.draw.g
    local x = math.floor((p.at - p.from) * p.per + 0.5)
    if x < 0 or x >= buf.width or p.at < p.lo or p.at > p.hi then return end
    local spans = p.spans_at and p.spans_at(x) or p.spans
    if spans then
      for _, s in ipairs(spans) do
        buf:fill(x, s[1], 1, s[2], s[4] ~= false and (s[4] or g.playhead) or nil, s[3])
      end
    else
      buf:fill(x, 1, 1, buf.height - 1, g.playhead, "Playhead")
    end
    buf:text(x, 0, g.cap, "RulerPlayhead")
  end,
})

--- A scroll bar along a side of what scrolls: `axis` "x" (along the
--- bottom) or "y" (down the right), its thumb over `from` to `from + span`
--- of `total`. A thin bar of eighth blocks in cells.
role("scrollbar", {
  props = { axis = "x | y", from = "number", span = "number", total = "number" },
  cells = function(buf, p)
    local long = p.axis == "x" and buf.width or buf.height
    local total = math.max(p.total or 1, p.span or 1, 1e-9)
    local n = math.max(1, math.floor((p.span or total) / total * long + 0.5))
    local a = paw.util.clamp(math.floor((p.from or 0) / total * long + 0.5), 0, math.max(0, long - n))
    if p.axis == "x" then
      buf:fill(a, 0, n, 1, paw.opt.ascii and "_" or "▁", "ScrollThumb")
    else
      buf:fill(0, a, 1, n, paw.opt.ascii and "|" or "▕", "ScrollThumb")
    end
  end,
})
