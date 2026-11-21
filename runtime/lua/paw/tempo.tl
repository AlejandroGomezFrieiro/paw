-- `paw.tempo`: the tempo map. Tempo and time signature can change along the
-- song; everything that turns beats into seconds or bars asks here.
--
--   paw.tempo.at(17)                       -- BPM at beat 17
--   paw.tempo.set(16, 96)                  -- 96 BPM from beat 16 on
--   paw.tempo.set(8, 120, { ramp = true }) -- from beat 8, ramp to the next point
--   paw.tempo.remove(16)
--   paw.tempo.points()                     -- { { beat, bpm, ramp }, ... }
--   paw.tempo.set_signature(9, 6, 8)       -- bar 9 and on in 6/8
--   paw.tempo.signature_at(33)             -- 6, 8
--   paw.tempo.beats_to_seconds(16)  paw.tempo.seconds_to_beats(8)
--   paw.tempo.bar_of(33)                   -- 9 (bars count from 1)
--
-- A ramp changes the tempo linearly in time, as REAPER's does. A signature
-- change starts a new bar where it is, cutting short a bar it falls inside.
-- `paw.project.tempo` is the tempo at the start.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type types = require("paw.types")
local type commands = require("paw.commands")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")

--- What `paw.tempo.set` takes besides the beat and the tempo.
local record SetOptions
  ramp: boolean
end

--- A change that a ruler marks (`paw.tempo.marks`).
local record Mark
  beat: number
  text: string
  kind: string
end

--- How `paw.tempo.commands` defines a command: as `paw.command` does.
local type Define = function(name: string, run: function(ctx: commands.Context): (commands.Result), opts?: commands.Options)

-- What this module reads of `paw`, which paw/init.lua makes.
--- paw/scope.tl, the part of it that this module reads: bars typed in a
--- scope with time are its own, from 1 at its start.
local record Scope
  bar_offset: function(): integer
end
local record Paw
  scope: Scope
  cursor: CursorModule
  project: objects.Project
  time: objects.Time
  notify: function(text: string, level?: string)
end
local paw = (_G as {string:Paw}).paw

local record M
  type SetOptions = SetOptions
  type Mark = Mark
  type Define = Define
  beats_to_seconds: function(beat: number): number
  seconds_to_beats: function(seconds: number): number
  is_bar_line: function(beat: number): boolean
end

--- The tempo at a beat (the start if left out).
function M.at(beat?: number): number return api.tempo_at(beat or 0) end

--- Set the tempo from `beat`. With `opts.ramp`, ramp from here to the tempo
--- of the next point, and do not hold. Without it, a point keeps its value.
function M.set(beat: number, bpm: number, opts?: SetOptions)
  api.tempo_set(beat, bpm, opts and opts.ramp)
end

--- Remove the tempo change at `beat`.
function M.remove(beat: number) api.tempo_remove(beat) end

--- Every tempo point, the start's first: { beat, bpm, ramp }.
function M.points(): {types.TempoPoint} return api.tempo_points().tempos end

--- Every signature point, the start's first: `{ beat, bar, num, den }`.
function M.signatures(): {types.SigPoint} return api.tempo_points().signatures end

--- The signature at a beat, as two numbers.
function M.signature_at(beat?: number): integer, integer return api.tempo_signature(beat or 0) end

--- Start bar `bar` (the first bar is 1) in `num`/`den`, up to the next change.
function M.set_signature(bar: integer, num: integer, den: integer)
  api.signature_set(api.tempo_bar_start(bar - 1), num, den)
end

--- Remove the signature change that starts bar `bar`.
function M.remove_signature(bar: integer) api.signature_remove(api.tempo_bar_start(bar - 1)) end

--- Replace the whole map: `set_points({ { beat = 0, bpm = 120 } }, { { beat = 0, num = 4, den = 4 } })`.
function M.set_points(tempos?: {types.TempoPoint}, signatures?: {types.SigPoint})
  api.tempo_set_points(tempos or M.points(), signatures or M.signatures())
end

M.beats_to_seconds = api.tempo_seconds
M.seconds_to_beats = api.tempo_beat

--- Seconds from beat `from` to beat `to`.
function M.seconds_between(from: number, to: number): number return api.tempo_seconds(to) - api.tempo_seconds(from) end

--- The bar that contains a beat, counted from 1.
function M.bar_of(beat: number): integer return api.tempo_bar_of(beat) + 1 end

--- Where bar `n` (the first bar is 1) starts, in beats.
function M.bar_start(n: integer): number return api.tempo_bar_start(n - 1) end

--- Whether a bar starts at this beat.
M.is_bar_line = api.tempo_is_bar_line

--- The bar and beat lines from one beat to another: { beat, bar, index },
--- `index` 0 on a bar line (bars count from 1).
function M.lines(from: number, to: number, limit?: integer): {types.TempoLine} return api.tempo_lines(from, to, limit) end

