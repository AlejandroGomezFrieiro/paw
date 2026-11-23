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
-- This module is in a low layer (tools/layers.txt). It does not read
-- paw.ext: paw.ext sets `registry.owner` and `registry.replaced`.
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
    label: function(key: string, value: T): string
    --- Runs after the entry that `get(key)` gives changed (nil: it went).
    changed: function(key: string, value: T)
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
    --- The entries by key, in a new table.
    entries: function(self: Registry<T>): {string: T}
    --- The keys of the entries that `owner` put, sorted.
    owned_by: function(self: Registry<T>, owner: string): {string}
  end

  --- The extension whose code calls, or nil: paw.ext sets it to
  --- `paw.ext.caller`. Nil until then, so the entries have no owner.
  owner: function(): string
  --- Runs when the extension `owner` puts an entry over an entry of the
  --- extension `previous`: paw.ext keeps it for `:checkhealth extensions`.
  replaced: function(registry: M.Owned, what: string, owner: string, previous: string)
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
--- `remove(key)`, `entries()` and `owned_by(name)`. `paw.ext.unload` takes
--- away the entries of an extension, and an entry that one of them
--- replaced comes back.
function M.new<T>(kind: string, title: string, options?: M.Options<T>): M.Registry<T>
  -- The stack of entries at each key, the entry on top first. A key with
  -- no entry is not in the table.
  local slots: {string: Slot<T>} = {}
  local label = options and options.label or function(key: string, _: T): string return key end
  local changed = options and options.changed

  local registry: M.Registry<T> = {kind = kind, title = title}

  function registry.put(_: M.Registry<T>, key: string, value: T, owner?: string)
    assert(value ~= nil, "usage: put(key, value): remove(key) takes an entry away")
    if owner == nil and M.owner then
      owner = M.owner()
    end
    local top = slots[key]
    if top and top.owner == owner then
      top.value = value
    else
      slots[key] = {value = value, owner = owner, below = top}
      -- An extension that replaces the entry of another extension.
      if top and top.owner and owner and M.replaced then
        M.replaced(registry, label(key, value), owner, top.owner)
      end
    end
    if changed then
      changed(key, value)
    end
  end

  function registry.remove(_: M.Registry<T>, key: string): T
    local top = slots[key]
    if not top then
      return nil
    end
    slots[key] = top.below
    if changed then
      changed(key, top.below and top.below.value)
    end
    return top.value
  end

  function registry.get(_: M.Registry<T>, key: string): T
    local top = slots[key]
    return top and top.value
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

  function registry.labels(_: M.Registry<T>, owner: string): {string}
    local out: {string} = {}
    for i, key in ipairs(registry:owned_by(owner)) do
      out[i] = label(key, holds(slots[key], owner).value)
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
        changed(key, kept and kept.value)
      end
    end
    return count
  end

  made[#made + 1] = registry
  return registry
end

return M
