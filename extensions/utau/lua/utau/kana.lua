-- Romaji <-> hiragana conversion for lyric batch edits (Hepburn plus the
-- common kunrei/wapuro spellings), in LuaJIT, which has no
-- `utf8` library. Text that is not entirely convertible
-- is left alone, so mixed lyrics ("R", "+", "a ka", English) are never
-- half-converted.
local K = {}

local ROMA = {
  a = "あ",
  i = "い",
  u = "う",
  e = "え",
  o = "お",
  ka = "か",
  ki = "き",
  ku = "く",
  ke = "け",
  ko = "こ",
  sa = "さ",
  shi = "し",
  si = "し",
  su = "す",
  se = "せ",
  so = "そ",
  ta = "た",
  chi = "ち",
  ti = "ち",
  tsu = "つ",
  tu = "つ",
  te = "て",
  to = "と",
  na = "な",
  ni = "に",
  nu = "ぬ",
  ne = "ね",
  no = "の",
  ha = "は",
  hi = "ひ",
  fu = "ふ",
  hu = "ふ",
  he = "へ",
  ho = "ほ",
  ma = "ま",
  mi = "み",
  mu = "む",
  me = "め",
  mo = "も",
  ya = "や",
  yu = "ゆ",
  yo = "よ",
  ra = "ら",
  ri = "り",
  ru = "る",
  re = "れ",
  ro = "ろ",
  wa = "わ",
  wi = "うぃ",
  we = "うぇ",
  wo = "を",
  n = "ん",
  nn = "ん",
  ga = "が",
  gi = "ぎ",
  gu = "ぐ",
  ge = "げ",
  go = "ご",
  za = "ざ",
  ji = "じ",
  zi = "じ",
  zu = "ず",
  ze = "ぜ",
  zo = "ぞ",
  da = "だ",
  di = "ぢ",
  du = "づ",
  de = "で",
  ["do"] = "ど",
  ba = "ば",
  bi = "び",
  bu = "ぶ",
  be = "べ",
  bo = "ぼ",
  pa = "ぱ",
  pi = "ぴ",
  pu = "ぷ",
  pe = "ぺ",
  po = "ぽ",
  kya = "きゃ",
  kyu = "きゅ",
  kyo = "きょ",
  gya = "ぎゃ",
  gyu = "ぎゅ",
  gyo = "ぎょ",
  sha = "しゃ",
  shu = "しゅ",
  sho = "しょ",
  sya = "しゃ",
  syu = "しゅ",
  syo = "しょ",
  she = "しぇ",
  ja = "じゃ",
  ju = "じゅ",
  jo = "じょ",
  je = "じぇ",
  zya = "じゃ",
  zyu = "じゅ",
  zyo = "じょ",
  cha = "ちゃ",
  chu = "ちゅ",
  cho = "ちょ",
  tya = "ちゃ",
  tyu = "ちゅ",
  tyo = "ちょ",
  che = "ちぇ",
  nya = "にゃ",
  nyu = "にゅ",
  nyo = "にょ",
  hya = "ひゃ",
  hyu = "ひゅ",
  hyo = "ひょ",
  bya = "びゃ",
  byu = "びゅ",
  byo = "びょ",
  pya = "ぴゃ",
  pyu = "ぴゅ",
  pyo = "ぴょ",
  mya = "みゃ",
  myu = "みゅ",
  myo = "みょ",
  rya = "りゃ",
  ryu = "りゅ",
  ryo = "りょ",
  fa = "ふぁ",
  fi = "ふぃ",
  fe = "ふぇ",
  fo = "ふぉ",
  tsa = "つぁ",
  thi = "てぃ",
  dhi = "でぃ",
  twu = "とぅ",
  dwu = "どぅ",
  va = "ゔぁ",
  vi = "ゔぃ",
  vu = "ゔ",
  ve = "ゔぇ",
  vo = "ゔぉ",
}

