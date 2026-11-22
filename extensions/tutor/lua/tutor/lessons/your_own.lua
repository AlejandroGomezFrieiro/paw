-- Lesson 15: options, mappings and commands of your own, and init.lua.
return {
  id = "your-own",
  title = "Make paw your own: options, keys, commands",
  intro = [[
In this lesson, we set an option, map a key and make a command with `:lua`,
and then we put them in `init.lua`.

Each key that you used is a usual mapping, and each command is a usual Lua
function, which paw makes with the same functions that you can use. Your
own file, `~/.config/paw/init.lua`, runs when paw starts, so paw applies the
options, mappings and commands in it each time.

`:lua` runs one line of Lua, and the values that you set with it stay until
you quit. The grid is an exception, because the tutor sets it back to its
old value when you leave the tutor.]],
  idea = [[
`paw.opt.name = value` sets an option, e.g., `:lua paw.opt.grid = 0.5`, and
`<leader>fo` shows the options. `paw.keymap.set(keys, command or function, {
desc = ..., view = ... })` maps keys. `<leader>` is the leader key, which is
the space bar, and `<localleader>` is the leader of the keys of one view,
which is a backslash.

`paw.command(name, function(ctx) ... end, { desc = ... })` makes a command.
`:name` runs the command, and a mapping can use its name. `:reload` runs
`init.lua` again and does not change the project.]],
  vim = [[
The `init.lua` of paw works as the `init.lua` of Neovim, with `paw.opt`,
`paw.keymap.set` and `paw.command` in place of `vim.opt`, `vim.keymap.set`
and `vim.api.nvim_create_user_command`. `:lua` is the same. A file with the
same name as a built-in module in `~/.config/paw/lua/` replaces the
module.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 8, notes = look.drums(look.beat, 2) })
    local keys = paw.add_track({ name = "Keys", volume = -8 })
    keys:add_device("synth", { wave = 3, attack = 0.02, release = 0.4, cutoff = 1800 })
    keys:add_clip({ name = "chords", start = 0, length = 8, notes = look.chord({ "E4", "G4", "B4" }, 8) })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 8, true
  end,
  at = function() paw.cursor.set_track(paw.track("Drums")) end,
  steps = {
    {
      say = "First, set an option. Type `:lua paw.opt.grid = 0.5` and `<CR>`, and then press `l`, and the cursor now moves half a beat.",
      keys = { ":lua paw.opt.grid = 0.5", "<CR>", "l" },
      check = function() return paw.opt.grid == 0.5 and paw.cursor.beat == 0.5 end,
      done = "The grid is half a beat, and the status line shows `grid 0.5`. `]g` and `[g` also change the grid.",
      hint = "Type the text exactly, with the spaces. On the command line, `<Up>` shows the text that you typed before.",
    },
    {
      say = 'Now map a key of your own. Type `:lua paw.keymap.set("<leader>k", "transport.metronome", { desc = "Click" })` and `<CR>`, and then press `<leader>k`.',
      keys = {
        ':lua paw.keymap.set("<leader>k", "transport.metronome", { desc = "Click" })',
        "<CR>",
        "<leader>k",
      },
      check = function() return paw.transport.metronome end,
      done = "`<leader>k` enables and disables the click, and `?` shows your mapping with its description.",
    },
    {
      say = 'Now make a command of your own. Type `:lua paw.command("hello", function() paw.notify("hello from my command") end)` and `<CR>`, and then type `:hello` and `<CR>`.',
      keys = {
        ':lua paw.command("hello", function() paw.notify("hello from my command") end)',
        "<CR>",
        ":hello",
        "<CR>",
      },
      check = function(ctx, look) return look.said(ctx, "hello from my command") end,
      done = "Your command ran, and `:commands` and the `<leader>f:` picker now show it with the built-in commands.",
    },
    {
      say = "To keep the option, the mapping and the command, open `~/.config/paw/init.lua` in your text editor. Add the same three lines without `:lua`, and save the file. Then type `:reload` in paw.",
      keys = {},
      unchecked = "The tutor does not read or write your configuration.",
      done = "Done.",
      hint = "In init.lua, each line is usual Lua, for example `paw.opt.grid = 0.5`. If there is an error, `:extensions` and `:messages` show it.",
    },
    {
      say = "Listen with your click. Press `<leader><Space>`, and then `<leader><Space>` to stop and `<leader>k` to disable the click.",
      keys = { "<leader><Space>", { wait = 300 }, "<leader><Space>", "<leader>k" },
      check = function(ctx, look) return look.played(ctx) and not paw.transport.metronome end,
      done = "The key that you mapped works.",
    },
  },
  outro = "We set an option, made a mapping and a command with `:lua`, and found where to keep them.",
}
