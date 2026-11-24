-- `paw.insert`: insert mode in the arrange view, and what its keys insert.
--
-- `i` in the arrange view starts insert mode, as in Vim; `<Esc>` ends it.
-- In it each key inserts one kind of thing at the cursor: `m` a MIDI clip,
-- `a` an automation point, `r` a region, `'` a marker, `f` a file. The
-- cursor steps past what was inserted, so `mmm` lays three clips one
-- after the other, and a count makes as many (`3m`). Letters only insert:
-- the arrows move. `<CR>` opens what was inserted last (the piano roll for
-- a MIDI clip), or, when nothing was, enters notes at the cursor as `i`
-- did before. `<BS>` takes back the last one. Everything inserted from `i`
-- to `<Esc>` is one undo step. Inserting never moves a clip: where a clip
-- is already, a clip is refused.
--
-- What a key inserts is data, which extensions and init.lua add and change:
--
--   paw.insert.add("M", { kind = "midi", desc = "A 4-bar clip of a drum pattern",
--     length = "4 bars", name = "Drums %d", notes = { { pitch = 36, start = 0, length = 1 } } })
--   paw.insert.set("r", { name = "Verse %d", length = "marker" })
--   paw.insert.set("m", { key = "n" })        -- `n` in place of `m`
--   paw.insert.remove("f")
--
-- The keys that work are those in `paw.opt.insertkeys`; `add` puts a new
-- key there, at the place of its `order`. A key with `view` belongs to
-- the insert mode of another view, which reads it from `view_kinds`:
--
--   paw.insert.add("C", { view = "devices", device = "chorus", desc = "A chorus" })
-- A kind of clip
-- (`paw.kinds.define("clip", ...)`) with an `insert` key gets one too. The
-- contract is `paw.contracts.InsertKind`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local registry = require("paw.registry")
local options = require("paw.options")
local events = require("paw.events")
local commands = require("paw.commands")
local objects = require("paw.objects")
local cursor = require("paw.cursor")
local util = require("paw.util")
local timegrid = require("paw.timegrid")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type MarkersModule = require("paw.markers")

local type Kind = contracts.InsertKind
local type Patch = contracts.InsertPatch
local type Context = contracts.InsertContext
local type Item = contracts.InsertedItem

--- What a mapping's function gets.
local type MapContext = contracts.KeyContext

--- `paw.part_kinds` (paw/part_kinds.lua), the piece this module reads.
local record PartKinds
  of: function(part: integer): string
end

--- `paw.ui.input`'s options, as far as this module gives them.
local record InputOptions
  prompt: string
  text: string
  label: string
  complete: function(text: string): {commands.Entry}
end

--- A view, as far as this module sets it: the arrange view lists the
--- keys of its insert mode (`paw.keymap.hints`).
local record View
  insert_hints: boolean
end

local record Ui
  focused: string
  views: registry.Registry<View>
  input: function(opts: InputOptions, on_submit: function(text: string))
end

--- A field of a kind, which `set` copies and never reads.
local record Field
end

--- `paw.clip_kinds` (paw/clip_kinds.tl), the part this module calls.
local record ClipKinds
  spec: function(name: string): contracts.ClipKind<Field>
  add: function(part: objects.Part, name: string, args: contracts.ClipKindArgs): objects.Clip
end

local record Paw is partial.Paw
  keymap: KeymapModule
  markers: MarkersModule
  clip_kinds: ClipKinds
  time: objects.Time
  ui: Ui
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local function keymap(): KeymapModule
  return paw.keymap
end

--- What one insert session has made, newest last, and the count typed.
local record Session
  items: {Item}
  specs: {Kind}
  count: integer
end

local record M
  --- The keys and what each inserts, by key, with the extension that
  --- added or changed each one (`add`, `set`).
  kinds: registry.Registry<Kind>
  --- What a view whose insert mode reads `view_kinds` does when a key of
  --- it changes, by the name of the view. The view sets it.
  on_view: {string: function()}
end

M.on_view = {}

-- The keys of the insert modes of other views, by the name of the view.
local view_kinds: {string: registry.Registry<Kind>} = {}

