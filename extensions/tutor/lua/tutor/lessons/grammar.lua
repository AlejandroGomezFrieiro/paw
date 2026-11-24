-- Lesson 5: operators, motions, text objects, counts and `.` on clips.
return {
  id = "grammar",
  title = "The grammar: operators, motions, text objects",
  intro = [[
In this lesson, we delete, mute and loop clips with short commands, and we
repeat the commands with `.`.

Most edits in paw use the same grammar. You type an operator, which is the
action, and then a motion or a text object, which is the item. For example,
`d` is delete and `w` is "to the next clip", so `dw` deletes up to the next
clip. `ic` is "the clip under the cursor", so `dic` deletes the clip under
the cursor.

A count gives the quantity, e.g., `d2W` deletes two bars. When you type the
operator two times, as in `dd`, it acts on whole parts. `.` repeats the
last change at the cursor.

In the practice project, the Beat part has four clips, which are kick,
snare, fill and crash, and the Bass part plays below them.]],
  idea = [[
The operators that edit are `d` (delete), `y` (yank, which copies) and `c`
(change). Other operators move and mark clips, e.g., `>` and `<` move later
and earlier, and `=` snaps to the grid. `gc` mutes, and `gl` loops. The
motions are all the keys from lesson 2.

The text objects are `ic` (the clip) and `ac` (the clip with the gap after
it). Moreover, `ib` is the bar, `il` the loop, `it` the whole part and
`ie` the project. When you learn some operators, motions and text objects,
you can use every combination of them, so six operators and ten motions
give sixty commands.]],
  vim = [[
paw uses the grammar of Vim with no change, which is an operator, a count,
and a motion or a text object. The operator typed two times selects whole
lines, and in paw the lines are parts. `.` accepts a new count.

In Vim, `gc` changes lines to comments, and in paw it mutes. `gl` (loop) is
new. `c` makes the range empty and opens a new clip in insert mode.]],
  setup = function(look)
    paw.project.tempo = 104
    local beat = paw.add_part({ name = "Beat" })
    beat:add_device("drums")
    beat:add_clip({ name = "kick", start = 0, length = 4, notes = look.drums({ [36] = "x...x...x...x..." }) })
    beat:add_clip({
      name = "snare",
      start = 4,
      length = 4,
      notes = look.drums({ [36] = "x.......x.......", [38] = "....x.......x..." }),
    })
    beat:add_clip({
      name = "fill",
      start = 8,
      length = 4,
      notes = look.drums({ [36] = "x.......", [38] = "........x.x.xxxx" }),
    })
    beat:add_clip({ name = "crash", start = 12, length = 4, notes = look.drums({ [36] = "x...", [46] = "x......." }) })
    local bass = paw.add_part({ name = "Bass", volume = -6 })
    bass:add_device("synth", { wave = 2, cutoff = 600, release = 0.05 })
    bass:add_clip({ name = "bass", start = 0, length = 16, notes = look.pulse("E2", 16) })
  end,
  at = function() paw.cursor.set_part(paw.part("Beat")) end,
  steps = {
    {
      say = "The cursor is at the start of `kick`. `d` is the delete operator and `w` is the motion to the next clip. Press `dw`.",
      keys = { "dw" },
      check = function(_, look) return look.names("Beat") == "snare fill crash" end,
      done = "paw deleted `kick`, because `dw` deletes from the cursor to the start of `snare`.",
      hint = "After `d`, the status line shows PENDING, which means that the operator waits for its motion. `<Esc>` cancels the operator.",
    },
    {
      say = "Press `u` to bring `kick` back.",
      keys = { "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Beat") == "kick snare fill crash" end,
      done = "The part has its four clips again.",
    },
    {
      say = "A text object names an item instead of a movement, e.g., `ic` is the clip under the cursor. Press `w` to go to `snare`, then press `dic`.",
      keys = { "w", "dic" },
      check = function(_, look) return look.names("Beat") == "kick fill crash" end,
      done = '`dic` means "delete in clip", and there is now a gap where `snare` was.',
    },
    {
      say = "`.` repeats the last change. Press `w` to go to `fill`, and then press `.` to delete it too.",
      keys = { "w", "." },
      check = function(_, look) return look.names("Beat") == "kick crash" end,
      done = "`.` did `dic` again, on the clip that is under the cursor now.",
    },
    {
      say = "To undo the two changes, press `u` two times.",
      keys = { "u", "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Beat") == "kick snare fill crash" end,
      done = "The part has four clips again.",
    },
    {
      say = "A count goes with the motion, so `d2W` deletes two bars from the cursor. Press `0`, then `d2W`.",
      keys = { "0", "d2W" },
      check = function(_, look) return look.names("Beat") == "fill crash" end,
      done = "paw deleted two bars of Beat. Bass did not change, because the operator works on the part of the cursor.",
    },
    {
      say = "Press `u` to undo that change.",
      keys = { "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Beat") == "kick snare fill crash" end,
      done = "The two bars are back.",
    },
    {
      say = "Other operators accept the same motions and objects, e.g., `gc` mutes. Press `gcic` to mute `kick`.",
      keys = { "gcic" },
      check = function(_, look)
        local c = look.clip("Beat", "kick")
        return c and c.muted
      end,
      done = "`kick` is muted and shows in gray. To unmute it, press `gcic` again.",
    },
    {
      say = "Press `w` to go to `snare`. Press `.` to mute it in the same way.",
      keys = { "w", "." },
      check = function(_, look)
        local c = look.clip("Beat", "snare")
        return c and c.muted
      end,
      done = "`.` repeats each type of change, e.g., delete, mute and move.",
    },
    {
      say = "An operator typed two times selects whole parts, so `dd` deletes a part. Press `j` to go to Bass, then press `dd`.",
      keys = { "j", "dd" },
      check = function(_, look) return look.part("Bass") == nil end,
      done = "paw deleted the Bass part and keeps it in the register.",
    },
    {
      say = "`p` puts the deleted item after the cursor, and a part goes below the cursor. Press `p`.",
      keys = { "p" },
      check = function(ctx, look) return look.became(ctx, "back", look.part("Bass") ~= nil and #paw.parts() == 2) end,
      done = "Bass is back, with its synth and its clip, so a delete is also a cut.",
    },
    {
      say = "`gl` is the loop operator. Press `k` to go up to Beat, and press `0` and `w` to put the cursor on `snare`. Then press `glic`.",
      keys = { "k", "0", "w", "glic" },
      check = function()
        return paw.transport.loop_enabled and paw.transport.loop_start == 4 and paw.transport.loop_end == 8
      end,
      done = "The loop is now over the snare clip, and the ruler shows the loop.",
    },
    {
      say = "Press `gcic` to unmute `snare`. Press `<leader><Space>` to hear the loop, and `<leader><Space>` again to stop.",
      keys = { "gcic", "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look)
        local c = look.clip("Beat", "snare")
        return c and not c.muted and look.played(ctx)
      end,
      done = "The snare bar and the bass play again and again.",
    },
  },
  outro = "We used operators with motions (`dw`, `d2W`) and with text objects (`dic`, `gcic`, `glic`), `dd` for parts, and `.` to repeat.",
}
