<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 15: Make paw your own: options, keys, commands

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 15`.*

In this lesson, we set an option, map a key and make a command with `:lua`, and then we put them in `init.lua`.

Each key that you used is a usual mapping, and each command is a usual Lua function, which paw makes with the same functions that you can use. Your own file, `~/.config/paw/init.lua`, runs when paw starts, so paw applies the options, mappings and commands in it each time.

`:lua` runs one line of Lua, and the values that you set with it stay until you quit. The grid is an exception, because the tutor sets it back to its old value when you leave the tutor.

## The idea

`paw.opt.name = value` sets an option, e.g., `:lua paw.opt.grid = 0.5`, and `<Space>fo` shows the options. `paw.keymap.set(keys, command or function, { desc = ..., view = ... })` maps keys. `<Space>` is the leader key, which is the space bar, and `<localleader>` is the leader of the keys of one view, which is a backslash.

`paw.command(name, function(ctx) ... end, { desc = ... })` makes a command. `:name` runs the command, and a mapping can use its name. `:reload` runs `init.lua` again and does not change the project.

## If you know Vim

The `init.lua` of paw works as the `init.lua` of Neovim, with `paw.opt`, `paw.keymap.set` and `paw.command` in place of `vim.opt`, `vim.keymap.set` and `vim.api.nvim_create_user_command`. `:lua` is the same. A file with the same name as a built-in module in `~/.config/paw/lua/` replaces the module.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. First, set an option. Type `:lua paw.opt.grid = 0.5` and `<CR>`, and then press `l`, and the cursor now moves half a beat.
   - *Hint:* Type the text exactly, with the spaces. On the command line, `<Up>` shows the text that you typed before.
   - ✓ The grid is half a beat, and the status line shows `grid 0.5`. `]g` and `[g` also change the grid.
2. Now map a key of your own. Type `:lua paw.keymap.set("<leader>k", "transport.metronome", { desc = "Click" })` and `<CR>`, and then press `<Space>k`.
   - ✓ `<Space>k` enables and disables the click, and `?` shows your mapping with its description.
3. Now make a command of your own. Type `:lua paw.command("hello", function() paw.notify("hello from my command") end)` and `<CR>`, and then type `:hello` and `<CR>`.
   - ✓ Your command ran, and `:commands` and the `<Space>f:` picker now show it with the built-in commands.
4. To keep the option, the mapping and the command, open `~/.config/paw/init.lua` in your text editor. Add the same three lines without `:lua`, and save the file. Then type `:reload` in paw.
   - *Hint:* In init.lua, each line is usual Lua, for example `paw.opt.grid = 0.5`. If there is an error, `:extensions` and `:messages` show it.
   - *The tutor cannot check this step* (The tutor does not read or write your configuration). `<Space>hn` moves to the next step.
5. Listen with your click. Press `<Space><Space>`, and then `<Space><Space>` to stop and `<Space>k` to disable the click.
   - ✓ The key that you mapped works.

## What we did

We set an option, made a mapping and a command with `:lua`, and found where to keep them.

- Previous: [Find a command or a key](14-finding.md)
- Next: [The bundled extensions](16-extensions.md)
- [All lessons](README.md)
