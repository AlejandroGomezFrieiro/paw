-- Registers and macros of the keymap (paw/keymap.tl gives their functions
-- as `paw.keymap.setreg`, `getreg`, `record`, `recording` and `play`).
--
-- A register holds what a yank or a delete took: a table with a `kind`. The
-- code that yanks and pastes it decides what else is in it. A macro is the
-- register kind "keys": the keys typed while it was recorded.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type SeatsModule = require("paw.seats")
local type partial = require("paw.partial")

--- What a register holds: its `kind`, and what the code that yanked it
--- put in it. A module that yanks gives it a record of its own that is a
--- Register, and casts what `getreg` gives back to that record.
local interface Register
  kind: string
end

--- A macro: the keys typed while it was recorded, as `feed` takes them.
local record Macro is Register
  keys: string
end

--- The recording that runs: the register it goes into, and the keys so far.
local record Recording
  name: string
  keys: {string}
end

--- What each seat has its own of.
local record Kept
  registers: {string: Register}
  recording: Recording
  last_macro: string
end

local record Paw is partial.Paw
  seats: SeatsModule
end
local paw = (_G as {string: Paw}).paw

local record M
  type Register = Register
  type Macro = Macro
  --- The registers by name: `"` the unnamed one, `0` the last yank, `a`
  --- to `z`. The table stays the same; each seat's contents move in and
  --- out of it (`paw.keymap.registers`).
  registers: {string: Register}
  --- Plays keys inside the command that runs now (`paw.keymap.normal`):
  --- paw/keymap.tl sets it. False when a key failed.
  replay: function(keys: string): boolean
end

M.registers = {}
local recording: Recording -- the macro being recorded, if any
local last_macro: string -- the register `@@` plays again

-- Each seat has registers and a macro of its own. The registers table
-- stays the one that `paw.keymap.registers` names: a seat's contents are
-- copied into it and out of it.
paw.seats.keep(
  "keymap.registers",
  function(): Kept
    local copy: {string: Register} = {}
    for name, value in pairs(M.registers) do
      copy[name] = value
    end
    return {registers = copy, recording = recording, last_macro = last_macro}
  end,
  function(k: Kept)
    for name in pairs(M.registers) do
      M.registers[name] = nil
    end
    for name, value in pairs(k.registers) do
      M.registers[name] = value
    end
    recording, last_macro = k.recording, k.last_macro
  end,
  function(): Kept return {registers = {}} end
)

--- Put a value in a register: the unnamed register, and `name` if given.
--- With `yank` and no name, it also goes to `"0`, which a delete never
--- changes. A value is a table with a `kind`. The code that yanks and
--- pastes it decides what else it contains. `"_` discards.
function M.setreg(value: Register, name?: string, yank?: boolean)
  if name == "_" then
    return
  end
  M.registers['"'] = value
  if name and name ~= '"' then
    M.registers[name:lower()] = value
  end
  if yank and not name then
    M.registers["0"] = value
  end
end

--- What a register holds (the unnamed one when `name` is nil).
function M.getreg(name?: string): Register
  return M.registers[name and name:lower() or '"']
end

--- Start recording keys into a register, or stop with no name.
function M.record(name: string)
  if not name:match("^%a$") then
    return paw.notify("a macro goes in a register named a to z", "warn")
  end
  recording = {name = name:lower(), keys = {}}
  api.ui_redraw()
end

--- The register being recorded into, if any.
function M.recording(): string
  return recording and recording.name
end

--- Add a key that the keyboard typed to the macro being recorded, if any.
function M.typed(key: string)
  if recording then
    recording.keys[#recording.keys + 1] = key
  end
end

--- End the recording at the key that started it: that key is not a part
--- of the macro. Says which register has it.
function M.stop()
  recording.keys[#recording.keys] = nil
  M.registers[recording.name] = {kind = "keys", keys = table.concat(recording.keys)} as Macro
  paw.notify("recorded @" .. recording.name)
  recording = nil
  api.ui_redraw()
end

--- Play the keys in a register `n` times. `@` as the name plays the last register again.
function M.play(name: string, n?: integer)
  if name == "@" then
    name = last_macro
  end
  local value = name and M.registers[name:lower()]
  if not (value and value.kind == "keys") then
    return paw.notify("no macro in register `" .. tostring(name) .. "`", "warn")
  end
  last_macro = name
  local keys = (value as Macro).keys
  for _ = 1, n or 1 do
    if not M.replay(keys) then
      break
    end
  end
end

return M
