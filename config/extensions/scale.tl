-- A one-file extension written in Teal: paw compiles it as it loads it.
-- `:scale.notes C4 dorian` says the notes of a scale.
--
-- paw.music is written in Teal and paw.command has a type
-- (`paw.contracts.Command`), so both are typed here: the command's function
-- gets a `paw.contracts.CommandContext`.

local function notes(root: string, scale: string): {string}
  local out: {string} = {}
  local steps = #(paw.music.scales[scale] or {})
  for degree = 1, steps + 1 do
    out[#out + 1] = paw.music.name(paw.music.degree(root, scale, degree))
  end
  return out
end

paw.command("scale.notes", function(ctx: paw.contracts.CommandContext)
  local root, scale = tostring(ctx.args[1] or "C4"), tostring(ctx.args[2] or "major")
  if not paw.music.scales[scale] then
    paw.notify("no scale `" .. scale .. "`", "error")
    return
  end
  paw.notify(scale .. " from " .. root .. ": " .. table.concat(notes(root, scale), " "))
end, { desc = "Say the notes of a scale: `scale.notes C4 dorian`" })
