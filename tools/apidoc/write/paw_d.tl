-- The writer of runtime/types/paw.d.tl, the `paw` global for the files
-- written in Teal (tlconfig.lua's global_env_def). It holds what Teal
-- cannot see by itself:
--
-- - `paw.api`, the functions of the kernel, as paw/api.d.tl declares them.
-- - the runtime's modules that are written in Teal, each by its own types
--   (`local type HarmonyReadModule = require("paw.harmony.read")`).
-- - the other values of `paw`: another name of a value of a module in Teal
--   or of the kernel has its type, a module in Lua its record of
--   partial.d.tl, and the rest is `Untyped`.
--
-- A module written in Lua is not declared: it is typed by porting it to
-- Teal. Each `any` in the file must be on the allow-list
-- (runtime/types/any-allowed.txt), with its reason, and the count only goes
-- down (docs/explanation/about-teal.md).
local model = require("apidoc.model")
local names = require("apidoc.names")
local anys = require("apidoc.anys")
local teal_type = require("apidoc.teal_type")

local type Table = model.Table

-- A record of the global: the records in it by key (`order` is their keys
-- in the order found, sorted when written) and its lines.
local record Node
  children: {string: Node}
  order: {string}
  lines: {string}
end

local function node(): Node
  return {children = {}, order = {}, lines = {}}
end

-- Another name of a kernel function (`paw.wait`) has its type, where the
-- type has no `any`.
local function kernel_forms(kernel: model.Kernel): {any: {string}}
  local out: {any: {string}} = {}
  for fn, name in pairs(kernel.name_of) do
    local f = kernel.functions[name]
    if f then
      local forms = teal_type.signatures(f)
      if not table.concat(forms, " "):find("%f[%w_]any%f[^%w_]") then
        out[fn] = forms
      end
    end
  end
  return out
end

local function text(m: model.Model, run: model.Run): string
  local out: {string} = {
    "-- " .. names.HEADER,
    "-- The `paw` global for the files written in Teal (tlconfig.lua's",
    "-- global_env_def): the kernel's functions, and the modules of the runtime",
    "-- that are written in Teal.",
    "",
    'local type Api = require("paw.api")',
    'local type UntypedLua = require("paw.untyped")',
    'local type Partial = require("paw.partial")',
    'local type types = require("paw.types")',
    'local type contracts = require("paw.contracts")',
  }
  local tree = node()
  -- The record of each module in Lua that partial.d.tl types, by its table.
  local partial_of: {any: string} = {}
  for _, rec in ipairs(m.lua_types.records) do
    partial_of[rec.table] = rec.record
  end
  local in_teal: {string: boolean} = {}
  for _, mod in ipairs(m.teal_modules) do
    in_teal[mod.name] = true
  end
  for _, mod in ipairs(m.teal_modules) do
    -- A module in Teal that holds others (`paw.harmony` holds
    -- `paw.harmony.read`) declares them in its own record.
    local nested = false
    for prefix in mod.name:gmatch("()%.") do
      local at = prefix as integer
      if at > 4 and in_teal[mod.name:sub(1, at - 1)] then
        nested = true
      end
    end
    if not nested then
      local alias = names.alias(mod.name)
      out[#out + 1] = "local type " .. alias .. ' = require("' .. mod.module .. '")'
      if not mod.hidden then
        local at = tree
        local parts: {string} = {}
        for part in mod.name:gmatch("[^.]+") do
          parts[#parts + 1] = part
        end
        for i = 2, #parts - 1 do
          local key = parts[i]
          if not at.children[key] then
            at.children[key] = node()
            at.order[#at.order + 1] = key
          end
          at = at.children[key]
        end
        at.lines[#at.lines + 1] = parts[#parts] .. ": " .. alias
      end
    end
  end
  out[#out + 1] = ""
  out[#out + 1] = "global record paw"
  out[#out + 1] = "   api: Api"
  -- What is still written in Lua: `paw.Untyped`, which any use takes and
  -- whose value is cast (`paw.cursor.part_id() as integer`). Each one is
  -- on the allow-list until its module is ported.
  out[#out + 1] = "   type Untyped = UntypedLua"
  local of_kernel = kernel_forms(m.kernel)
  -- The values of a record of the global that no module in Teal declares.
  local function untyped(at: Node, path: string, value: any)
    local taken: {string: boolean} = {api = path == "paw" or nil}
    for _, key in ipairs(at.order) do
      taken[key] = true
    end
    for _, line in ipairs(at.lines) do
      taken[line:match("^type ([%w_]+) =") or line:match("^([%w_]+)")] = true
    end
    local keys: {string} = {}
    for k in pairs(type(value) == "table" and value as Table or {}) do
      if k is string and k:match("^%a[%w_]*$") and not names.KEYWORDS[k] and not taken[k] then
        keys[#keys + 1] = k
      end
    end
    for _, k in ipairs(keys) do
      local v = (value as Table)[k]
      -- Another name of a value of a module in Teal has its type.
      local typed = m.teal_values[v]
      -- What the comments of a module in Lua type: a function by its forms,
      -- a module by its record of partial.d.tl, a value of `paw` by its type.
      local forms = m.lua_types.forms[v] or of_kernel[v] or (path == "paw" and m.lua_types.top[k])
      if typed and typed:match("^type ") then
        -- A record of a module in Teal: its type, and its table as a value.
        at.lines[#at.lines + 1] = "type " .. k .. " = " .. typed:sub(6)
      elseif typed then
        at.lines[#at.lines + 1] = k .. ": " .. typed
      elseif forms then
        for _, form in ipairs(forms) do
          at.lines[#at.lines + 1] = anys.count(run.anys, path .. "." .. k, k .. ": " .. form)
        end
      elseif partial_of[v] then
        at.lines[#at.lines + 1] = k .. ": Partial." .. partial_of[v]
      else
        at.lines[#at.lines + 1] = anys.count(run.anys, path .. "." .. k, k .. ": Untyped")
      end
    end
  end
  local function emit(at: Node, depth: integer, path: string, value: any)
    local pad = string.rep("   ", depth)
    untyped(at, path, value)
    table.sort(at.order)
    for _, key in ipairs(at.order) do
      out[#out + 1] = pad .. "record " .. key
      emit(at.children[key], depth + 1, path .. "." .. key, value and (value as Table)[key])
      out[#out + 1] = pad .. "end"
    end
    table.sort(at.lines)
    for _, line in ipairs(at.lines) do
      out[#out + 1] = pad .. line
    end
  end
  emit(tree, 1, "paw", m.paw)
  out[#out + 1] = "end"
  out[#out + 1] = ""
  -- A hidden module whose values `paw` holds with types written out in
  -- full (`paw.notify` of paw.messages) names no type of its alias: the
  -- strict check counts an unused alias, so it goes.
  local whole = table.concat(out, "\n")
  for i = #out, 1, -1 do
    local alias = out[i]:match("^local type ([%w_]+Module) = require")
    if alias and not whole:find("%f[%w_]" .. alias .. "%.") and not whole:find(": " .. alias .. "%f[^%w_]") then
      table.remove(out, i)
    end
  end
  return table.concat(out, "\n")
end

local writer: model.Writer = {path = "runtime/types/paw.d.tl", text = text}

return writer
