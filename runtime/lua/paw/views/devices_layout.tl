-- The layout of the devices view: a chain of devices as a graph of text.
-- The view (paw/views/devices.tl) gives it the chain as a tree of nodes and
-- takes back runs of text, each at a column and a row. The module knows no
-- project and no screen, so a test can lay out any tree.
--
-- Two layouts:
--
-- - The flow layout (72 columns or more) draws the signal from left to
--   right. A device or a folded container is a card of two rows. An open
--   split draws a fork, one lane for each branch, and a merge. An open rack
--   draws a frame. The top level wraps as text does: `↩` ends a row and
--   `↪` starts the next one.
-- - The outline layout (a narrow window) draws one row for each node, with
--   rails for the branches.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")

--- What a node of the tree is: a device, a split with branches, or a rack
--- (a split of the kind `chain` with one branch, which folds to a card).
local enum Kind
  "device"
  "split"
  "rack"
end

--- One path through a split: its label (`1 Low`), its gain as text and
--- its nodes in series.
local record Branch
  id: integer
  label: string
  gain: string
  items: {Node}
end

--- A node as the layout reads it. `summary` is the second row of its card,
--- `meter` the peak of its output from 0 to 1, `badges` the marks after its
--- name, `warn` a problem that shows on it (a split that the engine does
--- not play as its kind says), and `head` the header of an open split.
local record Node
  kind: Kind
  id: integer
  name: string
  summary: string
  meter: number
  badges: string
  off: boolean
  warn: string
  head: string
  branches: {Branch}
  devices: integer
end

--- A piece of text that the layout puts at `x`, `y`. `role` is what it
--- draws (`node`, `wire`, `lane` or `split`), `id` the node, branch or
--- split that it shows, `sub` the second row of a card.
local record Run
  x: integer
  y: integer
  w: integer
  text: string
  sub: string
  style: string
  sub_style: string
  role: string
  id: integer
end

--- What `M.flow` and `M.outline` give: the runs, the height in rows,
--- and the row of each node id, for the scroll.
local record Laid
  runs: {Run}
  height: integer
  rows: {integer: integer}
end

--- What the layout of a tree takes: the width, the open containers
--- (`open(id)`), the ids on the path from the root to the cursor, and the
--- cursor.
local record Options
  width: integer
  open: function(id: integer): boolean
  path: {integer: boolean}
  cursor: integer
end

--- A laid-out part of the graph: its width and height, the row where the
--- signal goes in and out (`entry`), and its runs from its own corner.
local record Block
  w: integer
  h: integer
  entry: integer
  runs: {Run}
end

local record M
  type Node = Node
  type Branch = Branch
  type Run = Run
  type Laid = Laid
  type Options = Options
  type Kind = Kind
  --- The narrowest window that gets the flow layout.
  FLOW: integer
  flow: function(items: {Node}, opts: Options): Laid
  outline: function(items: {Node}, opts: Options): Laid
  meter: function(level: number): string
end

M.FLOW = 72

local WIRE = " ━▶ "
local WRAP = " ━▶ ↩"
local LEVELS = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}

local function width(text: string): integer
  return api.str_width(text)
end

--- The text cut to `w` columns, without the spaces that `util.fit` adds.
local function cut(text: string, w: integer): string
  if w <= 0 then
    return ""
  end
  return (util.fit(text, w):gsub("%s+$", ""))
end

--- The cell of a meter: the peak `level` (0 to 1) as a bar of eight steps.
function M.meter(level: number): string
  local step = math.floor((level or 0) * 7 + 0.5) + 1
  return LEVELS[math.max(1, math.min(8, step))]
end

local function is_container(node: Node): boolean
  return node.kind == "split" or node.kind == "rack"
end

--- Move each run of `block` by `dx`, `dy` into `out`.
local function put(out: {Run}, block: Block, dx: integer, dy: integer)
  for _, r in ipairs(block.runs) do
    out[#out + 1] = {
      x = r.x + dx,
      y = r.y + dy,
      w = r.w,
      text = r.text,
      sub = r.sub,
      style = r.style,
      sub_style = r.sub_style,
      role = r.role,
      id = r.id,
    }
  end
end

