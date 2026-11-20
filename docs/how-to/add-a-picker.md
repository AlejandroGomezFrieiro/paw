# How to add a picker

This guide shows you how to add a picker of your own, in your `init.lua` or
in an extension. The example chooses a tempo from a list.

1. Add a source to `paw.pick.sources`, with a `desc`, a `title`, the
   `items` and `on_choose`:

   ```lua
   paw.pick.sources.tempo = {
     desc = "Set the tempo from a list",
     title = "Tempo",
     items = function()
       return { { bpm = 90, text = "90 hip hop" }, { bpm = 124, text = "124 house" }, { bpm = 174, text = "174 drum and bass" } }
     end,
     on_choose = function(item) paw.project.tempo = item.bpm end,
   }
   ```

2. To show more about the selected line, add a `preview`:

   ```lua
   paw.pick.sources.tempo.preview = function(item)
     return { "now " .. paw.project.tempo .. " bpm", "then " .. item.bpm .. " bpm" }
   end
   ```

3. To open the picker with a key, map one:

   ```lua
   paw.keymap.set("<leader>fT", function() paw.pick("tempo") end, { desc = "Choose a tempo" })
   ```

4. Type `:reload`.

Now `<Space>fT`, `:pick tempo` and `paw.pick("tempo")` open the picker, and `<Space>fp`
lists it.

If `items` is a function, paw calls it each time that the picker opens.
So the list is always current. A picker of a hundred thousand items is
fast.

To open the items in a split with `Ctrl-v`, give a `location`. To hear an
item when the selection stops on it, give an `audition`. For every field,
see [Pickers](../reference/pickers.md#lua).
