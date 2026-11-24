# How to change the status line

You can change what the status line shows with a few lines in your
`init.lua`.

1. Open `~/.config/paw/init.lua`.
2. Add a call to `paw.statusline.setup` with the sections to change.
   The example puts the part and clip under the cursor in section `b`:

   ```lua
   paw.statusline.setup({ sections = { b = { "cursor" } } })
   ```

3. Type `:reload` in paw.

The sections that you do not give keep their defaults. You can also change
the line in the following ways:

- To add a component of your own, give a function:

  ```lua
  paw.statusline.setup({ sections = { y = { function() return os.date("%H:%M") end } } })
  ```

- To show a component only on a wide screen, give its minimum width:
  `{ "grid", min = 120 }`.
- To use a different line in one view, use `views`:

  ```lua
  paw.statusline.setup({ views = { mixer = { sections = { c = {} } } } })
  ```

- To use one color for all modes, set `theme = "mono"`. To return to the
  default line, call `paw.statusline.reset()`.

If a component has an error, the line does not show it. To see the errors,
type `:lua =paw.statusline.line(120).errors`.

## See also

- [The status line](../reference/status-line.md): every component, field and option.
