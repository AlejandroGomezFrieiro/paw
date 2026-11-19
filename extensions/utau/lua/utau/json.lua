-- A small JSON writer and reader, for what the extension writes to files
-- and hands to `paw-utau-engine --export`: objects, arrays, strings, numbers,
-- booleans. A table is an array when it has `[1]` or is marked with
-- `M.array`; an empty table is an object unless marked.
local M = {}

local ARRAY = setmetatable({}, { __mode = "k" })

--- Mark a table as an array, so that it is written as one even when empty.
function M.array(t)
  t = t or {}
  ARRAY[t] = true
  return t
end

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }

local function write(v, out, indent, depth)
  local t = type(v)
  if t == "table" then
    local nl = indent and ("\n" .. string.rep(indent, depth + 1)) or ""
    local close = indent and ("\n" .. string.rep(indent, depth)) or ""
    if ARRAY[v] or v[1] ~= nil then
      if #v == 0 then out[#out + 1] = "[]" return end
      out[#out + 1] = "["
      for i, x in ipairs(v) do
        out[#out + 1] = (i > 1 and "," or "") .. nl
        write(x, out, indent, depth + 1)
      end
      out[#out + 1] = close .. "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      if #keys == 0 then out[#out + 1] = "{}" return end
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        out[#out + 1] = (i > 1 and "," or "") .. nl
        write(k, out, indent, depth + 1)
        out[#out + 1] = indent and ": " or ":"
        local value = v[k]
        if value == nil then value = v[tonumber(k)] end
        write(value, out, indent, depth + 1)
      end
      out[#out + 1] = close .. "}"
    end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "0"
    elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  else
    out[#out + 1] = "null"
  end
end

--- JSON text for a value; `indent` (such as "  ") makes it readable.
function M.encode(v, indent)
  local out = {}
  write(v, out, indent, 0)
  return table.concat(out)
end

local function utf8(code)
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64) end
  return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

--- The value of a JSON text. Errors on text that is not JSON.
function M.decode(s)
  local pos = 1
  local function fail(what) error(string.format("bad JSON at %d: %s", pos, what), 0) end
  local function space() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local value
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == '"' then pos = pos + 1 break end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if e == "u" then
          local code = tonumber(s:sub(pos + 2, pos + 5), 16) or fail("bad escape")
          if code >= 0xD800 and code < 0xDC00 and s:sub(pos + 6, pos + 7) == "\\u" then
            local low = tonumber(s:sub(pos + 8, pos + 11), 16) or fail("bad escape")
            code = 0x10000 + (code - 0xD800) * 1024 + (low - 0xDC00)
            local b = { 0xF0 + math.floor(code / 262144), 0x80 + math.floor(code / 4096) % 64,
              0x80 + math.floor(code / 64) % 64, 0x80 + code % 64 }
            out[#out + 1] = string.char(unpack(b))
            pos = pos + 12
          else
            out[#out + 1] = utf8(code)
            pos = pos + 6
          end
        else
          out[#out + 1] = map[e] or fail("bad escape")
          pos = pos + 2
        end
      else
        local stop = s:find('["\\]', pos) or #s + 1
        out[#out + 1] = s:sub(pos, stop - 1)
        pos = stop
      end
    end
    return table.concat(out)
  end
  function value()
    space()
    local c = s:sub(pos, pos)
    if c == "{" then
      local obj = {}
      pos = pos + 1
      space()
      if s:sub(pos, pos) == "}" then pos = pos + 1 return obj end
      while true do
        space()
        if s:sub(pos, pos) ~= '"' then fail("expected a key") end
        local k = str()
        space()
        if s:sub(pos, pos) ~= ":" then fail("expected `:`") end
        pos = pos + 1
        obj[k] = value()
        space()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then fail("expected `,` or `}`") end
      end
    elseif c == "[" then
      local arr = M.array({})
      pos = pos + 1
      space()
      if s:sub(pos, pos) == "]" then pos = pos + 1 return arr end
      while true do
        arr[#arr + 1] = value()
        space()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then fail("expected `,` or `]`") end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then fail("unexpected `" .. c .. "`") end
      pos = pos + #num
      return tonumber(num) or fail("bad number")
    end
  end
  local v = value()
  space()
  if pos <= #s then fail("text after the value") end
  return v
end

return M
