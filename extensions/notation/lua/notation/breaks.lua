-- Where systems break: measures into lines of a width, balanced over the
-- whole score rather than filled one line at a time (a total fit, in the
-- manner of Knuth and Plass), with the breaks a score asks for.
--
-- Every line is spread to the full width but the last. A line's cost grows
-- with the square of how far its measures are stretched beyond their own
-- widths, so that the stretch is shared out evenly: three lines a little
-- loose cost less than two tight ones and one loose. A line wider than the
-- width squeezes its measures and costs a great deal; one stretched beyond
-- `STRETCH` costs a great deal more than one that is not, so that no line
-- is left very loose while another way exists. The last line is free while
-- it is at least `LONELY` of the width, and costs more the emptier it is
-- below that, and a bar alone there costs more: it is not left alone at
-- the end when it can be helped.
--
-- What a score asks for (`notation.doc`'s `layout`, by measure id): a break
-- before a measure (`zs`), a measure kept on the line before (`zj`), and a
-- fixed number of measures to a line (`:notation.bars-per-system`).
local M = {}

--- The most a line is stretched without great cost: its measures twice
--- their own width.
M.STRETCH = 1.0
--- How much of the width the last line fills before it costs anything.
M.LONELY = 0.4
--- What a bar alone on the last line costs: as much as lines stretched by
--- three quarters of their width, so it is avoided unless that is worse.
M.ALONE = 60
--- What a line that ends where it had better end costs, of what it would.
M.RESTS = 0.6

--- The first measure of each line. `widths[i]` is each measure's own width,
--- `prefix(i)` the width of what starts a line at measure `i` (clef, key,
--- time), `width` the line's. `o`: `breaks[i]` (a line must start at `i`),
--- `joins[i]` (no line starts at `i`), `per` (measures to a line, the last
--- line fewer), `rests[i]` (a line had better end with measure `i`: a part
--- breaks after its rests, where a page can turn).
function M.lines(widths, prefix, width, o)
  o = o or {}
  local n = #widths
  if n == 0 then return {} end
  local breaks, joins, per = o.breaks or {}, o.joins or {}, o.per
  local best, from = { [1] = 0 }, {}
  -- `best[i]`: the least cost of lines over measures 1 .. i - 1 with a line
  -- starting at `i`.
  for i = 1, n do
    local base = best[i]
    if base and (i == 1 or not joins[i]) then
      local used = prefix(i)
      for j = i, n do
        used = used + widths[j]
        local count = j - i + 1
        local last = j == n
        local cost
        -- A line wider than twice the width is not worth weighing, unless
        -- the score asks for so many measures to a line.
        if count > 1 and used > 2 * width and not (per and per > 0) then break end
        if per and per > 0 and count > per then break end
        local own = used - prefix(i)
        local stretch = (width - used) / math.max(1, own)
        if used > width then
          cost = 1e6 * (1 + (used - width) / width) * count
        elseif last then
          local fill = used / width
          cost = (fill >= M.LONELY and 0 or 1e4 * (M.LONELY - fill) / M.LONELY)
            + (n > 1 and count == 1 and M.ALONE or 0)
        else
          cost = 100 * stretch * stretch + (stretch > M.STRETCH and 1e5 * (stretch - M.STRETCH) or 0)
        end
        if o.rests and o.rests[j] and not last then cost = cost * M.RESTS end
        cost = cost + 1
        if per and per > 0 and count < per and not last and not breaks[j + 1] then cost = cost + 1e8 end
        local total = base + cost
        local nxt = j + 1
        if not best[nxt] or total < best[nxt] then
          best[nxt], from[nxt] = total, i
        end
        -- A line never runs over a break the score asks for.
        if breaks[j + 1] then break end
      end
    end
  end
  local starts, at = {}, n + 1
  if not best[at] then
    -- Nothing fits the constraints (a join on the first measure of every
    -- way): one line each, as the measures come.
    for i = 1, n do
      starts[i] = i
    end
    return starts
  end
  while at > 1 do
    local i = from[at]
    table.insert(starts, 1, i)
    at = i
  end
  return starts
end

--- The cost of a breaking, as `lines` weighs it, and the most a line
--- (not the last) is stretched: for tests and the curious.
function M.measure(widths, prefix, width, starts)
  local worst, n = 0, #widths
  for k, i in ipairs(starts) do
    local j = (starts[k + 1] or n + 1) - 1
    if j < n then
      local own = 0
      for q = i, j do
        own = own + widths[q]
      end
      worst = math.max(worst, (width - prefix(i) - own) / math.max(1, own))
    end
  end
  return worst
end

return M
