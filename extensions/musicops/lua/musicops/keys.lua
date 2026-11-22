-- The keys of musicops: operators under `gz`, the phrase text objects and
-- motions of the vocal editor, the key commands, and the scale lock. The
-- piano roll's text objects (`ip`, `ic` and the rest) are paw's own.
--
-- Operators act in the piano roll and the vocal editor on the notes of the
-- region (as `d` and `>` do), and in the arrange view on the notes of the
-- MIDI clips the region reaches. A count typed in visual mode before the
-- operator sets its amount (`v3gzk` is up three scale steps); with a motion
-- or text object the count belongs to that, as with every operator.
local mo = require("musicops")
local scale = mo.scale
local api, keymap, edit = paw.api, paw.keymap, paw.edit
local EPS = 1e-9

local M = {}

local NOTES = { "pianoroll", "utau" } -- views that edit one clip's notes
local ALL = { "pianoroll", "utau", "arrange" }
local POLY = { "pianoroll", "arrange" } -- not the vocal editor: one voice, and lyrics

-- Targets ---------------------------------------------------------------------

--- The clip open in a note view, as a handle, and the view.
function M.view_clip(name)
  local v = paw.ui.views[name]
  if not (v and v.clip_id) then return end
  local ok, c = pcall(api.clip_get, v.clip_id)
  if ok and c.kind == "midi" then return paw.clip(v.clip_id), v end
end

