-- The roles of the devices view (paw/views/devices.tl): a `node` (a card of
-- a device or of a folded container, or a row of the outline), a `wire`
-- (the signal between nodes, a fork, a merge or a rail), a `lane` (the
-- label or the gain of a branch) and a `split` (the header of an open
-- split, or the top edge of the frame of a rack). Each draws in cells as the
-- terminal shows it. A window that does not know a role paints these cells,
-- so the window shows the same graph with no view of its own.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type contracts = require("paw.contracts")

local type Style = contracts.Style

--- The props of each role of the graph: its `text` in `style`, and for a
--- card the second row `sub` in `sub_style`. `selected` is where the cursor
--- of the graph is, `chosen` a node of the selection of visual mode; `id`
--- the node, the branch or the split that it shows.
local record GraphProps is contracts.MarkProps
  text: string
  sub: string
  style: Style
  sub_style: Style
  selected: boolean
  chosen: boolean
  id: integer
end

local PROPS: {string: string} = {
  text = "string: the first row",
  sub = "string: the second row of a card",
  style = "highlight group",
  sub_style = "highlight group of the second row",
  selected = "boolean: the cursor of the graph is on it",
  chosen = "boolean: the selection of visual mode holds it",
  id = "number: the node, branch or split",
}

--- Write the rows of a mark of the graph, on the color of the cursor when
--- it is selected, and on the color of a selection when it is chosen.
local function cells(buf: contracts.Buf, p: GraphProps)
  if p.selected then
    buf:fill(0, 0, buf.width, buf.height, " ", "Selected")
  elseif p.chosen then
    buf:fill(0, 0, buf.width, buf.height, " ", "Visual")
  end
  buf:text(0, 0, p.text or "", (p.selected or p.chosen) and "Bright" or p.style)
  if p.sub and buf.height > 1 then
    buf:text(0, 1, p.sub, p.sub_style)
  end
end

for _, name in ipairs({"node", "wire", "lane", "split"}) do
  paw.roles.define(name, {props = PROPS, cells = cells} as contracts.Role<GraphProps>)
end