local function wire(runs: {Run}, x: integer, y: integer, text: string, id?: integer)
  runs[#runs + 1] = {x = x, y = y, w = width(text), text = text, style = "Faint", role = "wire", id = id}
end

-- The flow layout ------------------------------------------------------------------------

local block_of: function(node: Node, opts: Options, cw: integer): Block

--- The name row of a card: the mark of a container, the name, its badges
--- and its count, cut to leave the meter its cell.
local function card_name(node: Node, cw: integer): string
  local mark = node.kind == "split" and "┳ " or node.kind == "rack" and "▣ " or ""
  local count = ""
  if node.kind == "split" then
    count = " " .. #node.branches
  elseif node.kind == "rack" then
    count = " " .. (node.devices or 0)
  end
  local badges = (node.badges and node.badges ~= "") and (" " .. node.badges) or ""
  local room = cw - 2 - width(mark) - width(count) - width(badges)
  return mark .. cut(node.name, math.max(1, room)) .. badges .. count
end

--- A card: a device, or a container that is folded.
local function card(node: Node, cw: integer): Block
  local name = card_name(node, cw)
  local text = name .. string.rep(" ", math.max(1, cw - 1 - width(name))) .. M.meter(node.meter)
  local sub = node.warn and ("⚠ " .. "plays branch 1") or node.summary or ""
  return {
    w = cw,
    h = 2,
    entry = 0,
    runs = {
      {
        x = 0,
        y = 0,
        w = cw,
        text = text,
        sub = cut(sub, cw),
        style = node.off and "Faint" or "DeviceName",
        sub_style = node.warn and "Warn" or "Faint",
        role = "node",
        id = node.id,
      },
    },
  }
end

--- Nodes in series, joined by wires on the row of their entry. An empty
--- series is a block of no width on one row.
local function series(items: {Node}, opts: Options, cw: integer): Block
  local blocks: {Block} = {}
  local entry = 0
  for i, item in ipairs(items) do
    blocks[i] = block_of(item, opts, cw)
    entry = math.max(entry, blocks[i].entry)
  end
  local out: Block = {w = 0, h = 1, entry = entry, runs = {}}
  local x = 0
  for i, b in ipairs(blocks) do
    if i > 1 then
      wire(out.runs, x, entry, WIRE)
      x = x + width(WIRE)
    end
    local dy = entry - b.entry
    put(out.runs, b, x, dy)
    out.h = math.max(out.h, dy + b.h)
    x = x + b.w
  end
  out.w = x
  return out
end

--- An open split: its header, then one lane for each branch: the fork, the
--- branch's label, its nodes, a wire to the column of the gains, its gain
--- and the merge.
local function split_block(node: Node, opts: Options, cw: integer): Block
  local n = #node.branches
  local label_w, gain_w, inner_w = 0, 0, 6
  local inner: {Block} = {}
  for i, b in ipairs(node.branches) do
    label_w = math.max(label_w, width(b.label or ""))
    gain_w = math.max(gain_w, width(b.gain or ""))
    inner[i] = series(b.items, opts, cw)
    inner_w = math.max(inner_w, inner[i].w)
  end
  local content_x = 4 + label_w + 1
  local gain_x = content_x + inner_w + 3
  local merge_x = gain_x + gain_w + 2
  local out: Block = {w = merge_x + 1, h = 1, entry = 1, runs = {}}
  local entries: {integer} = {}
  local y = 1
  for i, b in ipairs(node.branches) do
    local body = inner[i]
    local row = y + body.entry
    entries[i] = row
    local fork = n == 1 and "━" or i == 1 and "┳" or i == n and "┗" or "┣"
    local merge = n == 1 and "━" or i == 1 and "┳" or i == n and "┛" or "┫"
    wire(out.runs, 0, row, fork .. "━▶ ", b.id)
    out.runs[#out.runs + 1] = {
      x = 4,
      y = row,
      w = label_w,
      text = b.label or "",
      style = "Param",
      role = "lane",
      id = b.id,
    }
    put(out.runs, body, content_x, y)
    local from = content_x + body.w
    local fill = body.w > 0 and (" " .. string.rep("━", gain_x - from - 2) .. " ")
      or (string.rep("━", gain_x - from - 1) .. " ")
    wire(out.runs, from, row, fill)
    local gain = b.gain or ""
    out.runs[#out.runs + 1] = {
      x = gain_x + gain_w - width(gain),
      y = row,
      w = width(gain),
      text = gain,
      style = "ParamValue",
      role = "lane",
      id = b.id,
    }
    wire(out.runs, gain_x + gain_w, row, " ━" .. merge)
    y = y + body.h
  end
  out.h = y
  -- The rails between the first branch and the last, on the rows of no
  -- branch's entry.
  local at: {integer: boolean} = {}
  for _, row in ipairs(entries) do
    at[row] = true
  end
  for row = entries[1] + 1, (entries[n] or entries[1]) - 1 do
    if not at[row] then
      wire(out.runs, 0, row, "┃")
      wire(out.runs, merge_x, row, "┃")
    end
  end
  local head = node.head or node.name
  if node.warn then
    head = head .. " · ⚠ " .. node.warn
  end
  out.runs[#out.runs + 1] = {
    x = 0,
    y = 0,
    w = out.w,
    text = cut(head, out.w),
    style = node.warn and "Warn" or "Dim",
    role = "split",
    id = node.id,
  }
  out.entry = entries[1]
  return out
end

--- An open rack: its devices in series in a frame, with its name and its
--- summary on the frame's top edge.
local function rack_block(node: Node, opts: Options, cw: integer): Block
  local body = series(node.branches[1] and node.branches[1].items or {}, opts, cw)
  local w = body.w + 4
  local out: Block = {w = w, h = body.h + 2, entry = body.entry + 1, runs = {}}
  local title = "┌ ▣ "
    .. node.name
    .. ((node.summary and node.summary ~= "") and (" · " .. node.summary) or "")
    .. " "
  title = cut(title, w - 1)
  wire(out.runs, 0, 0, title .. string.rep("─", w - 1 - width(title)) .. "┐", node.id)
  out.runs[#out.runs].role, out.runs[#out.runs].style = "split", "Dim"
  for row = 1, body.h do
    if row == out.entry then
      wire(out.runs, 0, row, "━ ")
      wire(out.runs, w - 2, row, " ━")
    else
      wire(out.runs, 0, row, "│")
      wire(out.runs, w - 1, row, "│")
    end
  end
  put(out.runs, body, 2, 1)
  wire(out.runs, 0, body.h + 1, "└" .. string.rep("─", w - 2) .. "┘")
  return out
end

block_of = function(node: Node, opts: Options, cw: integer): Block
  if is_container(node) and opts.open(node.id) then
    if node.kind == "rack" then
      return rack_block(node, opts, cw)
    end
    return split_block(node, opts, cw)
  end
  return card(node, cw)
end

--- The containers under `node` (and `node`) that are open and off the
--- path to the cursor.
local function open_off_path(node: Node, opts: Options, out: {integer})
  if not is_container(node) then
    return
  end
  if opts.open(node.id) and not opts.path[node.id] then
    out[#out + 1] = node.id
  end
  for _, b in ipairs(node.branches or {}) do
    for _, item in ipairs(b.items) do
      open_off_path(item, opts, out)
    end
  end
end

--- Options in which the containers in `closed` are folded.
local function folding(opts: Options, closed: {integer: boolean}): Options
  return {
    width = opts.width,
    path = opts.path,
    cursor = opts.cursor,
    open = function(id: integer): boolean return not closed[id] and opts.open(id) end,
  }
end

--- The card width of a window `w` columns wide.
local function card_width(w: integer): integer
  return w >= 100 and 13 or 11
end

--- The flow layout of the top-level nodes `items`. A container that does
--- not fit in a row folds the open containers in it that are off the
--- path to the cursor, and then itself when it is off the path.
function M.flow(items: {Node}, opts: Options): Laid
  local cw = card_width(opts.width)
  local room = opts.width - 1 - 6 - width(WRAP)
  local closed: {integer: boolean} = {}
  local fit = folding(opts, closed)
  for _, item in ipairs(items) do
    if is_container(item) and block_of(item, fit, cw).w > room then
      local off: {integer} = {}
      open_off_path(item, fit, off)
      for _, id in ipairs(off) do
        if id ~= item.id then
          closed[id] = true
        end
      end
      if block_of(item, fit, cw).w > room and not opts.path[item.id] then
        closed[item.id] = true
      end
    end
  end
  -- The pieces of the top level: the nodes, then the end of the chain.
  local blocks: {Block} = {}
  for i, item in ipairs(items) do
    blocks[i] = block_of(item, fit, cw)
  end
  blocks[#blocks + 1] = {
    w = 3, h = 1, entry = 0, runs = {{x = 0, y = 0, w = 3, text = "out", style = "Dim", role = "wire"}}
  }
  -- Pack them in rows, as text wraps.
  local rows: {{Block}} = {{}}
  local x = 7
  for i, b in ipairs(blocks) do
    local row = rows[#rows]
    local last = i == #blocks
    local need = (#row > 0 and width(WIRE) or 0) + b.w + (last and 0 or width(WRAP))
    if #row > 0 and x + need > opts.width then
      rows[#rows + 1] = {}
      row = rows[#rows]
      x = 4
    end
    x = x + (#row > 0 and width(WIRE) or 0) + b.w
    row[#row + 1] = b
  end
  local out: Laid = {runs = {}, height = 0, rows = {}}
  local top = 0
  for r, row in ipairs(rows) do
    local entry = 0
    for _, b in ipairs(row) do
      entry = math.max(entry, b.entry)
    end
    local line: Block = {w = 0, h = 1, entry = entry, runs = {}}
    local start = r == 1 and 7 or 4
    if r == 1 then
      wire(line.runs, 1, entry, "in ━▶ ")
    else
      wire(line.runs, 2, entry, "↪ ")
    end
    local cx = start
    for i, b in ipairs(row) do
      if i > 1 then
        wire(line.runs, cx, entry, WIRE)
        cx = cx + width(WIRE)
      end
      put(line.runs, b, cx, entry - b.entry)
      line.h = math.max(line.h, entry - b.entry + b.h)
      cx = cx + b.w
    end
    if r < #rows then
      wire(line.runs, cx, entry, WRAP)
    end
    put(out.runs, line, 0, top)
    top = top + line.h
  end
  out.height = top
  for _, run in ipairs(out.runs) do
    if run.id and run.role ~= "wire" and out.rows[run.id] == nil then
      out.rows[run.id] = run.y
    end
  end
  return out
end

-- The outline layout ---------------------------------------------------------------------

--- The outline layout: one row for each node, with the rails of its
--- branches before it, and its summary and meter at the right.
function M.outline(items: {Node}, opts: Options): Laid
  local out: Laid = {runs = {}, height = 0, rows = {}}
  local w = opts.width
  local function row(rail: string, text: string, right: string, id: integer, style: string)
    local y = out.height
    out.height = y + 1
    out.rows[id] = out.rows[id] or y
    local left = rail .. text
    local right_w = width(right)
    local room = w - 2 - right_w - (right_w > 0 and 1 or 0)
    out.runs[#out.runs + 1] = {
      x = 1,
      y = y,
      w = w - 1,
      text = cut(left, room)
        .. string.rep(" ", math.max(0, room - width(cut(left, room))))
        .. (right_w > 0 and (" " .. right) or ""),
      style = style,
      role = "node",
      id = id,
    }
  end
  local walk: function(list: {Node}, rail: string)
  walk = function(list: {Node}, rail: string)
    for j, node in ipairs(list) do
      local last = j == #list
      local glyph = rail == "" and "" or (last and "┗ " or "┣ ")
      local meter = M.meter(node.meter)
      if is_container(node) then
        local open = opts.open(node.id)
        local mark = node.kind == "rack" and "▣ " or "┳ "
        local name = (open and "▾ " or "▸ ") .. mark .. node.name
        local right = open and meter or (node.warn and "⚠ plays branch 1" or ((node.summary or "") .. " " .. meter))
        row(rail .. glyph, name, right, node.id, node.warn and "Warn" or "DeviceName")
        if open then
          local inner = rail .. (rail == "" and "" or (last and "  " or "┃ "))
          for i, b in ipairs(node.branches) do
            local more = i < #node.branches
            if node.kind == "rack" then
              walk(b.items, inner .. "│")
            else
              row(inner .. (more and "┣┳ " or "┗┳ "), b.label or "", b.gain or "", b.id, "Param")
              walk(b.items, inner .. (more and "┃" or " "))
            end
          end
        end
      else
        local name = node.name .. ((node.badges and node.badges ~= "") and (" " .. node.badges) or "")
        row(rail .. glyph, name, (node.summary or "") .. " " .. meter, node.id, node.off and "Faint" or "DeviceName")
      end
    end
  end
  walk(items, "")
  return out
end

return M
