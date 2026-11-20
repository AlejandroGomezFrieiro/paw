-- A one-file extension written in Teal: paw compiles it as it loads it.
-- `:scale.notes C4 dorian` says the notes of a scale.
--
-- paw.music is written in Teal, so its functions are typed here. The parts
-- of paw that are still Lua (paw.command, paw.notify) are `paw.Untyped`:
-- what they give back is cast to its type.

--- The command's arguments, as the command line gives them.
local record Args
  {string}
end

local function notes(root: string, scale: string): {string}
  local out: {string} = {}
  local steps = #(paw.music.scales[scale] or {})
  for degree = 1, steps + 1 do
    out[#out + 1] = paw.music.name(paw.music.degree(root, scale, degree))
  end
  return out
end

paw.command("scale.notes", function(ctx: paw.Untyped)
  local args = ctx.args as Args
  local root, scale = args[1] or "C4", args[2] or "major"
  if not paw.music.scales[scale] then
    paw.notify("no scale `" .. scale .. "`", "error")
    return
  end
  paw.notify(scale .. " from " .. root .. ": " .. table.concat(notes(root, scale), " "))
end, { desc = "Say the notes of a scale: `scale.notes C4 dorian`" })
