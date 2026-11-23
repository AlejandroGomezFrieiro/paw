# The status line

<!-- tags: statusline lualine paw.statusline -->

The status line has six sections, as lualine has in Neovim, where sections `a`,
`b` and `c` are on the left and `x`, `y` and `z` are at the right edge. Each section is a
list of components. `paw.statusline.setup` changes the sections that you
give it, and the other sections keep their defaults.

## The default line

| Section | Components |
| --- | --- |
| `a` | `mode` |
| `b` | (empty) |
| `c` | `macro`, `transport`, `clock`, `tempo`, `flags`, `render`, `diagnostics`, `qf`, `pointer`, `grid`, `selection`, `view` |
| `x` | `keys`, `scope`, `project`, `engine`, `cpu` |
| `y`, `z` | (empty) |

Each component has the narrowest screen that shows it, so the line does
not change its shape when the width changes by one column. paw shortens the
name of the project before it removes a component.

## Components

| Component | Shows |
| --- | --- |
| `mode` | The mode, and the view that has the keys: `NORMAL·mixer`. |
| `macro` | The register of a macro that paw records. |
| `transport` | The transport state and the position of the playhead. In a scope with time, the position is in the bars of the scope, and outside the time of the scope it is the place in the song with `@` before it: `@1.1.00`. |
| `clock` | The time. |
| `tempo` | The tempo, and the time signature at the playhead. |
| `flags` | What is on: `loop 3–5` (the bars of the playback loop, while looping is on), `click`, punch, count-in, `rec`, `write`, and `edit q` while `paw.opt.quality` is `"edit"` (see [Edit quality](engine.md#edit-quality)). |
| `take` | The take that records. |
| `render` | The progress of a render. |
| `derived` | When paw takes more than a second to read the chords of the song again after an edit, what it reads and how far it is: `chords 40%`. |
| `diagnostics` | The count of diagnostics. |
| `qf` | The entries of the quickfix list: `qf E2 W5`, or `qf 3/7 E2 W5` after you go to one. |
| `pointer` | What is under the mouse pointer, and what a click there does. |
| `grid` | The grid. |
| `selection` | What a visual selection of the arrange view holds, the same in each visual mode: `bars 3–10 · 3 tracks`, or `2 tracks` for `V`. A selection that does not start and end on bar lines gives its two places, as in `3.2.00–4.1.00 · 1 track`. |
| `view` | The `status` of the view, buffer type or text buffer that has the keys. |
| `cursor` | The track and the clip under the cursor. |
| `buffer` | The text buffer that has the keys. |
| `keys` | The keys typed until now. |
| `scope` | The path of the scope of the window: `Song › Strings`. In a scope with time, also the place of the cursor in its bars and in the bars of the song: `Song › Bridge 3.2 (19.2)`. |
| `project` | The name of the project, with an amber dot if it has changes that are not saved. |
| `engine` | The audio engine. |
| `cpu` | The load of the engine, and the dropouts, if there are any: `xrun 3`. |
| `midi` | Lights for a moment after MIDI comes in. |

## paw.statusline.setup

```lua
paw.statusline.setup({
  sections = {
    a = { "mode" },
    b = { "take" },
    c = { "transport", "clock", "tempo", "flags", "cursor", "grid" },
    x = { "midi", "keys" },
    y = { "engine", "cpu" },
    z = { "project" },
  },
  separators = { component = "│", section = "│" },   -- "" for a space
  theme = "default",                                 -- "mono", or a table of highlight groups
  views = { pianoroll = { sections = { c = { "cursor", "grid" } } } },
})
```

| Field | Effect |
| --- | --- |
| `sections` | The sections to change, by letter. |
| `separators` | `component` and `section`: the text between components and between sections. `""` gives a space. |
| `theme` | `"default"`, `"mono"` (one color for all modes), or a table of highlight groups: `mode = { n = "...", i = "..." }` for each mode, a letter for each section (`c = "StatusDim"`), and `sep` for the separators. |
| `views` | Sections for the time that a view has the keys: `views = { mixer = { sections = { ... } } }`. |
| `inactive_sections` | Sections for the time that a float has the keys (a picker, help, the plan of a write). |
| `winbar` | Sections added to the title bar of the window that has the keys. |
| `inactive_winbar` | Sections added to the title bars of the other windows. |
| `tabline` | `{ sections = { z = { ... } }, always = true }`: sections at the right end of the row of tabs. With `always`, the row shows also with one tab. The graphical window does not show it yet. |

## Components

A component is one of the following:

- a name: `"tempo"`.
- a function, `function(ctx) return "text" end`. It returns nothing when it has nothing to show, or a string, or a list of `{ text, group }` pieces.
- a table with a name or a function first, and options after it:
  `{ "grid", min = 120 }`,
  `{ fn, rank = 2, style = "StatusDim", cond = function(ctx) return ... end, fmt = function(text) return text:upper() end }`.

| Option | Effect |
| --- | --- |
| `min` | The narrowest screen, in columns, that shows the component. |
| `rank` | When the line is too long, a component with a higher rank goes first. `0` never goes. |
| `style` | The highlight group of the text. |
| `cond` | A function. The component shows only when it gives `true`. |
| `fmt` | A function that changes the text. |
| `key` | A function. paw calls the component again only when the value of `key(ctx)` changes. The `project`, `engine` and `cpu` components use it. |
| `still` | `true` when the component changes only after a key, an edit or another change that draws the whole screen again. |
| `moves` | A function that gives a text of what the component changes with by itself, such as the position of the playhead. |

The options `key`, `still` and `moves` go on a component that `paw.statusline.component` adds. While the song plays, and for a moment after paw plays a note, the terminal draws the meters and the playhead again many times a second. It draws the status line again on those frames only when a component may have changed, which means that the `moves` text of a component changed, or else its `key`. A component with none of `still`, `moves` and `key` makes the terminal draw the status line again on each of those frames, which is correct and costs more time.

The `transport`, `clock`, `tempo`, `take`, `render`, `derived`, `pointer`, `engine` and `cpu` components have `moves`, and the `project` component has a `key`. The other built-in components are `still`.

`ctx` holds the fields below.

| Field | Value |
| --- | --- |
| `width` | The width of the screen. |
| `mode` | The mode. |
| `view` | The view that has the keys. |
| `focused` | For a winbar: the window has the keys. |
| `g` | The characters, as `paw.draw.g`. |
| `transport`, `project`, `engine` | The tables of `paw.api.transport_get`, `project_get` and `engine_get`. paw reads them only when a component asks. |

## Functions

| Function | Effect |
| --- | --- |
| `paw.statusline.setup(opts)` | Changes the line (above). |
| `paw.statusline.component(name, spec)` | Adds a component that a configuration can name: `paw.statusline.component("pulse", { fn = function(ctx) return "♥" end, min = 90, rank = 6 })`. |
| `paw.statusline.reset()` | Gives back the default line. |
| `paw.statusline.line(width)` | The line for a width. Its `errors` field lists the errors of components. An error does not show on the line. |

## In the graphical window

Until `setup` runs, the graphical window shows its own line, and after
`setup` the kernel sends the pieces of the line as `modal.statusline`
(`{ left, right }`, each a list of `{ text, group }`), and the window shows
them. See [The graphical frontend](window.md).
