-- The pieces of the core that heads draw with (paw/heads.tl): the name,
-- the badge of the kind, the chips, the automation letter, the bake
-- letter, the volume, the input button, the meter, the route, the sends,
-- the input. Each piece draws in the cells of a head from
-- the part of the context, and gives the columns that it used. The pieces
-- that take the pointer give hits; the arrange view's mouse code does
-- what they start (`paw.heads.gestures`).
--
-- The columns of a head count from the first cell after the stripe. A
-- head keeps its first column empty, and its last column too.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local places_text = require("paw.views.arrange_part").places_text
local type contracts = require("paw.contracts")
local type roles = require("paw.roles.arrange")
local type Ctx = contracts.HeadContext
local type Part = types.Part

local draw = paw.draw
local util = paw.util
local heads = require("paw.heads")
local gestures = heads.gestures

local record M
  level_glyph: function(level: number): string
end

-- What is kept between frames -------------------------------------------------------

-- What a part's devices are called, by the part and its list of devices: a
-- head draws its route on each frame. Forgotten when a device changes, and
-- when there are too many.
local KEEP = 4096
local chains: {string: string} = {}
local chain_count = 0

local function forget_chains()
  chains, chain_count = {}, 0
end
paw.on(kernel.device_changed, forget_chains)
paw.on(kernel.device_ready, forget_chains)
paw.on(kernel.project_loaded, forget_chains)

