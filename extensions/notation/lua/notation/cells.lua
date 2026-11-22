-- What the terminal's staff is drawn with: the characters, in a set every
-- common monospace font has (DejaVu Sans Mono, JetBrains Mono, Fira Code,
-- Noto Sans Mono: box drawing, half blocks, ● ○ and a few letters) and a
-- plain ASCII one under `paw.opt.ascii`; the clefs drawn in them; and the
-- rows a staff's lines and spaces fall on.
--
-- Two scales. Dense (`dense`): a row for each line, a space between two
-- rows, so a staff is five rows and a grand staff fits in about eighteen; a
-- head in a space is drawn across the two rows it lies between (▄ over ▀).
-- Open: a row for each line and each space, nine rows a staff, which is
-- easier to read and to point at.
local M = {}

-- The accidentals are the one exception to the common set: ♯ ♭ ♮ are in
-- DejaVu Sans Mono and Noto Sans Mono, which terminals fall back to for the
-- fonts that lack them, and they are one cell wide everywhere.
M.unicode = {
  line = "─",
  bar = "│",
  -- Barlines joining the lines: on the top line, a middle line, the bottom line.
  join = { "┬", "┼", "┴" },
  first = { "┌", "├", "└" },
  last = { "┐", "┤", "┘" },
  -- Heads, two cells wide: on a row; in a space, the row above's lower
  -- half and the row below's upper half. Open heads are outlined.
  filled = "██",
  hollow = "()",
  filled_space = { "▄▄", "▀▀" },
  hollow_space = { "╭╮", "╰╯" },
  -- An open head in a space with its stem: up from its right side, down from its left.
  hollow_up = "╭┤",
  hollow_down = "├╯",
  hollow_join = "├┤",
  stem = "│",
  beam = "━",
  beam_up = "┳",
  beam_down = "┻",
  stub_right = "━╸",
  stub_left = "╺━",
  flag_up = "╲",
  flag_down = "╱",
  ledger = "────",
  dot = "·",
  space_dot = ".",
  acc = { [1] = "♯", [-1] = "♭", [0] = "♮", [2] = "x", [-2] = "♭" },
  -- Rests: the whole hangs from the fourth line, the half sits on the
  -- third; the quarter zigzags down the middle of the staff; an eighth
  -- is a flag on a slanted stroke, one more for each shorter value.
  whole = "▄▄",
  half = "▀▀",
  whole_open = { "▄▄", "▀▀" },
  half_open = { "▀▀", "▄▄" },
  quarter = { "╲", "╱", "╲" },
  quarter_open = { { 0, "╲" }, { 1, "╲" }, { 1, "╱" }, { 0, "╱" }, { 0, "╲" } },
  flag_rest = "7",
  tie_under = { "╰", "─", "╯" },
  tie_over = { "╭", "─", "╮" },
  bracket_over = { "┌", "─", "┐" },
  bracket_under = { "└", "─", "┘" },
  arpeggio = "┆",
  grace = "•",
  repeat_bar = "║",
  brace = { "⎧", "⎪", "⎨", "⎩" },
  hairpin = "─",
  staccato = "·",
  tenuto = "–",
}

M.ascii = {
  line = "-",
  bar = "|",
  join = { "+", "+", "+" },
  first = { "+", "+", "+" },
  last = { "+", "+", "+" },
  filled = "@@",
  hollow = "()",
  filled_space = { "@@", "@@" },
  hollow_space = { "()", "()" },
  hollow_up = "()",
  hollow_down = "()",
  hollow_join = "()",
  stem = "|",
  beam = "=",
  beam_up = "=",
  beam_down = "=",
  stub_right = "=-",
  stub_left = "-=",
  flag_up = "\\",
  flag_down = "/",
  ledger = "----",
  dot = ".",
  space_dot = ".",
  acc = { [1] = "#", [-1] = "b", [0] = "n", [2] = "x", [-2] = "b" },
  whole = "==",
  half = "==",
  whole_open = { "==", "  " },
  half_open = { "==", "  " },
  quarter = { "\\", "/", "\\" },
  quarter_open = { { 0, "\\" }, { 1, "\\" }, { 1, "/" }, { 0, "/" }, { 0, "\\" } },
  flag_rest = "7",
  tie_under = { "\\", "_", "/" },
  tie_over = { "/", "~", "\\" },
  bracket_over = { "+", "-", "+" },
  bracket_under = { "+", "-", "+" },
  arpeggio = "S",
  grace = "*",
  repeat_bar = "#",
  brace = { "/", "|", "<", "\\" },
  hairpin = "-",
  staccato = ".",
  tenuto = "_",
}

--- The characters in use.
function M.glyphs() return paw.opt.ascii and M.ascii or M.unicode end

