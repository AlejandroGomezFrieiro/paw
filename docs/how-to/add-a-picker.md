# How to add a picker

You can add a picker of your own in your `init.lua` or in an extension.
The example on the page lets you choose a tempo from a list.

1. Put a source in `paw.pick.sources`, with a `desc`, a `title`, the
   `items` and `on_choose`:

   ```lua
   paw.pick.sources:put("tempo", {
     desc = "Set the tempo from a list",
     title = "Tempo",
     items = function()
       return { { bpm = 90, text = "90 hip hop" }, { bpm = 124, text = "124 house" }, { bpm = 174, text = "174 drum and bass" } }
     end,
     on_choose = function(item) paw.project.tempo = item.bpm end,
   })
   ```

2. If you want to show more about the selected line, add a `preview`:

   ```lua
   paw.pick.sources:get("tempo").preview = function(item)
     return { "now " .. paw.project.tempo .. " bpm", "then " .. item.bpm .. " bpm" }
   end
   ```

3. If you want a key that opens the picker, map one:

   ```lua
   paw.keymap.set("<leader>fT", function() paw.pick("tempo") end, { desc = "Choose a tempo" })
   ```

4. Type `:reload`.

After the reload, `<Space>fT`, `:pick tempo` and `paw.pick("tempo")` open
the picker, and `<Space>fp` lists it.

When `items` is a function, paw calls it each time the picker opens, so
the list is always current. A picker with a hundred thousand items is
still fast.

If you want `Ctrl-v` to open the items in a split, give the source a
`location`. If you want to hear an item when the selection stops on it,
give it an `audition`. Every field is listed in
[Pickers](../reference/pickers.md#lua).
