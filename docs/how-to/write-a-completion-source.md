# How to write a completion source

You can add a source of suggestions to the piano roll. The example source
suggests the selected notes one octave higher, and each field is in
[Completion](../reference/completion.md).

1. In `init.lua` or in an extension, register the source:

   ```lua
   paw.complete.register({
     name = "octaves", priority = 10,
     views = { "pianoroll" },
     auto = true,                         -- paw can ask it after a pause
     complete = function(ctx, done)
       local items = {}
       for _, n in ipairs(ctx.selection or {}) do
         items[#items + 1] = { pitch = n.pitch + 12, start = n.start, length = n.length }
       end
       done({ { label = "an octave up", notes = items } })   -- or done(nil): nothing to say
     end,
     cancel = function(ctx) end,          -- a newer request replaced ctx.id
   })
   ```

2. Type `:complete.sources` to make sure that paw lists `octaves`.
3. Open a clip in the piano roll and select some notes.
4. Press `<C-Space>`, and the ghost notes show one octave higher. Press
   `<Tab>` to accept them, or `<C-e>` to dismiss them.

If the source asks a program or a server, call `done` when the answer
comes. paw shows the answers that arrive in
`paw.opt.complete_deadline_ms`, and it adds later answers at the end.

If the source must run only after a key press, set `auto = false`.

To give more than one alternative, give more than one item to `done`, and
the user goes through them with `<C-n>` and `<C-p>`.