-- Clefs, as rows of text from their top, each with the staff step its row
-- is on (the dense scale's rows: lines; the open scale fills between).
-- The treble clef curls round its G line, the bass clef's dots sit either
-- side of its F line.
local CLEFS = {
  treble = {
    { 10, "  ╭╮" },
    { 8, "  │╯" },
    { 6, " ╭╯" },
    { 4, "╭┼╮" },
    { 2, "│●┼╮" },
    { 0, "╰─┼╯" },
    { -2, "  │" },
    { -4, " ╰╯" },
  },
  bass = { { 8, "╭─╮" }, { 6, "● │:" }, { 4, " ╱" }, { 2, "╱" } },
  -- A C clef's two strokes, its point on its middle line.
  alto = { { 8, "┃│╮" }, { 6, "┃│╯" }, { 4, "┃│<" }, { 2, "┃│╮" }, { 0, "┃│╯" } },
  tenor = { { 10, "┃│╮" }, { 8, "┃│╯" }, { 6, "┃│<" }, { 4, "┃│╮" }, { 2, "┃│╯" } },
}
CLEFS.treble8, CLEFS.bass8 = CLEFS.treble, CLEFS.bass
local ASCII_CLEFS = {
  treble = { { 2, "&" } },
  bass = { { 6, "?:" } },
  alto = { { 4, "B" } },
  tenor = { { 6, "B" } },
}
ASCII_CLEFS.treble8, ASCII_CLEFS.bass8 = ASCII_CLEFS.treble, ASCII_CLEFS.bass

-- A clef that changes inside a system: smaller, two columns, its sign on
-- the line it names.
local SMALL = {
  treble = { { 4, "╭╮" }, { 2, "●┼" }, { 0, "╰┘" } },
  bass = { { 6, "●╮" }, { 4, " ╯" } },
  alto = { { 6, "┃╯" }, { 4, "┃<" }, { 2, "┃╮" } },
  tenor = { { 8, "┃╯" }, { 6, "┃<" }, { 4, "┃╮" } },
}
SMALL.treble8, SMALL.bass8 = SMALL.treble, SMALL.bass

--- A clef changed inside a system, as rows `{ pos, text }`.
function M.small_clef(clef)
  if paw.opt.ascii then return ASCII_CLEFS[clef] or ASCII_CLEFS.treble end
  return SMALL[clef] or SMALL.treble
end

-- Box drawing characters by whether they reach the top and the bottom of their cell.
local REACH_DOWN = {
  ["│"] = true,
  ["┼"] = true,
  ["╭"] = true,
  ["╮"] = true,
  ["┬"] = true,
  ["├"] = true,
  ["┤"] = true,
  ["╷"] = true,
}
local REACH_UP = {
  ["│"] = true,
  ["┼"] = true,
  ["╰"] = true,
  ["╯"] = true,
  ["┴"] = true,
  ["├"] = true,
  ["┤"] = true,
  ["╵"] = true,
}

local function chars(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = ch
  end
  return out
end

--- A clef's rows as `{ pos, text }`: in the open scale the rows between two
--- of the drawing's continue the strokes that cross them.
function M.clef(clef, dense)
  if paw.opt.ascii then return ASCII_CLEFS[clef] or ASCII_CLEFS.treble end
  local art = CLEFS[clef] or CLEFS.treble
  if dense then return art end
  local out = {}
  for i, r in ipairs(art) do
    out[#out + 1] = r
    local below = art[i + 1]
    if below then
      local a, b = chars(r[2]), chars(below[2])
      local fill = {}
      for c = 1, math.max(#a, #b) do
        fill[c] = (REACH_DOWN[a[c] or ""] and REACH_UP[b[c] or ""]) and "│" or " "
      end
      out[#out + 1] = { r[1] - 1, table.concat(fill) }
    end
  end
  return out
end

--- How many columns a clef takes.
function M.clef_width(clef)
  local w = 0
  for _, r in ipairs((paw.opt.ascii and ASCII_CLEFS or CLEFS)[clef] or CLEFS.treble) do
    w = math.max(w, #chars(r[2]))
  end
  return w
end

--- Rows of a staff whose bottom line is on row `base`: `exact(pos)` (a
--- half row for a space on the dense scale), `above(pos)` the row a
--- one-row character for that step goes in (the row above a space),
--- `below(pos)` the row under a space, `pos_of(row)` the step on a row.
function M.rows(base, dense)
  if dense then
    return {
      exact = function(pos) return base - pos / 2 end,
      above = function(pos) return base - (pos + pos % 2) / 2 end,
      below = function(pos) return base - (pos - pos % 2) / 2 end,
      pos_of = function(row) return 2 * (base - row) end,
      step = 2,
    }
  end
  local function at(pos) return base - pos end
  return { exact = at, above = at, below = at, pos_of = function(row) return base - row end, step = 1 }
end

return M
