-- Lesson 14: finding any command or key.
return {
  id = "finding",
  title = "Find a command or a key",
  intro = [[
In this lesson, we find keys and commands from a part of their name. Then we
use them.

Nobody remembers all the keys. paw shows what you can do at each point. Stop
in the middle of a key sequence, and paw shows the keys that can come next.
`?` shows all the keys of the current view. `:` runs a command by its name,
and Tab completes the name. Pickers find a command, a key, a track or a clip
from some letters of its name.

Each key runs a command with a name. So you can type the name of each action
that a key does. You can also map each command that you find to a key.]],
  idea = [[
Key hints show when you stop after the start of a sequence (`g`, `<leader>`, `d`,
`"`). `?` is the list of keys for the view that has the keys. `:commands`
shows each command and what it does.

`<leader>fc` finds a command, `<leader>fk` a key, `<leader>ft` a track and `<leader>fl` a
clip. `<leader>fa` finds a device, `<leader>fm` a mark, `<leader>fr` a register and `<leader>fp` a picker. In a
picker, the text that you type makes the list shorter. The letters must be in
order, but they can have other letters between them. `<C-n>` `<C-p>` move,
`<CR>` selects and `<Esc>` cancels. `K` gives data about the clip and the
track under the cursor.]],
  vim = [[
The hints are those of which-key, built into paw. The pickers work as in
Telescope: fuzzy, with `<C-n>` `<C-p>`. `:` completes with Tab and keeps a
history (`<Up>`).]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 8, notes = look.drums(look.beat, 2) })
    local bass = paw.add_track({ name = "Bass", volume = 0 })
    bass:add_device("synth", { wave = 2, cutoff = 700, release = 0.05 })
    bass:add_clip({ name = "bass", start = 0, length = 8, notes = look.pulse("C2", 8) })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 8, true
  end,
  at = function() paw.cursor.set_track(paw.track("Drums")) end,
  steps = {
    {
      say = "Press `g` and wait. After half a second, a box shows all the keys that can come after `g`. Then press `<Esc>` to close the box.",
      keys = { "g", { wait = 700 }, "<Esc>" },
      check = function(ctx)
        if paw.keymap.hints() then ctx.hints = true end
        return ctx.hints and paw.keymap.pending() == ""
      end,
      done = "Each command that is not complete shows what can come next. Try `,`, `d` or `\"` later.",
      hint = "Do not press a key until the box shows.",
    },
    {
      say = "`:commands` shows each command and what it does. Type `:commands` and `<CR>`. Look at the list, then press `q` to close it.",
      keys = { ":commands", "<CR>", "q" },
      check = function(ctx, look) return look.ran(ctx, "commands") and not look.float() end,
      done = "Each key that you used runs one of those commands.",
    },
    {
      say = "Tab completes the names of commands. Press `j` to go to Bass. Type `:track.vol` and press `<Tab>`: it becomes `track.volume`. Then press `<Space>`, type `-6` and press `<CR>`.",
      keys = { "j", ":track.vol", "<Tab>", "<Space>", "-6", "<CR>" },
      check = function(_, look) return look.track("Bass").volume == -6 end,
      done = "Bass is at -6 dB. `+` and `-` run the command `track.volume`.",
    },
    {
      say = "`<leader>fc` opens a picker of all the commands. Type some letters, and `<CR>` runs the first command. Press `<leader>fc`, type `metro` and press `<CR>`.",
      keys = { "<leader>fc", "metro", "<CR>" },
      check = function() return paw.transport.metronome end,
      done = "The metronome is on. You ran `transport.metronome`, but you did not know its name or its key.",
    },
    {
      say = "`<leader>fk` finds a key from its action. Press `<leader>fk` and type `loop` to see all the keys for the loop. Then press `<Esc>`.",
      keys = { "<leader>fk", "loop", "<Esc>" },
      check = function(ctx, look)
        local state = paw.pick.state()
        if state and state.query == "loop" then ctx.found = true end
        return ctx.found and not look.float()
      end,
      done = "The list showed `gL`, `gl` and `il`. `<CR>` on a line types its key for you.",
    },
    {
      say = "`<leader>ft` goes to a track by its name. Press `<leader>ft`, type `dr` and press `<CR>`.",
      keys = { "<leader>ft", "dr", "<CR>" },
      check = function(ctx, look) return look.ran(ctx, "pick.tracks") and look.cursor_track() == "Drums" end,
      done = "The cursor is on Drums. `<leader>fl` does the same for clips.",
    },
    {
      say = "`K` gives data about the item under the cursor: the clip, the track and its devices. Press `K`, then `q` to close it.",
      keys = { "K", "q" },
      check = function(ctx, look) return look.ran(ctx, "info") and not look.float() end,
      done = "`K` is the fastest way to see the devices, sends and automation of a track.",
    },
    {
      say = "Listen with the click. Press `<leader><Space>`, then `<leader><Space>` to stop and `gm` to disable the click.",
      keys = { "<leader><Space>", { wait = 300 }, "<leader><Space>", "gm" },
      check = function(ctx, look) return look.played(ctx) and not paw.transport.metronome end,
      done = "The bass is quieter, and the click came from a command that you found by its name.",
    },
  },
  outro = "We used key hints, `?`, `:commands`, Tab on the command line, the `<leader>f` pickers and `K`.",
}
