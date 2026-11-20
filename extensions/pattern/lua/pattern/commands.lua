-- Commands and keys of the pattern extension.
local pattern = require("pattern")
local api = paw.api
local command, map = paw.command, paw.keymap.set

local M = {}

local function bar_text(pm)
  return pm and pm.beats and (pm.beats .. " beats") or "a bar"
end

--- The clip to act on: the MIDI clip under the cursor. With `create`, a new
--- clip at the cursor when there is none, `cycles` cycles long; with `new`,
--- a new clip whatever is there.
function M.target(create, cycles, new)
  local track = paw.cursor.track()
  if not track then return nil, paw.notify("no track: add one with `o` first", "warn") end
  local clip = not new and paw.cursor.clip()
  if clip then
    if clip.kind ~= "midi" then return nil, paw.notify("not a MIDI clip", "warn") end
    return clip
  end
  if not create then return nil, paw.notify("no clip under the cursor", "warn") end
  local length = (cycles or paw.opt.pattern_cycles) * paw.time.bar()
  return track:add_clip({ start = paw.cursor.beat, length = length, name = "pattern" }), true
end

local function report_error(err)
  paw.notify("pattern: " .. tostring(err), "error")
end

--- Give the clip under the cursor (or a new one) this text. Returns the clip,
--- or nil after reporting why not. A new clip is not made for text that does
--- not parse.
function M.set_text(text, cycles, new)
  local ok, err = pattern.parse(text)
  if not ok then return report_error(err) end
  local clip, made = M.target(true, cycles, new)
  if not clip then return end
  local notes, why = pattern.set(clip, text)
  if not notes then
    if made then clip:remove() end
    return report_error(why)
  end
  paw.notify(string.format("pattern: %d notes", #notes))
  return clip
end

--- Ask for a pattern on the command line, starting from `text`. On an error
--- the prompt opens again with the text as it was and the error in front.
function M.prompt(text, cycles, problem, new)
  local prompt = problem and ("pattern (" .. tostring(problem) .. "): ") or "pattern: "
  paw.ui.input({ prompt = prompt, text = text or "", history = "pattern", select = problem == nil }, function(value)
    if value:match("^%s*$") then return end
    local ok, err = pattern.parse(value)
    if not ok then return M.prompt(value, cycles, err, new) end
    M.set_text(value, cycles, new)
  end)
end

command("pattern.set", function(ctx)
  local text = ctx.args[1]
  if not text or text:match("^%s*$") then return paw.notify("usage: pattern.set <pattern>, e.g. `pattern.set bd*2 [~ sn]`", "warn") end
  return M.set_text(text, ctx.count)
end, { raw = true, desc = "Set the pattern of the clip under the cursor, or of a new clip: `pattern.set bd*2 [~ sn]`" })

command("pattern.edit", function(ctx)
  local clip = paw.cursor.clip()
  local text = ""
  if clip then
    if clip.kind ~= "midi" then return paw.notify("not a MIDI clip", "warn") end
    local pm = pattern.get(clip)
    text = pm and pm.text or pattern.detached(clip) or ""
  end
  M.prompt(text, ctx.count)
end, { desc = "Edit the pattern of the clip under the cursor on the command line (a new clip if there is none)" })

command("pattern.detach", function()
  local clip = M.target(false)
  if not clip then return end
  if pattern.detach(clip) then
    paw.notify("pattern detached; the notes stay")
  else
    paw.notify("the clip has no pattern", "warn")
  end
end, { desc = "Stop the clip following its pattern, keeping its notes" })

command("pattern.seed", function(ctx)
  local clip = M.target(false)
  if not clip then return end
  local pm = pattern.get(clip)
  if not pm then return paw.notify("the clip has no pattern", "warn") end
  local seed = tonumber(ctx.args[1]) or (pm.seed or 0) + (tonumber(ctx.args.by) or 1) * (ctx.count or 1)
  local notes, err = pattern.set(clip, pm.text, { seed = seed })
  if not notes then return report_error(err) end
  paw.notify(string.format("pattern seed %d: %d notes", seed, #notes))
end, { desc = "Set the seed of the clip's random choices: `pattern.seed 7`; with no number, the next one (`by=-1` the previous)" })

command("pattern.cycle", function(ctx)
  local clip = M.target(false)
  if not clip then return end
  local pm = pattern.get(clip)
  if not pm then return paw.notify("the clip has no pattern", "warn") end
  local value = ctx.args[1]
  local beats = tonumber(value)
  if value == "bar" then beats = false end
  if beats == nil or beats and beats <= 0 then
    return paw.notify("usage: pattern.cycle <beats> or pattern.cycle bar; now " .. bar_text(pm), "warn")
  end
  local notes, err = pattern.set(clip, pm.text, { beats = beats })
  if not notes then return report_error(err) end
  paw.notify("a cycle is " .. bar_text(pattern.get(clip)))
end, { desc = "Set how many beats a cycle of the clip's pattern lasts: `pattern.cycle 8`, `pattern.cycle bar`" })

command("pattern.info", function()
  local clip = M.target(false)
  if not clip then return end
  local pm = pattern.get(clip)
  if not pm then
    local old = pattern.detached(clip)
    return paw.notify(old and ("detached from `" .. old .. "`") or "the clip has no pattern")
  end
  paw.notify(string.format("%s   (seed %d, a cycle is %s, %d notes)", pm.text, pm.seed or 0, bar_text(pm), #clip:notes()))
end, { desc = "Show the clip's pattern, seed and cycle length" })

local amap = function(lhs, rhs, desc, opts)
  map(lhs, rhs, paw.util.merge(opts or {}, { view = "arrange", desc = desc }))
end
paw.keymap.group("<localleader>t", "pattern", { view = "arrange" })
amap("<localleader>tt", "pattern.edit", "Edit the clip's pattern (a new clip if none)")
amap("<localleader>tn", function(ctx)
  -- Always a new clip: right after the one under the cursor, if any.
  local clip = paw.cursor.clip()
  if clip then paw.cursor.set_beat(clip.start + clip.length) end
  M.prompt("", ctx.count, nil, true)
end, "New pattern clip at the cursor (after the clip under it)")
amap("<localleader>tr", function(ctx) paw.cmd("pattern.seed", {}, { count = ctx.count }) end, "Next seed: roll the random choices again")
amap("<localleader>tR", function(ctx) paw.cmd("pattern.seed", { by = -1 }, { count = ctx.count }) end, "Previous seed")
amap("<localleader>td", "pattern.detach", "Detach the clip from its pattern, keeping the notes")
amap("<localleader>ti", "pattern.info", "Show the clip's pattern")
amap("<localleader>tc", function()
  paw.ui.input({ prompt = "beats per cycle (or bar): ", history = "pattern.cycle" }, function(value)
    paw.cmd("pattern.cycle", { tonumber(value) or value })
  end)
end, "Set the beats per cycle of the clip's pattern")

return M
