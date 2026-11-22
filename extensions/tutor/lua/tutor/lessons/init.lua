-- The built-in lessons, in the order they are taken.
local tutor = require("tutor")

local order = {
  "first_steps", -- the screen, playing, the command line, quitting
  "moving", -- motions, counts, and why keys change meaning
  "making", -- tracks, instruments, clips, notes, hearing them
  "pianoroll", -- the piano roll and insert mode
  "grammar", -- operators, motions, text objects, counts, `.` on clips
  "grammar_notes", -- the same grammar on notes
  "visual", -- selecting first, then acting
  "registers", -- yank, paste, registers, undo, macros
  "devices", -- instruments, effects, parameters, plugins
  "mixing", -- faders, pan, mute, solo, buses, sends, automation
  "loops", -- looping, marks, jumps, search
  "recording", -- recording audio and MIDI
  "saving", -- saving and rendering
  "finding", -- finding any command or key
  "your_own", -- options, mappings and commands in init.lua
  "extensions", -- what each bundled extension adds
  "ranges", -- Ex lines: ranges of time and tracks, :s and :g
}

for _, name in ipairs(order) do
  tutor.register(require("tutor.lessons." .. name))
end

return order
