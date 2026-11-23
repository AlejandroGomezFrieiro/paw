-- The reader of the Teal of the runtime: which modules are in Teal, the
-- type of each value they give (from the text of their source), the event
-- descriptors they export, and the `any` of the records of the kernel's
-- data (types.tl, contracts.tl).
local model = require("apidoc.model")
local source = require("apidoc.source")
local names = require("apidoc.names")
local anys = require("apidoc.anys")

local type Module = model.Module
local type TealModule = model.TealModule

local record teal
  --- The files of records whose `any` count as the kernel's do, by the
  --- name that a declaration gives the module.
  RECORDS: {{string}}
end

teal.RECORDS = {{"types", "runtime/lua/paw/types.tl"}, {"contracts", "runtime/lua/paw/contracts.tl"}}

local loaded = package.loaded as {string: any}
local TEAL = {".tl", "/init.tl"}

--- The modules of the runtime written in Teal, by name. A module that is
--- no value of `paw` itself is `hidden`: its values are (`paw.Track` and
--- `paw.tracks` of paw.objects).
function teal.modules(modules: {Module}, global: model.Table): {TealModule}
  local out: {TealModule} = {}
  local seen: {string: boolean} = {}
  for _, mod in ipairs(modules) do
    -- Under any name: `paw.option` is the module paw.options.
    local file = mod.module and source.module_file(mod.module, TEAL)
    if file then
      out[#out + 1] = {name = mod.name, module = mod.module, file = file}
      seen[mod.module] = true
    end
  end
  -- A module in Teal that is a value of a module in Lua (`paw.ui.Buf`, the
  -- module paw.buf, of paw/ui.tl) is no field of the record of `paw`, which
  -- types that module as partial.d.tl does: it is left out until its parent
  -- is in Teal too.
  local teal_name: {string: boolean} = {}
  for _, mod in ipairs(out) do
    teal_name[mod.name] = true
  end
  for i = #out, 1, -1 do
    local parent = out[i].name:match("^(.+)%.[^.]+$")
    if parent and parent ~= "paw" and not teal_name[parent] then
      table.remove(out, i)
    end
  end
  -- The values of `paw`, to find the hidden modules that give some.
  local of_paw: {any: boolean} = {}
  for _, v in pairs(global) do
    of_paw[v] = true
  end
  local function gives(value: model.Table): boolean
    for _, v in pairs(value) do
      if type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean" and of_paw[v] then
        return true
      end
    end
    return false
  end
  for module, value in pairs(loaded) do
    local file = type(value) == "table"
      and module:match("^paw%.")
      and not seen[module]
      and gives(value as model.Table)
      and source.module_file(module, TEAL)
    if file then
      out[#out + 1] = {name = module, module = module, file = file, hidden = true}
    end
  end
  table.sort(out, function(a: TealModule, b: TealModule): boolean return a.name < b.name end)
  return out
end

--- The Teal type of each value that a module written in Teal gives, by the
--- value, for the names that are another way to it (`paw.on` is
--- `paw.events.on`, `paw.opt` is `paw.option.opt`): the function's
--- signature in its source, or the field's type in the module's record, with
--- the types that the module gives (`type Handler = Handler`) named as
--- `Alias.Handler`. The value of a record of the module's own is `type X`.
function teal.values(mods: {TealModule}): {any: string}
  local out: {any: string} = {}
  for _, mod in ipairs(mods) do
    local text = source.read(mod.file) or ""
    local alias = names.alias(mod.name)
    local exported: {string: boolean} = {}
    for name in text:gmatch("\n%s+type ([%w_]+) =") do
      exported[name] = true
    end
    local record_text = text:match("\nlocal record M\n(.-)\nend\n") or ""
    -- A record of the module's own (`record Track` in `local record M`):
    -- a type, and its value the table of the record (`paw.Track`).
    local records: {string: boolean} = {}
    for name in ("\n" .. record_text):gmatch("\n  record ([%w_]+)") do
      exported[name], records[name] = true, true
    end
    local function qualify(t: string): string
      -- The module's own types, `M.Event`, are the alias's.
      t = t:gsub("%f[%w_.]M%.", alias .. ".")
      return (
        t:gsub(
          "%f[%w_.][%a_][%w_]*%f[^%w_]",
          function(word: string): string return exported[word] and alias .. "." .. word or word end
        )
      )
    end
    local value = loaded[mod.module]
    for name, v in pairs(type(value) == "table" and value as model.Table or {}) do
      if name is string then
        local t: string
        if type(v) == "function" then
          local rest = text:match("\nfunction M%." .. name .. "(%f[^%w_][^\n]*)")
          local generics = rest and rest:match("^<[^>]*>") or ""
          local sig = rest and rest:sub(#generics + 1):match("^(%b().-)%s*$")
          -- A signature alone: not a function written on one line.
          if sig and not sig:find("%f[%w_]return%f[^%w_]") and not sig:find("%f[%w_]end%f[^%w_]") then
            t = "function" .. generics .. sig
          end
          -- A function written on one line: its type in the module's record.
          t = t or ("\n" .. record_text):match("\n  " .. name .. ": (function[^\n]+)")
        elseif records[name] and v == (value as model.Table)[name] then
          t = "type " .. name
        else
          -- A field of the module's record, not of a record in it.
          t = ("\n" .. record_text):match("\n  " .. name .. ": ([^\n]+)")
            or record_text:match("\n%s+" .. name .. ": ([^\n]+)")
            or record_text:match("^%s+" .. name .. ": ([^\n]+)")
        end
        if t and not out[v] then
          out[v] = t:match("^type ") and "type " .. alias .. "." .. name or qualify(t)
        end
      end
    end
  end
  return out
end

--- The `any` of the records of the kernel's data, by the name of what has
--- them (`types.Track.meta`): an `any` moved from a signature into a record
--- is still one.
function teal.record_anys(): {string: integer}
  local out: {string: integer} = {}
  local stack: {string | boolean} = {}
  for _, records in ipairs(teal.RECORDS) do
    for _, line in ipairs(source.lines(records[2]) or {}) do
      local code = line:gsub("%-%-.*$", "")
      local record = code:match("^%s*record%s+([%w_]+)")
        or code:match("^%s*local%s+record%s+([%w_]+)")
        or code:match("^%s*interface%s+([%w_]+)")
      if record then
        stack[#stack + 1] = record
      elseif code:match("^%s*enum%s") then
        stack[#stack + 1] = false
      elseif code:match("^%s*end%s*$") then
        stack[#stack] = nil
      else
        local field = code:match("^%s*type%s+([%w_]+)%s*=") or code:match('^%s*%[?"?([%w_]+)"?%]?%s*:')
        if field then
          local path: {string} = {}
          for i = 2, #stack do
            path[#path + 1] = tostring(stack[i])
          end
          path[#path + 1] = field
          local n = anys.words(code)
          if n > 0 then
            local name = records[1] .. "." .. table.concat(path, ".")
            out[name] = (out[name] or 0) + n
          end
        end
      end
    end
  end
  return out
end

-- The events of the runtime -------------------------------------------------------------
--
-- The module that sends an event exports its descriptor (paw/events.tl): a
-- field of the module's record, `changed: events.Event<Changed>`, under a
-- comment `--- The event `option.changed`: when it comes.`.

-- The file of a record type as a module names it: its own, types.tl or
-- the kernel's events. Nil for the empty payload of paw/events.tl.
local function record_file(type_name: string, path: string): string, string
  local qualifier, name = type_name:match("^([%w_]+)%.([%w_]+)$")
  if not qualifier then
    return path, type_name
  end
  if qualifier == "types" then
    return "runtime/lua/paw/types.tl", name
  end
  if qualifier == "kernel" then
    return names.EVENTS_TL, name
  end
  if qualifier == "events" and name == "Payload" then
    return nil
  end
  error(path .. ": the payload type " .. type_name .. " is in no file that tools/apidoc.lua reads")
end

-- The names of the fields of the record `name` in the file `path`, in
-- order: the fields one level in from the line `record name`.
local function field_names(path: string, name: string): {string}
  local lines = source.lines(path) or {}
  for i, line in ipairs(lines) do
    local indent = line:match("^(%s*)local record " .. name .. "%f[^%w_]")
      or line:match("^(%s*)record " .. name .. "%f[^%w_]")
    if indent then
      local fields: {string} = {}
      local inner: string
      for j = i + 1, #lines do
        local l = lines[j]
        if l:match("^" .. indent .. "end%s*$") then
          break
        end
        local pad = l:match("^(%s+)%S")
        inner = inner or (pad and not l:match("^%s*%-%-") and pad)
        local field = pad == inner and l:match("^%s+([%w_]+)%??:%s")
        if field then
          fields[#fields + 1] = field
        end
      end
      return fields
    end
  end
  error(path .. ": no record " .. name .. " for the payload of an event")
end

--- The descriptors that the runtime's modules export, sorted by the name
--- of the event. A descriptor whose comment does not say which event it is
--- and when it comes is an error.
function teal.events(modules: {Module}): {model.Event}
  -- The shortest name from `paw` of each module, for the column "In Teal".
  local reached: {string: string} = {}
  for _, m in ipairs(modules) do
    if m.module and not reached[m.module] then
      reached[m.module] = m.name
    end
  end
  local rows: {model.Event} = {}
  for module, value in pairs(loaded) do
    local path = type(value) == "table" and module:match("^paw%.") and source.module_file(module, TEAL)
    local lines = path and source.lines(path) or {}
    for i, line in ipairs(lines) do
      -- paw/events.tl names its own type `Event`, the others `events.Event`.
      local key, payload = line:match("^  ([%w_]+): events%.Event<([%w_.]+)>%s*$")
      if not key and path == "runtime/lua/paw/events.tl" then
        key, payload = line:match("^  ([%w_]+): Event<([%w_.]+)>%s*$")
      end
      if key then
        local doc = source.doc_over(lines, i)
        local event, when = table.concat(doc, " "):match("^The event `([^`]+)`: (.-)%.?$")
        local descriptor = (value as model.Table)[key]
        if not event then
          error(path .. ":" .. i .. ": say `--- The event `name`: when it comes.` over the descriptor " .. key)
        end
        if type(descriptor) ~= "table" or (descriptor as {string: string}).name ~= event then
          error(path .. ":" .. i .. ": the descriptor " .. key .. " is not the event `" .. event .. "`")
        end
        local file, record = record_file(payload, path)
        local fields = file and field_names(file, record) or {}
        rows[#rows + 1] = {
          event = event,
          payload = #fields == 0 and "{}" or "{ " .. table.concat(fields, ", ") .. " }",
          when = when,
          teal = (reached[module] or 'require("' .. module .. '")') .. "." .. key,
        }
      end
    end
  end
  table.sort(rows, function(a: model.Event, b: model.Event): boolean return a.event < b.event end)
  return rows
end

return teal