--- The insert keys of the view `name` (`paw.insert.add` with `view`), by
--- key. The view maps them: only the arrange view's keys are mapped here.
function M.view_kinds(name: string): registry.Registry<Kind>
  if not view_kinds[name] then
    view_kinds[name] = registry.new(
      "insert." .. name,
      "keys of insert mode in the " .. name .. " view",
      {
        label = function(key: string, _: Kind): string return key .. " (insert mode, " .. name .. ")" end,
        changed = function()
          local fn = M.on_view[name]
          if fn then
            fn()
          end
        end,
      }
    )
  end
  return view_kinds[name]
end

local session: Session = {items = {}, specs = {}}

local function has(list: {string}, value: string): boolean
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

local function shown(): {string}
  return (opt.insertkeys or {}) as {string}
end

local function set_shown(list: {string})
  opt.insertkeys = list
end

-- The keys -----------------------------------------------------------------------

-- The mapping made for each key from its kind, to know which are this
-- module's: those it takes away when the key goes.
local made: {string: Kind} = {}
local made_at: {string: integer} = {}

local press: function(key: string)

--- Map each key of `paw.opt.insertkeys` in the arrange view's insert mode,
--- and take away the mappings of keys that are no longer there.
local function sync()
  local km = keymap()
  local active: {string: boolean} = {}
  for i, key in ipairs(shown()) do
    local spec = M.kinds:get(key)
    if spec then
      active[key] = true
      if made[key] ~= spec or made_at[key] ~= i then
        km.set(key, function() press(key) end, {mode = "i", view = "arrange", desc = spec.desc, order = i})
        made[key], made_at[key] = spec, i
      end
    end
  end
  for key in pairs(made) do
    if not active[key] then
      km.del(key, {mode = "i", view = "arrange"})
      made[key], made_at[key] = nil, nil
    end
  end
  api.ui_redraw()
end

