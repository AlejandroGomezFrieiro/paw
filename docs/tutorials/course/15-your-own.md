<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 15: Make paw your own: options, keys, commands

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 15`.*

In this lesson, we set an option, map a key and make a command with `:lua`. Then we put them in `init.lua`.

Each key that you used is a usual mapping, and each command is a usual Lua function. paw makes them with the same functions that you can use. Your own file, `~/.config/paw/init.lua`, runs when paw starts. paw applies the options, mappings and commands in it each time.

`:lua` runs one line of Lua. The values that you set here stay until you quit. The grid is different: the tutor sets it to its old value when you leave the tutor.

## The idea

`paw.opt.name = value` sets an option (`:lua paw.opt.grid = 0.5`). `<Space>fo` shows the options. `paw.keymap.set(keys, command or function, { desc = ..., view = ... })` maps keys. `<Space>` is the leader (`,`), and `<localleader>` is the leader of the keys of one view (a backslash).

`paw.command(name, function(ctx) ... end, { desc = ... })` makes a command. `:name` runs it, and a mapping can use its name. `:reload` runs `init.lua` again and does not change the project.

## If you know Vim

This is the `init.lua` of Neovim, with `paw.opt`, `paw.keymap.set` and `paw.command` in place of `vim.opt`, `vim.keymap.set` and `vim.api.nvim_create_user_command`. `:lua` is the same. A file with the same name in `~/.config/paw/lua/` replaces a built-in module.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. First, set an option. Type `:lua paw.opt.grid = 0.5` and `<CR>`. Then press `l`: the cursor moves half a beat now.
   - *Hint:* Type the text exactly, with the spaces. On the command line, `<Up>` shows the text that you typed before.
   - ✓ The grid is half a beat, and the status line shows `grid 0.5`. `]g` and `[g` also change it.
2. Now map a key of your own. Type `:lua paw.keymap.set("<leader>z", "transport.metronome", { desc = "Click" })` and `<CR>`. Then press `<Space>z`.
   - ✓ `<Space>z` enables and disables the click. `?` shows your mapping with its description.
3. Now make a command of your own. Type `:lua paw.command("hello", function() paw.notify("hello from my command") end)` and `<CR>`. Then type `:hello` and `<CR>`.
   - ✓ Your command ran. `:commands` and the `<Space>fc` picker show it now, with the built-in commands.
4. To keep them, open `~/.config/paw/init.lua` in your text editor. Add the same three lines without `:lua`, and save. Then type `:reload` here.
   - *Hint:* In init.lua, each line is usual Lua, for example `paw.opt.grid = 0.5`. If there is an error, `:extensions` and `:messages` show it.
   - *The tutor cannot check this step* (The tutor does not read or write your configuration). `<Space>hn` moves to the next step.
5. Listen with your click. Press `<Space><Space>`, then `<Space><Space>` to stop and `<Space>z` to disable the click.
   - ✓ Your own key works.

## What we did

We made an option, a mapping and a command with `:lua`, and found where to keep them.

Previous: [Find a command or a key](14-finding.md) · [All lessons](README.md) · Next: [The bundled extensions](16-extensions.md)
