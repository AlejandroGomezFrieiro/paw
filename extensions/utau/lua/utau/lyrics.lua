-- Lyrics as text: splitting text into one syllable per note, and the lyric
-- sheet, where a clip's lyrics read one line per phrase.
local notes = require("utau.notes")

local M = {}

--- A gap of this many beats, or a rest, starts a new line of the sheet.
M.PHRASE_GAP = 1

local function codepoints(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local b1, b2, b3, b4 = ch:byte(1, -1)
    local cp
    if #ch == 1 then
      cp = b1
    elseif #ch == 2 then
      cp = (b1 - 192) * 64 + (b2 - 128)
    elseif #ch == 3 then
      cp = ((b1 - 224) * 64 + (b2 - 128)) * 64 + (b3 - 128)
    else
      cp = (((b1 - 240) * 64 + (b2 - 128)) * 64 + (b3 - 128)) * 64 + (b4 - 128)
    end
    out[#out + 1] = { ch = ch, cp = cp }
  end
  return out
end

local function japanese(cp)
  return (cp >= 0x3040 and cp <= 0x30FF) or (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0xFF66 and cp <= 0xFF9F)
end

-- Small kana, the long vowel mark and voicing marks belong to the kana before them.
local SMALL = {}
for _, cp in ipairs({
  0x30FC,
  0x3099,
  0x309A,
  0x3041,
  0x3043,
  0x3045,
  0x3047,
  0x3049,
  0x3083,
  0x3085,
  0x3087,
  0x308E,
  0x30A1,
  0x30A3,
  0x30A5,
  0x30A7,
  0x30A9,
  0x30E3,
  0x30E5,
  0x30E7,
  0x30EE,
}) do
  SMALL[cp] = true
end

--- Words of a text, one per note. With `per_kana`, Japanese runs are split
--- into one syllable per kana as well.
function M.tokens(text, per_kana)
  local out = {}
  for word in tostring(text or ""):gmatch("%S+") do
    local chars = per_kana and codepoints(word) or nil
    local jp = false
    for _, c in ipairs(chars or {}) do
      jp = jp or japanese(c.cp)
    end
    if jp then
      local current
      for _, c in ipairs(chars) do
        if current and SMALL[c.cp] then
          current = current .. c.ch
        else
          if current then out[#out + 1] = current end
          current = c.ch
        end
      end
      if current then out[#out + 1] = current end
    else
      out[#out + 1] = word
    end
  end
  return out
end

--- The sheet of a clip: its text, and the lines as `{ first, last }` note indexes.
function M.sheet(clip_id, default)
  local list = notes.list(clip_id)
  local lines, words, text = {}, {}, {}
  for i, n in ipairs(list) do
    local prev = list[i - 1]
    if prev and (n.start - (prev.start + prev.length) >= M.PHRASE_GAP - 1e-9 or notes.is_rest(notes.lyric(prev))) then
      text[#text + 1] = table.concat(words, " ")
      lines[#lines].last = i - 1
      words = {}
    end
    if #words == 0 then lines[#lines + 1] = { first = i, last = i } end
    words[#words + 1] = notes.lyric(n) or default or "a"
  end
  if #words > 0 then
    text[#text + 1] = table.concat(words, " ")
    lines[#lines].last = #list
  end
  return table.concat(text, "\n"), lines, list
end

--- Give the clip's notes, from `first` on (up to `last`), the words of
--- `text` in time order. Extra words are ignored, notes past the words keep
--- their lyrics.
--- Returns how many lyrics changed, and the number of words.
function M.apply(clip_id, text, opts)
  opts = opts or {}
  local words = M.tokens(text, opts.per_kana)
  local first, last = opts.first or 1, opts.last or math.huge
  local changed = notes.change(clip_id, function(note, index)
    local word = index <= last and words[index - first + 1]
    if not word or note.lyric == word then return false end
    note.lyric = word
    return true
  end)
  return changed, #words
end

return M
