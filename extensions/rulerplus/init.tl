-- rulerplus: an example of how to add to the ruler (paw.ruler, paw.marks,
-- docs/reference/ruler.md). It adds a row (`harmony`: the chord and the key
-- where they change), a namespace of marks (`rulerplus.phrase`: a mark at
-- the start of each phrase, over the bars) and changes the row `bars` of
-- paw: with `relativebar`, the counts get a sign, `+4` ahead and `-4`
-- behind. paw records each of them as the extension's, so
-- `:ext.unload rulerplus` puts the ruler back as it was.
local type Ctx = paw.contracts.RulerContext
local type Mark = paw.contracts.RulerMark

-- Options ------------------------------------------------------------------------

local phrase = paw.option.define("rulerplus_phrase", 4, {min = 0, max = 64, integer = true})
local signed = paw.option.define("rulerplus_signed", true)

-- The chord and the key: a row under the bars --------------------------------------

-- The key as a musician says it: `in C major`, `in A minor`, `in D dorian`.
local function spoken(key: paw.harmony.Key): string
  return "in " .. paw.harmony.pc_name(key.tonic, key) .. " " .. key.mode
end

-- Two lines: at each bar where the chord changes, its name; under it, where
-- the key changes, the key. A chord gets shorter with `…` where it has no
-- room, and a key is whole or not shown: a key cut short reads as another.
-- Styles: `chord`, `key`.
paw.ruler.row(
  "harmony",
  {
    after = "bars",
    styles = {chord = "RulerChord", key = "RulerTempo"},
    height = function(_: Ctx): integer return 2 end,
    marks = function(ctx: Ctx): {Mark}
      local out: {Mark} = {}
      for _, line in ipairs(paw.draw.grid_lines(ctx.axis, ctx.right)) do
        if line.bar then
          local before = line.bar > 1 and paw.time.bar_start(line.bar - 1) or nil
          local chord = paw.harmony.at(line.beat, true)
          local last = before and paw.harmony.at(before, true)
          if chord and not (last and last.name == chord.name and last.at == chord.at) then
            local name = paw.harmony.label(chord)
            out[#out + 1] = {
              beat = line.beat, label = name, priority = 20, style = ctx.styles.chord, text = "chord " .. name
            }
          end
          local key = paw.harmony.key(line.beat, true)
          if not before or paw.harmony.key(before, true).name ~= key.name then
            out[#out + 1] = {
              beat = line.beat,
              line = 1,
              label = spoken(key),
              whole = true,
              priority = 15,
              style = ctx.styles.key,
              text = "key " .. key.name,
            }
          end
        end
      end
      return out
    end,
  }
)

-- The phrases: a mark on the first bar of each, over the bars -------------------

-- Not on bar 1: the song starts there, and the mark would take room.
-- Glyphs: `sign`. Styles: `phrase`.
paw.marks.namespace(
  "rulerplus.phrase",
  {
    route = "over:bars",
    priority = 15,
    glyphs = {sign = "┃"},
    styles = {phrase = "RulerTempo"},
    source = function(ctx: Ctx): {Mark}
      local out: {Mark} = {}
      local n = phrase:get()
      if n <= 0 or not ctx.left then
        return out
      end
      for _, line in ipairs(paw.draw.bar_lines(ctx.left, ctx.right - ctx.left)) do
        if line.bar and line.bar > 1 and (line.bar - 1) % n == 0 then
          out[#out + 1] = {
            beat = line.beat,
            sign = paw.opt.ascii and "|" or ctx.glyphs.sign,
            style = ctx.styles.phrase,
            text = string.format("a phrase of %d bars", n),
          }
        end
      end
      return out
    end,
  }
)

-- The counts of relativebar, with a sign ----------------------------------------

local function apply()
  if signed:get() then
    paw.ruler.set("bars", {glyphs = {ahead = "+", behind = "-"}})
  else
    paw.ruler.set("bars", {glyphs = {ahead = "", behind = ""}})
  end
end
apply()

paw.on(
  paw.option.changed,
  function(e: paw.option.Changed)
    if e.name == "rulerplus_signed" then
      apply()
    end
  end
)

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