--- Replace the notes of a clip that `pick(note)` chooses with what
--- `fn(notes)` makes of them. The clip grows to hold notes that now reach
--- past its end. Returns how many notes were picked.
function M.apply_to_clip(clip, pick, fn)
  local inside, keep = {}, {}
  for _, n in ipairs(clip:notes()) do
    if pick(n) then
      inside[#inside + 1] = n
    else
      keep[#keep + 1] = n
    end
  end
  if #inside == 0 then return 0 end
  local finish = 0
  for _, n in ipairs(fn(inside)) do
    keep[#keep + 1] = n
    finish = math.max(finish, n.start + n.length)
  end
  if finish > clip.length + EPS then
    local grid = paw.opt.note_grid
    clip.length = math.ceil(finish / grid - EPS) * grid
  end
  clip:set_notes(keep)
  return #inside
end

--- Whether a clip is on a drum track (one with a drum map): its pitches
--- name drum sounds, not notes, so pitch operators leave it alone.
function M.on_drum_track(clip)
  local ok, t = pcall(api.track_get, clip:get().track)
  return ok and type(t.meta) == "table" and t.meta.drums ~= nil
end

--- Apply `fn(notes, index)` to the notes of the MIDI clips that a region of
--- the arrange view reaches: for whole tracks every note, otherwise the
--- notes that start inside the region. Each clip is done on its own; clips
--- that `skip(clip)` names are left as they are.
function M.apply_arrange(region, fn, skip)
  local index, count = 0, 0
  for _, track in ipairs(edit.arrange.tracks(region)) do
    for _, c in ipairs(api.clip_list(track)) do
      local whole = region.kind == "line"
      if
        c.kind == "midi"
        and (whole or (c.start < region.c1 - EPS and c.start + c.length > region.c0 + EPS))
        and not (skip and skip(paw.clip(c.id)))
      then
        index = index + 1
        local i = index
        count = count
          + M.apply_to_clip(paw.clip(c.id), function(n)
            local at = c.start + n.start
            return whole or (at >= region.c0 - EPS and at < region.c1 - EPS)
          end, function(notes) return fn(notes, i) end)
      end
    end
  end
  return count
end

--- Apply `fn(notes, index)` to what a region of `view` holds, leaving the
--- clips that `skip(clip)` names as they are.
function M.apply(view, region, fn, skip)
  if view == "arrange" then return M.apply_arrange(region, fn, skip) end
  -- The piano roll may edit several clips at once: each is done on its own,
  -- the region taken in its own beats, so that its notes stay in it.
  local parts = view == "pianoroll" and paw.roll_clips and paw.roll_clips.parts() or {}
  if #parts > 1 then
    local count = 0
    for i, part in ipairs(parts) do
      if not (skip and skip(part.clip)) then
        local mine = paw.util.merge(region, { c0 = region.c0 - part.offset, c1 = region.c1 - part.offset })
        count = count
          + M.apply_to_clip(
            part.clip,
            function(n) return edit.roll.inside(n, mine, part.clip.id) end,
            function(notes) return fn(notes, i) end
          )
      end
    end
    return count
  end
  local clip = M.view_clip(view)
  if not clip or (skip and skip(clip)) then return 0 end
  return M.apply_to_clip(
    clip,
    function(n) return edit.roll.inside(n, region, clip.id) end,
    function(notes) return fn(notes, 1) end
  )
end

-- Operators ---------------------------------------------------------------------

--- Every operator: { lhs, desc, views, pitched }, for the help and the tests.
M.operators = {}

--- Define a musical operator: `fn(notes, amount, info)` returns the new
--- notes; `amount` is the count typed in visual mode, or nil; `info.index`
--- counts the clips done by one use (arrange regions reach several). A
--- `pitched` operator changes pitches and leaves drum tracks alone.
function M.operator(lhs, desc, views, fn, pitched)
  M.operators[#M.operators + 1] = { lhs = lhs, desc = desc, views = views, pitched = pitched }
  for _, view in ipairs(views) do
    keymap.operator(lhs, function(region, ctx)
      local amount = region.visual and ctx.count or nil
      local drums = 0
      local skip = pitched
        and function(clip)
          if not M.on_drum_track(clip) then return false end
          drums = drums + 1
          return true
        end
      M.apply(
        view,
        region,
        function(notes, index) return fn(notes, amount, { index = index, view = view, ctx = ctx }) end,
        skip
      )
      if drums > 0 then
        paw.notify(
          string.format(
            "left %d clip%s of drum tracks alone: their pitches are drum sounds",
            drums,
            drums == 1 and "" or "s"
          ),
          "warn"
        )
      end
    end, { view = view, desc = desc })
  end
end

local function opt(name) return paw.opt["musicops_" .. name] end
local function pct(amount) return amount and amount / 100 end

local seeds = 0
local function seed()
  local fixed = opt("seed")
  if fixed then return fixed end
  seeds = seeds + 1
  return math.floor(api.now() * 1000 + seeds) % 2147483646
end

local last_seed
local op = M.operator
keymap.group("gz", "music ops")
op("gzh", "Humanize timing and velocity", ALL, function(notes, amount, info)
  if info.index == 1 then
    last_seed = seed()
    paw.notify(string.format("humanized, seed %d (:lua paw.opt.musicops_seed = %d repeats it)", last_seed, last_seed))
  end
  return mo.humanize(notes, {
    timing = pct(amount) or opt("humanize_timing"),
    velocity = amount or opt("humanize_velocity"),
    length = opt("humanize_length"),
    seed = last_seed + info.index - 1,
  })
end)
op(
  "gzs",
  "Strum chords upwards",
  POLY,
  function(notes, amount)
    return mo.strum(notes, { step = pct(amount) or opt("strum"), dir = "up", tolerance = opt("together") })
  end
)
op(
  "gzS",
  "Strum chords downwards",
  POLY,
  function(notes, amount)
    return mo.strum(notes, { step = pct(amount) or opt("strum"), dir = "down", tolerance = opt("together") })
  end
)
for lhs, mode in pairs({ gzp = "up", gzP = "down", gzb = "updown", gzB = "played" }) do
  op(
    lhs,
    "Arpeggiate chords " .. (mode == "played" and "as played" or mode),
    POLY,
    function(notes, amount)
      return mo.arpeggiate(notes, {
        mode = mode,
        step = amount and 1 / amount or opt("arp_step") or paw.opt.note_grid,
        gate = opt("arp_gate"),
        tolerance = opt("together"),
      })
    end
  )
end
op(
  "gzl",
  "Legato: hold each note to the next",
  ALL,
  function(notes) return mo.legato(notes, { gap = opt("legato_gap") }) end
)
op(
  "gzt",
  "Staccato: shorten the notes",
  ALL,
  function(notes, amount) return mo.staccato(notes, { factor = pct(amount) or opt("staccato") }) end
)
op(
  "gzq",
  "Quantize, with strength and swing",
  ALL,
  function(notes, amount)
    return mo.quantize(notes, {
      grid = paw.opt.note_grid,
      strength = pct(amount) or opt("strength"),
      swing = opt("swing"),
    })
  end
)
op(
  "gzw",
  "Quantize with swing",
  ALL,
  function(notes, amount)
    return mo.quantize(notes, {
      grid = paw.opt.note_grid,
      strength = opt("strength"),
      swing = pct(amount) or opt("swing_amount"),
    })
  end
)
op("gz>", "Crescendo", POLY, function(notes, amount) return mo.crescendo(notes, { amount = amount or opt("ramp") }) end)
op(
  "gz<lt>",
  "Diminuendo",
  POLY,
  function(notes, amount) return mo.diminuendo(notes, { amount = amount or opt("ramp") }) end
)
op(
  "gzc",
  "Compress velocities towards their average",
  POLY,
  function(notes, amount) return mo.compress(notes, { ratio = pct(amount) or opt("compress") }) end
)
op(
  "gzv",
  "Even out velocities: all the average, or the count",
  POLY,
  function(notes, amount) return mo.set_velocity(notes, { velocity = amount }) end
)
op(
  "gze",
  "Accent the notes on the beat",
  POLY,
  function(notes, amount) return mo.accent(notes, { amount = amount or opt("accent"), grid = 1 }) end
)
op("gzr", "Reverse in time", ALL, function(notes) return mo.reverse(notes) end)
op("gzd", "Double time: twice as fast", ALL, function(notes) return mo.double_time(notes) end)
op("gzD", "Half time: half as fast", ALL, function(notes) return mo.half_time(notes) end)
op(
  "gzu",
  "Invert chords upwards",
  POLY,
  function(notes, amount) return mo.invert(notes, { dir = 1, times = amount or 1, tolerance = opt("together") }) end,
  true
)
op(
  "gzU",
  "Invert chords downwards",
  POLY,
  function(notes, amount) return mo.invert(notes, { dir = -1, times = amount or 1, tolerance = opt("together") }) end,
  true
)
op(
  "gzk",
  "Up a step of the scale",
  ALL,
  function(notes, amount) return mo.transpose_scale(notes, amount or 1, scale.current()) end,
  true
)
op(
  "gzj",
  "Down a step of the scale",
  ALL,
  function(notes, amount) return mo.transpose_scale(notes, -(amount or 1), scale.current()) end,
  true
)
op(
  "gzn",
  "Snap to the scale",
  ALL,
  function(notes) return mo.snap_scale(notes, scale.current(), { dir = opt("snap") }) end,
  true
)
op(
  "gzm",
  "Mirror the melody around its first note, in the scale",
  ALL,
  function(notes) return mo.mirror(notes, { key = opt("mirror_chromatic") and nil or scale.current() }) end,
  true
)
op(
  "gzo",
  "Double an octave up",
  POLY,
  function(notes, amount) return mo.add_octave(notes, { by = 12 * (amount or 1) }) end,
  true
)
op(
  "gzO",
  "Double an octave down",
  POLY,
  function(notes, amount) return mo.add_octave(notes, { by = -12 * (amount or 1) }) end,
  true
)
op("gzx", "Remove overlapping notes of a pitch", ALL, function(notes) return mo.remove_overlaps(notes) end)

-- Text objects and motions ------------------------------------------------------------

local function phrases(clip) return mo.phrases(clip:notes(), paw.opt.phrase_rest) end

--- The phrase at the cursor (or the next one, from a rest) and `count - 1`
--- more; with `around` up to where the phrase after them starts.
function M.phrase_region(view, count, around)
  local clip, v = M.view_clip(view)
  if not clip then return end
  local list = phrases(clip)
  if #list == 0 then return end
  local first = #list
  for i, p in ipairs(list) do
    if v.beat < p.finish - EPS then
      first = i
      break
    end
  end
  local last = math.min(#list, first + (count or 1) - 1)
  local c0, c1 = list[first].start, list[last].finish
  if around then c1 = list[last + 1] and list[last + 1].start or math.max(c1, clip.length) end
  return { view = view, kind = "char", r0 = v.pitch, r1 = v.pitch, c0 = c0, c1 = c1 }
end

--- Go to the start of the next (`dir` 1) or previous (-1) phrase.
function M.phrase_motion(view, dir, count)
  local clip, v = M.view_clip(view)
  if not clip then return end
  local list = phrases(clip)
  local pitch, beat = v.pitch, v.beat
  for _ = 1, count or 1 do
    local found
    if dir > 0 then
      for _, p in ipairs(list) do
        if p.start > beat + EPS then
          found = p
          break
        end
      end
    else
      for i = #list, 1, -1 do
        if list[i].start < beat - EPS then
          found = list[i]
          break
        end
      end
    end
    if not found then
      beat = dir > 0 and clip.length or 0
      break
    end
    pitch, beat = found.notes[1].pitch, found.start
  end
  v.grid.set(pitch, beat)
end

-- The vocal editor's phrases; the piano roll has paw's own (`ip`, `(` `)`).
for _, view in ipairs({ "utau" }) do
  local function object(lhs, fn, desc) keymap.textobject(lhs, fn, { view = view, desc = desc }) end
  object(
    "ip",
    function(ctx) return M.phrase_region(view, ctx.count, false) end,
    "The phrase: notes with no long rest between them"
  )
  object("ap", function(ctx) return M.phrase_region(view, ctx.count, true) end, "The phrase and the rest after it")
  keymap.set(
    ")",
    function(ctx) M.phrase_motion(view, 1, ctx.count) end,
    { view = view, motion = true, jump = true, desc = "Next phrase" }
  )
  keymap.set(
    "(",
    function(ctx) M.phrase_motion(view, -1, ctx.count) end,
    { view = view, motion = true, jump = true, desc = "Start of this phrase, or the previous one" }
  )
end

-- Key and scale -----------------------------------------------------------------------

local function key_command(ctx)
  local words = {}
  for _, w in ipairs(ctx.args) do
    words[#words + 1] = tostring(w)
  end
  -- `:key D minor at 17`: a key change at bar 17, a marker (one undo step).
  local bar
  if #words >= 2 and words[#words - 1] == "at" then
    bar = tonumber(words[#words])
    if bar and bar % 1 ~= 0 then bar = nil end
    if not bar or bar < 1 then return paw.notify("key: at needs a bar number, from 1", "error") end
    words[#words], words[#words - 1] = nil, nil
  end
  local text = table.concat(words, " ")
  if bar and text ~= "" then
    local ok, key = pcall(paw.harmony.parse_key, text)
    if not ok then return paw.notify(tostring(key):gsub("^.-:%d+: ", ""), "error") end
    paw.markers.add(paw.time.bar_start(bar), "key " .. paw.harmony.key_name(key))
    return paw.notify("key: " .. paw.harmony.key_name(key) .. " from bar " .. bar)
  end
  if text == "" then
    local key = scale.project()
    return paw.notify(key and ("key: " .. scale.name(key)) or ("no key set; working in " .. scale.default))
  end
  if text == "off" or text == "none" then
    scale.set(nil)
    return paw.notify("key cleared")
  end
  local ok, err = pcall(scale.parse, text)
  if not ok then return paw.notify(tostring(err):gsub("^.-:%d+: ", ""), "error") end
  scale.set(text)
  paw.notify("key: " .. scale.name(text))
end
paw.command("musicops.key", key_command, {
  desc = "Set the project's key: `key D minor`, `key D minor at 17` (a key change at bar 17), `key off`; alone shows it",
})
if not paw.commands.get("key") or paw.commands.get("key").alias_of == "musicops.key" then
  paw.commands.alias("key", "musicops.key")
end
paw.command(
  "musicops.scales",
  function() paw.ui.page("Scales", scale.names()) end,
  { desc = "List the scales `key` knows" }
)

local function lock(ctx)
  local arg = ctx and ctx.args and ctx.args[1]
  if arg == nil then
    paw.opt.musicops_scale_lock = not paw.opt.musicops_scale_lock
  else
    paw.opt.musicops_scale_lock = arg == true or arg == "on" or arg == 1
  end
  paw.notify("scale lock " .. (paw.opt.musicops_scale_lock and ("on: " .. scale.name(scale.current())) or "off"))
end
paw.command(
  "musicops.lock",
  lock,
  { desc = "Keep note entry and transposing in the key: `musicops.lock on|off`, alone toggles" }
)
keymap.set("gzL", function() lock() end, { desc = "Scale lock on or off", repeatable = false })

--- Apply a function of the module to the notes of the clip being edited:
--- `:musicops.apply humanize timing=0.05 seed=3`, `:musicops.apply transpose_scale 2`.
local APPLY = {
  humanize = true,
  quantize = true,
  legato = true,
  staccato = true,
  set_length = true,
  reverse = true,
  stretch = true,
  double_time = true,
  half_time = true,
  strum = true,
  arpeggiate = true,
  invert = true,
  add_octave = true,
  transpose = true,
  transpose_scale = true,
  snap_scale = true,
  mirror = true,
  ramp = true,
  crescendo = true,
  diminuendo = true,
  compress = true,
  set_velocity = true,
  accent = true,
  remove_overlaps = true,
}
paw.command("musicops.apply", function(ctx)
  local name = ctx.args[1]
  if not APPLY[name] then
    local names = {}
    for k in pairs(APPLY) do
      names[#names + 1] = k
    end
    table.sort(names)
    return paw.notify("usage: musicops.apply <" .. table.concat(names, "|") .. "> name=value ...", "warn")
  end
  local opts = {}
  for k, v in pairs(ctx.args) do
    if type(k) == "string" then opts[k] = v end
  end
  local clip = M.view_clip(paw.ui.focused)
  if not clip then
    local at = paw.cursor.clip()
    clip = at and at.kind == "midi" and at or nil
  end
  if not clip then return paw.notify("no MIDI clip to change", "warn") end
  M.apply_to_clip(clip, function() return true end, function(notes)
    if name == "transpose" then return mo.transpose(notes, ctx.args[2] or opts.by) end
    if name == "transpose_scale" then return mo.transpose_scale(notes, ctx.args[2] or opts.by, opts.key) end
    if name == "snap_scale" then return mo.snap_scale(notes, opts.key, opts) end
    if name == "mirror" and opts.key == true then opts.key = scale.current() end
    return mo[name](notes, opts)
  end)
end, { desc = "Apply a musicops function to the clip being edited: `musicops.apply humanize seed=3`" })

-- Scale lock: entering notes and moving them stays in the key -----------------------------
--
-- With `musicops_scale_lock` on, the piano roll's insert-mode keys enter the
-- nearest pitch of the key, and `<C-a>` `<C-x>` move notes by scale steps in
-- the piano roll (normal and visual mode) and the vocal editor (visual
-- mode). These replace the runtime's mappings and hand back to them while
-- the lock is off.

paw.state.musicops_originals = paw.state.musicops_originals or {}
local saved = paw.state.musicops_originals

local function original(mode, view, lhs)
  local id = mode .. "|" .. view .. "|" .. lhs
  local want = table.concat(keymap.parse(lhs))
  for _, m in ipairs(keymap.list(mode, view)) do
    if m.scope == view and table.concat(m.keys) == want and not m.musicops then saved[id] = m end
  end
  return saved[id]
end

local function call(m, ...)
  if not m then return end
  if m.operator then return m.operator(...) end
  if type(m.rhs) == "function" then return m.rhs(...) end
  if type(m.rhs) == "string" then return paw.commands.exec(m.rhs, ...) end
end

local function locked() return paw.opt.musicops_scale_lock end

--- Put the scale-lock mappings in place over the runtime's (and the vocal
--- editor's, which may be loaded later: this runs again when a view is focused).
function M.install_locks()
  -- Insert mode drawing: the note being drawn moves by steps of the scale.
  for lhs, dir in pairs({ ["+"] = 1, ["<C-a>"] = 1, ["-"] = -1, ["<C-x>"] = -1 }) do
    local orig = original("i", "pianoroll", lhs)
    keymap.set(lhs, function(ctx)
      if not locked() then return call(orig, ctx) end
      paw.roll_draw.pitch(dir, function(pitch, n) return scale.step(scale.current(), pitch, dir * n) end)
    end, { view = "pianoroll", mode = "i", desc = orig and orig.desc, musicops = true })
  end

  -- `+` `-` are the pitch as `Ctrl-a` `Ctrl-x` are (docs/reference/key-rule.md).
  for lhs, dir in pairs({ ["<C-a>"] = 1, ["<C-x>"] = -1, ["+"] = 1, ["-"] = -1 }) do
    local orig = original("n", "pianoroll", lhs)
    keymap.set(lhs, function(ctx)
      if not locked() then return call(orig, ctx) end
      local roll = paw.ui.views.pianoroll
      local key, to = scale.current(), nil
      if
        roll:change(function(n)
          n.pitch = math.max(0, math.min(127, scale.step(key, n.pitch, dir * (ctx.count or 1))))
          to = n.pitch
        end)
      then
        roll:move(0, to - roll.pitch)
      end
    end, { view = "pianoroll", desc = orig and orig.desc, role = orig and orig.role, musicops = true })

    for _, view in ipairs(NOTES) do
      local xorig = original("x", view, lhs)
      keymap.set(lhs, nil, {
        view = view,
        mode = "x",
        desc = xorig and xorig.desc,
        musicops = true,
        operator = function(region, ctx)
          if not locked() then return call(xorig, region, ctx) end
          M.apply(
            view,
            region,
            function(notes) return mo.transpose_scale(notes, dir * (ctx.count or 1), scale.current()) end
          )
        end,
      })
    end
  end
end

M.install_locks()
paw.on("view.focused", function()
  local m = nil
  for _, map in ipairs(keymap.list("x", "utau")) do
    if map.scope == "utau" and map.lhs == "<C-a>" then m = map end
  end
  if m and not m.musicops then M.install_locks() end
end)

return M
