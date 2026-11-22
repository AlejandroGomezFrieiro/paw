-- Lesson 14: finding any command or key.
return {
  id = "finding",
  title = "Find a command or a key",
  intro = [[
In this lesson, we find keys and commands from a part of their name, and
then we use them.

You do not need to remember all the keys, because paw shows what you can do
at each point. When you stop in the middle of a key sequence, paw shows the
keys that can come next, and `?` shows all the keys of the current view.
`:` runs a command by its name, and Tab completes the name. Pickers find a
command, a key, a track or a clip from some letters of its name.

Each key runs a command with a name, so you can type the name of each action
that a key does. You can also map each command that you find to a key.]],
  idea = [[
Key hints show when you stop after the start of a sequence, e.g., `g`,
`<leader>`, `d` or `"`. `?` is the list of keys for the view that has the
keys, and `:commands` shows each command and what it does.

The keys that start with `<leader>f` open pickers. `<leader>f:` finds a
command and `<leader>fk` a key, while `<leader>ft` finds a track and
`<leader>fc` a clip. Moreover, `<leader>fm` finds a marker and `<leader>fr`
a region, while `<leader>f"` finds a register and `<leader>fp` a picker.

In a picker, the text that you type makes the list shorter. The letters
must be in order, but they can have other letters between them. `<C-n>`
and `<C-p>` move, `<CR>` selects and `<Esc>` cancels. `K` gives data about
the clip and the track under the cursor.]],
  vim = [[
The key hints are built into paw. The pickers use fuzzy
matching, and `<C-n>` `<C-p>` move in them. `:` completes with Tab and
keeps a history, which `<Up>` shows.]],
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
      say = "Press `g` and wait. After half a second, a box shows all the keys that can come after `g`, and then you can press `<Esc>` to close the box.",
      keys = { "g", { wait = 700 }, "<Esc>" },
      check = function(ctx)
        if paw.keymap.hints() then ctx.hints = true end
        return ctx.hints and paw.keymap.pending() == ""
      end,
      done = 'Each key sequence that is not complete shows what can come next. Later, try `<leader>`, `d` or `"`.',
      hint = "Do not press a key until the box shows.",
    },
    {
      say = "`:commands` shows each command and what it does. Type `:commands` and `<CR>`, look at the list, and then press `q` to close it.",
      keys = { ":commands", "<CR>", "q" },
      check = function(ctx, look) return look.ran(ctx, "commands") and not look.float() end,
      done = "Each key that you used runs one of the commands in the list.",
    },
    {
      say = "Tab completes the names of commands. Press `j` to go to Bass. Type `:track.vol` and press `<Tab>`, and the name becomes `track.volume`. Then press `<Space>`, type `-6` and press `<CR>`.",
      keys = { "j", ":track.vol", "<Tab>", "<Space>", "-6", "<CR>" },
      check = function(_, look) return look.track("Bass").volume == -6 end,
      done = "Bass is at -6 dB, and `+` and `-` run the same command, `track.volume`.",
    },
    {
      say = "`<leader>f:` opens a picker of all the commands. When you type some letters, `<CR>` runs the first command in the list. Press `<leader>f:`, type `metro` and press `<CR>`.",
      keys = { "<leader>f:", "metro", "<CR>" },
      check = function() return paw.transport.metronome end,
      done = "The metronome is on. You ran `transport.metronome` without knowing its name or its key.",
    },
    {
      say = "`<leader>fk` finds a key from its action. Press `<leader>fk` and type `loop` to see all the keys for the loop, and then press `<Esc>`.",
      keys = { "<leader>fk", "loop", "<Esc>" },
      check = function(ctx, look)
        local state = paw.pick.state()
        if state and state.query == "loop" then ctx.found = true end
        return ctx.found and not look.float()
      end,
      done = "The list showed `gL`, `gl` and `il`, and `<CR>` on a line types its key for you.",
    },
    {
      say = "`<leader>ft` goes to a track by its name. Press `<leader>ft`, type `dr` and press `<CR>`.",
      keys = { "<leader>ft", "dr", "<CR>" },
      check = function(ctx, look) return look.ran(ctx, "pick.tracks") and look.cursor_track() == "Drums" end,
      done = "The cursor is on Drums, and `<leader>fc` does the same for clips.",
    },
    {
      say = "`K` gives data about the item under the cursor, which is the clip, the track and its devices. Press `K`, and then `q` to close the window.",
      keys = { "K", "q" },
      check = function(ctx, look) return look.ran(ctx, "info") and not look.float() end,
      done = "With `K`, you can see the devices, sends and automation of a track with one key.",
    },
    {
      say = "Listen with the click. Press `<leader><Space>`, and then `<leader><Space>` to stop and `gm` to disable the click.",
      keys = { "<leader><Space>", { wait = 300 }, "<leader><Space>", "gm" },
      check = function(ctx, look) return look.played(ctx) and not paw.transport.metronome end,
      done = "The bass is quieter, and the click came from a command that you found by its name.",
    },
  },
  outro = "We used key hints, `?`, `:commands`, Tab on the command line, the `<leader>f` pickers and `K`.",
}
