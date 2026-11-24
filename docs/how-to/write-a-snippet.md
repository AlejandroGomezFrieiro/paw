# How to write a snippet

You can add a snippet that writes music from the harmony at the cursor.
The example writes IV and then I of the key, and each field is in
[Snippets](../reference/snippets.md).

1. Make the file `<config>/snippets/plagal.lua`, and add the snippet:

   ```lua
   paw.snippet.add({
     name = "plagal", desc = "IV then I of the key, two beats each",
     views = { "pianoroll" },
     choices = { { name = "voicing", values = { "smooth", "close", "open" } } },
     expand = function(ctx)
       local tonic = ctx.key.root
       local four = ctx:chord(ctx.harmony.tones((tonic + 5) % 12, "maj"), ctx.at, ctx.at + 2)
       local one = ctx:chord(ctx.harmony.tones(tonic, "maj"), ctx.at + 2, ctx.at + 4)
       for _, n in ipairs(one) do four[#four + 1] = n end
       return { notes = four }
     end,
   })
   ```

2. Start paw again, because paw loads the files in `<config>/snippets/`
   when it starts.
3. Open a clip in the piano roll and put the cursor where the chords must
   start. Press `<C-s>` and type `plagal`, and the piano roll shows the
   notes as ghost notes.
4. Use the snippet:
   1. Press `Enter`. The snippet writes the notes and stays active.
   2. Press `<Tab>` to select the `voicing` choice, and press `<C-n>` to
      try the next value.
   3. Press `<Esc>` to keep the notes.

`ctx:chord` puts the chord in the range of the part and leads it from the
chord before, and the `voicing` choice sets its style.

If the snippet cannot write anything at the cursor, return nil and a
reason, as in `return nil, "no key here"`, and the picker shows the
reason.

If the snippet uses the count itself, add `count = true` and read
`ctx.count`. If it does not, paw repeats the snippet for the count.

To ship snippets with an extension, put the files in the `snippets/`
directory of the extension.
