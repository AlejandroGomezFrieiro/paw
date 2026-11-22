# sections

This extension adds song sections, which are named parts of the timeline such as intro, verse and chorus.
A section has a name and a start, and it continues to the start of the next
section. The last section continues to the end of the project, for at least
one bar.

Sections are text objects and motions, so your usual operators work on a
full section. They are also the units that you arrange the song with, so you can move a chorus
past the verse, repeat it, cut it, or copy it to another place. Each edit
applies to every track and is one undo step.

```lua
paw.ext.load("extensions/sections")   -- or put it in ~/.config/paw/extensions
```

![The demo song named Intro and Verse with \Sa, [[ and ]] going between them, \S& repeats the verse after itself on every track, and u](images/tui-sections.gif)

## Try it

1. Type `:ext.load sections`, and open a song.
2. Put the cursor on bar 1. Press `\Sa`, type `Intro` and press Enter, and the
   name `Intro` appears on a second row of the ruler.
3. Move the cursor to bar 5. Press `\Sa`, type `Verse` and press Enter.
4. Press `[[`, then `]]`, and the cursor goes to the start of each section.
5. Press `\S&`, and the verse repeats after itself on every track. Press `u` to
   undo it.

## How to

### How to move a section

- To move it past the next section, press `\SL`. To move it past the
  section before, press `\SH`. A count moves it further.
- To move it to any place, press `\Sd` on the section. Move the cursor to
  the new place, and press `\SP`.

### How to repeat or copy a section

- To repeat a section after itself, press `\S&`.
- To put a copy of another section before the section at the cursor, press
  `\Sc` and choose the section.

### How to edit a full section with an operator

Use the text object `is` after the operator:

- `dis` empties the section on every track. With `paw.opt.ripple`, it
  closes the gap.
- `yis` yanks it, and `glis` loops it.
- `>is` moves its clips, and `vis` selects it.

### In the graphical window

- Click a section in the band under the ruler to go to its start.
- Choose More, then Sections, or "Open in a window" on `<localleader>Sl`, to open
  the list in a window of its own.

## Reference

### On the screen

- The name of each section is on a second row of the ruler, under the bar
  numbers, at the start of the section, and the row shows when there are sections.
- The section under the cursor is amber.
- When the start of a section is past the left edge, its name stays at the
  left, after a `‹`.
- The column where each section starts has a tint across the tracks.
- In the graphical window, the sections are a band under the ruler, each
  over its part. The section under the cursor is lit.

### Keys

In the arrange view.

| Keys | Effect |
| --- | --- |
| `]]` `[[` | `]]` goes to the start of the next section, and `[[` goes to the start of this section, or of the section before. A count goes further. After the last section, `]]` goes to the end of the project. They are motions, as in `d]]`, `y[[` and `v]]` |
| `is` | text object for the section under the cursor, on every track. `2is` takes that section and the next |
| `as` | the same text object, made wider to full bars (for a section that starts with a pickup) |
| `<localleader>Sa` | adds a section at the cursor and asks for a name, and Tab offers the usual names |
| `<localleader>Sr` | renames the section at the cursor |
| `<localleader>Sx` | removes the marker of the section, and the timeline does not change |
| `<localleader>Ss` | goes to a section, chosen from a list |
| `<localleader>Sl` | shows the list of sections |
| `<localleader>SL` `<localleader>SH` | moves the section later, past the next section, or earlier, past the section before. A count moves it further |
| `<localleader>S&` | repeats the section after itself, and moves the rest of the song later |
| `<localleader>Sd` | deletes the section from every track and closes the gap, and the section goes into the register |
| `<localleader>Sy` | yanks the section with its automation and marker |
| `<localleader>Sp` `<localleader>SP` | inserts the register after or before the section at the cursor, on every track, and moves the rest later |
| `<localleader>Sc` | inserts a copy of a section, chosen from the list, before the section at the cursor |

- Registers (`"a<localleader>Sy`), counts and `.` work as in all views.
- `<localleader>Ss` and `<localleader>Sc` choose with `paw.pick`, and without it they
  ask for a name on the command line (Tab completes).
- `<localleader>Sl` shows the list of sections over the views. From the list,
  you can go to a section, rename it, add one at the cursor, or remove one (see
  `section.list`).

### Commands

