-- Lesson 5: operators, motions, text objects, counts and `.` on clips.
return {
  id = "grammar",
  title = "The grammar: operators, motions, text objects",
  intro = [[
In this lesson, we delete, mute and loop clips with short commands. Then we
repeat them with `.`.

This grammar is the center of paw. Most edits are a short sentence: an
operator (the action), then a motion or a text object (the item). `d` is
delete and `w` is "to the next clip", so `dw` deletes up to the next clip.
`ic` is "the clip under the cursor", so `dic` deletes this clip.

A count gives the quantity: `d2W` deletes two bars. The operator two times
selects whole tracks: `dd`. `.` repeats the last change at the cursor.

In this practice project, the Beat track has four clips: kick, snare, fill
and crash. Bass plays below them.]],
  idea = [[
The operators are `d` delete, `y` yank (copy) and `c` change. `>` `<` move
later and earlier, `=` snaps to the grid, `gc` mutes and `gl` loops. The motions are
all the keys from lesson 2.

The text objects are `ic` the clip and `ac` the clip with the gap after it.
`ib` is the bar, `il` the loop, `it` all of the track and `ie` the project.
Learn some of each, and you know all their combinations. Six operators and
ten motions make sixty commands.]],
  vim = [[
This is the grammar of Vim, with no change: an operator, a count, and a
motion or a text object. The operator two times selects whole lines, which
are tracks here. `.` accepts a new count.

In Vim, `gc` changes lines to comments. Here it mutes. `gl` (loop) is new.
`c` makes the range empty and opens a new clip in insert mode.]],
  setup = function(look)
    paw.project.tempo = 104
    local beat = paw.add_track({ name = "Beat" })
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
    local bass = paw.add_track({ name = "Bass", volume = -6 })
    bass:add_device("synth", { wave = 2, cutoff = 600, release = 0.05 })
    bass:add_clip({ name = "bass", start = 0, length = 16, notes = look.pulse("E2", 16) })
  end,
  at = function() paw.cursor.set_track(paw.track("Beat")) end,
  steps = {
    {
      say = "The cursor is at the start of `kick`. `d` is the delete operator and `w` is the motion to the next clip. Press `dw`.",
      keys = { "dw" },
      check = function(_, look) return look.names("Beat") == "snare fill crash" end,
      done = "`kick` is deleted. `dw` deleted from the cursor to the start of `snare`.",
      hint = "After `d`, the status line shows PENDING: the operator waits for its motion. `<Esc>` cancels it.",
    },
    {
      say = "Press `u` to bring it back.",
      keys = { "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Beat") == "kick snare fill crash" end,
      done = "The track has its four clips again.",
    },
    {
      say = "A text object names an item, not a movement. `ic` is the clip under the cursor. Press `w` to go to `snare`, then press `dic`.",
      keys = { "w", "dic" },
      check = function(_, look) return look.names("Beat") == "kick fill crash" end,
      done = '`dic` means "delete in clip". A gap is now where `snare` was.',
    },
    {
      say = "`.` repeats the last change. Press `w` to go to `fill`. Then press `.` to delete it too.",
      keys = { "w", "." },
      check = function(_, look) return look.names("Beat") == "kick crash" end,
      done = "`.` did `dic` again, on the clip that is under the cursor now.",
    },
    {
      say = "Undo the two changes: press `u` two times.",
      keys = { "u", "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Beat") == "kick snare fill crash" end,
      done = "The track has four clips again.",
    },
    {
      say = "A count goes with the motion: `d2W` deletes two bars from the cursor. Press `0`, then `d2W`.",
      keys = { "0", "d2W" },
      check = function(_, look) return look.names("Beat") == "fill crash" end,
      done = "Two bars of Beat are deleted. Bass did not change, because the operator works on the track of the cursor.",
    },
    {
      say = "Press `u` to undo that change.",
      keys = { "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Beat") == "kick snare fill crash" end,
      done = "The two bars are back.",
    },
    {
      say = "Other operators accept the same motions and objects. `gc` mutes. Press `gcic` to mute `kick`.",
      keys = { "gcic" },
      check = function(_, look)
        local c = look.clip("Beat", "kick")
        return c and c.muted
      end,
      done = "`kick` is muted and gray. `gcic` again unmutes it.",
    },
    {
      say = "Press `w` to go to `snare`. Press `.` to mute it in the same way.",
      keys = { "w", "." },
      check = function(_, look)
        local c = look.clip("Beat", "snare")
        return c and c.muted
      end,
      done = "`.` repeats each type of change: delete, mute and move.",
    },
    {
      say = "An operator two times selects whole tracks: `dd` deletes a track. Press `j` to go to Bass, then press `dd`.",
      keys = { "j", "dd" },
      check = function(_, look) return look.track("Bass") == nil end,
      done = "The Bass track is deleted, and paw keeps it in the register.",
    },
    {
      say = "`p` puts the deleted item after the cursor. A track goes below the cursor. Press `p`.",
      keys = { "p" },
      check = function(ctx, look) return look.became(ctx, "back", look.track("Bass") ~= nil and #paw.tracks() == 2) end,
      done = "Bass is back, with its synth and its clip. So a delete is also a cut.",
    },
    {
      say = "`gl` is the loop operator. Press `k` to go up to Beat. Press `0` and `w` to put the cursor on `snare`. Then press `glic`.",
      keys = { "k", "0", "w", "glic" },
      check = function()
        return paw.transport.loop_enabled and paw.transport.loop_start == 4 and paw.transport.loop_end == 8
      end,
      done = "The loop is the snare clip. The ruler shows it.",
    },
    {
      say = "Press `gcic` to unmute `snare`. Press `<leader><Space>` to hear the loop. `<leader><Space>` stops.",
      keys = { "gcic", "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look)
        local c = look.clip("Beat", "snare")
        return c and not c.muted and look.played(ctx)
      end,
      done = "The snare bar and the bass play again and again.",
    },
  },
  outro = "We used operators with motions (`dw`, `d2W`) and with text objects (`dic`, `gcic`, `glic`), `dd` for tracks, and `.` to repeat.",
}