--- A copy of `list` with `key` in it at the place of its kind's `order`
--- (`util.by_order`): before the first key whose kind comes after it, else
--- last. A key with no kind does not move the others.
local function placed(list: {string}, key: string): {string}
  local spec = M.kinds:get(key)
  local copy: {string} = {}
  local put = false
  for _, k in ipairs(list) do
    local other = M.kinds:get(k)
    if not put and other and util.by_order(spec, other) then
      copy[#copy + 1], put = key, true
    end
    copy[#copy + 1] = k
  end
  if not put then
    copy[#copy + 1] = key
  end
  return copy
end

-- The keys that an extension moved with `set`: the kind at the old key
-- is hidden under a copy until the extension unloads.
local moved: {string: boolean} = {}

-- A key that goes leaves `paw.opt.insertkeys`, and a key that an
-- extension moved comes back to its place there when the extension
-- unloads. Then the mappings follow.
M.kinds = registry.new(
  "insert",
  "keys of insert mode",
  {
    label = function(key: string, spec: Kind): string return not spec.hidden and key .. " (insert mode)" or nil end,
    changed = function(key: string, spec: Kind)
      local list = shown()
      if not spec then
        local kept: {string} = {}
        for _, k in ipairs(list) do
          if k ~= key then
            kept[#kept + 1] = k
          end
        end
        set_shown(kept)
      elseif moved[key] and not spec.hidden then
        moved[key] = nil
        if not has(list, key) then
          set_shown(placed(list, key))
        end
      end
      sync()
    end,
  }
)

--- Add a key, or put a new kind in place of the one on it. It goes into
--- `paw.opt.insertkeys` (unless `hidden`) at the place of its `order`, so
--- it works at once.
---   paw.insert.add("M", { kind = "midi", desc = "A 4-bar clip", length = "4 bars", order = 15 })
function M.add(key: string, spec: Kind): Kind
  assert(
    type(key) == "string" and key ~= "" and type(spec) == "table",
    "usage: paw.insert.add(key, { kind = \"midi\", desc = \"A MIDI clip\" })"
  )
  if spec.view and spec.view ~= "arrange" then
    assert(
      spec.device ~= nil or spec.split ~= nil,
      "an insert key of the " .. spec.view .. " view has a `device` or a `split`"
    )
    spec.key = key
    spec.desc = spec.desc or ("A " .. tostring(spec.device or spec.split or key))
    spec.order = spec.order or 50
    spec.ext = spec.ext or paw.ext.caller()
    M.view_kinds(spec.view):put(key, spec)
    return spec
  end
  assert(spec.kind ~= nil or spec.insert ~= nil, "an insert key has a `kind` or an `insert` function")
  spec.key = key
  spec.desc = spec.desc or ("A " .. tostring(spec.kind))
  spec.order = spec.order or 50
  spec.ext = spec.ext or paw.ext.caller()
  M.kinds:put(key, spec)
  local list = shown()
  if not spec.hidden and not has(list, key) then
    set_shown(placed(list, key))
    sync()
  end
  return spec
end

--- Take a key away, and out of `paw.opt.insertkeys`. The kind that it
--- replaced, if any, comes back. With `view`, a key of that view's insert
--- mode.
function M.remove(key: string, view?: string)
  if view and view ~= "arrange" then
    M.view_kinds(view):remove(key)
    return
  end
  M.kinds:remove(key)
end

--- A copy of `from` with the fields of `patch` that are given. A copy, not
--- a change in place, so that it goes over the one it changed, which comes
--- back when the extension that changed it unloads.
local function patched(from: Kind, patch: Patch): Kind
  local out: {string: Field} = {}
  for k, v in pairs(from as {string: Field}) do
    out[k] = v
  end
  for k, v in pairs(patch as {string: Field}) do
    out[k] = v
  end
  return out as Kind
end

--- Change what a key inserts, a built-in key too: only the fields of
--- `patch` that are given. With `key`, the kind moves to that key (in the
--- same place of `paw.opt.insertkeys`). The key gets a changed copy.
---   paw.insert.set("r", { name = "Verse %d", length = "marker" })
---   paw.insert.set("m", { length = "1 bar", key = "n" })
function M.set(key: string, patch: Patch): Kind
  local spec = M.kinds:get(key)
  if not spec then
    error("no insert key `" .. tostring(key) .. "`", 2)
  end
  local copy = patched(spec, patch)
  copy.ext = paw.ext.caller()
  local to = patch.key or key
  copy.key = to
  if to ~= key then
    -- The new key takes the place of the old one in the list first: the
    -- removal of the old key takes it out of the list.
    local list: {string} = {}
    for _, k in ipairs(shown()) do
      if k == key then
        list[#list + 1] = to
      elseif k ~= to then
        list[#list + 1] = k
      end
    end
    set_shown(list)
    if copy.ext then
      -- An extension hides the kind at the old key under a copy, so that
      -- its unload gives the key back.
      moved[key] = true
      M.kinds:put(key, patched(spec, {hidden = true} as Patch))
    else
      M.kinds:remove(key)
    end
  end
  M.kinds:put(to, copy)
  return copy
end

--- What a key inserts, or nil.
function M.get(key: string): Kind
  return M.kinds:get(key)
end

--- The keys that work, in the order of `paw.opt.insertkeys`, each with
--- what it inserts.
function M.list(): {Kind}
  local out: {Kind} = {}
  for _, key in ipairs(shown()) do
    if M.kinds:get(key) then
      out[#out + 1] = M.kinds:get(key)
    end
  end
  return out
end

-- Lengths and names ----------------------------------------------------------------

--- The next marker, or start or end of a region, after `beat`.
local function next_edge(beat: number): number
  local best: number
  for _, m in ipairs(paw.markers.list()) do
    for _, at in ipairs({m.beat, m.length and m.beat + m.length or nil}) do
      if at > beat + 1e-9 and (not best or at < best) then
        best = at
      end
    end
  end
  return best
end

--- A kind's `length` in beats at `beat`; nil for a point (a step of the grid).
local function beats(length: contracts.InsertLength, beat: number, point: boolean): number, string
  if length == nil then
    return (not point) and opt.clip_length as number or nil
  end
  if length is number then
    if length > 0 then
      return length
    end
    return nil, "a length above 0, not " .. tostring(length)
  end
  local text = (length as string):lower()
  if text == "marker" then
    local edge = next_edge(beat)
    return edge and edge - beat or opt.clip_length as number
  end
  local n, unit = text:match("^%s*([%d%.]*)%s*(%a+)%s*$")
  local amount = n == "" and 1 or tonumber(n)
  if not amount or amount <= 0 then
    return nil, "a length such as `2 bars`, `3 steps`, `8 beats` or `marker`, not `" .. text .. "`"
  end
  if unit:match("^bars?$") then
    return amount * api.tempo_bar_length(beat)
  end
  if unit:match("^steps?$") then
    return amount * timegrid.step()
  end
  if unit:match("^beats?$") then
    return amount
  end
  return nil, "a length such as `2 bars`, `3 steps`, `8 beats` or `marker`, not `" .. text .. "`"
end

--- A name with `%d` made `n`.
local function named(pattern: string, n: integer): string
  if not pattern then
    return nil
  end
  return (pattern:gsub("%%d", tostring(n)))
end

-- What the built-in kinds insert ---------------------------------------------------

--- The clip on `part` that a stretch would overlap, or nil.
local function overlapping(part: objects.Part, from: number, to: number): objects.Clip
  for _, c in ipairs(part:clips()) do
    if c.start < to - 1e-9 and c.start + c.length > from + 1e-9 then
      return c
    end
  end
end

local function clip_item(clip: objects.Clip, text: string): Item
  return {
    what = "clip",
    id = clip.id,
    start = clip.start,
    length = clip.length,
    text = text,
    remove = function()
      if clip:exists() then
        clip:remove()
      end
    end,
  }
end

--- Why a clip cannot go at the cursor, or nil.
local function no_clip(ctx: Context): string
  if ctx.part == nil then
    return "no part here: `o` adds one"
  end
  if ctx.part == 0 then
    return "the master part has no clips: move to a part with <Up>"
  end
  local part = objects.part(ctx.part)
  local over = overlapping(part, ctx.beat, ctx.beat + (ctx.length or 0))
  if over then
    return string.format(
      "a clip is there already (%s at %s): insert mode does not move clips; <Esc>, move, then i",
      over.name,
      paw.time.format(over.start)
    )
  end
end

local builtin: {string: function(ctx: Context): Item, string} = {}

builtin.midi = function(ctx: Context): Item, string
  local why = no_clip(ctx)
  if why then
    return nil, why
  end
  local part = objects.part(ctx.part)
  local n = #part:clips() + 1
  local clip = part:add_clip({start = ctx.beat, length = ctx.length, name = named(ctx.name, n), notes = ctx.spec.notes})
  return clip_item(clip, "a MIDI clip")
end

builtin.audio = function(ctx: Context): Item, string
  if ctx.part == nil or ctx.part == 0 then
    return nil, no_clip(ctx)
  end
  local part = objects.part(ctx.part)
  if part:clip_at(ctx.beat) then
    return nil, no_clip(ctx)
  end
  local beat = ctx.beat
  paw.ui.input(
    {
      prompt = "File: ",
      label = "Insert a file",
      complete = function(text: string): {commands.Entry}
        return commands.completers:get("audio_files")(text) as {commands.Entry}
      end,
    },
    function(text: string)
      if text == "" then
        return
      end
      local saved = cursor.beat
      cursor.set_beat(beat)
      local ok, clip = pcall(commands.run, "clip.import", {text}) as (boolean, objects.Clip)
      cursor.set_beat(saved)
      if not ok or not clip then
        paw.notify("could not insert " .. text .. (ok and "" or ": " .. tostring(clip)), "error")
        return
      end
      ctx.placed(clip_item(clip, "the file " .. text))
    end
  )
  return nil, nil
end

builtin.marker = function(ctx: Context): Item, string
  local name = ctx.name and named(ctx.name, #paw.markers.list() + 1) or paw.markers.default_name()
  local m = paw.markers.add(ctx.beat, name)
  return {
    what = "marker",
    id = m.id,
    start = ctx.beat,
    text = "the marker " .. name,
    remove = function() paw.markers.remove(m.id) end,
  }
end

builtin.region = function(ctx: Context): Item, string
  local name = named(ctx.name, #paw.markers.regions() + 1) or ""
  local m = paw.markers.add(ctx.beat, name, {length = ctx.length})
  return {
    what = "region",
    id = m.id,
    start = ctx.beat,
    length = ctx.length,
    text = name ~= "" and "the region " .. name or "a region",
    remove = function() paw.markers.remove(m.id) end,
  }
end

builtin.automation = function(ctx: Context): Item, string
  local lane: objects.Lane
  if ctx.lane then
    lane = objects.lane(ctx.lane)
  elseif ctx.part and ctx.part ~= 0 then
    lane = objects.part(ctx.part):automate("volume")
  else
    return nil, "no part here: an automation point goes on a part or a lane"
  end
  local before = lane:points()
  local value = lane:value_at(ctx.beat)
  if value == nil or value ~= value then
    value = objects.part(ctx.part or lane:part().id):value_at("volume", ctx.beat)
  end
  lane:add(ctx.beat, value)
  local target = lane:get().target
  return {
    what = "point",
    id = lane.id,
    start = ctx.beat,
    text = string.format("a %s point (%g)", tostring(target), value),
    remove = function()
      if lane:exists() then
        api.lane_set_points(lane.id, before)
      end
    end,
  }
end

--- What a kind of clip from an extension (`paw.clip_kinds`) inserts.
local function custom_clip(ctx: Context): Item, string
  local why = no_clip(ctx)
  if why then
    return nil, why
  end
  local part = objects.part(ctx.part)
  local args: contracts.ClipKindArgs = {
    name = named(ctx.name, #part:clips() + 1), start = ctx.beat, length = ctx.length
  }
  for i, word in ipairs(ctx.spec.args or {}) do
    args[i] = word
  end
  local ok, clip = pcall(paw.clip_kinds.add, part, ctx.spec.kind, args) as (boolean, objects.Clip)
  if not ok then
    return nil, tostring(clip)
  end
  return clip_item(clip, "a " .. ctx.spec.kind .. " clip")
end

-- Inserting -------------------------------------------------------------------------

--- The kind for the cursor's part: its `per_part` patch for the
--- part's kind (`part` for a part of no kind) applied.
local function for_part(spec: Kind, kind: string): Kind
  local patch = spec.per_part and spec.per_part[kind]
  if patch then
    return patched(spec, patch)
  end
  return spec
end

local function step_after(item: Item)
  local length = item.length or timegrid.step()
  cursor.set_beat(item.start + length)
end

local function took(spec: Kind, item: Item)
  session.items[#session.items + 1] = item
  session.specs[#session.specs + 1] = spec
  step_after(item)
end

--- Insert what `key` inserts at the cursor, as many times as the count
--- typed before it (in insert mode). Says what it made, or why not.
press = function(key: string)
  local count = session.count or 1
  session.count = nil
  local base = M.kinds:get(key)
  if not base then
    return paw.notify("`" .. key .. "` inserts nothing: K lists the keys", "warn")
  end
  local made_n, last = 0, nil as Item
  for i = 1, count do
    local part = cursor.part_id()
    local kind = part and part ~= 0 and (paw.part_kinds as PartKinds).of(part) or nil
    local spec = for_part(base, kind or "part")
    if spec.parts and part ~= 0 and not has(spec.parts, kind or "part") then
      local where = table.concat(spec.parts, " or ")
      return paw.notify(
        string.format(
          "`%s` inserts on a %s part; this one is %s",
          key,
          where,
          kind and "a " .. kind .. " part" or "a part of no kind"
        ),
        "warn"
      )
    end
    local point = spec.kind == "marker" or spec.kind == "automation"
    local length, bad = beats(spec.length, cursor.beat, point)
    if bad then
      return paw.notify("`" .. key .. "`: " .. bad, "warn")
    end
    local ctx: Context = {
      key = key,
      spec = spec,
      part = part,
      lane = cursor.lane_id(),
      beat = cursor.beat,
      length = length,
      index = i,
      count = count,
      name = spec.name,
    }
    ctx.placed = function(item: Item)
      took(spec, item)
      paw.notify("inserted " .. item.text .. " at " .. paw.time.format(item.start))
    end
    local fn = spec.insert or builtin[spec.kind] or (paw.clip_kinds.spec(spec.kind) and custom_clip)
    if not fn then
      return paw.notify("`" .. key .. "`: no kind `" .. tostring(spec.kind) .. "` to insert", "warn")
    end
    local ok, item, why = pcall(fn, ctx) as (boolean, Item, string)
    if not ok then
      return paw.notify("`" .. key .. "`: " .. tostring(item), "error")
    end
    if not item then
      if why then
        paw.notify(why, "warn")
      end
      break
    end
    took(spec, item)
    made_n, last = made_n + 1, item
  end
  if last then
    local text = made_n == 1 and last.text or string.format("%d × %s", made_n, last.text)
    paw.notify("inserted " .. text .. " at " .. paw.time.format(session.items[#session.items - made_n + 1].start))
  end
end

--- Insert what `key` inserts at the cursor, as if typed in insert mode
--- (`count` times).
function M.insert(key: string, count?: integer)
  session.count = count
  press(key)
end

--- Start insert mode in the arrange view.
function M.start()
  keymap().set_mode("i")
end

--- `<CR>`: open what was inserted last, and end insert mode; with nothing
--- inserted, enter notes at the cursor, in a new clip if there is none.
function M.open()
  local item, spec = session.items[#session.items], session.specs[#session.specs]
  if not item then
    keymap().set_mode("n")
    commands.run("clip.insert")
    return
  end
  keymap().set_mode("n")
  if spec.open then
    spec.open(
      {
        key = spec.key,
        spec = spec,
        beat = item.start,
        length = item.length,
        index = 1,
        count = 1,
        part = cursor.part_id(),
      } as Context,
      item
    )
  end
end

--- `<BS>`: take back the last thing inserted, and the cursor with it.
function M.back()
  local item = table.remove(session.items)
  table.remove(session.specs)
  if not item then
    return paw.notify("nothing inserted to take back", "warn")
  end
  if item.remove then
    item.remove()
  end
  cursor.set_beat(item.start)
  paw.notify("took back " .. item.text)
end

--- A digit typed in insert mode: a count for the next key.
function M.digit(d: integer)
  if d == 0 and not session.count then
    return
  end
  session.count = (session.count or 0) * 10 + d
  api.ui_redraw()
end

--- The count typed so far in insert mode, or nil.
function M.count(): integer
  return session.count
end

--- What `K` says in insert mode: each key and what it inserts.
function M.describe(): string
  local lines: {string} = {"Insert mode: each key inserts at the cursor; <CR> opens it, <BS> takes it back, <Esc> ends"}
  for _, spec in ipairs(M.list()) do
    lines[#lines + 1] = string.format("  %-3s %s", spec.key, spec.desc)
  end
  return table.concat(lines, "\n")
end

-- A session is what is typed from `i` to `<Esc>`.
local type ModeChanged = KeymapModule.ModeChanged
local mode_changed = paw.keymap.mode_changed
events.on(
  mode_changed,
  function(e: ModeChanged)
    if e.mode == "i" or e.old == "i" then
      session = {items = {}, specs = {}}
    end
  end
)

-- `:set insertkeys=m,r` takes effect at once.
events.on(
  options.changed,
  function(e: options.Changed)
    if e.name == "insertkeys" then
      sync()
    end
  end
)

if paw.ui.views:get("arrange") then
  paw.ui.views:get("arrange").insert_hints = true
end

-- The built-in keys ---------------------------------------------------------------

local function open_midi(_: Context, item: Item)
  cursor.set_beat(item.start)
  commands.run("clip.insert")
end

local function rename(_: Context, item: Item)
  cursor.set_beat(item.start)
  commands.run("marker.rename")
end

M.add("m", {kind = "midi", desc = "A MIDI clip; Enter opens it in the piano roll", order = 10, open = open_midi})
M.add("a", {kind = "automation", desc = "An automation point: the lane's, else the volume's", order = 20})
M.add("r", {kind = "region", desc = "A region; Enter names it", order = 30, open = rename})
M.add("'", {kind = "marker", desc = "A marker; Enter names it", order = 40, open = rename})
M.add("f", {kind = "audio", desc = "A sound or MIDI file: type its name", order = 50})

-- The keys of insert mode that are not kinds: a count, Enter, Backspace,
-- the arrows (they move, as in Vim's insert mode), and K.
local function imap(lhs: string, fn: function(ctx: MapContext), desc: string)
  keymap().set(lhs, fn, {mode = "i", view = "arrange", desc = desc, repeatable = lhs ~= "K", hint = false})
end
for d = 0, 9 do
  imap(tostring(d), function() M.digit(d) end, "A count: as many as it says")
end
imap("<CR>", function() M.open() end, "Open what was inserted last; with nothing, enter notes here")
imap("<BS>", function() M.back() end, "Take back what was inserted last")
imap("K", function() paw.notify(M.describe()) end, "Say what each key inserts")
imap("<Left>", function() commands.run("cursor.left") end, "Left one grid step")
imap("<Right>", function() commands.run("cursor.right") end, "Right one grid step")
imap("<Up>", function() commands.run("cursor.up") end, "Previous part")
imap("<Down>", function() commands.run("cursor.down") end, "Next part")

return M