--- What a tempo change reads as on a ruler: "96" or "120>" for a ramp.
function M.label(point: types.TempoPoint): string
  return string.format("%g", math.floor(point.bpm * 100 + 0.5) / 100) .. (point.ramp and ">" or "")
end

--- Tempo and signature changes from one beat to another, for a ruler to
--- mark: { beat, text, kind = "tempo" | "signature" }, the start's left out.
function M.marks(from: number, to: number): {Mark}
  local p, out: types.TempoPoints, {Mark} = api.tempo_points(), {}
  for i, t in ipairs(p.tempos) do
    if i > 1 and t.beat >= from and t.beat < to then
      out[#out + 1] = { beat = t.beat, text = M.label(t), kind = "tempo" }
    end
  end
  for i, s in ipairs(p.signatures) do
    if i > 1 and s.beat >= from and s.beat < to then
      out[#out + 1] = { beat = s.beat, text = s.num .. "/" .. s.den, kind = "signature" }
    end
  end
  table.sort(out, function(a: Mark, b: Mark): boolean return a.beat < b.beat end)
  return out
end

-- Commands ------------------------------------------------------------------

--- A place given to a command: a bar (`17`), a bar and beat (`17.3`), or
--- `cursor` / `here`. The beat of the cursor when nothing is given. In a
--- scope with time (`paw.scope`), bars are its own, from 1 at its start.
function M.place(text?: commands.Arg): number
  if text == nil or text == "cursor" or text == "here" then return paw.cursor.beat end
  local bar_text, beat = tostring(text):match("^(%d+)%.?(%d*)$")
  if not bar_text then error("a place is a bar (17), a bar and beat (17.3) or `cursor`, not " .. tostring(text), 0) end
  local bar = tonumber(bar_text) as integer
  if bar < 1 then error("bars count from 1", 0) end
  -- In a scope with time, its own bars.
  local offset = paw.scope and paw.scope.bar_offset() or 0
  return api.tempo_from_bbt(bar - 1 + offset, math.max(0, (tonumber(beat) or 1) - 1) as integer)
end

--- The tempo point in effect at a beat.
function M.point_at(beat: number): types.TempoPoint
  local found: types.TempoPoint
  for _, p in ipairs(M.points()) do
    if p.beat <= beat + 1e-9 then found = p end
  end
  return found
end

--- What a position reads as in commands' messages: "bar 9" or "9.2.50".
local function where(beat: number): string
  local offset = paw.scope and paw.scope.bar_offset() or 0
  if api.tempo_is_bar_line(beat) then return "bar " .. (M.bar_of(beat) - offset) end
  return paw.time.format(beat)
end

--- The whole map as text, for example "120 bpm 4/4 at bar 1, 90 bpm from bar 3 with a ramp, ...".
function M.describe(): {string}
  local parts: {string} = {}
  for _, p in ipairs(M.points()) do
    parts[#parts + 1] = string.format("%s: %g bpm%s", where(p.beat), p.bpm, p.ramp and ", ramping to the next" or "")
  end
  for _, s in ipairs(M.signatures()) do
    parts[#parts + 1] = string.format("bar %d: %d/%d", s.bar, s.num, s.den)
  end
  return parts
end

local taps: {number} = {}

--- Completion for a place: `at`, `here`, and the bars where something changes.
local function places(_: string, info: commands.Info): {string}
  if info.words[#info.words] == "at" then
    local out = { "cursor" }
    for _, p in ipairs(M.points()) do out[#out + 1] = tostring(M.bar_of(p.beat)) end
    for _, sig in ipairs(M.signatures()) do out[#out + 1] = tostring(sig.bar) end
    return out
  end
  return { "at", "here" }
end

local SIGNATURES = { "4/4", "3/4", "6/8", "2/4", "5/4", "7/8", "12/8", "9/8" }

--- Define the tempo and time signature commands with `command`.
function M.commands(command: Define)
  command("tempo", function(ctx: commands.Context): commands.Result
    local a = ctx.args
    local bpm = tonumber(a[1])
    if a.by then bpm = paw.project.tempo + (tonumber(a.by) or 0 / 0) end
    if not bpm and a[1] == nil and a.by == nil then
      local beat = paw.cursor.beat
      paw.notify(string.format("tempo is %g bpm at the start, %g at the cursor (%s)", paw.project.tempo, M.at(beat), where(beat)))
      return
    end
    if not bpm or not (bpm >= 1 and bpm <= 999) then
      error(string.format("a tempo is from 1 to 999 bpm, not %s", a.by and tostring(bpm) or tostring(a[1])), 0)
    end
    local at = a.at or (a[2] == "at" and (a[3] or "cursor")) or ((a[2] == "here" or a[2] == "cursor") and "cursor")
    if not at then
      paw.project.tempo = bpm
      paw.notify(string.format("%g bpm", bpm))
    else
      local beat = M.place(at)
      api.tempo_set(beat, bpm)
      paw.notify(string.format("%g bpm from %s", bpm, where(beat)))
    end
  end, {
    desc = "Show or set the tempo: `tempo 140` (at the start), `tempo 96 at 17` (bar 17), `tempo 96 here`, `tempo by=-1`",
    label = "Set the tempo",
    complete = function(text: string, info: commands.Info): {string}
      if info.index == 1 then return { tostring(math.floor(M.at(paw.cursor.beat) + 0.5)) } end
      return places(text, info)
    end,
  })

  command("tempo.ramp", function(ctx: commands.Context): commands.Result
    local a = ctx.args
    local beat = (a[1] or a.at) and M.place(a.at or (a[1] == "at" and a[2] or a[1])) or paw.cursor.beat
    local p = M.point_at(beat)
    local on = not p.ramp
    if a.off or a[1] == "off" then on = false end
    api.tempo_set(p.beat, p.bpm, on)
    paw.notify(string.format("%g bpm at %s %s", p.bpm, where(p.beat), on and "ramps to the next change" or "holds"))
  end, {
    desc = "Make the tempo change before the cursor ramp to the next one, or hold again: `tempo.ramp`, `tempo.ramp 9`",
    label = "Ramp the tempo",
    complete = function(): {string} return { "off", "at" } end,
  })

  command("tempo.remove", function(ctx: commands.Context): commands.Result
    local a = ctx.args
    local beat = a[1] and M.place(a[1]) or paw.cursor.beat
    local p = M.point_at(beat)
    if p.beat == 0 then error("no tempo change at or before " .. where(beat) .. " but the start's", 0) end
    api.tempo_remove(p.beat)
    paw.notify("removed the tempo change at " .. where(p.beat))
  end, {
    desc = "Remove the tempo change at or before the cursor, or at a bar: `tempo.remove 17`",
    label = "Remove a tempo change",
    complete = function(): {commands.Candidate}
      local out: {commands.Candidate} = {}
      for i, p in ipairs(M.points()) do
        if i > 1 then out[#out + 1] = { text = tostring(M.bar_of(p.beat)), desc = string.format("%g bpm", p.bpm) } end
      end
      return out
    end,
  })

  command("tempo.list", function(): commands.Result
    local lines = M.describe()
    paw.notify(table.concat(lines, " · "))
    return lines as commands.Result
  end, { desc = "List the tempo and time signature changes" })

  command("tempo.tap", function(): commands.Result
    local now = api.now()
    if #taps > 0 and now - taps[#taps] > 2000 then taps = {} end
    taps[#taps + 1] = now
    while #taps > 8 do table.remove(taps, 1) end
    if #taps < 2 then
      paw.notify("tap again in time")
      return
    end
    local bpm = 60000 * (#taps - 1) / (taps[#taps] - taps[1])
    bpm = math.floor(math.max(1, math.min(999, bpm)) * 10 + 0.5) / 10
    local p = M.point_at(paw.cursor.beat)
    api.tempo_set(p.beat, bpm)
    paw.notify(string.format("tapped %g bpm at %s", bpm, where(p.beat)))
  end, { desc = "Tap in time, again and again, to set the tempo in effect at the cursor", label = "Tap the tempo" })

  command("timesig", function(ctx: commands.Context): commands.Result
    local a = ctx.args
    local text = a[1]
    if text == nil then
      local num, den = M.signature_at(paw.cursor.beat)
      paw.notify(string.format("%d/%d at %s", num, den, where(paw.cursor.beat)))
      return
    end
    local num, den = tostring(text):match("^(%d+)/(%d+)$")
    if not num then error("write a time signature as 6/8", 0) end
    local at = a.at or (a[2] == "at" and a[3]) or a[2]
    local beat = at and M.place(at) or paw.time.bar_floor(paw.cursor.beat)
    api.signature_set(beat, tonumber(num) as integer, tonumber(den) as integer)
    paw.notify(string.format("%s/%s from %s", num, den, where(beat)))
  end, {
    desc = "Set the time signature from the cursor's bar on, or from a bar: `timesig 6/8`, `timesig 3/4 at 9`",
    label = "Set the time signature",
    complete = function(text: string, info: commands.Info): {string}
      if info.index == 1 then return SIGNATURES end
      return places(text, info)
    end,
  })

  command("timesig.remove", function(ctx: commands.Context): commands.Result
    local beat = ctx.args[1] and M.place(ctx.args[1]) or paw.cursor.beat
    local found: types.SigPoint
    for _, s in ipairs(M.signatures()) do
      if s.beat <= beat + 1e-9 then found = s end
    end
    if found.beat == 0 then error("no signature change at or before " .. where(beat) .. " but the start's", 0) end
    api.signature_remove(found.beat)
    paw.notify("removed the signature change at bar " .. found.bar)
  end, {
    desc = "Remove the time signature change at or before the cursor, or at a bar",
    label = "Remove a time signature change",
    complete = function(): {commands.Candidate}
      local out: {commands.Candidate} = {}
      for i, sig in ipairs(M.signatures()) do
        if i > 1 then out[#out + 1] = { text = tostring(sig.bar), desc = sig.num .. "/" .. sig.den } end
      end
      return out
    end,
  })
end

return M
