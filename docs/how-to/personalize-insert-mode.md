# How to personalize insert mode

You can change what the keys of insert mode insert in the arrange view,
with a few lines in your `init.lua`. In the arrange view, `i` starts insert
mode, and then `m` inserts a MIDI clip, `r` a region and `'` a marker.
[Insert mode in the arrange view](../reference/insert-mode.md) lists all
the keys.

## Change what a key inserts

1. Open `~/.config/paw/init.lua`.
2. Make each region go to the next marker, with the name Verse 1,
   Verse 2 and so on:

   ```lua
   paw.insert.set("r", { name = "Verse %d", length = "marker" })
   ```

3. Make the MIDI clips one bar long:

   ```lua
   paw.insert.set("m", { length = "1 bar" })
   ```

4. Type `:reload` in paw.

The fields that you do not give stay as they are.

## Add a key for a clip with notes in it

You can add a key that inserts a clip with notes. The example key inserts
a drum clip of two bars, with a kick on each beat and a snare on beats 2
and 4. Add the key to your `init.lua`:

```lua
local notes = {}
for beat = 0, 7 do
  notes[#notes + 1] = { pitch = 36, start = beat, length = 0.5 }
  if beat % 2 == 1 then notes[#notes + 1] = { pitch = 38, start = beat, length = 0.5 } end
end
paw.insert.add("M", {
  kind = "midi",
  desc = "A two-bar drum clip",
  length = "2 bars",
  name = "Drums %d",
  notes = notes,
})
```

On a track, press `i`, then `M` two times, and then `Esc`. Two drum clips
are on the track, one after the other, and `u` removes both.

## Move a key, or remove it

- To insert MIDI clips with `n` and not with `m`:

  ```lua
  paw.insert.set("m", { key = "n" })
  ```

- To remove a key:

  ```lua
  paw.insert.remove("f")
  ```

- To keep only some keys, in the order that the box of keys shows them:

  ```lua
  paw.opt.insertkeys = { "m", "r", "'" }
  ```

## Related

- [Insert mode in the arrange view](../reference/insert-mode.md): the
  keys, and the fields of `paw.insert.add`.
- [How to personalize the track column and the
  ruler](personalize-the-track-column-and-the-ruler.md).
