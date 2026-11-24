-- A registry: entries by key that the core, the user and extensions add to,
-- each with the extension that put it there. A module that takes entries
-- (pickers, fields, sources) makes one registry for them:
--
--   local sources: registry.Registry<contracts.PickEntry> = registry.new("pickers", "picker sources")
--   sources:put("tempo", spec)       -- the owner is the extension whose code calls
--   sources:get("tempo")             -- the entry, or nil
--
-- paw.ext reads the owners: `:extensions` lists what an extension put, and
-- `paw.ext.unload` takes it away with `unload(owner)`. A module that makes a
-- registry needs no change in paw.ext: `registry.all()` gives each one.
--
-- An entry put over another keeps the one below it. When the entry on top
-- goes (`remove`, or the unload of its owner), the one below comes back: a
-- picker of the core that an extension replaced is there again after the
-- unload. The unload of an extension whose entry is below another removes
-- only its own entry, so the entry on top stays.
--
-- An extension that waits for its first use can wait for a key of any
-- registry (its `kind` trigger). A `get` of a key with no entry calls
-- `registry.missing`, which loads that extension, and then gives the entry
-- that the extension put.
--
-- This module is in a low layer (tools/layers.txt). It does not read
-- paw.ext: paw.ext sets `registry.owner`, `registry.maker` and
-- `registry.replaced`, and paw/lazy.tl sets `registry.missing` and
-- `registry.waiting`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

