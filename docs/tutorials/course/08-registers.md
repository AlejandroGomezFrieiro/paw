<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 8: Yank, paste, registers and macros

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 8`.*

In this lesson, we copy a short hook along a track and keep two bass clips in named registers. Then we record a macro that changes the hook.

A delete or a yank puts the items in a register, and a paste takes them from it. You use one register without a name. The named registers (`"a` to `"z`) keep several items at the same time. You can undo each change, and a count undoes more than one. A macro records keys into a register, and you can play them again.

The Lead track has a short hook. Bass has two clips, A and B.

## The idea

`y` yanks, and `d` and `x` delete into the register. `p` pastes after the clip (or note) under the cursor, and `P` pastes at the cursor. `3p` pastes three copies, one after the other, and `p` again continues from the last paste. `"a` before a command names the register: `"ayic`, `"ap`. `"0` keeps the last yank after deletes, `"_` discards, and `:registers` shows all the registers.

`u` undoes, `3u` undoes three times, and `<C-r>` redoes. `qq` records keys into register q until `q`. `@q` plays them, `@@` plays the last macro again, and `5@q` plays it five times.

## If you know Vim

Registers, `"0`, `"_`, `qq`…`q`, `@q`, `@@` and `@:` are from Vim. A register contains clips, tracks, notes or a device, not text. Pasted time replaces the items that were there. `:lua paw.opt.ripple = true` moves those items later.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. The cursor is on the hook. Press `yic` to yank (copy) the clip.
   - ✓ The hook is in the unnamed register. It is also in register 0, which keeps the last yank.
2. `p` pastes after the clip under the cursor. Press `p`.
   - ✓ A second hook shows immediately after the first.
3. A count pastes more than one copy, and `p` again continues from the last paste. Press `2p`.
   - ✓ Four hooks fill four bars.
4. Named registers keep more than one item. Press `j` to go to Bass and `0` to go to its start. Press `"ayic` to yank clip A into register a.
   - *Hint:* `"` is the double quote key. Press `"`, then `a`, then `yic`.
   - ✓ Register a contains A.
5. Press `w` to go to B. Press `"byic` to yank it into register b.
   - ✓ Register b contains B.
6. `:registers` shows the contents of each register. Type `:registers` and `<CR>`. Look at the list, then press `q` to close it.
   - ✓ The list showed `"a` and `"b`, with `"0` and the unnamed `""`.
7. Press `$` to go to the end of B. Press `"ap` to paste A there, and `"bp` to paste B after it.
   - ✓ The bass line is A B A B. It plays two times.
8. Undo also accepts a count. Press `2u` to undo the two pastes.
   - ✓ The bass line is A B again. `2<C-r>` redoes the two pastes.
9. Now we record a macro. Press `k` to go up to Lead and `0` to go to its start. Then press `qq` to record keys into register q.
   - ✓ The status line shows `recording @q`.
10. Type the change. `vic` selects the clip, `12<C-a>` moves its notes up one octave and `w` goes to the next clip. Then press `q` to stop the recording.
   - *Hint:* Without the selection, `<C-a>` on a track moves the fader. If the result is wrong, press `u` to undo the change and `qq` to record again.
   - ✓ The first hook went up one octave while you recorded. Register q contains `vic12<C-a>w`.
11. `@q` plays the macro on the clip under the cursor, and `@@` plays it again. Press `@q`, then `@@`.
   - ✓ Three hooks are one octave higher. The last hook did not change.
12. Listen to the result. Press `gs` and `<Space><Space>`. Press `<Space><Space>` to stop.
   - ✓ The hook goes up and then comes down again.

## What we did

We used `yic` and `p` with counts, named registers, `:registers` and `2u`. We recorded a macro with `qq` and played it with `@q` and `@@`.

Previous: [Visual mode: select, then act](07-visual.md) · [All lessons](README.md) · Next: [Devices, parameters and plugins](09-devices.md)
