-- The writer of runtime/types/paw.lua, a LuaLS meta file: point LuaLS at
-- runtime/types (`workspace.library`), and editors complete `paw.*` in a
-- configuration or an extension.
local model = require("apidoc.model")
local names = require("apidoc.names")

local type Type = model.Type

-- The LuaLS type of each named type of an argument of a kernel function.
local LUALS: {string: string} = {
  String = "string",
  f64 = "number",
  f32 = "number",
  i64 = "integer",
  u64 = "integer",
  u32 = "integer",
  i32 = "integer",
  usize = "integer",
  u8 = "integer",
  u16 = "integer",
  Id = "integer",
  bool = "boolean",
  LuaValue = "any",
  Table = "table",
  Function = "function",
}

-- The LuaLS type of an argument of a kernel function: `T?` for an
-- `Option`, `T[]` for a list, `any` for a type LuaLS has no name for.
local function luals(t: Type): string
  if t.kind == "optional" then
    return luals(t.of) .. "?"
  elseif t.kind == "list" then
    return luals(t.of) .. "[]"
  elseif t.kind == "tuple" then
    return #t.items == 0 and "nil" or "any"
  end
  return LUALS[t.text] or "any"
end

--- How a function is called: `paw.Track:clips` for a method.
local function call_name(f: model.Function): string
  return f.method and (f.name:gsub("%.([%w_]+)$", ":%1")) or f.name
end

local function text(m: model.Model): string
  local out: {string} = {
    "---@meta",
    "-- " .. names.HEADER,
    "-- Point LuaLS at this directory (`workspace.library`) to complete `paw.*`.",
    "",
  }
  local function add(line: string)
    out[#out + 1] = line
  end
  for _, mod in ipairs(m.modules) do
    add("---@class " .. mod.name)
    add(mod.name .. " = {}")
    add("")
  end
  add("---@class paw.api")
  add("paw.api = {}")
  add("---@type string")
  add("paw.api.version = " .. string.format("%q", m.kernel.version))
  add("")
  for _, f in ipairs(m.functions) do
    if f.alias_of then
      add(f.name .. " = " .. f.alias_of)
    else
      for _, line in ipairs(f.doc or {}) do
        if not line:match("^@") then
          add("--- " .. line)
        end
      end
      for _, p in ipairs(f.params) do
        if p ~= "..." and not (f.doc and table.concat(f.doc, "\n"):find("@param " .. p .. "%f[^%w_]")) then
          add("---@param " .. p .. " any")
        end
      end
      add("function " .. call_name(f) .. "(" .. table.concat(f.params, ", ") .. ") end")
    end
    add("")
  end
  for _, name in ipairs(m.kernel.names) do
    local k = m.kernel.functions[name]
    if k then
      -- The `@param`/`@return` lines are in Teal's notation, for paw.d.tl.
      local params: {string} = {}
      for _, line in ipairs(k.doc) do
        add("--- " .. line)
      end
      for i, p in ipairs(k.params) do
        add("---@param " .. p.name .. " " .. luals(p.type))
        params[i] = p.name
      end
      add("function paw.api." .. name .. "(" .. table.concat(params, ", ") .. ") end")
    else
      add("---@type fun(...): any")
      add("paw.api." .. name .. " = nil")
    end
    add("")
  end
  return table.concat(out, "\n")
end

local writer: model.Writer = {path = "runtime/types/paw.lua", text = text}

return writer