| Command | Effect |
| --- | --- |
| `section.add [name] [at=beat]` | adds a section at the cursor, or at a beat. It asks for the name if there is none |
| `section.rename [name] [section=old]` | renames the section at the cursor, or the section that `section=` names |
| `section.remove [name]` | removes the marker of a section |
| `section.list` | shows the list of sections, where `j` `k` choose one (or a click), Enter (or a second click) goes there, `r` renames it, `a` adds one at the cursor, `x` removes its marker, and `q` closes |
| `section.goto [name or number]` | goes to a section, and with neither a name nor a number you choose from the list |
| `section.move [name] [by=1]` | moves a section past the section after it. `by=-1` moves it earlier |
| `section.duplicate [name]` | repeats a section after itself |
| `section.delete [name]` | deletes a section and closes the gap, and the section goes into the register |
| `section.yank [name]` | yanks a section into the register |
| `section.put [before=true]` | inserts the register after (or before) the section at the cursor |
| `section.copy [name] [after=true]` | inserts a copy of a section before (or after) the section at the cursor |

Without a name, the commands act on the section under the cursor. A name
matches exactly first, then without regard to case, and then by its start (`chor`).

### What moves

- Each command that arranges acts on every track at the same time.
- Clips across the edges of a section are cut there first, and the pieces go
  with their sections. A MIDI note belongs to the piece that it starts in,
  and becomes shorter to fit in it, as with the built-in operators.
- A clip that moves keeps its id and its `meta`.
- Automation lanes (volume, pan and device parameters, on every track and
  the master track) move with their sections. Each piece of the song takes
  the values of the lane at its edges as points, so a moved section sounds
  as before. Where it touches a different section, the lane steps from one
  value to the other, and paw then removes points that change nothing.
- Section markers move with what they mark. When a chorus moves, its name
  moves, a duplicate makes a second chorus, and a delete removes the marker. A
  section yanked with `<localleader>Sy` or deleted with `<localleader>Sd` brings its
  marker back when you insert it.
- The tempo, the time signature, the loop and the playhead do not move.

### The Lua module

```lua
local sections = require("sections")

sections.list()                 -- { { index, name, start, finish }, ... } in order
sections.at(beat)               -- the section of a beat. nil before the first
sections.current()              -- the section under the edit cursor
sections.find("chor")           -- by name: exact, any case, or its start
sections.get(which)             -- an index, a name, a section, or nil for the current one
sections.next_start(beat)       sections.prev_start(beat)

sections.add("Chorus", 64)      -- fails if a section starts there
sections.rename("Chorus", "Hook")
sections.remove(3)
sections.set_start("Hook", 60)  -- moves the marker only
sections.set({ { name = "A", start = 0 }, { name = "B", start = 32 } })

-- Arrange, on every track. Each returns the section at its new place.
sections.move("Verse", 1)       -- past the next section. -1 past the section before
sections.duplicate("Chorus")
local value = sections.delete("Bridge")   -- a register value
sections.insert(value, 96)                -- moves what is at 96 later and puts it there
sections.copy("Chorus", 128)
sections.yank("Chorus")
sections.rebuild(plan)          -- the general form. See lua/sections/arrange.lua

paw.on("sections.changed", function(event) print(#event.sections) end)
```

- The project keeps the sections in `project.meta.sections`, a list of
  `{ name, start }`, so they are saved with the project, and `u` undoes each change.
- paw sends `sections.changed` when the list changes for any reason, such as edits,
  undo, redo, or a new or opened project. It sends the event when the command that
  changed the list returns, or at `paw.flush()`.
- A register value from `sections.yank` or `sections.delete` is an ordinary
  `range` value, so `p` and `P` paste it too, from the cursor track down,
  without automation or markers. The value also has `lanes` and `sections`.

### Limits

- The status line does not show the current section, because the extension adds no
  component to the status line, but the ruler keeps the name of the current
  section in view.
- An insert finds tracks by their position, so if you add, remove or move
  tracks between the yank and the insert, its clips go on the tracks that
  are now at those positions.
- An insert finds automation by target, parameter and position of the
  device on the track. paw drops a lane that has no match where the section
  goes.
- Notes that sound across the edge of a section become shorter and do
  not continue into the next piece.
- The right half of a clip cut at the edge of a section is a new clip, which
  keeps the `meta` of the clip but not its id.
- You cannot drag sections with the pointer.
