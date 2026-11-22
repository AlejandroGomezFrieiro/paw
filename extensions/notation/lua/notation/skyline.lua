-- Skylines, and what is placed against them.
--
-- A skyline is the outline of what is drawn on a staff, seen from above
-- and from below: for each pixel column, the highest and the lowest pixel
-- inked. Every staff of a system has one, made of its measures' notes,
-- stems, beams, flags, accidentals, ledger lines, articulations, ties and
-- tuplets (each measure's is kept with its ink). What stands outside the
-- staff is placed against it, nearest first, each clear of all before it,
-- and each is then added to it: slurs, then marks by their kind's `order`.
-- The room between staves and between systems is then what their skylines
-- need, so nothing overlaps (Gould, Behind Bars; Sibelius' magnetic
-- layout; LilyPond's skylines).
--
-- Coordinates are pixels, y down, in a staff's own frame: y 0 is the top
-- of its top line.
--
-- Kinds of marks. A mark on a measure (`m.marks`, `{ at, kind, value,
-- to?, staff? }`, beats of the clip) is placed when its kind is known:
--
--   skyline.kind("chord", {
--     order = 50,          -- placed after lower orders, so further out
--     side = "above",      -- or "below", or function(item) -> "above" | "below"
--     pad = 0.6,           -- staff spaces clear of what is there already
--     row = "chords",      -- optional: a row's marks on a system share one line
--     staff = 1,           -- optional: the staff it goes on (default the
--                          -- mark's `staff`, else 1); "last" for the lowest
--     ink = function(ink, st, item) ... end,
--     collect = function(m, add) ... end,   -- optional, see below
--   })
--
-- `ink` draws the mark with its origin at `item.x` (the x of `item.at` on
-- the page) and its line at y 0, using the engraver's ink (`ink:glyph(st,
-- x, y, name, colour, scale)`, `ink:text(x, y, text, colour, size, bold,
-- align, width)`, `ink:rect(...)`, `ink:path(...)`); what it draws is its
-- shape, and the placer moves it up or down until it is clear. `item` has
-- the mark's fields, `x`, `x1` (the x of `to`, where there is one on this
-- system, else the system's end), `staff` and `system`. `st` is the style:
-- `st.sp` the staff space, `st.ink` the colour. `collect(m, add)` finds
-- marks that are not on `m.marks` (lyrics on the events, say): it calls
-- `add({ at = beat, staff = k, ... })` for each.
--
-- The kinds the engraver places itself, by order: bar numbers (5),
-- lyrics (20), dynamics and hairpins (30, one row along the system, below
-- the staff, above it on a staff with lyrics), text (40, above). Chord
-- symbols (50), rehearsal marks (60) and tempo text (70) have their places
-- in the order kept for them (`skyline.ORDER`).
local floor, ceil, max, min, huge = math.floor, math.ceil, math.max, math.min, math.huge

local K = { kinds = {} }

--- Where the kinds that others add go in the order, nearest the staff first.
K.ORDER = { number = 5, slur = 10, lyric = 20, dynamics = 30, text = 40, chord = 50, rehearsal = 60, tempo = 70 }

-- Skylines ------------------------------------------------------------------------------------

local Sky = {}
Sky.__index = Sky

--- A skyline `width` px wide from x 0, of a staff reaching from `top` to
--- `bottom`. The columns (`top[x]`, `bottom[x]`) hold only what is drawn;
--- `over` and `distance` count the staff too, so that marks stay outside
--- it, while a slur may bend inside it.
function K.new(width, top, bottom)
  local n = max(1, ceil(width))
  local t, b = {}, {}
  for i = 0, n do
    t[i], b[i] = huge, -huge
  end
  return setmetatable({ n = n, top = t, bottom = b, staff_top = top or huge, staff_bottom = bottom or -huge }, Sky)
end

--- A rectangle `l, t, r, b`.
function Sky:box(l, t, r, b)
  local tops, bottoms = self.top, self.bottom
  for i = max(0, floor(l)), min(self.n, ceil(r) - 1) do
    if t < tops[i] then tops[i] = t end
    if b > bottoms[i] then bottoms[i] = b end
  end
end

--- A line from `x0, y0` to `x1, y1`, `w` px thick.
function Sky:line(x0, y0, x1, y1, w)
  if x1 < x0 then
    x0, y0, x1, y1 = x1, y1, x0, y0
  end
  local half = (w or 1) / 2
  local tops, bottoms = self.top, self.bottom
  local span = x1 - x0
  for i = max(0, floor(x0)), min(self.n, ceil(x1)) do
    local f = span > 0 and min(1, max(0, (i + 0.5 - x0) / span)) or 0
    local y = y0 + (y1 - y0) * f
    if y - half < tops[i] then tops[i] = y - half end
    if y + half > bottoms[i] then bottoms[i] = y + half end
  end
end

--- What a drawing's shape covers (see `K.shape`), moved by `dx, dy`.
function Sky:shape(shape, dx, dy)
  dx, dy = dx or 0, dy or 0
  for _, s in ipairs(shape) do
    if s[1] == 1 then
      self:box(s[2] + dx, s[3] + dy, s[4] + dx, s[5] + dy)
    else
      self:line(s[2] + dx, s[3] + dy, s[4] + dx, s[5] + dy, s[6])
    end
  end
end

--- Another skyline laid into this one at `dx` (whole px), moved by `dy`.
function Sky:merge(other, dx, dy)
  dx, dy = floor(dx + 0.5), dy or 0
  local tops, bottoms = self.top, self.bottom
  for i = 0, other.n do
    local at = i + dx
    if at >= 0 and at <= self.n then
      local t, b = other.top[i] + dy, other.bottom[i] + dy
      if t < tops[at] then tops[at] = t end
      if b > bottoms[at] then bottoms[at] = b end
    end
  end
end

--- The highest top and the lowest bottom over the columns `l` to `r`, the
--- staff's own lines counted unless `bare`.
function Sky:over(l, r, bare)
  local t, b = huge, -huge
  if not bare then
    t, b = self.staff_top, self.staff_bottom
  end
  local tops, bottoms = self.top, self.bottom
  for i = max(0, floor(l)), min(self.n, ceil(r)) do
    if tops[i] < t then t = tops[i] end
    if bottoms[i] > b then b = bottoms[i] end
  end
  return t, b
end

--- The box of a shape: left, top, right, bottom, or nil for none.
function K.bounds(shape)
  local l, t, r, b = huge, huge, -huge, -huge
  for _, s in ipairs(shape) do
    local half = s[1] == 2 and (s[6] or 1) / 2 or 0
    l, r = min(l, s[2], s[4]), max(r, s[2], s[4])
    t, b = min(t, s[3] - half, s[5] - half), max(b, s[3] + half, s[5] + half)
  end
  if l > r then return nil end
  return l, t, r, b
end

--- The room two skylines need between them: how far below the top of the
--- upper one's frame the lower one's frame must start, so that the lower's
--- tops clear the upper's bottoms by `gap`, column by column.
function K.distance(upper, lower, gap)
  local need = upper.staff_bottom - lower.staff_top + gap
  local ub, lt = upper.staff_bottom, lower.staff_top
  for i = 0, min(upper.n, lower.n) do
    local d = max(upper.bottom[i], ub) - min(lower.top[i], lt) + gap
    if d > need then need = d end
  end
  return need
end

-- Kinds -------------------------------------------------------------------------------------

--- Make a kind of mark known (see the top of this file). Registering a
--- name again replaces it.
function K.kind(name, spec)
  spec.name = name
  spec.order = spec.order or K.ORDER[name] or 50
  spec.pad = spec.pad or 0.5
  K.kinds[name] = spec
  return spec
end

--- Place items on a system's staves: `items` (each with `kind`, `x`,
--- `staff`), `skies[staff]`, `st`, `new_ink()` an empty ink. Each item gets
--- `ink` (drawn at its line), `dy` (where its line goes, in its staff's
--- frame) and `side`, in the order of its kind; a row's items on a staff
--- and side share one `dy`. Every item placed is added to its skyline.
function K.place(items, skies, st, new_ink)
  local s = st.sp
  local by_order = {}
  for _, item in ipairs(items) do
    local kind = K.kinds[item.kind]
    if kind and skies[item.staff] then
      item.spec = kind
      by_order[#by_order + 1] = item
    end
  end
  table.sort(by_order, function(a, b)
    if a.spec.order ~= b.spec.order then return a.spec.order < b.spec.order end
    if a.staff ~= b.staff then return a.staff < b.staff end
    return a.x < b.x
  end)
  -- Items of one order are placed together: a row's at once, the rest one
  -- after another from the left, each clear of those before.
  local i = 1
  while i <= #by_order do
    local order = by_order[i].spec.order
    local j = i
    while by_order[j + 1] and by_order[j + 1].spec.order == order do
      j = j + 1
    end
    local rows, singles = {}, {}
    for k = i, j do
      local item = by_order[k]
      local spec = item.spec
      local side = type(spec.side) == "function" and spec.side(item) or spec.side or "above"
      item.side = side
      local ink = new_ink()
      spec.ink(ink, st, item)
      item.ink = ink
      item.box = { K.bounds(ink.shape) }
      if item.box[1] then
        if spec.row then
          local key = spec.row .. ":" .. item.staff .. ":" .. side
          rows[key] = rows[key] or {}
          table.insert(rows[key], item)
          if #rows[key] == 1 then rows[#rows + 1] = rows[key] end
        else
          singles[#singles + 1] = item
        end
      end
    end
    local function need(item)
      local sky, pad = skies[item.staff], item.spec.pad * s
      local l, t, r, b = item.box[1], item.box[2], item.box[3], item.box[4]
      local top, bottom = sky:over(l - pad, r + pad)
      if item.side == "above" then return top - pad - b end
      return bottom + pad - t
    end
    for _, row in ipairs(rows) do
      local dy
      for _, item in ipairs(row) do
        local d = need(item)
        if not dy or (item.side == "above" and d < dy) or (item.side ~= "above" and d > dy) then dy = d end
      end
      for _, item in ipairs(row) do
        item.dy = dy
      end
      for _, item in ipairs(row) do
        skies[item.staff]:shape(item.ink.shape, 0, dy)
      end
    end
    for _, item in ipairs(singles) do
      item.dy = need(item)
      skies[item.staff]:shape(item.ink.shape, 0, item.dy)
    end
    i = j + 1
  end
  return by_order
end

return K