--- An entry and the extension that put it there (nil for the core's and
--- the user's). `below` is the entry that it replaced, or nil.
local record Slot<T>
  value: T
  owner: string
  below: Slot<T>
end

local record M
  --- What a module can give with the kind and the title of its registry.
  record Options<T>
    --- The entry in a few words, for `:extensions` (the key when not given).
    --- Nil leaves the entry out of the list, for an entry that another
    --- registry lists (the view of a buffer type).
    label: function(key: string, value: T): string
    --- Runs after the entry that `get(key)` gives changed: `value` is the
    --- new entry (nil: it went), and `old` the entry before.
    changed: function(key: string, value: T, old: T)
    --- True: the owner of an entry is the extension whose files made it
    --- (`registry.maker`), not the extension whose code calls `put`. A
    --- timer that the core starts again while an extension loads stays the
    --- core's.
    made: boolean
  end

  --- An entry as `registry.maker` reads it: a function, or a table.
  record Made
  end

  --- The entries of a registry as `save` found them, with their owners,
  --- for `restore`.
  record Saved
  end

  --- What paw.ext reads of each registry, whatever the type of its entries.
  interface Owned
    --- The name of the registry in `paw.ext.provides` (`pickers`).
    kind: string
    --- The name in words for `:extensions` (`picker sources`).
    title: string
    --- The labels of the entries that `owner` put, sorted by key.
    labels: function(self: Owned, owner: string): {string}
    --- Remove every entry that `owner` put. Gives how many went.
    unload: function(self: Owned, owner: string): integer
  end

  --- Entries of type `T` by key, each with its owner.
  record Registry<T> is Owned
    --- Put `value` at `key`. `owner` is the extension that puts it: when
    --- it is not given, the extension whose code calls (`paw.ext.caller()`).
    --- A put by the owner of the entry on top replaces it. A put by
    --- another goes over it, and the entry below comes back when the new
    --- one goes.
    put: function(self: Registry<T>, key: string, value: T, owner?: string)
    --- Remove the entry on top at `key`, so that the entry below it (if
    --- any) comes back. Gives the entry removed, or nil.
    remove: function(self: Registry<T>, key: string): T
    --- The entry at `key`, or nil.
    get: function(self: Registry<T>, key: string): T
    --- The extension that put the entry on top at `key`: nil for an entry
    --- of the core or the user, and for a key with no entry.
    owner: function(self: Registry<T>, key: string): string
    --- The entries by key, in a new table.
    entries: function(self: Registry<T>): {string: T}
    --- The keys of the entries that `owner` put, sorted.
    owned_by: function(self: Registry<T>, owner: string): {string}
    --- The entry in a few words, as `:extensions` shows it.
    label: function(self: Registry<T>, key: string, value: T): string
    --- The entry that `owner` put at `key`, and the entry below it: the
    --- one that it replaced. Nil when `owner` put none there.
    put_by: function(self: Registry<T>, key: string, owner: string): T, T
    --- The entries as they are now, each with its owner and the entries
    --- below it. A test that takes entries away gives this to `restore`
    --- after it: a `put` from the code of an extension would make that
    --- extension the owner of an entry of the core.
    save: function(self: Registry<T>): M.Saved
    --- Put back the entries that `save` gave, with their owners, in place
    --- of the entries now.
    restore: function(self: Registry<T>, saved: M.Saved)
  end

  --- The extension whose code calls, or nil: paw.ext sets it to
  --- `paw.ext.caller`. Nil until then, so the entries have no owner.
  owner: function(): string
  --- The extension whose files made `value` (a function of its files, or
  --- a table with one among its fields), or nil: paw.ext sets it. A
  --- registry with `made` reads it in place of `owner`.
  maker: function(value: M.Made): string
  --- Runs when the extension `owner` puts an entry over an entry of the
  --- extension `previous`: paw.ext keeps it for `:checkhealth extensions`.
  replaced: function(registry: M.Owned, what: string, owner: string, previous: string)
  --- Runs when `get` finds no entry at `key`: paw/lazy.tl loads the
  --- extension that waits for this key of this registry, and gives true.
  --- `get` then looks again. Nil until paw/lazy.tl sets it.
  missing: function(registry: M.Owned, key: string): boolean
  --- True when an extension waits for a key of `registry`: a module that
  --- skips its work while the registry is empty does it then, so that its
  --- `get` loads the extension. paw/lazy.tl sets it.
  waiting: function(registry: M.Owned): boolean
end

-- Every registry made, in the order of `new`.
local made: {M.Owned} = {}

--- The registries made so far, in the order they were made.
function M.all(): {M.Owned}
  local out: {M.Owned} = {}
  for i, registry in ipairs(made) do
    out[i] = registry
  end
  return out
end

--- A copy of the stack of entries that starts at `slot`.
local function copy<T>(slot: Slot<T>): Slot<T>
  if not slot then
    return nil
  end
  return {value = slot.value, owner = slot.owner, below = copy(slot.below)}
end

--- The entry that `owner` put in the stack that starts at `slot`, or nil.
local function holds<T>(slot: Slot<T>, owner: string): Slot<T>
  while slot do
    if slot.owner == owner then
      return slot
    end
    slot = slot.below
  end
  return nil
end

--- A new registry: entries by key, each with the extension that put it
--- there. `kind` names it in `paw.ext.provides` and `title` in
--- `:extensions`. Its functions are `put(key, value)`, `get(key)`,
--- `remove(key)`, `entries()`, `owned_by(name)`, `put_by(key, name)` and
--- `label(key, value)`. `paw.ext.unload` takes
--- away the entries of an extension, and an entry that one of them
--- replaced comes back.
function M.new<T>(kind: string, title: string, options?: M.Options<T>): M.Registry<T>
  -- The stack of entries at each key, the entry on top first. A key with
  -- no entry is not in the table.
  local slots: {string: Slot<T>} = {}
  local label = options and options.label or function(key: string, _: T): string return key end
  local changed = options and options.changed
  local by_maker = options and options.made

  local registry: M.Registry<T> = {kind = kind, title = title}

  function registry.put(_: M.Registry<T>, key: string, value: T, owner?: string)
    assert(value ~= nil, "usage: put(key, value): remove(key) takes an entry away")
    if owner == nil and by_maker then
      owner = M.maker and M.maker(value as M.Made)
    elseif owner == nil and M.owner then
      owner = M.owner()
    end
    local top = slots[key]
    local old = top and top.value
    if top and top.owner == owner then
      top.value = value
    else
      slots[key] = {value = value, owner = owner, below = top}
      -- An extension that replaces the entry of another extension, where
      -- this registry lists the entry.
      local what = top and top.owner and owner and M.replaced and label(key, value)
      if what then
        M.replaced(registry, what, owner, top.owner)
      end
    end
    if changed then
      changed(key, value, old)
    end
  end

  function registry.remove(_: M.Registry<T>, key: string): T
    local top = slots[key]
    if not top then
      return nil
    end
    slots[key] = top.below
    if changed then
      changed(key, top.below and top.below.value, top.value)
    end
    return top.value
  end

  function registry.get(_: M.Registry<T>, key: string): T
    local top = slots[key]
    -- A key that an extension that waits gives: it loads now.
    if not top and key ~= nil and M.missing and M.missing(registry, key) then
      top = slots[key]
    end
    return top and top.value
  end

  function registry.owner(_: M.Registry<T>, key: string): string
    local top = slots[key]
    return top and top.owner
  end

  function registry.entries(_: M.Registry<T>): {string: T}
    local out: {string: T} = {}
    for key, slot in pairs(slots) do
      out[key] = slot.value
    end
    return out
  end

  function registry.owned_by(_: M.Registry<T>, owner: string): {string}
    local out: {string} = {}
    for key, slot in pairs(slots) do
      if holds(slot, owner) then
        out[#out + 1] = key
      end
    end
    table.sort(out)
    return out
  end

  function registry.label(_: M.Registry<T>, key: string, value: T): string
    return label(key, value)
  end

  function registry.put_by(_: M.Registry<T>, key: string, owner: string): T, T
    local slot = holds(slots[key], owner)
    if not slot then
      return nil
    end
    return slot.value, slot.below and slot.below.value
  end

  function registry.labels(_: M.Registry<T>, owner: string): {string}
    local out: {string} = {}
    for _, key in ipairs(registry:owned_by(owner)) do
      out[#out + 1] = label(key, holds(slots[key], owner).value)
    end
    return out
  end

  function registry.unload(_: M.Registry<T>, owner: string): integer
    local count = 0
    for _, key in ipairs(registry:owned_by(owner)) do
      -- Take the owner's entries out of the stack. Only a change of the
      -- entry on top is a change for `changed`.
      local top = slots[key]
      local kept: Slot<T> = nil
      local last: Slot<T> = nil
      local slot = top
      while slot do
        if slot.owner == owner then
          count = count + 1
        elseif last then
          last.below, last = slot, slot
        else
          kept, last = slot, slot
        end
        slot = slot.below
      end
      if last then
        last.below = nil
      end
      slots[key] = kept
      if changed and kept ~= top then
        changed(key, kept and kept.value, top.value)
      end
    end
    return count
  end

  function registry.save(_: M.Registry<T>): M.Saved
    local out: {string: Slot<T>} = {}
    for key, slot in pairs(slots) do
      out[key] = copy(slot)
    end
    return out as M.Saved
  end

  function registry.restore(_: M.Registry<T>, saved: M.Saved)
    local wanted = saved as {string: Slot<T>}
    -- Each key whose entry on top differs: the key of an entry that went,
    -- and the key of an entry that comes back.
    local keys: {string: boolean} = {}
    for key in pairs(slots) do
      keys[key] = true
    end
    for key in pairs(wanted) do
      keys[key] = true
    end
    for key in pairs(keys) do
      local top, back = slots[key], copy(wanted[key])
      slots[key] = back
      local old, value = top and top.value, back and back.value
      if changed and old ~= value then
        changed(key, value, old)
      end
    end
  end

  made[#made + 1] = registry
  return registry
end

return M
