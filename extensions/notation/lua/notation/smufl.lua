-- The music font: what the engraver reads of it, behind one function.
--
-- `smufl.font(name)` gives the font's SMuFL metadata in a form the engraver
-- uses: `defaults` (the engraving defaults, in staff spaces: line, stem and
-- beam thicknesses and so on), and `glyphs[name]` with each glyph's code
-- point `cp`, bounding box `bbox` ({ sw x, sw y, ne x, ne y }) and `anchors`
-- (`stemUpSE` and the like), in staff spaces with y up as SMuFL gives them.
--
-- It is read from the fonts the kernel embeds for its rasterizer
-- (`paw.api.smufl`), which also gives a frontend that cannot draw the font
-- each glyph's outline (`paw.canvas.glyph_outline`).
local M = { fonts = {} }

M.DEFAULT = "Leland"

--- A glyph by name, made from the metadata the first time it is asked for.
local function glyphs_of(meta)
  local boxes, anchored = meta.glyphBBoxes or {}, meta.glyphsWithAnchors or {}
  return setmetatable({}, {
    __index = function(t, gname)
      local cp = meta.glyphs[gname]
      if not cp then return nil end
      local own = { cp = cp }
      local bb = boxes[gname]
      if bb then own.bbox = { bb.bBoxSW[1], bb.bBoxSW[2], bb.bBoxNE[1], bb.bBoxNE[2] } end
      if anchored[gname] then
        own.anchors = {}
        for k, v in pairs(anchored[gname]) do
          own.anchors[k] = { v[1], v[2] }
        end
      end
      t[gname] = own
      return own
    end,
  })
end

--- The font `name` (Leland when nil, or when the kernel has no such font),
--- read once.
function M.font(name)
  name = name or M.DEFAULT
  if M.fonts[name] then return M.fonts[name] end
  local meta = paw.api.smufl(name) or paw.api.smufl(M.DEFAULT)
  local font = { name = meta.fontName, defaults = meta.engravingDefaults, glyphs = glyphs_of(meta) }
  M.fonts[name] = font
  return font
end

return M
