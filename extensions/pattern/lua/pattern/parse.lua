-- The parser: pattern text to a tree. See README.md beside the extension for
-- the language. Errors are tables { message, pos, text } raised with
-- `error(err, 0)`; `parse` catches them and returns nil and the error.
local names = require("pattern.names")

local M = {}

-- What the values after `# name` are, and how their words are read.
M.params = {
  vel = "number", -- 0..1 of full velocity (above 1: a MIDI velocity)
  legato = "number", -- note length as a share of the event's length
  add = "number", -- semitones added to every note (scale steps with a key)
  oct = "number", -- octaves added
  key = "pitch", -- root note: numbers become scale degrees
  scale = "scale", -- scale for degrees (with `key`, or C4 without)
  ch = "number", -- a channel number, kept in each note's meta
}

local Error = {}
Error.__index = Error
Error.__tostring = function(e) return M.format_error(e) end

--- "col 5: expected `]`", and the text with a caret under the place.
function M.format_error(e) return string.format("col %d: %s", e.pos, e.message) end

--- The text with a caret line under the error's place, for showing.
function M.caret(e) return e.text .. "\n" .. string.rep(" ", e.pos - 1) .. "^" end

--- The most times `*` repeats a step.
M.MAX_REPEAT = 256

local P = {}
P.__index = P

function P:fail(message, pos)
  error(setmetatable({ message = message, pos = pos or self.pos, text = self.text }, Error), 0)
end

function P:peek(offset)
  local at = self.pos + (offset or 0)
  return self.text:sub(at, at)
end

function P:skip() self.pos = self.text:find("[^%s]", self.pos) or #self.text + 1 end

function P:eof() return self.pos > #self.text end

function P:next_seed()
  self.seeds = self.seeds + 1
  return self.seeds - 1
end

-- `#` starts a parameter when it begins a word (a note name like `f#` has a
-- letter before it).
function P:at_param()
  return self.top and self:peek() == "#" and (self.pos == 1 or self.text:sub(self.pos - 1, self.pos - 1):match("%s"))
end

local closers = { ["]"] = true, [">"] = true, ["}"] = true, [")"] = true, [","] = true, ["|"] = true }

-- Words and numbers -------------------------------------------------------------

