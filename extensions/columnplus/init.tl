-- columnplus: an example of how to personalize the track column
-- (paw.trackcolumn, docs/reference/trackcolumn.md). It adds two parts of
-- its own (a strip in the color of each track, the count of its clips),
-- two signs (takes, frozen), and changes two parts of paw (the glyphs and
-- the place of the folds, the color of the cursor's number). paw records
-- each of them as the extension's, so `:ext.unload columnplus` puts the
-- column back as it was.
local kernel = require("paw.events.kernel")

local type Ctx = paw.contracts.TrackColumnContext
local type Cells = paw.contracts.ColumnCells
local type Frame = paw.contracts.TrackColumnFrame
local type Component = paw.contracts.TrackColumnComponent

-- Options ------------------------------------------------------------------------

local folds = paw.option.define("columnplus_folds", "arrows", {values = {"arrows", "plus", "paw"}})
local foldfirst = paw.option.define("columnplus_foldfirst", true)

-- What a track holds, worked out once for each change of the project -----------

local record Stats
  clips: integer
  --- The clips that have more than one take.
  takes: integer
  --- "frozen", "held" (it plays through a frozen track), or nil.
  freeze: string
end

local stats: {integer: Stats} = {}
paw.on(kernel.changed, function() stats = {} end)

local function stats_of(track: integer): Stats
  local s = stats[track]
  if s then
    return s
  end
  s = {clips = 0, takes = 0}
  local ok, clips = pcall(paw.api.clip_list, track)
  for _, c in ipairs(ok and clips or {}) do
    s.clips = s.clips + 1
    if paw.takes.count(c) > 1 then
      s.takes = s.takes + 1
    end
  end
  s.freeze = paw.freeze.state(track) as string
  stats[track] = s
  return s
end

-- The strip: the color of the track, down all of its lines ----------------------

paw.trackcolumn.add(
  "strip",
  {
    order = 1,
    width = 1,
    glyphs = {strip = "▎"},
    render = function(track: integer, ctx: Ctx): Cells
      local hue = paw.draw.track_hue(paw.api.track_get(track), ctx.row)
      local glyph = paw.opt.ascii and "|" or ctx.glyphs.strip
      return {{glyph, hue.fg}}
    end,
    -- A click on the strip chooses the color of the track.
    click = function(track: integer, _: Ctx) paw.cursor.set_track(track); paw.cmd("track.color.pick") end,
  }
)

-- The clips: how many the track has, against the right edge --------------------

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

paw.trackcolumn.add(
  "clips",
  {
    order = 40,
    width = clips_width,
    styles = {count = "Dim", takes = "Info"},
    render = function(track: integer, ctx: Ctx): Cells
      if ctx.line ~= 0 or ctx.kind ~= "track" then
        return nil
      end
      local s = stats_of(track)
      if s.clips == 0 then
        return nil
      end
      local text = string.format("%" .. (ctx.width - 1) .. "d ", s.clips)
      return {{text, s.takes > 0 and ctx.styles.takes or ctx.styles.count}}
    end,
    describe = function(track: integer, _: Ctx): string
      local s = stats_of(track)
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

-- The signs: takes, and a frozen track -------------------------------------------

paw.trackcolumn.sign(
  "takes",
  {
    priority = 15,
    glyphs = {takes = "≡"},
    styles = {takes = "Info"},
    render = function(track: integer, ctx: Ctx): Cells
      if stats_of(track).takes == 0 then
        return nil
      end
      return {{paw.opt.ascii and "=" or ctx.glyphs.takes, ctx.styles.takes}}
    end,
    describe = function(track: integer, _: Ctx): string
      local n = stats_of(track).takes
      if n == 0 then
        return nil
      end
      return string.format("takes on %d clip%s (zt shows the take lanes)", n, n == 1 and "" or "s")
    end,
  }
)

paw.trackcolumn.sign(
  "frozen",
  {
    priority = 25,
    glyphs = {frozen = "∗", held = "∘"},
    styles = {frozen = "Accent"},
    render = function(track: integer, ctx: Ctx): Cells
      local state = stats_of(track).freeze
      if not state then
        return nil
      end
      local glyph = paw.opt.ascii and (state == "frozen" and "*" or "o") or ctx.glyphs[state]
      return {{glyph, ctx.styles.frozen}}
    end,
    describe = function(track: integer, _: Ctx): string
      local state = stats_of(track).freeze
      if state == "frozen" then
        return "frozen: it plays its file (:unfreeze plays the devices again)"
      end
      if state == "held" then
        return "it plays through a frozen track"
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
local found: Component = paw.trackcolumn.components:get("fold")

local function apply()
  if not found then
    return
  end
  paw.trackcolumn.add("fold", found)
  local name = folds:get()
  if name == "arrows" and paw.opt.ascii then
    name = "plus"
  end
  local look = looks[name]
  if look or foldfirst:get() then
    paw.trackcolumn.set("fold", {order = foldfirst:get() and 5 or found.order, glyphs = look})
  end
end
apply()

-- The number of the cursor's track, in the color of the accent.
paw.trackcolumn.set("number", {styles = {cursor = "Accent"}})

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
    local shown = paw.trackcolumn.shows("clips")
    local list: {string} = {}
    for _, n in ipairs(paw.opt.trackcolumn as {string}) do
      if n ~= "clips" then
        list[#list + 1] = n
      end
    end
    if not shown then
      list[#list + 1] = "clips"
    end
    paw.opt.trackcolumn = list
    paw.notify(shown and "clip counts hidden" or "clip counts shown")
  end,
  {desc = "Show or hide the count of clips in the track column"}
)

paw.keymap.set("<localleader>z", "columnplus.folds", {view = "arrange", desc = "Next look of the folds"})
paw.keymap.set("<localleader>#", "columnplus.clips", {view = "arrange", desc = "Show or hide the clip counts"})
