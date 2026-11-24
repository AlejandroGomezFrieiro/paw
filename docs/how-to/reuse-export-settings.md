# How to reuse your export settings

You can save the words of an export as a preset, and export the same way
again with one name. Each word is in
[Export](../reference/export.md#presets).

## Save a preset in the project

1. Export once with the words that you want, for example
   `:export stems format=flac bits=16`. You can press `Esc` in the plan if
   you don't want the files yet.
2. Type `:export.preset delivery`. paw saves the words in the project, and
   the message shows them.
3. Save the project with `:w`. The preset is in `project.toml`, so it goes
   with the song when you share the folder.

Next time, type `:export delivery`. To change a word for one export, type
it after the name, as in `:export delivery bits=24`.

If the project already has a preset of that name, type
`:export.preset! delivery` to replace it. To take a save back, press `u`.

## Choose a preset from a list

1. Press `<Space>ep`. paw lists the presets, with where each one comes
   from.
2. Type a few letters of the name. The preview shows the plan of the
   preset: the files, what each one holds, and where it listens.
3. Press `Enter` to export. For more than one file, paw shows the plan
   again, and `y` writes the files.

To export the selection with a preset, select the parts and the time in
the arrange view, and press `<Space>ep`.

## Export several things at once

A preset can be a list of exports, such as a FLAC master and the stems.
paw shows one plan for all of the files and writes them in one queue.

1. Open `project.toml` of the project, or your `init.lua`.
2. Add the list. In `project.toml`:

   ```toml
   [export.presets]
   delivery = ["mix format=flac", "stems"]
   ```

   In `init.lua`, for each project:

   ```lua
   paw.export.presets.delivery = { "mix format=flac", "stems" }
   ```

3. Type `:export delivery`, and press `y` in the plan.

To see each preset and where it comes from, type `:export.preset`. A
preset of the project comes before the one of `init.lua`, and that one
comes before the presets of paw.
