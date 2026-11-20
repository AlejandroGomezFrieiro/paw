-- An extension that adds one command and one key.
--
--   :euclid 5 16             five hits over sixteen steps, on the kick
--   :euclid 3 8 pitch=42     three over eight, on the closed hat
--   :euclid 7 16 rotate=2 step=0.25
--
-- It writes into the clip under the cursor, or makes one if there is none.
local euclid = require("euclid")

paw.command("euclid", function(ctx)
  local hits, steps = tonumber(ctx.args[1]), tonumber(ctx.args[2]) or 16
  if not hits then return paw.notify("usage: euclid <hits> [steps] [pitch=36] [step=0.25] [rotate=0]", "warn") end
  local track = paw.cursor.track()
  if not track then return paw.notify("no track selected", "warn") end

  local step = tonumber(ctx.args.step) or 0.25
  local pitch = paw.music.pitch(ctx.args.pitch or 36)
  local clip = paw.cursor.clip() or track:add_clip({ start = paw.cursor.beat, length = steps * step, name = "euclid" })

  -- Replace this pitch's notes and keep the others, so that patterns layer.
  local notes = {}
  for _, note in ipairs(clip:notes()) do
    if note.pitch ~= pitch then notes[#notes + 1] = note end
  end
  local pattern = euclid.pattern(hits, steps, tonumber(ctx.args.rotate))
  -- Repeat the pattern to fill the clip.
  local length = clip.length
  for offset = 0, length - 1e-9, steps * step do
    for _, note in ipairs(euclid.notes(pattern, { pitch = pitch, step = step, velocity = ctx.args.velocity })) do
      note.start = note.start + offset
      if note.start < length then notes[#notes + 1] = note end
    end
  end
  clip:set_notes(notes)
  paw.notify(string.format("euclid %d/%d on %s", hits, steps, paw.music.name(pitch)))
end, { desc = "Fill the clip with a Euclidean rhythm: `euclid 5 16 pitch=36`" })

paw.keymap.set("<leader>e", function(ctx)
  paw.cmd("euclid", { ctx.count or 4, 16 })
end, { view = "arrange", desc = "Euclidean rhythm with N hits (default 4)" })
