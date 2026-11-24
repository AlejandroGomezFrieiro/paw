-- `paw.modifiers`: the modifier stack of a MIDI clip as Lua reads it. The
-- kernel runs the stack (crates/paw-core/src/model/modifiers.rs). This
-- module gives the words of each entry (the label of a clip, `K`, the
-- list of `:clip.stack`), the top of the stack that the piano roll and
-- the readers of a clip use (`prefix`), and a copy of a stack to change.
-- The top is the part of the stack that Lua can apply and take back: a
-- `transpose` and a `velocity` change for all of the clip.
--
-- Each function takes the entries of a clip (`clip.modifiers`). A clip
-- with no stack has no entries (nil), and each function accepts nil.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type types = require("paw.types")

local record M
  --- A built-in kind: the name of its one value, and its words.
  record Builtin
    main: string
    short: function(value: integer): string
    long: function(value: integer): string
  end

  --- What the top of a stack does: the semitones up, and the velocity
  --- changes in the order of the entries.
  record Prefix
    transpose: integer
    velocities: {integer}
  end

  --- The built-in kinds, by name.
  builtin: {string: Builtin}
end

local type Stack = {types.Modifier}

M.builtin = {
  transpose = {
    main = "semitones",
    short = function(n: integer): string return string.format("%+d", n) end,
    long = function(n: integer): string return string.format("transpose %+d", n) end,
  } as M.Builtin,
  velocity = {
    main = "add",
    short = function(n: integer): string return string.format("v%+d", n) end,
    long = function(n: integer): string return string.format("velocity %+d", n) end,
  } as M.Builtin,
}

--- More entries than this show as `ƒN` in the label of a clip.
local LABEL_ENTRIES = 3

--- The one value of a built-in entry, or nil for another kind.
function M.value(m: types.Modifier): integer
  local kind = M.builtin[m.kind]
  if not kind then
    return nil
  end
  return math.floor(tonumber((m.params or {})[kind.main]) or 0)
end

--- The entry in words, as `transpose +3` or `velocity -10`. A kind that paw
--- doesn't have yet shows as its name and a `?`, and it waits for its
--- extension.
function M.describe(m: types.Modifier): string
  local kind = M.builtin[m.kind]
  local text = kind and kind.long(M.value(m)) or (m.kind .. " ?")
  return m.off and (text .. " (off)") or text
end

--- The label of a stack, as `+3 v-10`, with the short form of each entry
--- that is on. A kind that waits for its extension shows as `?`, and more
--- than three entries show as `ƒ4`. Gives nil when no entry is on.
function M.label(stack: Stack): string
  local on: Stack = {}
  for _, m in ipairs(stack or {}) do
    if not m.off then
      on[#on + 1] = m
    end
  end
  if #on == 0 then
    return nil
  end
  if #on > LABEL_ENTRIES then
    return "ƒ" .. #on
  end
  local parts: {string} = {}
  for _, m in ipairs(on) do
    local kind = M.builtin[m.kind]
    parts[#parts + 1] = kind and kind.short(M.value(m)) or "?"
  end
  return table.concat(parts, " ")
end

--- The entries that are on, in words, as `transpose +3, velocity -10`.
--- Gives nil when no entry is on.
function M.text(stack: Stack): string
  local parts: {string} = {}
  for _, m in ipairs(stack or {}) do
    if not m.off then
      parts[#parts + 1] = M.describe(m)
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

--- What the top of a stack does to the notes. The top is the entries at
--- the start of the stack that are a `transpose` or a `velocity` for all
--- of the clip, and an entry that is off doesn't end it. The piano roll
--- shows the notes after the top, and the export of a MIDI file and the
--- chord names read the notes through it.
function M.prefix(stack: Stack): M.Prefix
  local out: M.Prefix = {transpose = 0, velocities = {}}
  for _, m in ipairs(stack or {}) do
    if not m.off then
      if m.scope or not M.builtin[m.kind] then
        break
      end
      if m.kind == "transpose" then
        out.transpose = out.transpose + M.value(m)
      else
        out.velocities[#out.velocities + 1] = M.value(m)
      end
    end
  end
  return out
end

--- Whether the top of the stack is all of it, so that each entry that is
--- on is a `transpose` or a `velocity` for all of the clip.
function M.reversible(stack: Stack): boolean
  for _, m in ipairs(stack or {}) do
    if not m.off and (m.scope or not M.builtin[m.kind]) then
      return false
    end
  end
  return true
end

--- The semitones that the top of the stack moves the notes, which is what
--- `Clip:shifted` takes.
function M.shift(stack: Stack): integer
  return M.prefix(stack).transpose
end

--- The `velocity` of a note after the velocity changes at the top of the
--- stack. Each change keeps it in 1 to 127, as the kernel does.
function M.velocity(stack: Stack, velocity: integer): integer
  for _, add in ipairs(M.prefix(stack).velocities) do
    velocity = math.max(1, math.min(127, velocity + add))
  end
  return velocity
end

--- The stack as one line of text, which is the same for the same stack, for
--- the key of a cache. It names each value, also of a kind that paw doesn't
--- know.
function M.key(stack: Stack): string
  local parts: {string} = {}
  for _, m in ipairs(stack or {}) do
    local names: {string} = {}
    for k in pairs(m.params or {}) do
      names[#names + 1] = k
    end
    table.sort(names)
    local values: {string} = {}
    for _, k in ipairs(names) do
      values[#values + 1] = k .. "=" .. tostring(m.params[k])
    end
    local scope = m.scope and string.format("@%.17g:%.17g", m.scope.from, m.scope.to) or ""
    parts[#parts + 1] = string.format(
      "%s%s v%d (%s)%s", m.off and "-" or "", m.kind, m.version or 1, table.concat(values, ","), scope
    )
  end
  return table.concat(parts, "|")
end

--- A copy of the entries, to change and give to `clip_set`.
function M.copy(stack: Stack): Stack
  local out: Stack = {}
  for i, m in ipairs(stack or {}) do
    local params: types.Meta = {}
    for k, v in pairs(m.params or {}) do
      params[k] = v
    end
    out[i] = {kind = m.kind, params = params, off = m.off, scope = m.scope, version = m.version}
  end
  return out
end

--- The first entry of `kind` in `stack`, and its place.
function M.find(stack: Stack, kind: string): types.Modifier, integer
  for i, m in ipairs(stack or {}) do
    if m.kind == kind then
      return m, i
    end
  end
  return nil, nil
end

return M