-- preferred spelling for kana -> romaji (Hepburn)
local PREFER = {
  ["し"] = "shi",
  ["ち"] = "chi",
  ["つ"] = "tsu",
  ["ふ"] = "fu",
  ["じ"] = "ji",
  ["ん"] = "n",
  ["を"] = "wo",
  ["ぢ"] = "di",
  ["づ"] = "du",
  ["しゃ"] = "sha",
  ["しゅ"] = "shu",
  ["しょ"] = "sho",
  ["じゃ"] = "ja",
  ["じゅ"] = "ju",
  ["じょ"] = "jo",
  ["ちゃ"] = "cha",
  ["ちゅ"] = "chu",
  ["ちょ"] = "cho",
}
local KANA = {}
for r, k in pairs(ROMA) do
  if not KANA[k] or (#r < #KANA[k]) then KANA[k] = r end
end
for k, r in pairs(PREFER) do
  KANA[k] = r
end

local SMALL_TSU = "っ"

local function utf8_chars(s)
  local t = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    t[#t + 1] = ch
  end
  return t
end

-- Only kana are converted, all of them three bytes long in UTF-8.
local function codepoint(ch)
  if #ch ~= 3 then return -1 end
  local a, b, c = ch:byte(1, 3)
  return ((a - 224) * 64 + (b - 128)) * 64 + (c - 128)
end

local function char3(cp) return string.char(224 + math.floor(cp / 4096), 128 + math.floor(cp / 64) % 64, 128 + cp % 64) end

--- "ka" -> "か", "kka" -> "っか", "kyo" -> "きょ". Returns nil when the text is not plain romaji.
function K.to_hiragana(text)
  local s = text:lower()
  if s == "" or s:find("[^a-z']") then return nil end
  local out, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "'" then
      i = i + 1
    elseif (c ~= "n" and c:match("[bcdfghjkmprstvwz]") and s:sub(i + 1, i + 1) == c) or s:sub(i, i + 2) == "tch" then
      out[#out + 1] = SMALL_TSU
      i = i + 1
    elseif c == "n" and s:sub(i + 1, i + 1) == "n" then
      -- "nn" is ん, except "nni" = ん + に (IME rule: the second n starts the next syllable before a vowel / y)
      out[#out + 1] = "ん"
      i = i + (s:sub(i + 2, i + 2):match("[aiueoy]") and 1 or 2)
    else
      local hit
      for len = 3, 1, -1 do
        local k = ROMA[s:sub(i, i + len - 1)]
        -- a lone "n" before a vowel or "y" belongs to the next syllable
        if k and not (len == 1 and c == "n" and s:sub(i + 1, i + 1):match("[aiueoy]")) then
          hit = len
          out[#out + 1] = k
          break
        end
      end
      if not hit then return nil end
      i = i + hit
    end
  end
  return table.concat(out)
end

--- "か" -> "ka", "っか" -> "kka", "きょ" -> "kyo". Katakana is converted too. Returns nil when not pure kana.
function K.to_romaji(text)
  if text == "" then return nil end
  local chars = utf8_chars(text)
  -- katakana -> hiragana (U+30A1..U+30F6 -> U+3041..U+3096)
  for i, ch in ipairs(chars) do
    local cp = codepoint(ch)
    if cp >= 0x30A1 and cp <= 0x30F6 then chars[i] = char3(cp - 0x60) end
  end
  local out, i, double = {}, 1, false
  while i <= #chars do
    local ch = chars[i]
    if ch == SMALL_TSU then
      double = true
      i = i + 1
    elseif ch == "ー" then
      local last = out[#out]
      if not last then return nil end
      out[#out + 1] = last:sub(-1)
      i = i + 1
    else
      local r
      if chars[i + 1] then r = KANA[ch .. chars[i + 1]] end
      local n = 2
      if not r then
        r, n = KANA[ch], 1
      end
      if not r then return nil end
      if double then
        r = (r:sub(1, 2) == "ch" and "t" or r:sub(1, 1)) .. r
        double = false
      end
      out[#out + 1] = r
      i = i + n
    end
  end
  if double then out[#out + 1] = "t" end
  return table.concat(out)
end

return K
