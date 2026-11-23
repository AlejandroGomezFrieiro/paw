-- The piano roll beside the notation view: with the two on screen, both on
-- one clip and both `timebind`, the note under one's cursor is outlined in
-- the other, found by the note's id. The roll is otherwise the roll: it
-- edits the clip's MIDI, which the score is a view of.
local view = require("notation")

local M = {}
local roll = paw.ui.views:get("pianoroll")

--- Whether the roll and the notation view are on screen, each with
--- `timebind`, both on this clip.
function M.bound(id)
  local have = {}
  for _, win in ipairs(paw.layout.windows(paw.ui.layout)) do
    if win.opts and win.opts.timebind then have[win.view] = true end
  end
  return have.pianoroll and have.notation and view.clip_id == id and roll.clip_id == id or false
end

--- The MIDI id of the note under the cursor of the other window, to
--- outline in the window `of` ("pianoroll" or "notation").
function M.partner(of)
  local clip = view:clip()
  if not (clip and M.bound(clip.id)) then return nil end
  local note
  if of == "pianoroll" then
    note = view:note()
  else
    note = roll:note_at(roll.pitch, roll.beat)
  end
  return note and note.id
end

--- Where, among its clip's notes, the note under the roll's cursor is.
function M.partner_place()
  local id = M.partner("notation")
  if not id then return nil end
  for i, n in ipairs(view:clip():notes()) do
    if n.id == id then return i end
  end
end

local function glyphs()
  local ascii = paw.opt.ascii
  return { open = ascii and "[" or "⟦", close = ascii and "]" or "⟧", one = ascii and "*" or "◆" }
end

-- On the roll's notes: the outline of the note under the notation's cursor.
local function paint(L)
  local outline = M.partner("pianoroll")
  if not outline then return end
  local g = glyphs()
  for _, n in ipairs(L.clip:notes()) do
    local row = L.row(n.pitch)
    if n.id == outline and row and n.start < L.to and n.start + n.length > L.from then
      local x0, x1 = L.x(n.start), L.x(n.start + n.length)
      local nw = math.max(1, x1 - x0)
      if nw == 1 then
        L.roll:text(x0, row, g.one, "Bright")
      else
        L.roll:text(x0, row, g.open, "Bright")
        L.roll:text(x0 + nw - 1, row, g.close, "Bright")
      end
    end
  end
end

roll.layer("notation", 36, paint)

return M
