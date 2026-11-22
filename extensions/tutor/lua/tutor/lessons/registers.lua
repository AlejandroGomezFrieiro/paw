-- Lesson 8: yank, paste, registers, undo with counts, macros.
local HOOK = "A4:0:0.5 C5:0.5:0.5 E5:1:1 D5:2:0.5 C5:2.5:0.5 A4:3:1"

--- The hook's notes moved by `by` semitones, as `look.melody` writes them.
local function hook(look, by)
  local notes = look.notes(HOOK)
  for _, n in ipairs(notes) do
    n.pitch = n.pitch + by
  end
  local out = {}
  for i, n in ipairs(notes) do
    out[i] = string.format("%d@%g+%g", n.pitch, n.start, n.length)
  end
  table.sort(out)
  return table.concat(out, " ")
end

local function sorted(look, clip)
  local list = {}
  for item in look.melody(clip):gmatch("%S+") do
    list[#list + 1] = item
  end
  table.sort(list)
  return table.concat(list, " ")
end

return {
  id = "registers",
  title = "Yank, paste, registers and macros",
  intro = [[
In this lesson, we copy a short hook along a track and keep two bass clips
in named registers. Then we record a macro that changes the hook.

A delete or a yank puts the items in a register, and a paste takes them from
the register. Usually you use the register without a name, but the named
registers (`"a` to `"z`) let you keep several items at the same time. You
can undo each change, and with a count you undo more than one change. A
macro records keys into a register, so that you can play the keys again.

The Lead track has a short hook, and the Bass track has two clips, A and
B.]],
  idea = [[
`y` yanks, and `d` and `x` delete into the register. `p` pastes after the
clip (or note) under the cursor, and `P` pastes at the cursor. `3p` pastes
three copies, one after the other, and `p` again continues from the last
paste.

`"a` before a command names the register, e.g., `"ayic` or `"ap`. `"0`
keeps the last yank after deletes, and `"_` discards. `:registers` shows
all the registers.

`u` undoes, `3u` undoes three times, and `<C-r>` redoes. `qq` records keys
into register q until you press `q`, and `@q` plays the keys. `@@` plays
the last macro again, and `5@q` plays it five times.]],
  vim = [[
Registers, `"0`, `"_`, `qq`…`q`, `@q`, `@@` and `@:` come from Vim. A
register contains clips, tracks, notes or a device instead of text. Pasted
time replaces the items that were there, and `:lua paw.opt.ripple = true`
moves the old items later instead.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 16, notes = look.drums(look.beat, 4) })
    local lead = paw.add_track({ name = "Lead", volume = -6 })
    lead:add_device("synth", { wave = 1, cutoff = 2400, release = 0.2 })
    lead:add_clip({ name = "hook", start = 0, length = 4, notes = look.notes(HOOK) })
    local bass = paw.add_track({ name = "Bass", volume = -4 })
    bass:add_device("synth", { wave = 2, cutoff = 600, release = 0.05 })
    bass:add_clip({ name = "A", start = 0, length = 4, notes = look.pulse("A1", 4) })
    bass:add_clip({ name = "B", start = 4, length = 4, notes = look.pulse("F1", 4) })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 16, true
  end,
  at = function() paw.cursor.set_track(paw.track("Lead")) end,
  steps = {
    {
      say = "The cursor is on the hook. Press `yic` to yank (copy) the clip.",
      keys = { "yic" },
      start = function(ctx) ctx.before = paw.keymap.getreg() end,
      check = function(ctx)
        local r = paw.keymap.getreg()
        return r ~= ctx.before and r and r.kind == "range" and paw.keymap.getreg("0") == r
      end,
      done = "The hook is in the unnamed register, and also in register 0, which keeps the last yank.",
    },
    {
      say = "`p` pastes after the clip under the cursor. Press `p`.",
      keys = { "p" },
      check = function(_, look) return look.layout("Lead") == "hook@0+4 hook@4+4" end,
      done = "A second hook shows immediately after the first.",
    },
    {
      say = "A count pastes more than one copy, and `p` again continues from the last paste. Press `2p`.",
      keys = { "2p" },
      check = function(_, look) return look.layout("Lead") == "hook@0+4 hook@4+4 hook@8+4 hook@12+4" end,
      done = "Four hooks fill four bars.",
    },
    {
      say = 'Named registers keep more than one item. Press `j` to go to Bass and `0` to go to its start. Press `"ayic` to yank clip A into register a.',
      keys = { "j", "0", '"ayic' },
      start = function(ctx) ctx.before = paw.keymap.getreg("a") end,
      check = function(ctx)
        local r = paw.keymap.getreg("a")
        return r and r ~= ctx.before and r.kind == "range" and r.rows[1] and r.rows[1][1] and r.rows[1][1].name == "A"
      end,
      done = "Register a contains A.",
      hint = '`"` is the double quote key. Press `"`, then `a`, then `yic`.',
    },
    {
      say = 'Press `w` to go to B. Press `"byic` to yank it into register b.',
      keys = { "w", '"byic' },
      start = function(ctx) ctx.before = paw.keymap.getreg("b") end,
      check = function(ctx)
        local r = paw.keymap.getreg("b")
        return r and r ~= ctx.before and r.kind == "range" and r.rows[1] and r.rows[1][1] and r.rows[1][1].name == "B"
      end,
      done = "Register b contains B.",
    },
    {
      say = "`:registers` shows the contents of each register. Type `:registers` and `<CR>`, look at the list, and then press `q` to close it.",
      keys = { ":registers", "<CR>", "q" },
      check = function(ctx, look) return look.ran(ctx, "registers") and not look.float() end,
      done = 'The list showed `"a` and `"b`, with `"0` and the unnamed `""`.',
    },
    {
      say = 'Press `$` to go to the end of B. Press `"ap` to paste A there, and `"bp` to paste B after it.',
      keys = { "$", '"ap', '"bp' },
      check = function(_, look) return look.names("Bass") == "A B A B" end,
      done = "The bass line is A B A B, so it plays two times.",
    },
    {
      say = "Undo also accepts a count. Press `2u` to undo the two pastes.",
      keys = { "2u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Bass") == "A B" end,
      done = "The bass line is A B again, and `2<C-r>` would redo the two pastes.",
    },
    {
      say = "Now we record a macro. Press `k` to go up to Lead and `0` to go to its start. Then press `qq` to record keys into register q.",
      keys = { "k", "0", "qq" },
      check = function(_, look)
        return paw.keymap.recording() == "q" and look.cursor_track() == "Lead" and paw.cursor.beat == 0
      end,
      done = "The status line shows `recording @q`.",
    },
    {
      say = "Type the change. `vic` selects the clip, and `12<C-a>` moves its notes up one octave. `w` goes to the next clip, and then `q` stops the recording.",
      keys = { "vic", "12<C-a>", "w", "q" },
      start = function(ctx) ctx.before = paw.keymap.registers.q end,
      check = function(ctx)
        local r = paw.keymap.registers.q
        return paw.keymap.recording() == nil and r ~= ctx.before and r and r.kind == "keys" and r.keys == "vic12<C-a>w"
      end,
      done = "The first hook went up one octave while you recorded, and register q contains `vic12<C-a>w`.",
      hint = "Without the selection, `<C-a>` on a track moves the fader. If the result is wrong, press `u` to undo the change, and `qq` to record again.",
    },
    {
      say = "`@q` plays the macro on the clip under the cursor, and `@@` plays it again. Press `@q`, then `@@`.",
      keys = { "@q", "@@" },
      check = function(_, look)
        local clips = look.clips("Lead")
        return #clips == 4
          and sorted(look, clips[2]) == hook(look, 12)
          and sorted(look, clips[3]) == hook(look, 12)
          and sorted(look, clips[4]) == hook(look, 0)
      end,
      done = "Three hooks are one octave higher, and the last hook did not change.",
    },
    {
      say = "Listen to the result. Press `gs` and `<leader><Space>`, and press `<leader><Space>` again to stop.",
      keys = { "gs", "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.ran(ctx, "transport.start") and look.played(ctx) end,
      done = "The hook goes up and then comes down again.",
    },
  },
  outro = "We used `yic` and `p` with counts, and we used named registers, `:registers` and `2u`. Then we recorded a macro with `qq` and played it with `@q` and `@@`.",
}
