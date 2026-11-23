-- rulerplus: an example of how to personalize the bar labels of the ruler
-- (paw.ruler, docs/reference/partcolumn.md). It adds three parts (a mark
-- at the start of each phrase, the key where it changes, the chord where
-- it changes) and changes the part `number` of paw: with `relativebar`,
-- the counts get a sign, `+4` ahead and `-4` behind. paw records each of
-- them as the extension's, so `:ext.unload rulerplus` puts the ruler back
-- as it was.
local type Ctx = paw.contracts.RulerContext
local type Cells = paw.contracts.ColumnCells
local type Label = paw.contracts.RulerLabel

-- Options ------------------------------------------------------------------------

local phrase = paw.option.define("rulerplus_phrase", 4, {min = 0, max = 64, integer = true})
local signed = paw.option.define("rulerplus_signed", true)

--- `text` with a space before it, cut to the room that the label has left.
local function fit(text: string, room: integer): string
  if room < 2 then
    return nil
  end
  text = " " .. text
  if paw.api.str_width(text) > room then
    text = paw.util.fit(text, room)
  end
  return text
end

-- The phrases: a mark before the number of the first bar of each ----------------

paw.ruler.add(
  "phrase",
  {
    order = 5,
    glyphs = {phrase = "┃"},
    styles = {phrase = "RulerTempo"},
    render = function(bar: integer, ctx: Ctx): Cells
      local n = phrase:get()
      -- Not on bar 1: the song starts there, and the mark would take room.
      if n <= 0 or bar == 1 or (bar - 1) % n ~= 0 then
        return nil
      end
      return {{paw.opt.ascii and "|" or ctx.glyphs.phrase, ctx.styles.phrase}}
    end,
  }
)

-- The chord and the key: on the bars where they change -------------------------

paw.ruler.add(
  "chord",
  {
    order = 25,
    styles = {chord = "RulerChord"},
    render = function(bar: integer, ctx: Ctx): Cells
      local chord = paw.harmony.at(ctx.beat, true)
      if not chord then
        return nil
      end
      local before = bar > 1 and paw.harmony.at(paw.time.bar_start(bar - 1), true) or nil
      if before and before.name == chord.name and before.at == chord.at then
        return nil
      end
      local text = fit(paw.harmony.label(chord), ctx.room)
      return text and {{text, ctx.styles.chord}} or nil
    end,
  }
)

-- The key in short, in brackets: `(C)` C major, `(Am)` A minor, `(D dor)`.
local function short(key: paw.harmony.Key): string
  local mode = key.mode == "major" and "" or key.mode == "minor" and "m" or " " .. key.mode:sub(1, 3)
  return "(" .. paw.harmony.pc_name(key.tonic, key) .. mode .. ")"
end

paw.ruler.add(
  "key",
  {
    order = 30,
    styles = {key = "RulerTempo"},
    render = function(bar: integer, ctx: Ctx): Cells
      local key = paw.harmony.key(ctx.beat, true)
      if bar > 1 and paw.harmony.key(paw.time.bar_start(bar - 1), true).name == key.name then
        return nil
      end
      -- Whole or not at all: a key cut short reads as another.
      local text = " " .. short(key)
      if paw.api.str_width(text) > ctx.room then
        return nil
      end
      return {{text, ctx.styles.key}}
    end,
  }
)

-- The number of paw, with a sign on the counts --------------------------------

local found: Label = paw.ruler.labels:get("number")
if found then
  local base = found.render
  paw.ruler.set(
    "number",
    {
      render = function(bar: integer, ctx: Ctx): Cells
        local cells = base(bar, ctx)
        if signed:get() and ctx.relative and cells is {paw.contracts.Piece} and cells[1] then
          local ahead = bar > paw.time.bar_of(paw.cursor.beat)
          cells[1] = {(ahead and "+" or "-") .. cells[1][1], cells[1][2]}
        end
        return cells
      end,
    }
  )
end

-- Commands and keys ---------------------------------------------------------------

local lengths: {integer} = {4, 8, 16, 0}

paw.command(
  "rulerplus.phrase",
  function(ctx: paw.contracts.CommandContext)
    local n = math.tointeger(tonumber(ctx.args[1] as string))
    if ctx.args[1] and not (n and n >= 0 and n <= 64) then
      return paw.notify("rulerplus.phrase takes a number of bars from 0 to 64", "warn")
    end
    if not n then
      local at = #lengths
      for i, l in ipairs(lengths) do
        if l == phrase:get() then
          at = i
        end
      end
      n = lengths[at % #lengths + 1]
    end
    phrase:set(n)
    paw.notify(n > 0 and string.format("a phrase is %d bars", n) or "no phrase marks")
  end,
  {desc = "Mark a phrase every N bars on the ruler: 4, 8, 16, 0 for none (no number: the next length)"}
)

paw.keymap.set(
  "<localleader>p", "rulerplus.phrase", {view = "arrange", desc = "Next phrase length: 4, 8, 16 bars, none"}
)
