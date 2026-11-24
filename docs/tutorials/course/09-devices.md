<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 9: Devices, parameters and plugins

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 9`.*

In this lesson, we make a synth brighter and darker, add an echo after it, and bypass the echo.

Each part has a chain of devices. The first device is an instrument, which makes sound from notes, and the effects come after it. Each effect changes the sound of the device before it. The device panel shows the chain of the part under the cursor, with the parameters of each device, and you use the same kind of keys there as in the other views.

The built-in devices include `synth`, `drums`, `gain`, `delay` and `limiter`. The CLAP, LV2 and VST3 plugins that you installed are also devices, and most of them have their own window.

## The idea

In the device panel, `j` and `k` select a row, which is the name of a device or one of its parameters, and `w` and `b` select a device. `+` and `-` change a parameter by one step, and a count before them, e.g., `10+`, changes it by more steps.

`a` adds a device, `x` removes one and `gc` bypasses one. `yy`, `dd` and `p` copy and move devices, also to other parts. `<A-j>` and `<A-k>` change the order, and `ge` opens the window of a plugin.

`<Space>dd` shows and hides the panel, and `<C-w>c` closes it. In the arrange view, `ge` opens the plugin window of the part.

## If you know Vim

`<C-w>c` closes a panel as it closes a window in Vim, and `yy` `dd` `p` work on devices as they work on lines. `+` and `-` change a value as `<C-a>` and `<C-x>` change a number, and `gc` bypasses a device as it changes a line to a comment.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. The cursor is on Lead. Press `<Space>dd` (the space bar, then d two times) to show its device panel on the right, and the panel gets the keys.
   - *Hint:* The leader key is the space bar, and it starts many commands of two keys.
   - ✓ The panel shows the name of the synth, and below it one row for each parameter.
2. `j` and `k` select a row. Press `6j` to go down to `cutoff`, which sets how bright the sound is.
   - ✓ `cutoff` is selected.
3. `+` increases the parameter by one step, and `-` decreases it. A count before them gives the number of steps. Press `10+` three times.
   - ✓ The sound is brighter, and the bar and the number show the new value.
4. Listen while you change the value. Press `<Space><Space>`, and then press `-` some times to make the sound darker. Press `<Space><Space>` to stop.
   - ✓ You can change parameters while the song plays.
5. `a` adds a device after the instrument. Press `a`, type `delay` and press `<CR>`.
   - ✓ An echo now comes after the synth.
6. `w` goes to the next device. Press `w` to go down to the `Delay` heading.
   - *Hint:* `b` goes to the previous device, and `j` and `k` move one row at a time.
   - ✓ The delay is selected.
7. `gcc` bypasses the selected device, so the device stays in the chain but does nothing. Press `gcc`, and then `gcc` again to enable the device.
   - ✓ With bypass, you can compare the sound with and without an effect. In the other views, `gc` mutes.
8. `ge` opens the window of a plugin. Built-in devices have no window, and the message line says so. Press `ge`.
   - ✓ For a plugin, the window opens, and `ge` again closes it, in every view.
9. If you installed plugins, `a` shows them with the built-in devices. Press `a`, type a part of the name of a plugin and press `<CR>`, and then press `ge` to see its window. `:devices` shows all the devices.
   - *The tutor cannot check this step* (The installed plugins are different on each computer, and a plugin window needs a desktop). `<Space>hn` moves to the next step.
10. `<C-w>c` closes the panel, and the arrange view gets the keys again. Press `<C-w>c`.
    - ✓ The panel is closed, and `<Space>dd` shows it again.
11. Listen to the line with its echo. Press `<Space><Space>`, and `<Space><Space>` to stop.
    - ✓ You hear a synth and a delay that you adjusted by ear.

## What we did

We used the device panel to select and change parameters. We added and bypassed a device, and we found where plugin windows open.

- Previous: [Yank, paste, registers and macros](08-registers.md)
- Next: [The mix: faders, pan, buses, sends, automation](10-mixing.md)
- [All lessons](README.md)
