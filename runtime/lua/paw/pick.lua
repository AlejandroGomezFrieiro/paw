-- `paw.pick`: choose one of many things by typing a few letters of it.
--
--   paw.pick({
--     title = "Tracks",
--     items = { { text = "Bass", id = 3 }, "Drums" },   -- or a function returning the list
--     format = function(item) return item.text end,    -- optional: the line shown and matched
--     on_choose = function(item) end,                  -- Enter
--     on_cancel = function() end,                      -- optional: Escape
--   })
--
-- Optional fields beyond those: `query` (typed in already), `prompt`,
-- `preview(item)` returning lines (strings or `{ text, style }`) for a pane
-- beside the list, `actions` mapping other keys to `function(item, query)`
-- (or `{ fn = ..., desc = ..., keep = true }` to leave the picker open),
-- `multi = true` to mark several with Tab and get them in
-- `on_choose_multi(items)`, `width` and `height`, `top = true` to sit at the
-- top of the screen (leaving what is below in view), `choose` (what Enter does,
-- for the key line), `empty` (what to say
-- when there is nothing to choose from), and `primary(item)`: the part of
-- the line that counts first, so that lines matching there rank above
-- lines matching only elsewhere. `search(item)` is the whole text that
-- a query matches, where the line shows only a part of it.
--
-- `boost(item)` returns a number added to the score of an item that
-- matches (up to 120): what is used often, or belongs to the focused view.
--
-- Every picker marks lines with Tab (unless `multi = false`), steps its
-- mode with Ctrl-r (`mode` starts it "exact" or "regex"), recalls what was
-- typed with Ctrl-Up, and has the keys of `paw.pick.keys`: what they do
-- with an item comes from `location(item)` (its address), `open(item,
-- how)`, `delete(items)` and `insert(item)`. `preview(item, width,
-- height)` is given the pane's size.
--
-- `audition(item)` lets the item under the selection be heard: once the
-- selection has rested on an item for `paw.opt.audition_delay` ms, the one
-- before is stopped (its trial taken back, see `paw.audition`) and the hook
-- plays this one. It returns a label for the preview pane ("Warm Pad ·
-- loop bar 5"), or a table `{ label, loading, keep }`: `loading()` says
-- whether it is still being made ready, and `keep(item)`, when given, is
-- run in place of `on_choose` when the item heard is chosen, its trial
-- kept as the undo step. Escape takes everything back; `<C-Space>` turns
-- hearing on and off, remembered for each source (`audition_key`, else
-- the source's name or the title), on unless `audition_default = false`.
-- `audition_delay(item, ms)` may return a longer rest for an item that is
-- slow to make ready.
--
-- `paw.pick("tracks")` opens a source by name. `paw.pick.sources` holds them:
-- add a table of the same fields with a `desc`, or a function returning one.
-- The picker of pickers (`paw.pick("pickers")`) lists every source.
local api = paw.api
local M = {
  --- The pickers by name, for `paw.pick(name)`: a picker, or a function
  --- that makes one.
  --- @type {string:contracts.PickEntry}
  sources = {},
}

local byte, lower, sub = string.byte, string.lower, string.sub
local floor, max, min = math.floor, math.max, math.min

-- Matching ---------------------------------------------------------------------
--
-- The scoring follows fzf's: every matched character is worth `MATCH`, a gap
-- costs `GAP_START` and `GAP_EXTEND` for each further character skipped, and a
-- character earns a bonus for where it is: after a space, a separator or at the
-- start of a word, at a lower-to-upper case change, or when it carries on a run
-- of consecutive matches. The first character's bonus counts double. Of all the
-- ways the query can be found in a line, the best scoring one is taken. Equal
-- scores go to the match nearer the start, then to the shorter line.

local MATCH, GAP_START, GAP_EXTEND = 16, -3, -1
local BONUS_BOUNDARY = MATCH / 2                         -- 8: start of a word
local BONUS_WHITE = BONUS_BOUNDARY + 2                   -- 10: after a space
local BONUS_DELIMITER = BONUS_BOUNDARY + 1               -- 9: after / : , ; |
local BONUS_NONWORD = BONUS_BOUNDARY                     -- 8: punctuation itself
local BONUS_CAMEL = BONUS_BOUNDARY + GAP_EXTEND          -- 7: aB, a1
local BONUS_CONSECUTIVE = -(GAP_START + GAP_EXTEND)      -- 4
local FIRST_MULTIPLIER = 2
local NONE = -1e9

-- Character classes, by byte.
local WHITE, NONWORD, DELIM, LOWER, UPPER, NUMBER = 0, 1, 2, 3, 4, 5
local class = {}
for b = 0, 255 do
  local c = NONWORD
  if b == 32 or b == 9 or b == 10 or b == 13 then
    c = WHITE
  elseif b >= 97 and b <= 122 or b >= 128 then
    c = LOWER   -- bytes of non-ASCII characters count as letters
  elseif b >= 65 and b <= 90 then
    c = UPPER
  elseif b >= 48 and b <= 57 then
    c = NUMBER
  elseif b == 47 or b == 58 or b == 44 or b == 59 or b == 124 then
    c = DELIM
  end
  class[b] = c
end

local function bonus_for(prev, cur)
  if cur > DELIM then
    if prev == WHITE then return BONUS_WHITE end
    if prev == DELIM then return BONUS_DELIMITER end
    if prev == NONWORD then return BONUS_BOUNDARY end
  end
  if prev == LOWER and cur == UPPER or prev ~= NUMBER and cur == NUMBER then return BONUS_CAMEL end
  if cur == NONWORD or cur == DELIM then return BONUS_NONWORD end
  if cur == WHITE then return BONUS_WHITE end
  return 0
end

local bonus_table = {}
for prev = 0, 5 do
  bonus_table[prev] = {}
  for cur = 0, 5 do bonus_table[prev][cur] = bonus_for(prev, cur) end
end

-- Scratch rows, reused for every line so that matching makes no garbage.
local bonus, cmp, first, last = {}, {}, {}, {}
local prev_score, prev_run, score_row, run_row = {}, {}, {}, {}

--- Score one term (no spaces) against a line. `text` is the line as it is
--- compared: lowered when the term is. Returns the score, or nil when the term
--- is not in the line. With `trace` a table, fills it with the byte positions
--- matched.
local function match_term(term, text, orig, trace)
  local m, n = #term, #text
  if m == 0 then return 0 end
  if m > n then return nil end
  -- Where each character of the term can first and last be, which also
  -- rejects lines that do not hold the term as a subsequence.
  local j = 1
  for i = 1, m do
    local c = byte(term, i)
    while j <= n and byte(text, j) ~= c do j = j + 1 end
    if j > n then return nil end
    first[i] = j
    j = j + 1
  end
  j = n
  for i = m, 1, -1 do
    local c = byte(term, i)
    while byte(text, j) ~= c do j = j - 1 end
    last[i] = j
    j = j - 1
  end

  local lo, hi = first[1], last[m]
  local prev_class = lo > 1 and class[byte(orig, lo - 1)] or WHITE
  for k = lo, hi do
    local cur = class[byte(orig, k)]
    bonus[k] = bonus_table[prev_class][cur]
    prev_class = cur
    cmp[k] = byte(text, k)
  end

  -- prev_score[k]: best score with term[i-1] matched at k; run: length of the
  -- run of consecutive matches ending there.
  local from = trace and {} or nil
  local c1 = byte(term, 1)
  for k = lo, hi do
    if k >= first[1] and k <= last[1] and cmp[k] == c1 then
      prev_score[k], prev_run[k] = MATCH + bonus[k] * FIRST_MULTIPLIER, 1
    else
      prev_score[k], prev_run[k] = NONE, 0
    end
  end
  if from then
    from[1] = {}
  end
  for i = 2, m do
    local c = byte(term, i)
    local a, b = first[i], last[i]
    local gap, gap_at = NONE, 0   -- best of prev_score[k] less the gap up to here
    local row_from = from and {} or nil
    if from then from[i] = row_from end
    for k = lo, hi do
      -- Bring the gap candidate forward to column k: a match of the
      -- previous character two or more columns back.
      if k - 2 >= lo then
        local p = prev_score[k - 2]
        if gap ~= NONE then gap = gap + GAP_EXTEND end
        if p ~= NONE and p + GAP_START > gap then gap, gap_at = p + GAP_START, k - 2 end
      end
      local s, r, src = NONE, 0, nil
      if k >= a and k <= b and cmp[k] == c then
        local own = bonus[k]
        local d = k > lo and prev_score[k - 1] or NONE
        if d ~= NONE then
          local run = prev_run[k - 1]
          local start_bonus = bonus[k - run]
          local bb = own
          if own >= BONUS_BOUNDARY and own > start_bonus then
            run = 0   -- a new word starts here: a run of its own
          else
            bb = max(own, BONUS_CONSECUTIVE, start_bonus)
          end
          s, r, src = d + MATCH + bb, run + 1, k - 1
        end
        if gap ~= NONE and gap + MATCH + own > s then
          s, r, src = gap + MATCH + own, 1, gap_at
        end
      end
      score_row[k], run_row[k] = s, r
      if row_from then row_from[k] = src end
    end
    for k = lo, hi do
      prev_score[k], prev_run[k] = score_row[k], run_row[k]
    end
  end
  local best, at = NONE, nil
  for k = lo, hi do
    if prev_score[k] > best then best, at = prev_score[k], k end
  end
  if best == NONE then return nil end
  local finish = at
  if trace then
    for i = m, 1, -1 do
      trace[#trace + 1] = at
      at = i > 1 and from[i][at] or nil
    end
  end
  return best, finish
end

-- The ways a query is read: "fuzzy" (letters in order, with fzf's `'`,
-- `^`, `$` and `!` before or after a word), "exact" (each word as it is
-- written, anywhere) and "regex" (the whole query, `paw.regex`).
M.MODES = { "fuzzy", "exact", "regex" }

--- Split a query into terms. A term with a capital letter is matched as
--- typed; one without ignores case. In fuzzy mode a term may say how it
--- matches, as in fzf: `'word` as written, `^word` at the start of the
--- line, `word$` at its end, `!word` not in the line (`!^word`, `!word$`).
local function terms_of(query, mode)
  local out = {}
  if mode == "regex" then
    if query:match("%S") then
      local re, err = paw.regex.try(query)
      out[1] = { kind = "regex", re = re, invalid = err, text = query }
    end
    return out
  end
  for word in query:gmatch("%S+") do
    local kind, negate = mode == "exact" and "exact" or "fuzzy", false
    if mode ~= "exact" then
      if #word > 1 and sub(word, 1, 1) == "!" then negate, word, kind = true, sub(word, 2), "exact" end
      if #word > 1 and sub(word, 1, 1) == "'" then
        kind, word = "exact", sub(word, 2)
      elseif #word > 1 and sub(word, 1, 1) == "^" then
        kind, word = "prefix", sub(word, 2)
      elseif #word > 1 and sub(word, -1) == "$" then
        kind, word = "suffix", sub(word, 1, -2)
      end
    end
    out[#out + 1] = { text = word, exact = word:find("%u") ~= nil, kind = kind, negate = negate }
  end
  return out
end

--- Score a term that is not fuzzy: the place it is found, worth what the
--- same characters in a run would be, with the bonus of where it starts.
local function match_plain(term, text, orig, trace)
  local a, b
  if term.invalid then
    return nil
  elseif term.kind == "regex" then
    a, b = term.re:find(orig)
    if a and b < a then b = a end
  elseif term.kind == "prefix" then
    if sub(text, 1, #term.text) == term.text then a, b = 1, #term.text end
  elseif term.kind == "suffix" then
    if #term.text <= #text and sub(text, -#term.text) == term.text then a, b = #text - #term.text + 1, #text end
  else
    a, b = text:find(term.text, 1, true)
  end
  if term.negate then return (not a) and 0 or nil, 0 end
  if not a then return nil end
  local prev = a > 1 and class[byte(orig, a - 1)] or WHITE
  local start = bonus_table[prev][class[byte(orig, a)] or WHITE] or 0
  if trace then
    for k = a, b do trace[#trace + 1] = k end
  end
  return (b - a + 1) * (MATCH + BONUS_CONSECUTIVE) + start * FIRST_MULTIPLIER, b
end

--- Score one term of any kind against a line; `low` is the line lowered.
local function score_term(term, orig, low, trace)
  local text = term.exact and orig or low
  if term.kind == "fuzzy" then return match_term(term.text, text, orig, trace) end
  return match_plain(term, text, orig, trace)
end

--- Lower the text of the terms that ignore case, once.
local function ready(terms)
  for _, term in ipairs(terms) do
    if not term.exact and term.text and term.kind ~= "regex" then term.text = lower(term.text) end
  end
  return terms
end

--- How well `query` matches `text`: a score, higher is better, and the byte
--- positions of the matched characters in order. Nil when it does not match.
--- Words of the query separated by spaces must each match. `mode` is one
--- of `paw.pick.MODES`, "fuzzy" by default.
---   paw.pick.match("bs", "Bass Synth")   --> score, { 1, 6 }
function M.match(query, text, want_positions, mode)
  if want_positions == nil then want_positions = true end
  local total, positions = 0, want_positions and {} or nil
  local low = lower(text)
  for _, term in ipairs(ready(terms_of(query, mode))) do
    local s = score_term(term, text, low, positions)
    if not s then return nil end
    total = total + s
  end
  if positions then table.sort(positions) end
  return total, positions
end

--- Entries for a list of items: { item, text, low, index }, and `primary`
--- (lowered) when the picker says which part of a line counts first.
--- `search(item)` gives the whole text that a query matches, when the line
--- shows a part of it (a description cut to the width).
local function entries_of(items, format, primary, search)
  local out = {}
  for i, item in ipairs(items) do
    local text
    if format then
      text = format(item)
    elseif type(item) == "table" then
      text = item.text or item.name or item[1]
    end
    text = tostring(text == nil and item or text):gsub("[\r\n\t]", " ")
    out[i] = { item = item, text = text, low = lower(text), index = i }
    if primary then out[i].primary = tostring(primary(item) or "") end
    if search then
      local hay = tostring(search(item) or text):gsub("[\r\n\t]", " ")
      out[i].hay, out[i].hay_low = hay, lower(hay)
    end
  end
  return out
end

-- What a match in an entry's primary part (a command's name, say) is worth
-- over one found only in the rest of the line.
local PRIMARY_BONUS = 1000

-- A line holding every term as the start of a word ("send" in "Send the
-- track"), a primary part that starts with the term or is it: worth more
-- than the same letters scattered, and less than a match in the primary.
local WORD_BONUS, PREFIX_BONUS, EXACT_BONUS = 200, 300, 600

-- What a picker's `boost` may add: more than the difference between two
-- matches in the same name, less than a prefix match is worth over one.
local BOOST_MAX = 120

--- Whether `text` has `term` at the start of a word.
local function starts_word(text, term)
  local from = 1
  while true do
    local at = text:find(term, from, true)
    if not at then return false end
    if at == 1 or not sub(text, at - 1, at - 1):match("%w") then return true end
    from = at + 1
  end
end

-- Equal scores go to the match that ends sooner, then to the shorter line.
local function by_score(a, b)
  if a.score ~= b.score then return a.score > b.score end
  if a.finish ~= b.finish then return a.finish < b.finish end
  if #a.text ~= #b.text then return #a.text < #b.text end
  return a.index < b.index
end

--- Keep the entries that match `query`, best first. An empty query keeps
--- every entry, in its order.
local function filter_entries(query, entries, mode)
  local terms = ready(terms_of(query, mode))
  if #terms == 0 then
    local out = {}
    for i, e in ipairs(entries) do
      e.score, e.finish = 0, 0
      out[i] = e
    end
    return out
  end
  -- A regex finds a place rather than ranks: the lines keep their order.
  local plain = mode == "regex"
  local out = {}
  for _, e in ipairs(entries) do
    local total, finish = 0, nil
    for _, term in ipairs(terms) do
      local s, at = score_term(term, e.hay or e.text, e.hay_low or e.low)
      if not s then
        total = nil
        break
      end
      total, finish = total + s, finish or at
    end
    if plain then
      total, finish = total and 0, 0
    elseif total and e.primary then
      local all = true
      local low = lower(e.primary)
      for _, term in ipairs(terms) do
        if not term.negate and not score_term(term, e.primary, low) then
          all = false
          break
        end
      end
      if all then
        total = total + PRIMARY_BONUS
        if #terms == 1 and (terms[1].exact and e.primary or low) == terms[1].text then
          total = total + EXACT_BONUS
        elseif #terms == 1 and sub(terms[1].exact and e.primary or low, 1, #terms[1].text) == terms[1].text then
          total = total + PREFIX_BONUS
        end
      end
    end
    if total and not plain and not (e.primary and total >= PRIMARY_BONUS) then
      local words = true
      for _, term in ipairs(terms) do
        if not term.negate and not starts_word(term.exact and (e.hay or e.text) or (e.hay_low or e.low), term.text) then
          words = false
          break
        end
      end
      if words then total = total + WORD_BONUS end
    end
    if total then
      e.score, e.finish = total, finish
      out[#out + 1] = e
    end
  end
  table.sort(out, by_score)
  return out
end

--- The items that match `query`, best first, each as { item, text, score }.
--- `mode` is as `paw.pick.match` takes it.
---   paw.pick.filter("bass", { "Bass", "Bass Synth", "Drums" })
function M.filter(query, items, format, primary, mode)
  local out = {}
  for i, e in ipairs(filter_entries(query, entries_of(items, format, primary), mode)) do
    out[i] = { item = e.item, text = e.text, score = e.score }
  end
  return out
end

-- The picker --------------------------------------------------------------------

local active        -- the open picker
local last_spec     -- for `resume`
paw.seats.keep("pick",
  function() return active, last_spec end,
  function(a, spec) active, last_spec = a, spec end,
  function() return nil, nil end)

local view = { modal = true }

local function chars_of(text)
  local out = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end

--- Whether a query typed on from `before` can only narrow what it matched:
--- in fuzzy and exact mode, unless a word says what must not be there or
--- what the line ends with.
local function narrows(p, before, query)
  if before == "" or query:sub(1, #before) ~= before or p.mode == "regex" then return false end
  return not (query:find("!", 1, true) or query:find("$", 1, true)) or p.mode == "exact"
end

local function refilter(p)
  local query = table.concat(p.query)
  -- Typing on only narrows the matches (a longer term, another term, a
  -- capital that makes a term match case), so start from the last ones.
  local base = p.entries
  if narrows(p, p.last_query, query) and p.last_mode == p.mode then base = p.matches end
  p.last_mode = p.mode
  -- A picker may match and rank its items itself: `rank(item, query, line)`
  -- returns a score, higher first, or nil to leave the item out.
  if p.spec.rank then
    local kept = {}
    for _, e in ipairs(base) do
      e.score, e.finish = p.spec.rank(e.item, query, e.text), 0
      if e.score then kept[#kept + 1] = e end
    end
    -- With nothing typed the list keeps its own order.
    if query ~= "" then table.sort(kept, by_score) end
    p.matches = kept
  else
    p.matches = filter_entries(query, base, p.mode)
    -- A picker may weigh its items by something besides the match (what is
    -- used often, what belongs to the focused view): `boost(item)` is added
    -- to the score, at most BOOST_MAX, so that exact and prefix matches stay first.
    if p.spec.boost and query ~= "" and p.mode ~= "regex" then
      for _, e in ipairs(p.matches) do e.score = e.score + min(max(p.spec.boost(e.item) or 0, 0), BOOST_MAX) end
      table.sort(p.matches, by_score)
    end
  end
  p.last_query = query
  p.selected, p.top = 1, 1
end

local function current(p)
  local e = p.matches[p.selected]
  return e and e.item, e
end

-- Hearing ------------------------------------------------------------------------

local function hear_key(p)
  return "pick.audition." .. tostring(p.spec.audition_key or p.source or p.spec.title or "?")
end

local function hearing_on(p)
  if not p.spec.audition then return false end
  local on = paw.state[hear_key(p)]
  if on == nil then return p.spec.audition_default ~= false end
  return on
end

--- Forget what the picker plays, and stop its timer.
local function hush(p)
  if p.hear_timer then paw.cancel(p.hear_timer) end
  if p.hear_ticker then paw.cancel(p.hear_ticker) end
  p.hear_timer, p.hear_ticker, p.hear_item, p.heard, p.hearing, p.hear_error = nil, nil, nil, nil, nil, nil
end

local function hear(p, item)
  p.hear_timer = nil
  if active ~= p then return end
  paw.audition.revert()
  p.heard, p.hearing, p.hear_error = nil, nil, nil
  if item == nil then return paw.audition.stop() end
  local asked = paw.audition.asked
  local ok, result = pcall(p.spec.audition, item)
  if not ok then
    paw.audition.stop()
    p.hear_error = tostring(result):match("^[^\n]*"):gsub("^[^:]*:%d+: ", "")
  else
    -- An item with nothing to hear silences the one before.
    if paw.audition.asked == asked then paw.audition.quiet() end
    p.heard, p.hearing = item, type(result) == "table" and result or { label = result }
  end
  -- While something plays or loads, the pane follows it.
  if not p.hear_ticker then
    p.hear_ticker = paw.every(100, function()
      if active == p and (paw.audition.state() or (p.hearing and p.hearing.loading)) then api.ui_redraw() end
    end)
  end
  api.ui_redraw()
end

--- After the selection moved: hear the item now under it once it rests there.
local function follow(p)
  if not hearing_on(p) then return end
  local item = current(p)
  if item == p.hear_item then return end
  p.hear_item = item
  if p.hear_timer then paw.cancel(p.hear_timer) end
  -- A file stops at once; a phrase plays on until the next sound is ready.
  api.preview_stop()
  -- A source may wait longer for what is slow to make ready (a plugin).
  local delay = tonumber(paw.opt.audition_delay) or 150
  if p.spec.audition_delay and item ~= nil then delay = p.spec.audition_delay(item, delay) or delay end
  p.hear_timer = paw.defer(function() hear(p, item) end, math.max(0, delay))
end

local function toggle_hearing(p)
  if not p.spec.audition then return paw.notify("nothing to hear in this picker", "warn") end
  local on = not hearing_on(p)
  paw.state[hear_key(p)] = on
  hush(p)
  if on then follow(p) else paw.audition.stop() end
  -- The pane says so at once: `♪ off` gives way to what plays, or to `…`.
  api.ui_redraw()
end

local function close(p)
  if active == p then active = nil end
  if p.spec.audition then
    hush(p)
    paw.audition.quiet()
  end
  if paw.ui.float and paw.ui.float.name == "pick" then paw.ui.close() end
end

local function choose(p)
  local item = current(p)
  local keep = p.hearing and p.hearing.keep
  local kept = keep and item ~= nil and p.heard == item and not (p.multi and next(p.marked))
  close(p)
  if p.spec.audition then
    -- What was heard is what is kept, as the step that choosing it makes.
    if kept and api.trial_active() then
      paw.audition.keep()
      return keep(item)
    end
    paw.audition.revert()
  end
  if p.multi and next(p.marked) then
    local items = {}
    for _, e in ipairs(p.entries) do
      if p.marked[e] then items[#items + 1] = e.item end
    end
    if p.spec.on_choose_multi then return p.spec.on_choose_multi(items) end
    for _, it in ipairs(items) do p.spec.on_choose(it) end
    return
  end
  if item == nil then
    if p.spec.on_cancel then p.spec.on_cancel() end
    return
  end
  if p.spec.on_choose then p.spec.on_choose(item) end
end

local function cancel(p)
  close(p)
  paw.audition.revert()
  if p.spec.on_cancel then p.spec.on_cancel() end
end

local function move(p, by)
  local n = #p.matches
  if n == 0 then return end
  p.selected = (p.selected - 1 + by) % n + 1
end

local function action_of(p, key)
  local a = p.spec.actions and p.spec.actions[key]
  if type(a) == "function" then return { fn = a } end
  return a
end

-- History -------------------------------------------------------------------------
--
-- What was typed in each picker before, newest first, kept until the
-- program ends: `Ctrl-Up` and `Ctrl-Down` step through it, as Telescope's.

local HISTORY = 50

local function source_key(p) return tostring(p.source or p.spec.title or "?") end

local function history_of(p) return paw.state["pick.history." .. source_key(p)] or {} end

--- Remember the query of a picker that was used, unless it is the last one.
local function remember(p)
  local query = table.concat(p.query)
  if not query:match("%S") then return end
  local list = { query }
  for _, q in ipairs(history_of(p)) do
    if q ~= query and #list < HISTORY then list[#list + 1] = q end
  end
  paw.state["pick.history." .. source_key(p)] = list
end

local function step_history(p, by)
  local list = history_of(p)
  if #list == 0 then return paw.notify("nothing typed in this picker before", "warn") end
  if not p.history_at then p.typed = table.concat(p.query) end
  local at = max(0, min(#list, (p.history_at or 0) + by))
  p.history_at = at
  p.query = chars_of(at == 0 and (p.typed or "") or list[at])
  refilter(p)
end

-- Keys every picker has --------------------------------------------------------------
--
-- As Telescope's: `Ctrl-v`, `Ctrl-x` and `Ctrl-t` open what is chosen in a
-- window beside, below or in a tab, `Ctrl-q` sends the marked lines (or all
-- that match) to the quickfix list and `Ctrl-l` to the window's location
-- list, `Ctrl-y` types the line on the command line, `Alt-d` deletes.
-- What the item is comes from the picker: `location(item)` its address,
-- `open(item, how)` opening it some way of its own, `delete(items)` and
-- `insert(item)`. A picker's own `actions` come before these.

--- The entries marked, in their order, or the one under the selection
--- (with `all`, every one that matches).
local function chosen_entries(p, all)
  local out = {}
  for _, e in ipairs(p.entries) do
    if p.marked[e] then out[#out + 1] = e end
  end
  if #out == 0 then
    if all then
      for i, e in ipairs(p.matches) do out[i] = e end
    else
      local _, e = current(p)
      out[1] = e
    end
  end
  return out
end

local function location_of(p, item)
  if not p.spec.location or item == nil then return nil end
  local ok, loc = pcall(p.spec.location, item)
  if not ok or not loc then return nil end
  if type(loc) == "string" then loc = { uri = loc } end
  return loc
end

-- The view that shows an address best, for a window of its own.
local function view_for(loc)
  local parsed = paw.address.parse(loc.uri)
  if not parsed then return "arrange" end
  if parsed.kind == "note" or parsed.kind == "control" then return "pianoroll" end
  if parsed.kind == "clip" then
    local ok, c = pcall(api.clip_get, parsed.clip)
    return ok and c.kind == "midi" and "pianoroll" or "arrange"
  end
  if parsed.kind == "device" or parsed.kind == "param" then return "devices" end
  return "arrange"
end

--- Show a location: in place (`how` nil), or in a new window to the side
--- ("vsplit"), below ("split") or in a new tab ("tab"). The view that shows
--- it best moves there. Returns true if there was a place to go.
function M.show(loc, how)
  if type(loc) == "string" then loc = { uri = loc } end
  if not how then return paw.qf.go({ location = loc }) end
  local name = view_for(loc)
  local L = paw.layout
  if how == "tab" then
    L.tab_new(nil, name)
  elseif not (L.current() and L.current().view == name) then
    local made, why = L.split({ vertical = how == "vsplit", view = name })
    if not made then paw.notify(why, "warn") end
  end
  paw.ui.focus(name)
  local locator = paw.ui.locators[name]
  if locator and locator.place(loc, true) then
    locator.go(loc)
    return true
  end
  return paw.qf.go({ location = loc })
end

local function open_with(how)
  return function(p, entries)
    local e = entries[1]
    if not e then return end
    if #entries > 1 then paw.notify(string.format("opened the first of %d marked", #entries)) end
    if p.spec.open then return p.spec.open(e.item, how) end
    local loc = location_of(p, e.item)
    if not loc then return paw.notify("this line has nowhere to open", "warn") end
    M.show(loc, how)
  end
end

--- The lines as quickfix entries, with their addresses when the picker has them.
local function send_to_list(loc)
  return function(p, entries)
    local list = {}
    for i, e in ipairs(entries) do list[i] = { location = location_of(p, e.item), text = e.text } end
    local query = table.concat(p.query)
    paw.qf.set(list, { title = (p.spec.title or "pick") .. (query ~= "" and " · " .. query or ""), win = loc or nil, source = "pick" })
    paw.qf.open({ loc = loc })
    paw.notify(string.format("%d line%s in the %s", #list, #list == 1 and "" or "s", loc and "location list" or "quickfix list"))
  end
end

local function insert(p, entries)
  local e = entries[1]
  if not e then return end
  if p.spec.insert then return p.spec.insert(e.item) end
  local text = e.text:gsub("^%s+", ""):gsub("%s+$", "")
  paw.ui.input({ prompt = ":", history = "cmdline", text = text }, function(line)
    if line:match("%S") then paw.commands.exec(line) end
  end)
end

--- Read a picker's items again, keeping what is typed.
local function reload(p)
  local items = p.spec.items
  if type(items) == "function" then items = items() end
  p.entries = entries_of(items or {}, p.spec.format, p.spec.primary, p.spec.search)
  p.marked, p.last_query = {}, ""
  refilter(p)
end

local function delete(p, entries)
  if #entries == 0 then return end
  local items = {}
  for i, e in ipairs(entries) do items[i] = e.item end
  local ok, err = pcall(p.spec.delete, items)
  if not ok then paw.notify((tostring(err):gsub("^[^:]*:%d+: ", "")), "error") end
  local selected = p.selected
  reload(p)
  p.selected = max(1, min(selected, #p.matches))
end

local function can_open(p) return p.spec.location ~= nil or p.spec.open ~= nil end

--- The keys every picker has, by key: `{ desc, when(p), all, keep, fn(p, entries) }`.
M.keys = {
  ["<C-v>"] = { desc = "split right", when = can_open, fn = open_with("vsplit") },
  ["<C-x>"] = { desc = "split below", when = can_open, fn = open_with("split") },
  ["<C-t>"] = { desc = "tab", when = can_open, fn = open_with("tab") },
  ["<C-q>"] = { desc = "quickfix", all = true, fn = send_to_list(false) },
  ["<C-l>"] = { desc = "location list", all = true, fn = send_to_list(true) },
  ["<C-y>"] = { desc = "insert", fn = insert },
  ["<A-d>"] = { desc = "delete", when = function(p) return p.spec.delete ~= nil end, keep = true, fn = delete },
}

local function generic_of(p, key)
  local g = M.keys[key]
  if g and (not g.when or g.when(p)) then return g end
end

local function cycle_mode(p)
  local at = 1
  for i, m in ipairs(M.MODES) do
    if m == p.mode then at = i end
  end
  p.mode = M.MODES[at % #M.MODES + 1]
  paw.state["pick.mode." .. source_key(p)] = p.mode
  refilter(p)
end

function view:on_key(key)
  local p = active
  if not p then return paw.ui.close() end
  -- `resume` reopens as it was when Enter or Escape closed it.
  local function keep_for_resume()
    if last_spec and last_spec.spec == p.spec then
      last_spec.query, last_spec.mode, last_spec.selected = table.concat(p.query), p.mode, p.selected
    end
  end
  keep_for_resume()
  local action = action_of(p, key)
  local g = not action and generic_of(p, key)
  if action or g then
    local item, entries = current(p), g and chosen_entries(p, g.all)
    remember(p)
    if not (action or g).keep then
      close(p)
      paw.audition.revert()
    end
    if action then action.fn(item, table.concat(p.query), p) else g.fn(p, entries) end
    if active == p then follow(p) end
    return api.ui_redraw()
  end
  local stepping = key == "<C-Up>" or key == "<C-Down>"
  if not stepping then p.history_at = nil end
  if key == "<CR>" then
    remember(p)
    return choose(p)
  elseif key == "<Esc>" or key == "<C-c>" then
    return cancel(p)
  elseif key == "<C-Space>" then
    toggle_hearing(p)
  elseif key == "<C-r>" then
    -- A picker that ranks its items itself reads what is typed its own way.
    if p.spec.rank then paw.notify("this picker reads what is typed its own way", "warn") else cycle_mode(p) end
  elseif stepping then
    step_history(p, key == "<C-Up>" and 1 or -1)
  elseif key == "<C-a>" and p.multi then
    -- Mark every line that matches, or none when all are.
    local all = #p.matches > 0
    for _, e in ipairs(p.matches) do all = all and p.marked[e] end
    for _, e in ipairs(p.matches) do p.marked[e] = (not all) or nil end
  elseif key == "<C-n>" or key == "<Down>" or key == "<C-j>" then
    move(p, 1)
  elseif key == "<C-p>" or key == "<Up>" or key == "<C-k>" then
    move(p, -1)
  elseif key == "<PageDown>" or key == "<C-d>" then
    p.selected = min(#p.matches, p.selected + (p.rows or 10))
  elseif key == "<PageUp>" then
    p.selected = max(1, p.selected - (p.rows or 10))
  elseif key == "<Home>" then
    p.selected = 1
  elseif key == "<End>" then
    p.selected = max(1, #p.matches)
  elseif key == "<Tab>" and p.multi then
    local _, e = current(p)
    if e then p.marked[e] = not p.marked[e] or nil end
    move(p, 1)
  elseif key == "<S-Tab>" and p.multi then
    local _, e = current(p)
    if e then p.marked[e] = not p.marked[e] or nil end
    move(p, -1)
  elseif key == "<C-u>" then
    p.query = {}
    refilter(p)
  elseif key == "<C-w>" then
    local q = p.query
    while #q > 0 and q[#q] == " " do q[#q] = nil end
    while #q > 0 and q[#q] ~= " " do q[#q] = nil end
    refilter(p)
  elseif key == "<BS>" or key == "<C-h>" then
    if #p.query > 0 then
      p.query[#p.query] = nil
      refilter(p)
    end
  else
    local ch = key == "<Space>" and " " or key == "<lt>" and "<" or key
    if not ch:match("^<.+>$") then
      p.query[#p.query + 1] = ch
      refilter(p)
    end
  end
  keep_for_resume()
  follow(p)
  api.ui_redraw()
end

function view:on_mouse(event)
  local p = active
  if not p then return end
  if event.kind == "scroll_down" then
    move(p, 3)
  elseif event.kind == "scroll_up" then
    move(p, -3)
  elseif event.kind == "down" and p.list_y and event.y >= p.list_y then
    local at = p.top + event.y - p.list_y
    if p.matches[at] then
      if at == p.selected then return choose(p) end
      p.selected = at
    end
  end
  follow(p)
  api.ui_redraw()
end

--- Draw `text` cut to `width` columns, with the characters at byte
--- `positions` (sorted) in `style`.
local function draw_matched(buf, x, y, text, positions, width, style)
  buf:text(x, y, paw.util.fit(text, width), nil)
  if not positions or #positions == 0 then return end
  -- A line that does not fit ends in "…" in its last column.
  local limit = api.str_width(text) > width and width - 1 or width
  local at, col, pi = 1, 0, 1
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local w = api.str_width(ch)
    if col + w > limit then break end
    local stop = at + #ch - 1
    while positions[pi] and positions[pi] < at do pi = pi + 1 end
    if not positions[pi] then break end
    if positions[pi] <= stop then buf:fill(x + col, y, w, 1, nil, style) end
    at, col = stop + 1, col + w
  end
end

local function clock(seconds)
  seconds = seconds or 0
  return string.format("%d:%04.1f", math.floor(seconds / 60), seconds % 60)
end

--- The top of the preview pane in a picker that can be heard: what plays,
--- and a sound file's outline with the place it has got to.
local function hearing_lines(p, width)
  if not hearing_on(p) then return { { text = "♪ off · Ctrl-Space hears", style = "Dim" }, { text = "" } } end
  local lines = {}
  local now = paw.audition.state()
  local h = p.hearing
  if p.hear_error then
    lines[1] = { text = "✗ " .. p.hear_error, style = "Warn" }
  elseif p.hear_timer or p.heard == nil or p.heard ~= current(p) then
    lines[1] = { text = "…", style = "Dim" }
  elseif h.loading and h.loading() then
    lines[1] = { text = "… loading " .. tostring(h.label or ""), style = "Dim" }
  elseif now and now.kind == "file" then
    local mark = ({ loading = "… reading ", failed = "✗ ", ended = "■ " })[now.state] or "♪ "
    local name = h.label or now.file:match("[^/]*$")
    lines[1] = { text = mark .. name .. (now.error and " · " .. now.error or ""), style = now.state == "failed" and "Warn" or "PickPlaying" }
    if now.outline then
      for _, row in ipairs(paw.audition.outline_lines(now.outline, width, 3, now.position, now.length)) do
        lines[#lines + 1] = { text = row.text, style = "PickWave", at = row.at }
      end
      lines[#lines + 1] = { text = clock(now.position) .. " / " .. clock(now.length), style = "Dim" }
    end
  elseif now and now.kind == "phrase" then
    local label = h.label or now.label
    lines[1] = { text = (now.silent and "■ " or "♪ ") .. tostring(label) .. (now.silent and " · " .. now.silent or ""), style = "PickPlaying" }
  elseif h.label then
    lines[1] = { text = "♪ " .. tostring(h.label), style = "PickPlaying" }
  else
    lines[1] = { text = "■ nothing to hear here", style = "Dim" }
  end
  lines[#lines + 1] = { text = "" }
  return lines
end

local function preview_lines(p, item, width, height)
  if item == nil or not p.spec.preview then return {} end
  local ok, lines = pcall(p.spec.preview, item, width, height)
  if not ok then return { { text = tostring(lines), style = "Error" } } end
  if type(lines) == "string" then lines = { lines } end
  local out = {}
  for _, line in ipairs(lines or {}) do
    line = type(line) == "table" and line or { text = line }
    for part in (tostring(line.text) .. "\n"):gmatch("([^\n]*)\n") do
      out[#out + 1] = { text = part:gsub("\t", "  "), style = line.style }
    end
  end
  return out
end

function view:render(buf, ctx)
  local p = active
  if not p then return end
  local w, h = buf.width, buf.height
  buf:fill(0, 0, w, h, " ", "Normal")

  -- The query line: the prompt, what is typed, and how many match.
  local query = table.concat(p.query)
  local count = string.format("%d/%d", #p.matches, #p.entries)
  -- A mode other than fuzzy says so beside the count.
  if p.mode ~= "fuzzy" then count = p.mode .. "  " .. count end
  if p.multi and next(p.marked) then
    local n = 0
    for _ in pairs(p.marked) do n = n + 1 end
    count = string.format("(%d) %s", n, count)
  end
  local used = buf:text(0, 0, p.prompt, "PickPrompt")
  local room = max(1, w - used - #count - 2)
  local shown = query
  if api.str_width(shown) > room then shown = "…" .. shown:sub(-(room - 1)) end
  local qw = buf:text(used, 0, shown, "Normal")
  buf:text(w - #count, 0, count, "PickCount")
  if ctx then api.ui_cursor(ctx.x + used + qw, ctx.y) end
  buf:text(0, 1, string.rep("─", w), "Border")

  -- A preview pane takes the right 40% when there is room for one.
  local list_w = w
  local has_preview = (p.spec.preview or p.spec.audition) and w >= 60
  if has_preview then list_w = floor(w * 0.6) end

  local footer = p.footer
  local rows = h - 2 - (footer and 1 or 0)
  p.rows, p.list_y = rows, 2
  if p.selected < p.top then p.top = p.selected end
  if p.selected >= p.top + rows then p.top = p.selected - rows + 1 end
  p.top = max(1, min(p.top, max(1, #p.matches - rows + 1)))

  if #p.entries == 0 then
    buf:text(2, 2, p.spec.empty or "Nothing to choose from.", "Dim")
  elseif #p.matches == 0 then
    local bad = p.mode == "regex" and select(2, paw.regex.try(query))
    buf:text(2, 2, bad and paw.util.fit(bad, list_w - 3) or "Nothing matches.", bad and "Warn" or "Dim")
  end
  -- The column of marks shows once something is marked.
  local mark_room = (p.spec.multi or next(p.marked)) and 2 or 0
  local terms_query = query:match("%S") and query or nil
  for row = 0, rows - 1 do
    local index = p.top + row
    local e = p.matches[index]
    if not e then break end
    local y = 2 + row
    local selected = index == p.selected
    if selected then buf:fill(0, y, list_w, 1, nil, "PickSelected") end
    -- The cursor is `▶`; the row that is heard has `♪` in its place.
    local heard = selected and p.heard ~= nil and p.heard == e.item and paw.audition.state() ~= nil
    buf:text(0, y, heard and "♪" or selected and "▶" or " ", selected and "PickCaret" or nil)
    if mark_room > 0 then buf:text(2, y, p.marked[e] and "+" or " ", "PickMarked") end
    local positions
    if terms_query then
      local _, pos = M.match(terms_query, e.text, true, p.mode)
      positions = pos
    end
    draw_matched(buf, 2 + mark_room, y, e.text, positions, list_w - 3 - mark_room, "PickMatch")
  end

  if has_preview then
    for y = 2, h - 1 - (footer and 1 or 0) do buf:text(list_w, y, "│", "Border") end
    local pw = w - list_w - 2
    local lines = preview_lines(p, current(p), pw, rows)
    if p.spec.audition then
      local top = hearing_lines(p, pw)
      for i = #top, 1, -1 do table.insert(lines, 1, top[i]) end
    end
    for i, line in ipairs(lines) do
      if i > rows then break end
      buf:text(list_w + 2, 1 + i, paw.util.fit(line.text, pw), line.style or "Normal")
      -- The column a sound file has got to, across its outline.
      if line.at and line.at <= pw then buf:fill(list_w + 1 + line.at, 1 + i, 1, 1, nil, "PickPlayhead") end
    end
  end
  if footer then buf:text(0, h - 1, paw.util.fit(footer, w), "Dim") end
end

paw.ui.view("pick", view)

-- The key line while a picker is open: what the keys of this one do (the
-- keys themselves are not mapped: the picker takes every key).
paw.ui.keybar.set("pick", "n", function()
  local out = { { "", active and active.spec.choose or "choose", "Enter" } }
  local keys = {}
  for key, a in pairs(active and active.spec.actions or {}) do
    if type(a) == "table" and a.desc then keys[#keys + 1] = { "", a.desc, paw.ui.keybar.show(key) } end
  end
  table.sort(keys, function(a, b) return a[3] < b[3] end)
  for _, entry in ipairs(keys) do out[#out + 1] = entry end
  out[#out + 1] = { "", "close", "Esc" }
  return out
end)

local function footer_of(p)
  local spec = p.spec
  local parts = { "Enter choose", "Esc cancel", "C-n/C-p move" }
  if p.multi then parts[#parts + 1] = "Tab mark" end
  if spec.audition then parts[#parts + 1] = "C-Space hear" end
  local keys = {}
  for key, a in pairs(spec.actions or {}) do
    if type(a) == "table" and a.desc then keys[#keys + 1] = key:gsub("^<(.*)>$", "%1") .. " " .. a.desc end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = k end
  -- Then the keys every picker has that this one can use.
  if can_open(p) and not (spec.actions and spec.actions["<C-v>"]) then parts[#parts + 1] = "C-v/C-x/C-t split/tab" end
  if not (spec.actions and spec.actions["<C-q>"]) then parts[#parts + 1] = "C-q quickfix" end
  if spec.delete then parts[#parts + 1] = "A-d delete" end
  if not spec.rank then parts[#parts + 1] = "C-r mode" end
  return table.concat(parts, "  ")
end

--- Open a picker. See the top of this file for the fields of `spec`, or pass
--- the name of a source. Returns the picker's state.
--- @type function<T>(spec: contracts.PickSource<T>)
--- @type function(name: string, extra?: contracts.PickExtra)
--- @call function<T>(spec: string | contracts.PickSource<T>, extra?: contracts.PickExtra)
function M.open(spec, extra)
  local source_name
  if type(spec) == "string" then
    local name = spec
    source_name = name
    local source = M.sources[name]
    if not source then error("no picker `" .. name .. "`", 2) end
    spec = type(source) == "function" and source(extra or {}) or source
    if not spec then return end
    if extra and extra.query then spec = paw.util.merge(spec, { query = extra.query }) end
    if not spec.title then spec = paw.util.merge(spec, { title = name }) end
  end
  assert(type(spec) == "table", "usage: paw.pick({ items = ..., on_choose = function(item) end })")
  local items = spec.items
  if type(items) == "function" then items = items() end
  -- A picker opened over one being heard takes over from it.
  if active and active.spec.audition then
    close(active)
    paw.audition.revert()
  end
  local p = {
    spec = spec, source = source_name, prompt = spec.prompt or "> ", query = chars_of(spec.query or ""),
    entries = entries_of(items or {}, spec.format, spec.primary, spec.search), selected = 1, top = 1,
    multi = spec.multi ~= false, marked = {}, last_query = "",
  }
  -- The mode chosen last in this picker, else the picker's own.
  p.mode = not spec.rank and (paw.state["pick.mode." .. source_key(p)] or spec.mode) or "fuzzy"
  p.matches = p.entries
  p.footer = footer_of(p)
  if #p.query > 0 or spec.rank then refilter(p) end
  active, last_spec = p, { spec = spec, query = spec.query, source = source_name }
  local width, height = api.ui_size()
  paw.ui.open("pick", {
    title = spec.title or "Pick",
    width = spec.width or ((spec.preview or spec.audition) and min(120, width - 4) or min(80, width - 4)),
    height = spec.height or min(28, max(10, height - 4)),
    top = spec.top,
  })
  follow(p)
  return p
end

--- Open the last picker again, as it was: what was typed, the mode, the
--- line selected. Its items are read again.
function M.resume()
  if not last_spec then return paw.notify("no picker opened yet", "warn") end
  local was = last_spec
  local p = M.open(was.spec)
  p.source, last_spec.source = was.source, was.source
  p.mode = was.mode or p.mode
  p.query = chars_of(was.query or "")
  refilter(p)
  p.selected = max(1, min(was.selected or 1, #p.matches))
  follow(p)
  return p
end

--- The open picker, if any: its query, the matches as lines, and the item
--- under the selection. For tests and for frontends.
function M.state()
  local p = active
  if not p or not (paw.ui.float and paw.ui.float.name == "pick") then return nil end
  local lines = {}
  for i, e in ipairs(p.matches) do lines[i] = e.text end
  local hearing
  if p.spec.audition then
    hearing = { on = hearing_on(p), item = p.heard, label = p.hearing and p.hearing.label, error = p.hear_error, waiting = p.hear_timer ~= nil }
  end
  local marked = {}
  for _, e in ipairs(p.entries) do
    if p.marked[e] then marked[#marked + 1] = e.item end
  end
  return { query = table.concat(p.query), matches = lines, selected = p.selected, item = current(p), title = p.spec.title or "Pick",
    audition = hearing, mode = p.mode, marked = marked, source = p.source }
end

local palette = require("paw.theme").palette
for name, def in pairs({
  PickPrompt = { fg = palette.blue, bold = true },
  PickCount = { fg = palette.dim },
  PickMatch = { fg = palette.orange, bold = true },
  PickSelected = { bg = palette.bg_hl },
  PickCaret = { fg = palette.orange, bold = true },
  PickMarked = { fg = palette.green, bold = true },
  PickPlaying = { fg = palette.green, bold = true },
  PickWave = { fg = palette.blue },
  PickPlayhead = { fg = palette.bg, bg = palette.orange },
}) do
  api.hl_set(name, def)
end

local SOUND = { wav = true, wave = true, aif = true, aiff = true, flac = true, mp3 = true, ogg = true, oga = true }

--- Hear a file in a picker of files: a sound file on its own, the first
--- bars of a MIDI file through an instrument. The label for the pane.
function M.hear_file(path)
  local ext = (path:match("%.([^./]+)$") or ""):lower()
  if paw.midifile.is_midi_file(path) then
    return paw.audition.try(function() return paw.audition.midi_file(path) end)
  end
  if SOUND[ext] then
    paw.audition.file(path)
    return path:match("[^/]*$")
  end
end

M.sources = require("paw.pick.sources")(M)

--- Select a file from a tree of directories:
---
---   paw.pick.file({ title = "Import audio", extensions = { "wav", "mp3" },
---                   on_choose = function(path) end })
---
--- Directories come first, and Enter opens them. `..` goes up. The list
--- shows only files with one of `extensions` (all files without it). It
--- starts in `dir`. If not given, it starts where you last selected a file,
--- then next to the project, then in the home directory. With
--- `directory = true`, the first item selects the directory that shows,
--- and `on_choose` gets it.
function M.file(opts)
  local wanted
  if opts.extensions then
    wanted = {}
    for _, ext in ipairs(opts.extensions) do wanted[ext:lower()] = true end
  end
  local function open(dir)
    dir = dir:gsub("/+$", "")
    if dir == "" then dir = "/" end
    local items = {}
    if dir ~= "/" then items[1] = { name = "..", dir = true, path = dir:match("^(.*)/[^/]+$") or "/" } end
    local dirs, files = {}, {}
    for _, entry in ipairs(api.read_dir(dir)) do
      if opts.hidden or entry.name:sub(1, 1) ~= "." then
        local path = (dir == "/" and "" or dir) .. "/" .. entry.name
        if entry.is_dir then
          dirs[#dirs + 1] = { name = entry.name, dir = true, path = path }
        elseif not wanted or wanted[(entry.name:match("%.([^.]+)$") or ""):lower()] then
          files[#files + 1] = { name = entry.name, path = path }
        end
      end
    end
    -- Choosing a directory rather than a file: this one, as the first item.
    if opts.directory then table.insert(items, 1, { name = "[choose this directory]", here = true, path = dir }) end
    for _, item in ipairs(dirs) do items[#items + 1] = item end
    for _, item in ipairs(files) do items[#items + 1] = item end
    M.open({
      title = (opts.title or "Open") .. " · " .. dir,
      items = items,
      format = function(item) return (item.dir and "▸ " or "  ") .. item.name .. (item.dir and "/" or "") end,
      empty = "nothing here to choose",
      audition_key = "files",
      audition = function(item)
        if not item.dir then return M.hear_file(item.path) end
      end,
      on_choose = function(item)
        if item.here then paw.state.pick_dir = dir return opts.on_choose(dir) end
        if item.dir then return open(item.path == "" and "/" or item.path) end
        paw.state.pick_dir = dir
        opts.on_choose(item.path)
      end,
      on_cancel = opts.on_cancel,
    })
  end
  local project = api.project_get and api.project_get("path")
  open(opts.dir or paw.state.pick_dir or (project and project:match("^(.*)/[^/]+$")) or os.getenv("HOME") or "/")
end

return setmetatable(M, { __call = function(_, spec, extra) return M.open(spec, extra) end })
