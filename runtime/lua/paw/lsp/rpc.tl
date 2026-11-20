-- JSON-RPC messages as bytes, both ways: newline-delimited JSON (one message
-- a line, as MIDI LSP's engine speaks on `--stdio`) or LSP's
-- `Content-Length` headers.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type util = require("paw.util")

--- How messages are cut from the bytes: one a line (the default), or
--- LSP's `Content-Length` headers.
local enum Framing
  "lines" "headers"
end

--- A JSON value whose shape the method of its message names (the `params`
--- of a request, the `result` of an answer, a subject's document). The code
--- that reads one casts it once to the record of that method.
local record Payload
end

--- What a JSON value is in Lua: text, a number, true or false, or a table
--- (a list or an object).
local type Json = util.Data

--- The error of an answer, as JSON-RPC has it.
local record RpcError
  code: integer
  message: string
  data: Payload
end

--- A request's id: a number from this program, a number or text from a server.
local type Id = integer | string

--- A JSON-RPC message: a request (`id` and `method`), a notification
--- (`method` only) or an answer (`id` with `result` or `error`). A part of
--- the bytes that is not JSON comes as `{ invalid = text, error = why }`.
local record Message
  jsonrpc: string
  id: Id
  method: string
  params: Payload
  result: Payload
  error: string | RpcError
  invalid: string
end

--- What takes bytes as they arrive and gives back whole messages.
local record Reader
  push: function(self: Reader, bytes: string): {Message}
end

local record M
  type Framing = Framing
  type Payload = Payload
  type Json = Json
  type RpcError = RpcError
  type Id = Id
  type Message = Message
  type Reader = Reader
end

local object_mt: metatable<{Json:Json}> = {}

--- A table that is written as a JSON object even when it is empty
--- (`{}` alone is written as `[]`): `t`, or a new table.
function M.object(t?: {string:Json}): Payload
  return setmetatable((t or {}) as {Json:Json}, object_mt) as Payload
end

local escapes: {string:string} = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function is_array(t: {Json:Json}): boolean
  if getmetatable(t) == object_mt then return false end
  local n = #(t as {Json})
  if n == 0 then return next(t) == nil end
  for k in pairs(t) do
    if k is number then
      if k < 1 or k > n or k % 1 ~= 0 then return false end
    else
      return false
    end
  end
  return true
end

local encode: function(t: {Json:Json}, out: {string})

local function value(v: Json, out: {string})
  if v is string then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c: string): string return escapes[c] or string.format("\\u%04x", c:byte()) end) .. '"'
  elseif v is number then
    -- Whole numbers as integers: ticks, pitches and ids are integers to a
    -- server, and Lua has only one kind of number.
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif v % 1 == 0 and math.abs(v) < 2 ^ 53 then
      out[#out + 1] = string.format("%d", math.floor(v))
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif v is boolean then
    out[#out + 1] = tostring(v)
  elseif v is {Json:Json} then
    encode(v, out)
  else
    out[#out + 1] = "null"
  end
end

encode = function(t: {Json:Json}, out: {string})
  if is_array(t) then
    out[#out + 1] = "["
    for i, v in ipairs(t as {Json}) do
      if i > 1 then out[#out + 1] = "," end
      value(v, out)
    end
    out[#out + 1] = "]"
  else
    out[#out + 1] = "{"
    local first = true
    for k, v in pairs(t) do
      if not first then out[#out + 1] = "," end
      first = false
      value(tostring(k), out)
      out[#out + 1] = ":"
      value(v, out)
    end
    out[#out + 1] = "}"
  end
end

--- A value as JSON text: text, a number, true or false, or a table of them.
function M.encode<T>(v: T): string
  local out: {string} = {}
  value(v as Json, out)
  return table.concat(out)
end

--- A message as the bytes to send in `framing` ("lines" or "headers").
function M.frame<T>(message: T, framing?: Framing): string
  local text = M.encode(message)
  if framing == "headers" then return "Content-Length: " .. #text .. "\r\n\r\n" .. text end
  return text .. "\n"
end

--- Something that takes bytes as they arrive and gives back whole messages:
---   local reader = rpc.reader("lines")
---   for _, message in ipairs(reader:push(bytes)) do ... end
--- A part that is not JSON is given back as `{ invalid = text, error = why }`.
function M.reader(framing?: Framing): Reader
  local buffer = ""
  local self: Reader = {}
  local function decode(text: string, out: {Message})
    local message, err = api.json_decode(text)
    -- The one place a message comes in: JSON as the kernel reads it.
    out[#out + 1] = type(message) == "table" and message as Message or { invalid = text, error = err or "not an object" }
  end
  function self:push(bytes: string): {Message}
    buffer = buffer .. bytes
    local out: {Message} = {}
    if framing == "headers" then
      while true do
        local head_end = buffer:find("\r\n\r\n", 1, true)
        if not head_end then break end
        local length = tonumber(buffer:sub(1, head_end):match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
        if not length then
          -- Not a header we understand: drop it and look for the next one.
          buffer = buffer:sub(head_end + 4)
        elseif #buffer < head_end + 3 + length then
          break
        else
          decode(buffer:sub(head_end + 4, head_end + 3 + math.floor(length)), out)
          buffer = buffer:sub(head_end + 4 + math.floor(length))
        end
      end
    else
      while true do
        local nl = buffer:find("\n", 1, true)
        if not nl then break end
        local line = buffer:sub(1, nl - 1)
        buffer = buffer:sub(nl + 1)
        if line:match("%S") then decode(line, out) end
      end
    end
    return out
  end
  return self
end

return M
