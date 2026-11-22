-- Lesson 15: options, mappings and commands of your own, and init.lua.
return {
  id = "your-own",
  title = "Make paw your own: options, keys, commands",
  intro = [[
In this lesson, we set an option, map a key and make a command with `:lua`.
Then we put them in `init.lua`.

Each key that you used is a usual mapping, and each command is a usual Lua
function. paw makes them with the same functions that you can use. Your own
file, `~/.config/paw/init.lua`, runs when paw starts. paw applies the options,
mappings and commands in it each time.

`:lua` runs one line of Lua. The values that you set here stay until you
quit. The grid is different: the tutor sets it to its old value when you
leave the tutor.]],
  idea = [[
`paw.opt.name = value` sets an option (`:lua paw.opt.grid = 0.5`). `<leader>fo`
shows the options. `paw.keymap.set(keys, command or function, { desc = ...,
view = ... })` maps keys. `<leader>` is the leader (`,`), and
`<localleader>` is the leader of the keys of one view (a backslash).

`paw.command(name, function(ctx) ... end, { desc = ... })` makes a command.
`:name` runs it, and a mapping can use its name. `:reload` runs `init.lua`
again and does not change the project.]],
  vim = [[
This is the `init.lua` of Neovim, with `paw.opt`, `paw.keymap.set` and
`paw.command` in place of `vim.opt`, `vim.keymap.set` and
`vim.api.nvim_create_user_command`. `:lua` is the same. A file with the same
name in `~/.config/paw/lua/` replaces a built-in module.]],
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
      say = "First, set an option. Type `:lua paw.opt.grid = 0.5` and `<CR>`. Then press `l`: the cursor moves half a beat now.",
      keys = { ":lua paw.opt.grid = 0.5", "<CR>", "l" },
      check = function() return paw.opt.grid == 0.5 and paw.cursor.beat == 0.5 end,
      done = "The grid is half a beat, and the status line shows `grid 0.5`. `]g` and `[g` also change it.",
      hint = "Type the text exactly, with the spaces. On the command line, `<Up>` shows the text that you typed before.",
    },
    {
      say = 'Now map a key of your own. Type `:lua paw.keymap.set("<leader>z", "transport.metronome", { desc = "Click" })` and `<CR>`. Then press `<leader>z`.',
      keys = {
        ':lua paw.keymap.set("<leader>z", "transport.metronome", { desc = "Click" })',
        "<CR>",
        "<leader>z",
      },
      check = function() return paw.transport.metronome end,
      done = "`<leader>z` enables and disables the click. `?` shows your mapping with its description.",
    },
    {
      say = 'Now make a command of your own. Type `:lua paw.command("hello", function() paw.notify("hello from my command") end)` and `<CR>`. Then type `:hello` and `<CR>`.',
      keys = {
        ':lua paw.command("hello", function() paw.notify("hello from my command") end)',
        "<CR>",
        ":hello",
        "<CR>",
      },
      check = function(ctx, look) return look.said(ctx, "hello from my command") end,
      done = "Your command ran. `:commands` and the `<leader>f:` picker show it now, with the built-in commands.",
    },
    {
      say = "To keep them, open `~/.config/paw/init.lua` in your text editor. Add the same three lines without `:lua`, and save. Then type `:reload` here.",
      keys = {},
      unchecked = "The tutor does not read or write your configuration.",
      done = "Done.",
      hint = "In init.lua, each line is usual Lua, for example `paw.opt.grid = 0.5`. If there is an error, `:extensions` and `:messages` show it.",
    },
    {
      say = "Listen with your click. Press `<leader><Space>`, then `<leader><Space>` to stop and `<leader>z` to disable the click.",
      keys = { "<leader><Space>", { wait = 300 }, "<leader><Space>", "<leader>z" },
      check = function(ctx, look) return look.played(ctx) and not paw.transport.metronome end,
      done = "Your own key works.",
    },
  },
  outro = "We made an option, a mapping and a command with `:lua`, and found where to keep them.",
}
