-- The status line: what `paw.statusline` builds from its sections (the
-- mode first, the project's name on the right, a segment dropped when the
-- screen is too narrow for it). See paw/statusline.tl for how to change it.
-- All of it is a live part of the screen (paw/ui.tl): its clock moves as
-- the song plays, and it is drawn again by itself when a component that
-- moves changes (`view:live_stamp`).
local view = { focusable = false, live_part = true }

--- A grid in beats as a note value: 1 is `1/4`, 0.25 is `1/16`.
function view.grid_text(grid) return paw.statusline.grid_text(grid) end

--- The segments for a screen `width` wide, as `{ left = {...}, right = {...} }`.
function view.segments(width) return paw.statusline.segments(width) end

function view:render(buf) paw.statusline.draw(buf) end

--- What the line is drawn from now: it is drawn again between whole frames
--- only when this changes (`paw.statusline.stamp`).
function view:live_stamp(width) return paw.statusline.stamp(width) end

paw.ui.view("status", view)
return view