local function chord_mods(self, mods, pos)
  local out = {}
  for _, mod in ipairs(mods) do
    if mod:match("^%d+$") then
      out[#out + 1] = { "range", tonumber(mod) }
    elseif mod:match("^i+$") then
      out[#out + 1] = { "invert", #mod }
    elseif mod == "o" then
      out[#out + 1] = { "open" }
    elseif mod:match("^d%d+$") then
      out[#out + 1] = { "drop", tonumber(mod:sub(2)) }
    else
      self:fail("unknown chord modifier `" .. mod .. "` (a number of notes, i, ii, iii, o or d1, d2...)", pos)
    end
  end
  return out
end

--- Read one word or number at the cursor and resolve it for the current mode.
function P:atom()
  local pos = self.pos
  local text = self.text:match("^%-?%d*%.?%d+", pos)
  local is_number = text ~= nil
  if not text then text = self.text:match("^[%a][%w#]*", pos) end
  if not text then
    local ch = self:peek()
    if ch == "" then self:fail("the pattern ends where a step was expected") end
    self:fail("unexpected `" .. ch .. "`")
  end
  self.pos = pos + #text
  -- A chord: `c'maj`, `e3'min7'ii`, `60'maj'5`.
  local chord_text = self.text:match("^'[%w#']*", self.pos)
  if chord_text then self.pos = self.pos + #chord_text end
  local raw = self.text:sub(pos, self.pos - 1)
  local mode = self.mode
  if chord_text and mode ~= "note" then self:fail("a chord is not allowed here", pos) end

  local value
  if mode == "number" then
    if not is_number then self:fail("expected a number, not `" .. text .. "`", pos) end
    value = tonumber(text)
  elseif mode == "pitch" then
    local pitch = is_number and tonumber(text) or names.note(text)
    if not pitch then self:fail("expected a note name or number, not `" .. text .. "`", pos) end
    value = { kind = "note", pitch = pitch }
  elseif mode == "scale" then
    if is_number or not names.scales[text] then self:fail("unknown scale `" .. text .. "`", pos) end
    value = text
  else
    if is_number then
      local n = tonumber(text)
      if n ~= math.floor(n) then self:fail("a note number must be whole, not `" .. text .. "`", pos) end
      value = { kind = "number", n = n }
    elseif names.drums[text] or names.drums[text:lower()] then
      value = { kind = "drum", pitch = names.drums[text] or names.drums[text:lower()] }
    elseif names.note(text) then
      value = { kind = "note", pitch = names.note(text) }
    else
      self:fail("unknown name `" .. text .. "`: not a note, a number or a drum", pos)
    end
    if chord_text then
      if value.kind == "drum" then self:fail("a drum cannot be a chord", pos) end
      local parts = {}
      for part in chord_text:sub(2):gmatch("[^']+") do
        parts[#parts + 1] = part
      end
      if #parts == 0 then self:fail("expected a chord name after `'`", pos + #text) end
      local shape = names.chords[parts[1]]
      if not shape then self:fail("unknown chord `" .. parts[1] .. "`", pos + #text + 1) end
      table.remove(parts, 1)
      value = { kind = "chord", root = value, shape = shape, mods = chord_mods(self, parts, pos + #text) }
    end
  end
  return { t = "atom", v = value, pos = pos, text = raw }
end

-- Structure ---------------------------------------------------------------------

--- A term: an atom, a rest, or a bracketed group.
function P:term()
  local pos = self.pos
  local ch = self:peek()
  if ch == "[" then
    self.pos = self.pos + 1
    local layers = self:group("]")
    return #layers == 1 and layers[1] or { t = "stack", items = layers, pos = pos }
  elseif ch == "<" then
    self.pos = self.pos + 1
    local layers = self:group(">")
    return { t = "poly", layers = layers, steps = { t = "atom", v = 1 }, pos = pos }
  elseif ch == "{" then
    self.pos = self.pos + 1
    local layers = self:group("}")
    local node = { t = "poly", layers = layers, pos = pos }
    if self:peek() == "%" then
      self.pos = self.pos + 1
      node.steps = self:numeric_term()
    end
    return node
  elseif ch == "~" then
    self.pos = self.pos + 1
    return { t = "rest", pos = pos }
  end
  return self:atom()
end

--- A term whose words must be numbers: the argument of `*`, `/` and `%`.
function P:numeric_term()
  local mode = self.mode
  self.mode = "number"
  local node = self:term()
  self.mode = mode
  return node
end

--- An optional number right after a modifier, as in `a?0.3`.
function P:number_after()
  local text = self.text:match("^%d*%.?%d+", self.pos)
  if not text then return nil end
  self.pos = self.pos + #text
  return tonumber(text)
end

--- A step: a term and its modifiers. Returns the node, its weight and how
--- many times it repeats.
function P:step()
  local node = self:term()
  local weight, reps = 1, 1
  while true do
    local ch, pos = self:peek(), self.pos
    if ch == "*" or ch == "/" then
      self.pos = self.pos + 1
      if self:peek() == "" or self:peek():match("%s") then self:fail("expected a number after `" .. ch .. "`") end
      node = { t = ch == "*" and "fast" or "slow", node = node, by = self:numeric_term(), pos = pos }
      -- More would make more notes than a clip can sensibly hold.
      local by = node.by
      if ch == "*" and by.t == "atom" and type(by.v) == "number" and by.v > M.MAX_REPEAT then
        self:fail("at most " .. M.MAX_REPEAT .. " repeats in a step", pos)
      end
    elseif ch == "(" then
      self.pos = self.pos + 1
      local args = {}
      local mode = self.mode
      self.mode = "number"
      repeat
        args[#args + 1] = self:group(nil, true)[1]
        local sep = self:peek()
        if sep == "," then self.pos = self.pos + 1 end
      until sep ~= ","
      self.mode = mode
      if self:peek() ~= ")" then self:fail("expected `)`") end
      self.pos = self.pos + 1
      if #args < 2 or #args > 3 then
        self:fail("a Euclidean rhythm takes 2 or 3 numbers: (hits,steps) or (hits,steps,rotation)", pos)
      end
      node = { t = "euclid", node = node, args = args, pos = pos }
    elseif ch == "?" then
      self.pos = self.pos + 1
      local prob = self:number_after() or 0.5
      if prob > 1 then self:fail("a probability is between 0 and 1", pos + 1) end
      node = { t = "degrade", node = node, prob = prob, seed = self:next_seed(), pos = pos }
    elseif ch == "!" then
      self.pos = self.pos + 1
      local n = self:number_after()
      if n and n ~= math.floor(n) then self:fail("`!` takes a whole number", pos + 1) end
      reps = n and reps * n or reps + 1
    elseif ch == "@" then
      self.pos = self.pos + 1
      local w = self:number_after()
      if not w then self:fail("expected a number after `@`") end
      weight = w
    else
      break
    end
  end
  return node, weight, reps
end

--- A sequence of steps, up to a closing bracket, `,`, `|` or the end.
function P:sequence()
  local pos = self.pos
  local groups, steps = {}, {}
  while true do
    self:skip()
    local ch = self:peek()
    if ch == "" or closers[ch] or self:at_param() then break end
    local at = self.pos
    if ch == "." and self:peek(1) == "." then
      -- A range: `0 .. 3`.
      self.pos = self.pos + 2
      local last = steps[#steps]
      if not last or last.node.t ~= "atom" or last.node.v.kind ~= "number" then
        self:fail("`..` needs a whole number before it", at)
      end
      self:skip()
      local stop = self:atom()
      if type(stop.v) ~= "table" or stop.v.kind ~= "number" then
        self:fail("`..` needs a whole number after it", stop.pos)
      end
      local from, to = last.node.v.n, stop.v.n
      local dir = to >= from and 1 or -1
      for n = from + dir, to, dir do
        steps[#steps + 1] =
          { node = { t = "atom", v = { kind = "number", n = n }, pos = stop.pos, text = tostring(n) }, weight = 1 }
      end
    elseif ch == "." and (self:peek(1) == "" or self:peek(1):match("%s")) then
      -- `a b . c d` groups into `[a b] [c d]`.
      self.pos = self.pos + 1
      if #steps == 0 then self:fail("`.` needs steps before it", at) end
      groups[#groups + 1] = steps
      steps = {}
    elseif ch == "_" then
      self.pos = self.pos + 1
      local last = steps[#steps]
      if not last then self:fail("`_` needs a step before it to lengthen", at) end
      last.weight = last.weight + 1
    elseif ch == "!" and (self:peek(1) == "" or self:peek(1):match("%s")) then
      self.pos = self.pos + 1
      local last = steps[#steps]
      if not last then self:fail("`!` needs a step before it to repeat", at) end
      steps[#steps + 1] = { node = last.node, weight = last.weight }
    else
      local node, weight, reps = self:step()
      for _ = 1, reps do
        steps[#steps + 1] = { node = node, weight = weight }
      end
      local after = self:peek()
      if after ~= "" and not after:match("%s") and not closers[after] then
        self:fail("unexpected `" .. after .. "` (steps are separated by spaces)")
      end
    end
  end
  if #groups > 0 then
    if #steps == 0 then self:fail("`.` needs steps after it") end
    groups[#groups + 1] = steps
    local outer = {}
    for i, g in ipairs(groups) do
      outer[i] = { node = { t = "seq", steps = g, pos = pos }, weight = 1 }
    end
    steps = outer
  end
  return { t = "seq", steps = steps, pos = pos }
end

--- The inside of brackets: sequences separated by `,` (played together) and
--- `|` (one chosen at random each cycle; `|` binds tighter than `,`).
--- Consumes the closing bracket when one is given. With `single` it stops
--- at a `,` (the arguments of a Euclidean rhythm).
function P:group(closer, single)
  local open = self.pos - 1
  local layers = {}
  while true do
    local options = { self:sequence() }
    while self:peek() == "|" do
      self.pos = self.pos + 1
      options[#options + 1] = self:sequence()
    end
    for _, option in ipairs(options) do
      -- An empty pattern or parameter is reported by the caller, which knows what it is.
      if #option.steps == 0 and (closer or single or #options > 1) and not (closer and self:eof()) then
        self:fail("empty sequence", option.pos)
      end
    end
    layers[#layers + 1] = #options == 1 and options[1]
      or { t = "choose", items = options, seed = self:next_seed(), pos = options[1].pos }
    if single or self:peek() ~= "," then break end
    self.pos = self.pos + 1
  end
  if closer then
    local ch = self:peek()
    if ch ~= closer then
      if ch == "" then self:fail("missing `" .. closer .. "` for the bracket at col " .. open, open) end
      self:fail("expected `" .. closer .. "`, not `" .. ch .. "`")
    end
    self.pos = self.pos + 1
  end
  return layers
end

--- Parse a whole pattern: the notes, then any `# name values` parameters.
--- Returns { main = node, params = { name = node }, seeds = n } or nil, error.
function M.parse(text)
  if type(text) ~= "string" then
    return nil, setmetatable({ message = "a pattern is text", pos = 1, text = tostring(text) }, Error)
  end
  local self = setmetatable({ text = text, pos = 1, seeds = 0, mode = "note", top = true }, P)
  local ok, result = pcall(function()
    local layers = self:group(nil)
    local main = #layers == 1 and layers[1] or { t = "stack", items = layers, pos = 1 }
    local params, order = {}, {}
    while not self:eof() do
      local ch = self:peek()
      if self:at_param() then
        local at = self.pos
        self.pos = self.pos + 1
        self:skip()
        local name = self.text:match("^[%a_]+", self.pos)
        if not name then self:fail("expected a parameter name after `#`") end
        if not M.params[name] then
          local known = {}
          for k in pairs(M.params) do
            known[#known + 1] = k
          end
          table.sort(known)
          self:fail("unknown parameter `" .. name .. "` (" .. table.concat(known, ", ") .. ")")
        end
        if params[name] then self:fail("`" .. name .. "` is given twice", at) end
        self.pos = self.pos + #name
        self.mode = M.params[name]
        local values = self:group(nil)
        self.mode = "note"
        local node = #values == 1 and values[1] or { t = "stack", items = values, pos = at }
        if node.t == "seq" and #node.steps == 0 then self:fail("`" .. name .. "` needs a value") end
        params[name] = node
        order[#order + 1] = name
      elseif ch == "]" or ch == ">" or ch == "}" or ch == ")" then
        self:fail("`" .. ch .. "` without an opening bracket")
      else
        self:fail("unexpected `" .. ch .. "`")
      end
    end
    if main.t == "seq" and #main.steps == 0 then self:fail("the pattern is empty", 1) end
    return { main = main, params = params, order = order, seeds = self.seeds, text = text }
  end)
  if ok then return result end
  if getmetatable(result) == Error then return nil, result end
  error(result, 0)
end

M.Error = Error
return M