--- What a part's sound goes through, in a few words: `synth › delay`.
local function chain(t: Part): string
  local key = t.id .. ":" .. table.concat(t.devices or {}, ",") .. (paw.opt.ascii and "a" or "")
  local kept = chains[key]
  if kept then
    return kept
  end
  local names: {string} = {}
  for _, id in ipairs(t.devices or {}) do
    local ok, device = pcall(api.device_get, id)
    if ok then
      names[#names + 1] = device.name
    end
  end
  kept = table.concat(names, " " .. draw.g.chain .. " ")
  if chain_count >= KEEP then
    forget_chains()
  end
  chains[key], chain_count = kept, chain_count + 1
  return kept
end

-- Small helpers ------------------------------------------------------------------------

--- Words on a head in `style`, which a window writes in its font for
--- words, in the colour `tone` (a name of the palette).
local function words(ctx: Ctx, x: integer, y: integer, text: string, style: string, tone: string)
  local props: contracts.LabelMark = {text = text, style = style, font = "sans", tone = tone}
  ctx.buf:mark("label", x, y, math.max(1, api.str_width(text)), 1, props)
end

--- Where a fader of the volume stands, from 0 at -60 dB to 1 at +6 dB.
local function fader_at(volume: number): number
  return util.clamp(((volume or 0) + 60) / 66, 0, 1)
end

--- One character for a level, 0 to 1 linear, from -60 dB up: a dot for silence.
function M.level_glyph(level: number): string
  if level <= 0.001 then
    return draw.g.dot
  end
  local db = 20 * math.log10(level)
  return draw.g.eighths[math.floor(util.clamp(math.floor((db + 60) / 60 * 8) + 1, 1, 8))]
end

local function not_master(ctx: Ctx): boolean
  return not ctx.part.master
end

-- The first line ----------------------------------------------------------------------

--- The name a head shows. A folded group says how many parts it holds,
--- and a group with linked faders has `≡` after its name. The part
--- column's `fold` shows the groups as a tree; without it, a member
--- stands a step in under its group, and a group has a mark that says
--- whether it is open.
local function name_text(t: Part): string
  local name = t.name
  if t.master then
    return name
  end
  local g, groups = draw.g, paw.groups
  -- The first row of a fold of parts stands for all of it, by its name.
  local fold = paw.folds.row(t.id)
  local returned = not fold and paw.nest.returns(t.id)
  if fold then
    name = paw.folds.name(fold) .. " +" .. paw.folds.count(fold)
  elseif groups.is_group(t.id) and groups.folded(t.id) then
    name = name .. " +" .. #groups.members(t.id)
  elseif returned then
    -- A return row: `⧉ Bridge ×2`, the places the song plays it in.
    name = g.nest .. name .. places_text(returned)
  end
  -- A group whose members' faders move together: `Drums ≡`, as a linked
  -- clip says it.
  if groups.is_group(t.id) and groups.linked(t.id) then
    name = name .. " " .. g.link
  end
  if not paw.partcolumn.shows("fold") then
    name = string.rep(" ", groups.depth(t.id)) .. name
    if fold then
      name = g.closed .. " " .. name
    elseif groups.is_group(t.id) then
      name = (groups.folded(t.id) and g.closed or g.open) .. " " .. name
    end
  end
  return name
end

heads.piece(
  "name",
  {
    keep = 100,
    min = 5,
    draw = function(ctx: Ctx, x: integer, y: integer, w: integer): integer
      local t = ctx.part
      local name = name_text(t)
      if api.str_width(name) > w then
        name = util.fit(name, w)
      end
      -- In words, in a window.
      local label: contracts.LabelMark = {
        text = name,
        style = ctx.selected and "PartNameSel" or "PartName",
        font = "title",
        tone = "text",
      }
      ctx.buf:mark("label", x, y, w, 1, label)
      ctx.mark_at = x - 1
      -- Without the column's `fold`, the mark of a group before its name
      -- folds it.
      if paw.groups.is_group(t.id) and not paw.partcolumn.shows("fold") then
        ctx:hit(x, y, 1, 1, function(s: contracts.HeadSubject, e: contracts.MouseEvent) gestures.fold(s, e) end, "fold")
      end
      return w
    end,
  }
)

--- The kind of a part as defined, or nil.
local function kind_of(ctx: Ctx): contracts.PartKind
  return not ctx.part.master and paw.part_kinds.spec(ctx.part.id) as contracts.PartKind or nil
end

-- The letter of the part's kind. On a narrow head it stands in the first
-- column, and else a column in from the stripe, clear of the name.
heads.piece(
  "badge",
  {
    keep = 90,
    edge = true,
    width = function(ctx: Ctx): integer return ctx.class == "narrow" and 1 or 2 end,
    has = function(ctx: Ctx): boolean return kind_of(ctx) ~= nil end,
    draw = function(ctx: Ctx, x: integer, y: integer, _: integer): integer
      local narrow = ctx.class == "narrow"
      ctx.buf:text(x + (narrow and 0 or 1), y, kind_of(ctx).letter:sub(1, 1), "PartIndex")
      return narrow and 1 or 2
    end,
  }
)

--- A chip of a head: its letter, whether it is on, its style when on,
--- and the flag it switches.
local record Chip
  letter: string
  on: boolean
  style: string
  flag: string
end

--- The colours a window lights each chip in.
local chip_tones: {string: string} = {mute = "mute", solo = "solo", armed = "rec", monitor = "select"}

--- The chips to show: M S R I, or on a narrow head only those that are on.
local function chips(ctx: Ctx): {Chip}
  local t = ctx.part
  local all: {Chip} = {
    {letter = "M", on = t.mute, style = "Mute", flag = "mute"},
    {letter = "S", on = t.solo, style = "Solo", flag = "solo"},
    {letter = "R", on = t.armed, style = "Armed", flag = "armed"},
    {letter = "I", on = t.monitor, style = "Monitor", flag = "monitor"},
  }
  if ctx.class ~= "narrow" then
    return all
  end
  local lit: {Chip} = {}
  for _, chip in ipairs(all) do
    if chip.on then
      lit[#lit + 1] = chip
    end
  end
  return lit
end

--- The columns between two chips: one on a wide head.
local function chip_gap(ctx: Ctx): integer
  return ctx.class == "wide" and 1 or 0
end

-- M S R I with room, MSRI in less, only those that are on in less still.
-- Each is a switch, which a window paints as a button, and a press on one
-- switches it.
heads.piece(
  "chips",
  {
    keep = 80,
    flags = {"mute", "solo", "armed", "monitor"},
    has = not_master,
    width = function(ctx: Ctx): integer local n = #chips(ctx); return n > 0 and n + chip_gap(ctx) * (n - 1) or 0 end,
    draw = function(ctx: Ctx, x: integer, y: integer, _: integer): integer
      local list, gap = chips(ctx), chip_gap(ctx)
      for i, chip in ipairs(list) do
        local cx = x + (i - 1) * (1 + gap)
        local props: contracts.SwitchMark = {
          letter = chip.letter,
          on = chip.on or false,
          style = chip.style,
          tone = chip_tones[chip.flag],
          icon = chip.flag == "monitor" and "speaker" or nil,
          label = chip.flag,
        }
        ctx.buf:mark("switch", cx, y, 1, 1, props)
        local flag = chip.flag
        ctx:hit(
          cx, y, 1, 1, function(s: contracts.HeadSubject, e: contracts.MouseEvent) gestures.flag(s, e, flag) end, flag
        )
      end
      return #list > 0 and #list + gap * (#list - 1) or 0
    end,
  }
)

--- The letter of each automation mode before the chips.
local mode_letters: {string: string} = {read = "A", touch = "T", latch = "L", write = "W", off = "-"}

-- An `A` when the part has automation, and the letter of its automation
-- mode when that is not the usual one (Touch, Latch, Write, or `-` for
-- off).
heads.piece(
  "automation",
  {
    keep = 40,
    width = function(): integer return 1 end,
    has = function(ctx: Ctx): boolean
      return (ctx.part.automation or "read") ~= "read" or #api.lane_list(ctx.part.id) > 0
    end,
    draw = function(ctx: Ctx, x: integer, y: integer, _: integer): integer
      local mode = ctx.part.automation or "read"
      local on = false
      for _, lane in ipairs(api.lane_list(ctx.part.id)) do
        on = on or lane.enabled and lane.point_count > 0
      end
      local writes = mode == "touch" or mode == "latch" or mode == "write"
      local style = writes and "Armed" or (on and mode ~= "off") and "Automation" or "PartIndex"
      ctx.buf:text(x, y, mode_letters[mode as string] or "A", style)
      return 1
    end,
  }
)

--- How the part is frozen: "frozen", "held" inside a frozen group, or nil.
local function frozen(ctx: Ctx): string
  return not ctx.part.master and paw.freeze and paw.freeze.state(ctx.part.id) as string or nil
end

-- An `F` on a frozen part, an `f` on one held inside a frozen group.
heads.piece(
  "bake",
  {
    keep = 60,
    width = function(): integer return 1 end,
    has = function(ctx: Ctx): boolean return frozen(ctx) ~= nil end,
    draw = function(ctx: Ctx, x: integer, y: integer, _: integer): integer
      ctx.buf:text(x, y, frozen(ctx) == "frozen" and "F" or "f", "PartInfo")
      return 1
    end,
  }
)

-- The volume in dB, on a head of one row: a taller head has the meter.
heads.piece(
  "volume",
  {
    keep = 30,
    width = function(ctx: Ctx): integer return #draw.db_text(ctx.part.volume) end,
    has = function(ctx: Ctx): boolean return ctx.height == 1 and ctx.class ~= "narrow" end,
    draw = function(ctx: Ctx, x: integer, y: integer, _: integer): integer
      local vol = draw.db_text(ctx.part.volume)
      ctx.buf:text(x, y, vol, "PartInfo")
      return #vol
    end,
  }
)

-- The meter line -------------------------------------------------------------------------

-- The input's button, which a press chooses from: lit when the part has
-- one. It stands in the first column of the head.
heads.piece(
  "input_button",
  {
    keep = 20,
    edge = true,
    width = function(): integer return 2 end,
    has = function(ctx: Ctx): boolean return ctx.class ~= "narrow" and not ctx.part.master end,
    draw = function(ctx: Ctx, x: integer, y: integer, _: integer): integer
      local input: contracts.ButtonMark = {
        text = "in",
        icon = "mic",
        on = ctx.part.input ~= nil,
        on_style = "Input",
        style = "PartIndex",
        quiet = true,
        label = "input",
      }
      ctx.buf:mark("button", x, y, 2, 1, input)
      ctx:hit(x, y, 2, 1, function(s: contracts.HeadSubject, e: contracts.MouseEvent) gestures.input(s, e) end, "input")
      return 2
    end,
  }
)

-- The meter with the fader's place, which a window moves with the live
-- values, the volume at its end, and the clip light (both sides on the
-- master's). A drag along it moves the volume; a press on the volume puts
-- the clip light out.
heads.piece(
  "meter",
  {
    keep = 70,
    line = true,
    draw = function(ctx: Ctx, x: integer, y: integer, w: integer): integer
      local t = ctx.part
      local left, right, hold, clipped = draw.part_peak(t.id)
      local vol = draw.db_text(t.volume)
      local vol_at = x + w - #vol
      if vol_at - 1 > x then
        local meter: roles.HmeterProps = {
          levels = {left, right},
          hold = hold,
          clipped = clipped,
          stereo = t.master or nil,
          at = fader_at(t.volume),
          bind = "meter:" .. t.id,
        }
        ctx.buf:mark("hmeter", x, y, vol_at - 1 - x, 1, meter)
        ctx:hit(
          x,
          y,
          vol_at - x,
          1,
          function(s: contracts.HeadSubject, e: contracts.MouseEvent) gestures.volume(s, e) end,
          "volume"
        )
      end
      ctx.buf:text(vol_at, y, vol, ctx.selected and "Bright" or "PartInfo")
      ctx:hit(
        vol_at, y, #vol, 1, function(s: contracts.HeadSubject, e: contracts.MouseEvent) gestures.peak(s, e) end, "peak"
      )
      return w
    end,
  }
)

-- The lines under the meter --------------------------------------------------------------

-- The pan as a knob (a window turns it, a drag moves it), the devices the
-- sound goes through, and the part it goes out to.
heads.piece(
  "route",
  {
    keep = 50,
    line = true,
    draw = function(ctx: Ctx, x: integer, y: integer, w: integer): integer
      local t, g = ctx.part, draw.g
      local right = x + w
      local narrow = ctx.class == "narrow"
      local pan = draw.pan_text(t.pan or 0)
      local at = x
      if not (narrow and pan == "C") then
        local knob: contracts.KnobMark = {
          value = t.pan or 0,
          text = pan,
          style = pan == "C" and "PartIndex" or "PartInfo",
          round = true,
          label = "pan",
        }
        ctx.buf:mark("knob", at, y, math.max(3, #pan), 1, knob)
        ctx:hit(at, y, 4, 1, function(s: contracts.HeadSubject, e: contracts.MouseEvent) gestures.pan(s, e) end, "pan")
        at = at + (narrow and #pan + 1 or math.max(4, #pan + 1))
      end
      local out = ""
      if t.output and t.output ~= 0 then
        local ok, to = pcall(api.part_get, t.output)
        if ok then
          out = g.out .. " " .. to.name
        end
      end
      local devices = chain(t)
      local room_left = right - at
      if out ~= "" then
        local out_w = api.str_width(out)
        if out_w > room_left - 2 then
          out = util.fit(out, math.max(1, room_left - 2))
          out_w = api.str_width(out)
        end
        words(ctx, right - out_w, y, out, "PartInfo", "text_3")
        room_left = room_left - out_w - 1
      end
      if devices ~= "" and room_left > 2 then
        if api.str_width(devices) > room_left then
          devices = util.fit(devices, room_left)
        end
        words(ctx, at, y, devices, "PartRoute", "text_2")
      end
      return w
    end,
  }
)

--- What a part sends, in a few words: `↗ Reverb -9  ↗ Delay -12`.
local function sends_text(t: Part): string
  local out: {string} = {}
  for _, send in ipairs(t.sends or {}) do
    local ok, to = pcall(api.part_get, send.target)
    if ok then
      out[#out + 1] = draw.g.send
        .. " "
        .. to.name
        .. " "
        .. string.format("%g", math.floor(send.level * 10 + 0.5) / 10)
    end
  end
  return table.concat(out, "  ")
end

heads.piece(
  "sends",
  {
    keep = 40,
    line = true,
    has = function(ctx: Ctx): boolean return #(ctx.part.sends or {}) > 0 end,
    draw = function(ctx: Ctx, x: integer, y: integer, w: integer): integer
      local text = sends_text(ctx.part)
      if api.str_width(text) > w then
        text = util.fit(text, w)
      end
      words(ctx, x, y, text, "PartInfo", "text_3")
      return w
    end,
  }
)

-- What the part takes in, with the level that arrives there whether or
-- not it is heard, so that a guitar can be seen before anything is armed.
heads.piece(
  "input",
  {
    keep = 45,
    line = true,
    has = function(ctx: Ctx): boolean return not ctx.part.master and paw.audio.label(ctx.part) as string ~= nil end,
    draw = function(ctx: Ctx, x: integer, y: integer, w: integer): integer
      local t = ctx.part
      local label = paw.audio.label(t) as string
      local right = x + w
      local heard = t.input and (t.monitor or t.armed)
      if t.input then
        local level = paw.audio.level(t) as number
        ctx.buf:text(x, y, M.level_glyph(level), level > 0.001 and "Input" or "PartIndex")
        x = x + 2
      end
      label = util.fit(label, math.max(1, right - x))
      words(ctx, x, y, label, heard and "Input" or "PartInfo", heard and "select" or "text_3")
      return w
    end,
  }
)

return M
