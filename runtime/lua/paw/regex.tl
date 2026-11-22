-- `paw.regex`: regular expressions of the common kind, made into Lua
-- patterns, for the pickers' regex mode, `:vimgrep` and `paw.query`.
--
--   local re = paw.regex.compile("pizz|spicc")
--   re:find("Violins pizz")   --> 9, 12
--
-- What is understood: `.` `*` `+` `?` `{n}` `{n,m}` `{n,}` `^` `$`,
-- classes `[abc]` `[^a-z]`, `\d` `\w` `\s` (and `\D` `\W` `\S`), `\` before
-- any other character for itself, `|` between alternatives, and `( )` to
-- group alternatives that do not repeat. Lower case matches either case;
-- a capital letter makes the whole expression match case, as 'smartcase'.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

--- What `compile` takes: `case` true matches case, false ignores it.
local record Options
  case: boolean
end

--- An expression ready to match: its text, whether it ignores case, and
--- the Lua patterns of its alternatives.
local record Regex
  text: string
  fold: boolean
  patterns: {string}
end

local record M
end

local metatable_of_regex: metatable<Regex> = {__index = Regex}

local MAGIC = "^$()%.[]*+-?"
local CLASS: {string: string} = {d = "%d", D = "%D", w = "[%w_]", W = "[^%w_]", s = "%s", S = "%S"}
local IN_CLASS: {string: string} = {d = "%d", D = "%D", w = "%w_", s = "%s", S = "%S"}

local function fail(text: string, why: string)
  error(string.format("`%s`: %s", text, why), 0)
end

local function literal(c: string, fold: boolean): string
  if fold then
    c = c:lower()
  end
  if MAGIC:find(c, 1, true) then
    return "%" .. c
  end
  return c
end

--- Split at the `|`s that are not escaped, inside a class or a group.
local function alternatives(text: string): {string}
  local out: {string} = {}
  local depth, at, i = 0, 1, 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == "\\" then
      i = i + 1
    elseif c == "[" then
      local close = text:find("]", i + (text:sub(i + 1, i + 1) == "^" and 3 or 2), true)
      if not close then
        fail(text, "a `[` is not closed")
      end
      i = close
    elseif c == "(" then
      depth = depth + 1
    elseif c == ")" then
      depth = depth - 1
    elseif c == "|" and depth == 0 then
      out[#out + 1] = text:sub(at, i - 1)
      at = i + 1
    end
    i = i + 1
  end
  out[#out + 1] = text:sub(at)
  return out
end

--- One alternative as a Lua pattern.
local record Atom
  text: string
  atom: boolean
  quantified: boolean
end

local function translate(text: string, fold: boolean, whole: string): string
  local out: {Atom} = {} -- atoms, each a piece of pattern a quantifier may follow
  local i = 1
  local function last_atom(): Atom
    local a = out[#out]
    if not a or a.quantified or not a.atom then
      fail(whole, "a repeat with nothing before it to repeat")
    end
    return a
  end
  while i <= #text do
    local c = text:sub(i, i)
    if c == "\\" then
      local n = text:sub(i + 1, i + 1)
      if n == "" then
        fail(whole, "a `\\` at the end")
      end
      out[#out + 1] = {text = CLASS[n] or literal(n, fold), atom = true}
      i = i + 2
    elseif c == "[" then
      local j = i + 1
      local body: {string} = {"["}
      if text:sub(j, j) == "^" then
        body[#body + 1] = "^"
        j = j + 1
      end
      local first = true
      while true do
        local ch = text:sub(j, j)
        if ch == "" then
          fail(whole, "a `[` is not closed")
        end
        if ch == "]" and not first then
          break
        end
        if ch == "\\" then
          local n = text:sub(j + 1, j + 1)
          body[#body + 1] = IN_CLASS[n] or ("%" .. n)
          j = j + 2
        else
          if ch == "%" or ch == "]" then
            body[#body + 1] = "%" .. ch
          else
            body[#body + 1] = fold and ch:lower() or ch
          end
          j = j + 1
        end
        first = false
      end
      body[#body + 1] = "]"
      out[#out + 1] = {text = table.concat(body), atom = true}
      i = j + 1
    elseif c == "." then
      out[#out + 1] = {text = ".", atom = true}
      i = i + 1
    elseif c == "*" or c == "+" or c == "?" then
      local a = last_atom()
      a.text, a.quantified = a.text .. (c == "*" and "*" or c == "+" and "+" or "?"), true
      i = i + 1
    elseif c == "{" then
      local lo_text, comma, hi_text, close_at = text:match("^{(%d*)(,?)(%d*)}()", i)
      local close = tonumber(close_at) as integer
      if not close then
        out[#out + 1] = {text = literal(c, fold), atom = true}
        i = i + 1
      else
        local a = last_atom()
        local lo = tonumber(lo_text) as integer or 0
        local hi = comma == "" and lo or tonumber(hi_text) as integer
        if hi and hi < lo then
          fail(whole, "a repeat `{n,m}` with m less than n")
        end
        local base = a.text
        local parts: {string} = {}
        for _ = 1, lo do
          parts[#parts + 1] = base
        end
        if hi then
          for _ = lo + 1, hi do
            parts[#parts + 1] = base .. "?"
          end
        else
          parts[#parts + 1] = base .. "*"
        end
        a.text, a.quantified = table.concat(parts), true
        i = close
      end
    elseif c == "(" or c == ")" then
      -- A group that holds no alternatives only groups: it goes, unless
      -- something would repeat it, which Lua's patterns cannot.
      local after = text:sub(i + 1, i + 1)
      if c == ")" and (after == "*" or after == "+" or after == "?" or after == "{") then
        fail(whole, "a group cannot repeat: repeat one character or class")
      end
      out[#out + 1] = {text = ""}
      i = i + 1
    elseif c == "^" and #out == 0 then
      out[#out + 1] = {text = "^"}
      i = i + 1
    elseif c == "$" and i == #text then
      out[#out + 1] = {text = "$"}
      i = i + 1
    else
      out[#out + 1] = {text = literal(c, fold), atom = true}
      i = i + 1
    end
  end
  local parts: {string} = {}
  for k, a in ipairs(out) do
    parts[k] = a.text
  end
  return table.concat(parts)
end

--- Expand a group of alternatives inside an alternative (`(pizz|spicc)ato`)
--- into whole alternatives, since a Lua pattern has none.
local function expand(alt: string, whole: string): {string}
  local open: integer = nil
  local depth, i = 0, 1
  while i <= #alt do
    local c = alt:sub(i, i)
    if c == "\\" then
      i = i + 1
    elseif c == "[" then
      i = alt:find("]", i + (alt:sub(i + 1, i + 1) == "^" and 3 or 2), true) or #alt
    elseif c == "(" then
      if depth == 0 then
        open = i
      end
      depth = depth + 1
    elseif c == ")" then
      depth = depth - 1
      if depth == 0 and open then
        local inner = alt:sub(open + 1, i - 1)
        local subs = alternatives(inner)
        if #subs > 1 then
          local out: {string} = {}
          for _, s in ipairs(subs) do
            for _, rest in ipairs(expand(alt:sub(1, open - 1) .. s .. alt:sub(i + 1), whole)) do
              out[#out + 1] = rest
            end
          end
          return out
        end
        open = nil
      end
    end
    i = i + 1
  end
  if depth ~= 0 then
    fail(whole, "a `(` is not closed")
  end
  return {alt}
end

--- Whether an expression has a capital letter of its own (not one of `\D`).
local function has_capital(text: string): boolean
  return text:gsub("\\.", ""):find("%u") ~= nil
end

--- Where the expression first matches in `s`: start and end, or nil.
function Regex:find(s: string, init?: integer): integer, integer
  if self.fold then
    s = s:lower()
  end
  local best_a, best_b: integer, integer
  for _, pat in ipairs(self.patterns) do
    local a, b = s:find(pat, init)
    if a and (not best_a or a < best_a or (a == best_a and b > best_b)) then
      best_a, best_b = a, b
    end
  end
  return best_a, best_b
end

--- Whether the expression matches anywhere in `s`.
function Regex:test(s: string): boolean
  return self:find(s) ~= nil
end

--- Make an expression ready to match. If it is not correct, raise an error
--- that tells the problem. `opts.case` true matches case, and false ignores
--- case. By default, an expression in lowercase ignores case.
function M.compile(text: string, opts?: Options): Regex
  text = tostring(text or "")
  local fold: boolean
  if opts and opts.case ~= nil then
    fold = not opts.case
  else
    fold = not has_capital(text)
  end
  local patterns: {string} = {}
  for _, alt in ipairs(alternatives(text)) do
    for _, one in ipairs(expand(alt, text)) do
      local pat = translate(one, fold, text)
      -- Check it is a pattern Lua takes, now rather than at the first match.
      local ok, err = pcall(string.find, "", pat)
      if not ok then
        fail(text, (tostring(err):gsub("^.-: ", "")))
      end
      patterns[#patterns + 1] = pat
    end
  end
  return setmetatable({text = text, fold = fold, patterns = patterns} as Regex, metatable_of_regex)
end

--- An expression ready to match, or nil and what is wrong with it.
function M.try(text: string, opts?: Options): Regex, string
  local ok, re = pcall(M.compile, text, opts)
  if ok then
    return re as Regex
  end
  return nil, tostring(re)
end

return M
