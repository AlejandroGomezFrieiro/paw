<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# The course

In this course, we use paw to make and change small songs. Each lesson takes about ten minutes and opens a small practice project of its own, and at the end of each lesson, we hear what we made or changed. The same lessons run in paw, where the tutor tells you what to do next and checks each step when you do it. To load the tutor, add this line to your configuration:

```lua
paw.ext.load("extensions/tutor")   -- in ~/.config/paw/init.lua, or link the directory into ~/.config/paw/extensions
```

Then type `:tutor` in paw. The tutor makes these pages from its lessons, so the pages and the tutor give the same steps. [Keys, by idea](../../reference/keys.md) is a page of keys to keep near the keyboard.

You can also do the course without an install. [The course in your browser](in-the-browser.md) has every lesson on one page, with paw running beside the steps.

| | Lesson | What we do |
| --- | --- | --- |
| 1 | [First steps: the screen, play and quit](01-first-steps.md) | We played a song, moved the cursor, used the command line and found the list of all the keys. |
| 2 | [Move the cursor, and keys that change meaning](02-moving.md) | We moved by steps, clips, bars and parts, with counts. The same keys had other meanings in visual mode and in the piano roll. |
| 3 | [Parts, clips and notes](03-making.md) | We made a part and gave it a name and an instrument. We added notes, repeated and deleted clips, and undid a change. |
| 4 | [The piano roll and insert mode](04-pianoroll.md) | We moved by pitch and by time, and changed a note in normal mode. Then we drew a line and a chord in insert mode, and met step input from a MIDI keyboard. |
| 5 | [The grammar: operators, motions, text objects](05-grammar.md) | We used operators with motions (`dw`, `d2W`) and with text objects (`dic`, `gcic`, `glic`), `dd` for parts, and `.` to repeat. |
| 6 | [The same grammar on notes](06-grammar-notes.md) | We used the grammar of lesson 5 on notes: `dw`, `.`, `>in`, `yie` `p`, `cin`, `dd` and `/`. |
| 7 | [Visual mode: select, then act](07-visual.md) | We selected with `v`, `V` and motions, and then used `x`, `y`, `~`, or a count and `<C-a>`. We also used `gv` to select again, and we used visual mode in the piano roll. |
| 8 | [Yank, paste, registers and macros](08-registers.md) | We used `yic` and `p` with counts, and we used named registers, `:registers` and `2u`. Then we recorded a macro with `qq` and played it with `@q` and `@@`. |
| 9 | [Devices, parameters and plugins](09-devices.md) | We used the device panel to select and change parameters. We added and bypassed a device, and we found where plugin windows open. |
| 10 | [The mix: faders, pan, buses, sends, automation](10-mixing.md) | We used the faders, pan, solo and mute of the mixer. We made a bus with `:part.output`, and we added a send and volume automation with `A`. |
| 11 | [Loops, marks and jumps](11-loops.md) | We set the loop with `gL`, `glic` and `gl2W`, and the click with `gm`. We used `/` to find clips, and `ma`, `'a` and `''` to jump. |
| 12 | [Record audio and MIDI](12-recording.md) | We selected an input with `I`, armed the part with `r`, recorded with `R` and stopped with `<Esc>`, and we made an audio take and a MIDI take. |
| 13 | [Save and export](13-saving.md) | We saved with `:w`, and we saw `[+]` for changes that are not saved. Then we exported with `:export name.wav tail=2` and read `:messages`. |
| 14 | [Find a command or a key](14-finding.md) | We used key hints, `?`, `:commands`, Tab on the command line, the `<Space>f` pickers and `K`. |
| 15 | [Make paw your own: options, keys, commands](15-your-own.md) | We set an option, made a mapping and a command with `:lua`, and found where to keep them. |
| 16 | [The bundled extensions](16-extensions.md) | We tried one feature of each of pattern, musicops, sections, undotree, mixdiag, interop and utau, and their READMEs describe the rest. |
| 17 | [Ranges, :s and :g: edit by line](17-ranges.md) | We used `:2,3d`, `:t2 4d`, `:t* volume -=3`, `:%s/c4/d4/g` and `:g/name:b/mute`, which are each a range followed by a command, with one undo step for each. |

Lessons 1 to 4 teach the screen, the cursor, and how to make parts and notes. Lessons 5 to 8 teach the grammar of the keys, which all of paw uses. Lessons 9 to 13 teach devices, the mix, loops and recordings, and how to save and render. Lessons 14 to 16 help you find keys, make paw your own, and use the extensions. Lesson 17 edits by line, with ranges of bars and parts, `:s` and `:g`.

The five lessons of [Make music with paw](../make-music/README.md) make one song, from the first note to an MP3 file, with the keys of the course.
