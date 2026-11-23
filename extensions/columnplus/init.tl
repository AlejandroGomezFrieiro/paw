-- columnplus: an example of how to personalize the part column
-- (paw.partcolumn, docs/reference/partcolumn.md). It adds two parts of
-- its own (a strip in the color of each part, the count of its clips),
-- two signs (takes, frozen), and changes two parts of paw (the glyphs and
-- the place of the folds, the color of the cursor's number). paw records
-- each of them as the extension's, so `:ext.unload columnplus` puts the
-- column back as it was.
local kernel = require("paw.events.kernel")

local type Ctx = paw.contracts.PartColumnContext
local type Cells = paw.contracts.ColumnCells
local type Frame = paw.contracts.PartColumnFrame
local type Component = paw.contracts.PartColumnComponent

-- Options ------------------------------------------------------------------------

local folds = paw.option.define("columnplus_folds", "arrows", {values = {"arrows", "plus", "paw"}})
local foldfirst = paw.option.define("columnplus_foldfirst", true)

-- What a part holds, worked out once for each change of the project -----------

local record Stats
  clips: integer
  --- The clips that have more than one take.
  takes: integer
  --- "frozen", "held" (it plays through a frozen part), or nil.
  freeze: string
end

local stats: {integer: Stats} = {}
paw.on(kernel.changed, function() stats = {} end)

local function stats_of(part: integer): Stats
  local s = stats[part]
  if s then
    return s
  end
  s = {clips = 0, takes = 0}
  local ok, clips = pcall(paw.api.clip_list, part)
  for _, c in ipairs(ok and clips or {}) do
    s.clips = s.clips + 1
    if paw.takes.count(c) > 1 then
      s.takes = s.takes + 1
    end
  end
  s.freeze = paw.freeze.state(part) as string
  stats[part] = s
  return s
end

-- The strip: the color of the part, down all of its lines ----------------------

paw.partcolumn.add(
  "strip",
  {
    order = 1,
    width = 1,
    glyphs = {strip = "▎"},
    render = function(part: integer, ctx: Ctx): Cells
      local hue = paw.draw.part_hue(paw.api.part_get(part), ctx.row)
      local glyph = paw.opt.ascii and "|" or ctx.glyphs.strip
      return {{glyph, hue.fg}}
    end,
    -- A click on the strip chooses the color of the part.
    click = function(part: integer, _: Ctx) paw.cursor.set_part(part); paw.cmd("part.color.pick") end,
  }
)

-- The clips: how many the part has, against the right edge --------------------

local function clips_width(frame: Frame): integer
  local most = 0
  for _, id in ipairs(frame.rows) do
    most = math.max(most, stats_of(id).clips)
  end
  if most == 0 then
    return 0
  end
  return #tostring(most) + 1
end

paw.partcolumn.add(
  "clips",
  {
    order = 40,
    width = clips_width,
    styles = {count = "Dim", takes = "Info"},
    render = function(part: integer, ctx: Ctx): Cells
      if ctx.line ~= 0 or ctx.kind ~= "part" then
        return nil
      end
      local s = stats_of(part)
      if s.clips == 0 then
        return nil
      end
      local text = string.format("%" .. (ctx.width - 1) .. "d ", s.clips)
      return {{text, s.takes > 0 and ctx.styles.takes or ctx.styles.count}}
    end,
    describe = function(part: integer, _: Ctx): string
      local s = stats_of(part)
      if s.clips == 0 then
        return nil
      end
      local words = string.format("%d clip%s", s.clips, s.clips == 1 and "" or "s")
      if s.takes > 0 then
        words = words .. string.format(", %d with takes", s.takes)
      end
      return words
    end,
  }
)

-- The signs: takes, and a frozen part -------------------------------------------

paw.partcolumn.sign(
  "takes",
  {
    priority = 15,
    glyphs = {takes = "≡"},
    styles = {takes = "Info"},
    render = function(part: integer, ctx: Ctx): Cells
      if stats_of(part).takes == 0 then
        return nil
      end
      return {{paw.opt.ascii and "=" or ctx.glyphs.takes, ctx.styles.takes}}
    end,
    describe = function(part: integer, _: Ctx): string
      local n = stats_of(part).takes
      if n == 0 then
        return nil
      end
      return string.format("takes on %d clip%s (zt shows the take lanes)", n, n == 1 and "" or "s")
    end,
  }
)

paw.partcolumn.sign(
  "frozen",
  {
    priority = 25,
    glyphs = {frozen = "∗", held = "∘"},
    styles = {frozen = "Accent"},
    render = function(part: integer, ctx: Ctx): Cells
      local state = stats_of(part).freeze
      if not state then
        return nil
      end
      local glyph = paw.opt.ascii and (state == "frozen" and "*" or "o") or ctx.glyphs[state]
      return {{glyph, ctx.styles.frozen}}
    end,
    describe = function(part: integer, _: Ctx): string
      local state = stats_of(part).freeze
      if state == "frozen" then
        return "frozen: it plays its file (:unfreeze plays the devices again)"
      end
      if state == "held" then
        return "it plays through a frozen part"
      end
    end,
  }
)

-- Parts of paw, changed ----------------------------------------------------------

-- The glyphs of the folds, by look: an open group, a folded group, the
-- guide down its members and the mark of its last member.
local looks: {string: {string: string}} = {
  arrows = {open = "▿", closed = "▹", guide = "┆", last = "└"},
  plus = {open = "-", closed = "+", guide = "|", last = "`"},
}

-- The folds as they were before this extension changed them: each change
-- starts from them, so that "paw" gives them back.
local found: Component = paw.partcolumn.components:get("fold")

local function apply()
  if not found then
    return
  end
  paw.partcolumn.add("fold", found)
  local name = folds:get()
  if name == "arrows" and paw.opt.ascii then
    name = "plus"
  end
  local look = looks[name]
  if look or foldfirst:get() then
    paw.partcolumn.set("fold", {order = foldfirst:get() and 5 or found.order, glyphs = look})
  end
end
apply()

-- The number of the cursor's part, in the color of the accent.
paw.partcolumn.set("number", {styles = {cursor = "Accent"}})

paw.on(
  paw.option.changed,
  function(e: paw.option.Changed)
    if e.name == "columnplus_folds" or e.name == "columnplus_foldfirst" or e.name == "ascii" then
      apply()
    end
  end
)

-- Commands and keys ---------------------------------------------------------------

local order: {string} = {"arrows", "plus", "paw"}

paw.command(
  "columnplus.folds",
  function(ctx: paw.contracts.CommandContext)
    local name = ctx.args[1] as string
    if not name then
      local at = 1
      for i, n in ipairs(order) do
        if n == folds:get() then
          at = i
        end
      end
      name = order[at % #order + 1]
    end
    if not looks[name] and name ~= "paw" then
      return paw.notify("columnplus.folds takes " .. table.concat(order, ", "), "warn")
    end
    folds:set(name)
    paw.notify("folds: " .. name)
  end,
  {desc = "Change the look of the folds: arrows, plus or paw (no name: the next look)", complete = order}
)

paw.command(
  "columnplus.clips",
  function(_: paw.contracts.CommandContext)
    local shown = paw.partcolumn.shows("clips")
    local list: {string} = {}
    for _, n in ipairs(paw.opt.partcolumn as {string}) do
      if n ~= "clips" then
        list[#list + 1] = n
      end
    end
    if not shown then
      list[#list + 1] = "clips"
    end
    paw.opt.partcolumn = list
    paw.notify(shown and "clip counts hidden" or "clip counts shown")
  end,
  {desc = "Show or hide the count of clips in the part column"}
)

paw.keymap.set("<localleader>z", "columnplus.folds", {view = "arrange", desc = "Next look of the folds"})
paw.keymap.set("<localleader>#", "columnplus.clips", {view = "arrange", desc = "Show or hide the clip counts"})
